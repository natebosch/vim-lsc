" Refresh highlight matches on all visible windows.
function! lsc#highlights#updateDisplayed() abort
  call lsc#util#winDo('call lsc#highlights#update()')
endfunction

" Refresh highlight matches in the current window.
function! lsc#highlights#update() abort
  call <SID>ClearHighlights()
  if !has_key(g:lsc_server_commands, &filetype)
    return
  endif
  for line in values(lsc#diagnostics#forFile(expand('%:p')))
    for diagnostic in line
      let match = matchaddpos(diagnostic.group, [diagnostic.range])
      call add(w:lsc_diagnostic_matches, match)
    endfor
  endfor
endfunction!

" Remove all highlighted matches in the current window.
function! s:ClearHighlights() abort
  if exists('w:lsc_diagnostic_matches')
    for current_match in w:lsc_diagnostic_matches
      silent! call matchdelete(current_match)
    endfor
  endif
  let w:lsc_diagnostic_matches = []
endfunction
