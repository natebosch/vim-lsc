" Refresh highlight matches on all visible windows.
function! lsc#highlights#updateDisplayed() abort
  if s:DeferForMode() | return | endif
  call lsc#util#winDo('call lsc#highlights#updateIfActive()')
endfunction

function! lsc#highlights#updateIfActive() abort
  if !has_key(g:lsc_servers_by_filetype, &filetype) | return | endif
  call lsc#highlights#update()
endfunction

" Refresh highlight matches in the current window.
function! lsc#highlights#update() abort
  if s:CurrentWindowIsFresh() | return | endif
  call lsc#highlights#clear()
  if &diff | return | endif
  for line in values(lsc#diagnostics#forFile(lsc#file#fullPath()))
    for diagnostic in line
      let match = matchaddpos(diagnostic.group, diagnostic.ranges, -1)
      call add(w:lsc_diagnostic_matches, match)
    endfor
  endfor
  call s:MarkCurrentWindowFresh()
endfunction

" Remove all highlighted matches in the current window.
function! lsc#highlights#clear() abort
  if exists('w:lsc_diagnostic_matches')
    for current_match in w:lsc_diagnostic_matches
      silent! call matchdelete(current_match)
    endfor
  endif
  let w:lsc_diagnostic_matches = []
  if exists('w:lsc_highlights_version')
    unlet w:lsc_highlights_version
  endif
endfunction

" If vim is in select or visual mode return true and attempt to schedule an
" update to highlights for after returning to normal mode. If vim enters insert
" mode the text will be changed and highlights will update anyway.
function! s:DeferForMode() abort
  let mode = mode()
  if mode == 's' || mode == 'S' || mode == "\<c-s>" ||
      \ mode == 'v' || mode == 'V' || mode == "\<c-v>"
    call lsc#util#once('CursorHold,CursorMoved',
        \ function('lsc#highlights#updateDisplayed'))
    return v:true
  endif
  return v:false
endfunction

" Whether the diagnostic highlights for the current window are up to date.
function! s:CurrentWindowIsFresh() abort
  if !exists('w:lsc_diagnostics_version') | return v:true | endif
  if !exists('w:lsc_highlights_version') | return v:false | endif
  return w:lsc_highlights_version == w:lsc_diagnostics_version &&
      \ w:lsc_highlights_file == w:lsc_diagnostics_file
endfunction

function! s:MarkCurrentWindowFresh() abort
  let w:lsc_highlights_version = w:lsc_diagnostics_version
  let w:lsc_highlights_file = w:lsc_diagnostics_file
endfunction
