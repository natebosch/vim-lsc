if !exists('s:file_diagnostics')
  " file path -> line number -> [diagnostic]
  "
  " Diagnostics are dictionaries with:
  " 'group': The highlight group, like 'lscDiagnosticError'.
  " 'ranges': 1-based [[start line, start column, length]]
  " 'message': The message to display.
  " 'type': Single letter representation of severity for location list.
  let s:file_diagnostics = {}

  " file path -> incrementing version number
  let s:diagnostic_versions = {}
endif

" Converts between an LSP diagnostic and the internal representation used for
" highlighting.
function! s:Convert(diagnostic) abort
  let start = a:diagnostic.range.start
  let end = a:diagnostic.range.end
  if end.line > start.line
    let ranges =[[
        \ start.line + 1,
        \ start.character + 1,
        \ 99
        \]]
    " Renders strangely until a `redraw!` if lines are mixed with line ranges
    call extend(ranges, map(range(start.line + 2, end.line), {_, l->[l,0,99]}))
    call add(ranges, [
        \ end.line + 1,
        \ 1,
        \ end.character
        \])
  else
    let ranges = [[
        \ start.line + 1,
        \ start.character + 1,
        \ end.character - start.character]]
  endif
  let group = <SID>SeverityGroup(a:diagnostic.severity)
  let type = <SID>SeverityType(a:diagnostic.severity)
  let message = a:diagnostic.message
  if has_key(a:diagnostic, 'code')
    let message = message.' ['.a:diagnostic.code.']'
  endif
  return {'group': group, 'ranges': ranges, 'message': message, 'type': type}
endfunction

function! lsc#diagnostics#clean(filetype) abort
  for buffer in getbufinfo({'loaded': v:true})
    if getbufvar(buffer.bufnr, '&filetype') != a:filetype | continue | endif
    call lsc#diagnostics#setForFile(buffer.name, [])
  endfor
endfunction

" Finds the highlight group given a diagnostic severity level
function! s:SeverityGroup(severity) abort
    if a:severity == 1
      return 'lscDiagnosticError'
    elseif a:severity == 2
      return 'lscDiagnosticWarning'
    elseif a:severity == 3
      return 'lscDiagnosticInfo'
    elseif a:severity == 4
      return 'lscDiagnosticHint'
    endif
endfunction

" Finds the location list type given a diagnostic severity level
function! s:SeverityType(severity) abort
    if a:severity == 1
      return 'E'
    elseif a:severity == 2
      return 'W'
    elseif a:severity == 3
      return 'I'
    elseif a:severity == 4
      return 'H'
    endif
endfunction

function! lsc#diagnostics#forFile(file_path) abort
  if !has_key(s:file_diagnostics, a:file_path)
    return {}
  endif
  return s:file_diagnostics[a:file_path]
endfunction

function! s:DiagnosticsVersion(file_path) abort
  if !has_key(s:diagnostic_versions, a:file_path)
    return 0
  endif
  return s:diagnostic_versions[a:file_path]
endfunction

