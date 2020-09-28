if !exists('s:file_diagnostics')
  " file path -> Diagnostics
  "
  " Diagnostics are dictionaries with:
  " 'Highlights()': Highlight groups and ranges
  " 'ByLine()': Nested dictionaries with the structure:
  "     { line: [{
  "         message: Human readable message with code
  "         range: LSP Range object
  "         severity: String label for severity
  "       }]
  "     }
  " 'ListItems()': QuickFix or Location list items
  let s:file_diagnostics = {}
endif

function! lsc#diagnostics#clean(filetype) abort
  for buffer in getbufinfo({'bufloaded': v:true})
    if getbufvar(buffer.bufnr, '&filetype') != a:filetype | continue | endif
    call lsc#diagnostics#setForFile(lsc#file#normalize(buffer.name), [])
  endfor
endfunction

" Finds the highlight group given a diagnostic severity level
function! s:SeverityGroup(severity) abort
  return 'lscDiagnostic'.s:SeverityLabel(a:severity)
endfunction

" Finds the human readable label for a diagnsotic severity level
function! s:SeverityLabel(severity) abort
    if a:severity == 1 | return 'Error'
    elseif a:severity == 2 | return 'Warning'
    elseif a:severity == 3 | return 'Info'
    elseif a:severity == 4 | return 'Hint'
    else | return ''
    endif
endfunction

" Finds the location list type given a diagnostic severity level
function! s:SeverityType(severity) abort
    if a:severity == 1 | return 'E'
    elseif a:severity == 2 | return 'W'
    elseif a:severity == 3 | return 'I'
    elseif a:severity == 4 | return 'H'
    else | return ''
    endif
endfunction

function! s:DiagnosticMessage(diagnostic) abort
  let l:message = a:diagnostic.message
  if has_key(a:diagnostic, 'code')
    let l:message = message.' ['.a:diagnostic.code.']'
  endif
  return l:message
endfunction

function! lsc#diagnostics#forFile(file_path) abort
  if !has_key(s:file_diagnostics, a:file_path)
    return s:EmptyDiagnostics()
  endif
  return s:file_diagnostics[a:file_path]
endfunction

