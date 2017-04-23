" file path -> line number -> [diagnostic]
"
" Diagnostics are dictionaries with:
" 'group': The highlight group, like 'lscDiagnosticError'
" 'range': 1-based [start line, start column, length]
" 'message': The message to display
" 'type': Single letter representation of severity for location list
let s:file_diagnostics = {}

" Converts between an LSP diagnostic and the internal representation used for
" highlighting.
function! lsc#diagnostics#convert(diagnostic) abort
  let line = a:diagnostic.range.start.line + 1
  let character = a:diagnostic.range.start.character + 1
  " TODO won't work for multiline error
  let length = a:diagnostic.range.end.character + 1 - character
  let range = [line, character, length]
  let group = <SID>SeverityGroup(a:diagnostic.severity)
  let type = <SID>SeverityType(a:diagnostic.severity)
  return {'group': group, 'range': range,
      \ 'message': a:diagnostic.message, 'type': type}
endfunction

" Converts between an internal diagnostic and an item for the location list.
function! s:locationListItem(bufnr, diagnostic) abort
  return {'bufnr': a:bufnr,
      \ 'lnum': a:diagnostic.range[0], 'col': a:diagnostic.range[1],
      \ 'text': a:diagnostic.message, 'type': a:diagnostic.type}
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

function! lsc#diagnostics#setForFile(file_path, diagnostics) abort
  call map(a:diagnostics, 'lsc#diagnostics#convert(v:val)')
  let diagnostics_by_line = {}
  for diagnostic in a:diagnostics
    if !has_key(diagnostics_by_line, diagnostic.range[0])
      let diagnostics_by_line[diagnostic.range[0]] = []
    endif
    call add(diagnostics_by_line[diagnostic.range[0]], diagnostic)
  endfor
  let s:file_diagnostics[a:file_path] = diagnostics_by_line
  call lsc#util#winDo('call lsc#diagnostics#update("'.a:file_path.'")')
endfunction

" Updates highlighting and location list for the current window if it matches
" [file_path]
function! lsc#diagnostics#update(file_path) abort
  if a:file_path != expand('%:p') | return | endif
  call lsc#highlights#update()
  let bufnr = bufnr('%')
  let items = []
  for line in values(lsc#diagnostics#forFile(a:file_path))
    for diagnostic in line
      call add(items, s:locationListItem(bufnr, diagnostic))
    endfor
  endfor
  call setloclist(0, items)
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
    let range = diagnostic.range
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
