" Refresh highlight matches on windows open for [bufnr].
function! lsc#highlights#updateDisplayed(bufnr) abort
  for l:window_id in win_findbuf(a:bufnr)
    call win_execute(l:window_id, 'call lsc#highlights#update()')
  endfor
endfunction

" Refresh highlight matches in the current window.
function! lsc#highlights#update() abort
  if s:CurrentWindowIsFresh() | return | endif
  call lsc#highlights#clear()
  if &diff | return | endif
  for l:highlight in lsc#diagnostics#forFile(lsc#file#fullPath()).Highlights()
    let l:priority = -1 * l:highlight.severity
    let l:group = l:highlight.group
    if l:highlight.ranges[0][0] > line('$')
      " Diagnostic starts after end of file
      let l:match = matchadd(l:group, '\%'.line('$').'l$', l:priority)
    elseif len(l:highlight.ranges) == 1 &&
        \ l:highlight.ranges[0][1] > len(getline(l:highlight.ranges[0][0]))
      " Diagnostic starts after end of line
      let l:line_range = '\%'.l:highlight.ranges[0][0].'l$'
      let l:match = matchadd(l:group, l:line_range, l:priority)
    else
      let l:match = matchaddpos(l:group, l:highlight.ranges, l:priority)
    endif
    call add(w:lsc_diagnostic_matches, l:match)
  endfor
  call s:MarkCurrentWindowFresh()
endfunction

" Remove all highlighted matches in the current window.
function! lsc#highlights#clear() abort
  if exists('w:lsc_diagnostic_matches')
    for l:current_match in w:lsc_diagnostic_matches
      silent! call matchdelete(l:current_match)
    endfor
  endif
  let w:lsc_diagnostic_matches = []
  if exists('w:lsc_highlights_source')
    unlet w:lsc_highlights_source
  endif
endfunction

" Whether the diagnostic highlights for the current window are up to date.
function! s:CurrentWindowIsFresh() abort
  if !exists('w:lsc_diagnostics') | return v:true | endif
  if !exists('w:lsc_highlights_source') | return v:false | endif
  return w:lsc_highlights_source is w:lsc_diagnostics
endfunction

function! s:MarkCurrentWindowFresh() abort
  let w:lsc_highlight_source = w:lsc_diagnostics
endfunction