function! lsc#diagnostics#setForFile(file_path, diagnostics) abort
  if empty(a:diagnostics) && !has_key(s:file_diagnostics, a:file_path)
    return
  endif
  if has_key(s:diagnostic_versions, a:file_path)
    let s:diagnostic_versions[a:file_path] += 1
  else
    let s:diagnostic_versions[a:file_path] = 1
  endif
  call map(a:diagnostics, {_, diagnostic -> s:Convert(diagnostic)})
  if !empty(a:diagnostics)
    let diagnostics_by_line = {}
    for diagnostic in a:diagnostics
      let line_number = string(diagnostic.ranges[0][0])
      if !has_key(diagnostics_by_line, line_number)
        let line = []
        let diagnostics_by_line[line_number] = line
      else
        let line = diagnostics_by_line[line_number]
      endif
      call add(line, diagnostic)
    endfor
    let s:file_diagnostics[a:file_path] = diagnostics_by_line
  else
    unlet s:file_diagnostics[a:file_path]
  endif
  call lsc#diagnostics#updateLocationList(a:file_path)
  call lsc#highlights#updateDisplayed()
  if(a:file_path ==# expand('%:p'))
    call lsc#cursor#onMove()
  endif
endfunction

" Updates location list for all windows showing [file_path].
function! lsc#diagnostics#updateLocationList(file_path) abort
  let bufnr = bufnr(a:file_path)
  if bufnr == -1 | return | endif
  let file_ref = {'bufnr': bufnr}
  let diagnostics_version = s:DiagnosticsVersion(a:file_path)
  for window_id in lsc#util#windowsForFile(a:file_path)
    if !s:WindowIsCurrent(window_id, a:file_path, diagnostics_version)
      if !exists('l:items')
        let items = s:ListItems(a:file_path, file_ref)
      endif
      call setloclist(window_id, items)
      call s:MarkManagingLocList(window_id, a:file_path, diagnostics_version)
    else
    endif
  endfor
endfunction

" Returns a list of quick fix or location list items for the diagnostics in
" [file_path].
"
" [file_ref] is a dict with either 'bufnr' or 'filename'.
function! s:ListItems(file_path, file_ref) abort
  let items = []
  for line in values(lsc#diagnostics#forFile(a:file_path))
    for diagnostic in line
      call add(items, s:ListItem(diagnostic, a:file_ref))
    endfor
  endfor
  call sort(items, 'lsc#util#compareQuickFixItems')
  return items
endfunction

" Converts between an internal diagnostic and an item for the location list.
function! s:ListItem(diagnostic, file_ref) abort
  let range = a:diagnostic.ranges[0]
  let item = {'lnum': range[0], 'col': range[1],
      \ 'text': a:diagnostic.message, 'type': a:diagnostic.type}
  call extend(item, a:file_ref)
  return item
endfunction


function! s:MarkManagingLocList(window_id, file_path, version) abort
  let window_info = getwininfo(a:window_id)[0]
  let tabnr = window_info.tabnr
  let winnr = window_info.winnr
  call settabwinvar(tabnr, winnr, 'lsc_diagnostics_file', a:file_path)
  call settabwinvar(tabnr, winnr, 'lsc_diagnostics_version', a:version)
endfunction

" Returns the total number of diagnostics in all files.
"
" If the number grows very large returns instead a String like `'500+'`
function! lsc#diagnostics#count() abort
  let total = 0
  for file_path in keys(s:file_diagnostics)
    for line in values(lsc#diagnostics#forFile(file_path))
      let total += len(line)
    endfor
    if total > 500
      return string(total).'+'
    endif
  endfor
  return total
endfunction

" Finds all diagnostics and populates the quickfix list.
function! lsc#diagnostics#showInQuickFix() abort
  let all_diagnostics = []
  for file_path in keys(s:file_diagnostics)
    let bufnr = bufnr(file_path)
    if bufnr == -1
      let file_ref = {'filename': fnamemodify(file_path, ':.')}
    else
      let file_ref = {'bufnr': bufnr}
    endif
    call extend(all_diagnostics, s:ListItems(file_path, file_ref))
  endfor
  call sort(all_diagnostics, 'lsc#util#compareQuickFixItems')
  call setqflist(all_diagnostics)
  copen
endfunction

" Whether the location list has the most up to date diagnostics.
"
" Multiple events can cause the location list for a window to get updated. Track
" the currently held file and version for diagnostics and block updates if they
" are already current.
function! s:WindowIsCurrent(window_id, file_path, version) abort
  let window_info = getwininfo(a:window_id)[0]
  let tabnr = window_info.tabnr
  let winnr = window_info.winnr
  return gettabwinvar(tabnr, winnr, 'lsc_diagnostics_version', -1) == a:version
      \ && gettabwinvar(tabnr, winnr, 'lsc_diagnostics_file', '') == a:file_path
endfunction


" Remove the LSC controlled location list for the current window.
function! lsc#diagnostics#clear() abort
  call setloclist(0, [])
  unlet w:lsc_diagnostics_version
  unlet w:lsc_diagnostics_file
endfunction

" Finds the first diagnostic which is under the cursor on the current line. If
" no diagnostic is directly under the cursor returns the last seen diagnostic
" on this line.
function! lsc#diagnostics#underCursor() abort
  let file_diagnostics = lsc#diagnostics#forFile(expand('%:p'))
  let line = line('.')
  if !has_key(file_diagnostics, line)
    return {}
  endif
  let diagnostics = file_diagnostics[line]
  let col = col('.')
  let closest_diagnostic = {}
  let closest_distance = -1
  for diagnostic in diagnostics
    let range = diagnostic.ranges[0]
    let start = range[1]
    let end = range[1] + range[2]
    let distance = min([abs(start - col), abs(end - col)])
    if closest_distance < 0 || distance < closest_distance
      let closest_diagnostic = diagnostic
      let closest_distance = distance
    endif
  endfor
  return closest_diagnostic
endfunction
