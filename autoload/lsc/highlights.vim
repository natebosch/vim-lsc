" Refresh highlight matches on all visible windows.
function! lsc#highlights#updateDisplayed() abort
  if s:DeferForSelect() | return | endif
  call lsc#util#winDo('call lsc#highlights#update()')
endfunction

" Refresh highlight matches in the current window.
function! lsc#highlights#update() abort
  call lsc#highlights#clear()
  if !has_key(g:lsc_server_commands, &filetype) || &diff
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
function! lsc#highlights#clear() abort
  if exists('w:lsc_diagnostic_matches')
    for current_match in w:lsc_diagnostic_matches
      silent! call matchdelete(current_match)
    endfor
  endif
  let w:lsc_diagnostic_matches = []
endfunction

" If vim is in select mode return true and attempt to schedule an update to
" highlights for after returning to normal mode. If vim enters insert mode the
" text will be changed and highlights will update anyway.
function! s:DeferForSelect() abort
  let mode = mode()
  if mode == 's' || mode == 'S' || mode == '\<c-s>'
    call lsc#util#once('CursorHold,CursorMoved',
        \ function('lsc#highlights#updateDisplayed'))
    return v:true
  endif
  return v:false
endfunction