function! lsc#diagnostics#setForFile(file_path, diagnostics) abort
  if exists('g:lsc_enable_diagnostics') && !g:lsc_enable_diagnostics
    return
  endif
  if empty(a:diagnostics) && !has_key(s:file_diagnostics, a:file_path)
    return
  endif
  if !empty(a:diagnostics)
    if has_key(s:file_diagnostics, a:file_path) &&
        \ s:file_diagnostics[a:file_path].lsp_diagnostics == a:diagnostics
      return
    endif
    let s:file_diagnostics[a:file_path] =
        \ s:Diagnostics(a:file_path, a:diagnostics)
  else
    unlet s:file_diagnostics[a:file_path]
  endif
  call s:UpdateWindowStates(a:file_path)
  call lsc#highlights#updateDisplayed()
  call s:UpdateQuickFix()
  if exists('#User#LSCDiagnosticsChange')
    doautocmd <nomodeline> User LSCDiagnosticsChange
  endif
  if(a:file_path ==# lsc#file#fullPath())
    call lsc#cursor#showDiagnostic()
  endif
endfunction

" Updates location list for all windows showing [file_path].
"
" If a window already has a location list which aren't LSC owned diagnostics
" the list is left as is. If there is no location list or the list is LSC owned
" diagnostics, check if it is stale and update it to the new diagnostics.
function! s:UpdateWindowStates(file_path) abort
  if lsc#file#bufnr(a:file_path) == -1 | return | endif
  let l:diagnostics = lsc#diagnostics#forFile(a:file_path)
  for l:window_id in win_findbuf(lsc#file#bufnr(a:file_path))
    call s:UpdateWindowState(l:window_id, l:diagnostics)
  endfor
endfunction

function! lsc#diagnostics#updateCurrentWindow() abort
  let l:diagnostics = lsc#diagnostics#forFile(lsc#file#fullPath())
  if exists('w:lsc_diagnostics') && w:lsc_diagnostics is l:diagnostics
    return
  endif
  call s:UpdateWindowState(win_getid(), l:diagnostics)
endfunction

function! s:UpdateWindowState(window_id, diagnostics) abort
  call settabwinvar(0, a:window_id, 'lsc_diagnostics', a:diagnostics)
  let l:list_info = getloclist(a:window_id, {'changedtick': 1})
  let l:new_list = get(l:list_info, 'changedtick', 0) == 0
  if l:new_list
    call s:CreateLocationList(a:window_id, a:diagnostics.ListItems())
  else
    call s:UpdateLocationList(a:window_id, a:diagnostics.ListItems())
  endif
endfunction

function! s:CreateLocationList(window_id, items) abort
  call setloclist(a:window_id, [], ' ', {
      \ 'title': 'LSC Diagnostics',
      \ 'items': a:items,
      \})
  let l:new_id = getloclist(a:window_id, {'id': 0}).id
  call settabwinvar(0, a:window_id, 'lsc_location_list_id', l:new_id)
endfunction

" Update an existing location list to contain new items.
"
" If the LSC diagnostics location list is not reachable with `lolder` or
" `lhistory` the update will silently fail.
function! s:UpdateLocationList(window_id, items) abort
  let l:list_id = gettabwinvar(0, a:window_id, 'lsc_location_list_id', -1)
  call setloclist(a:window_id, [], 'r', {
      \ 'id': l:list_id,
      \ 'items': a:items,
      \})
endfunction

function! lsc#diagnostics#showLocationList() abort
  let l:window_id = win_getid()
  if &filetype ==# 'qf'
    let l:list_window = get(getloclist(0, {'filewinid': 0}), 'filewinid', 0)
    if l:list_window != 0
      let l:window_id = l:list_window
    endif
  endif
  let l:list_id = gettabwinvar(0, l:window_id, 'lsc_location_list_id', -1)
  if l:list_id != -1 && !s:SurfaceLocationList(l:list_id)
    let l:path = lsc#file#normalize(bufname(winbufnr(l:window_id)))
    let l:items = lsc#diagnostics#forFile(l:path).ListItems()
    call s:CreateLocationList(l:window_id, l:items)
  endif
  lopen
endfunction

" If the LSC maintained location list exists in the location list stack, switch
" to it and return true, otherwise return false.
function! s:SurfaceLocationList(list_id) abort
  let l:list_info = getloclist(0, {'nr': 0, 'id': a:list_id})
  let l:nr = get(l:list_info, 'nr', -1)
  if l:nr <= 0 | return v:false | endif

  let l:diff = getloclist(0, {'nr': 0}).nr - l:nr
  if l:diff == 0
    " already there
  elseif l:diff > 0
    execute 'lolder '.string(l:diff)
  else
    execute 'lnewer '.string(abs(l:diff))
  endif
  return v:true
endfunction

" Returns the total number of diagnostics in all files.
"
" If the number grows very large returns instead a String like `'500+'`
function! lsc#diagnostics#count() abort
  let l:total = 0
  for l:diagnostics in values(s:file_diagnostics)
    let l:total += len(l:diagnostics.lsp_diagnostics)
    if l:total > 500
      return string(l:total).'+'
    endif
  endfor
  return l:total
endfunction

" Finds all diagnostics and populates the quickfix list.
function! lsc#diagnostics#showInQuickFix() abort
  call setqflist([], ' ', {
      \ 'items': s:AllDiagnostics(),
      \ 'title': 'LSC Diagnostics',
      \ 'context': {'client': 'LSC'}
      \})
  copen
endfunction

function! s:UpdateQuickFix() abort
  let l:current = getqflist({'context': 1, 'idx': 1, 'items': 1})
  let l:context = get(l:current, 'context', 0)
  if type(l:context) != type({}) ||
      \ !has_key(l:context, 'client') ||
      \ l:context.client !=# 'LSC'
    return
  endif
  let l:new_list = {'items': s:AllDiagnostics()}
  if len(l:new_list.items) > 0 &&
      \ l:current.idx > 0 &&
      \ len(l:current.items) >= l:current.idx
    let l:prev_item = l:current.items[l:current.idx - 1]
    let l:new_list.idx = s:FindNearest(l:prev_item, l:new_list.items)
  endif
  call setqflist([], 'r', l:new_list)
endfunction

function! s:FindNearest(prev, items) abort
  let l:idx = 1
  for l:item in a:items
    if lsc#util#compareQuickFixItems(l:item, a:prev) >= 0
      return l:idx
    endif
    let l:idx += 1
  endfor
  return l:idx - 1
endfunction

function! s:AllDiagnostics() abort
  let l:all_diagnostics = []
  let l:files = sort(keys(s:file_diagnostics), function('lsc#file#compare'))
  for l:file_path in l:files
    let l:diagnostics = s:file_diagnostics[l:file_path]
    call extend(l:all_diagnostics, l:diagnostics.ListItems())
    if len(l:all_diagnostics) >= 500
      break
    endif
  endfor
  return l:all_diagnostics
endfunction

" Clear the LSC controlled location list for the current window.
function! lsc#diagnostics#clear() abort
  if !empty(w:lsc_diagnostics.lsp_diagnostics)
    call s:UpdateLocationList(win_getid(), [])
  endif
  unlet w:lsc_diagnostics
endfunction

" Finds the first diagnostic which is under the cursor on the current line. If
" no diagnostic is directly under the cursor returns the last seen diagnostic
" on this line.
function! lsc#diagnostics#underCursor() abort
  let l:file_diagnostics = lsc#diagnostics#forFile(lsc#file#fullPath()).ByLine()
  let l:line = line('.')
  if !has_key(l:file_diagnostics, l:line)
    if l:line != line('$') | return {} | endif
    " Find a diagnostic reported after the end of the file
    for l:diagnostic_line in keys(l:file_diagnostics)
      if l:diagnostic_line > l:line
        return l:file_diagnostics[l:diagnostic_line][0]
      endif
    endfor
    return {}
  endif
  let l:diagnostics = l:file_diagnostics[l:line]
  let l:col = col('.')
  let l:closest_diagnostic = {}
  let l:closest_distance = -1
  let l:closest_is_within = v:false
  for l:diagnostic in l:file_diagnostics[l:line]
    let l:range = l:diagnostic.range
    let l:is_within = l:range.start.character < l:col &&
        \ (l:range.end.line >= l:line || l:range.end.character > l:col)
    if l:closest_is_within && !l:is_within
      continue
    endif
    let l:distance = abs(l:range.start.character - l:col)
    if l:closest_distance < 0 || l:distance < l:closest_distance
      let l:closest_diagnostic = l:diagnostic
      let l:closest_distance = l:distance
      let l:closest_is_within = l:is_within
    endif
  endfor
  return l:closest_diagnostic
endfunction

" Returns the original LSP representation of diagnostics on a zero-indexed line.
function! lsc#diagnostics#forLine(file, line) abort
  let l:result = []
  for l:diagnostic in lsc#diagnostics#forFile(a:file).lsp_diagnostics
    if l:diagnostic.range.start.line <= a:line &&
        \ l:diagnostic.range.end.line >= a:line
      call add(l:result, l:diagnostic)
    endif
  endfor
  return l:result
endfunction

function! lsc#diagnostics#echoForLine() abort
  let l:file_diagnostics = lsc#diagnostics#forFile(lsc#file#fullPath()).ByLine()
  let l:line = line('.')
  if !has_key(l:file_diagnostics, l:line)
    echo 'No diagnostics'
    return
  endif
  let l:diagnostics = l:file_diagnostics[l:line]
  for l:diagnostic in l:diagnostics
    let l:label = '['.l:diagnostic.severity.']'
    if stridx(l:diagnostic.message, "\n") >= 0
      echo l:label
      echo l:diagnostic.message
    else
      echo l:label.': '.l:diagnostic.message
    endif
  endfor
endfunction

function! s:Diagnostics(file_path, lsp_diagnostics) abort
  let l:diagnostics = {
      \ 'file_path': a:file_path,
      \ 'lsp_diagnostics': a:lsp_diagnostics,
      \}
  function! l:diagnostics.Highlights() abort
    if !has_key(self, '_highlights')
      let self._highlights = []
      for l:diagnostic in self.lsp_diagnostics
        call add(self._highlights, {
            \ 'group': s:SeverityGroup(l:diagnostic.severity),
            \ 'ranges': lsc#convert#rangeToHighlights(l:diagnostic.range),
            \})
      endfor
    endif
    return self._highlights
  endfunction
  function! l:diagnostics.ListItems() abort
    if !has_key(self, '_list_items')
      let self._list_items = []
      let l:bufnr = lsc#file#bufnr(self.file_path)
      if l:bufnr == -1
        let l:file_ref = {'filename': fnamemodify(self.file_path, ':.')}
      else
        let l:file_ref = {'bufnr': l:bufnr}
      endif
      for l:diagnostic in self.lsp_diagnostics
        let l:item = {
            \ 'lnum': l:diagnostic.range.start.line + 1,
            \ 'col': l:diagnostic.range.start.character + 1,
            \ 'text': s:DiagnosticMessage(l:diagnostic),
            \ 'type': s:SeverityType(l:diagnostic.severity)
            \}
        call extend(l:item, l:file_ref)
        call add(self._list_items, l:item)
      endfor
      call sort(self._list_items, 'lsc#util#compareQuickFixItems')
    endif
    return self._list_items
  endfunction
  function! l:diagnostics.ByLine() abort
    if !has_key(self, '_by_line')
      let self._by_line = {}
      for l:diagnostic in self.lsp_diagnostics
        let l:start_line = string(l:diagnostic.range.start.line + 1)
        if !has_key(self._by_line, l:start_line)
          let l:line = []
          let self._by_line[l:start_line] = l:line
        else
          let l:line = self._by_line[l:start_line]
        endif
        let l:simple = {
            \ 'message': s:DiagnosticMessage(l:diagnostic),
            \ 'range': l:diagnostic.range,
            \ 'severity': s:SeverityLabel(l:diagnostic.severity),
            \}
        call add(l:line, l:simple)
      endfor
      for l:line in values(self._by_line)
        call sort(l:line, function('<SID>CompareRanges'))
      endfor
    endif
    return self._by_line
  endfunction
  return l:diagnostics
endfunction

function! s:EmptyDiagnostics() abort
  if !exists('s:empty_diagnostics')
    let s:empty_diagnostics = {'lsp_diagnostics': []}
    function! s:empty_diagnostics.Highlights() abort
      return []
    endfunction
    function! s:empty_diagnostics.ListItems() abort
      return []
    endfunction
    function! s:empty_diagnostics.ByLine() abort
      return {}
    endfunction
  endif
  return s:empty_diagnostics
endfunction

" Compare the ranges of 2 diagnostics that start on the same line
function! s:CompareRanges(d1, d2) abort
  if a:d1.range.start.character != a:d2.range.start.character
    return a:d1.range.start.character - a:d2.range.start.character
  endif
  if a:d1.range.end.line != a:d2.range.end.line
    return a:d1.range.end.line - a:d2.range.end.line
  endif
  return a:d1.range.end.character - a:d2.range.end.character
endfunction
