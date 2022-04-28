if !exists('s:initialized')
  let s:initialized = v:true
  let s:highlights_request = 0
  let s:pending = {}
endif

function! lsc#cursor#onMove() abort
  call lsc#cursor#showDiagnostic()
  call s:HighlightReferences(v:false)
endfunction

function! lsc#cursor#onWinEnter() abort
  call s:HighlightReferences(v:false)
endfunction

function! lsc#cursor#showDiagnostic() abort
  if !get(g:, 'lsc_diagnostic_highlights', v:true) | return | endif
  let l:diagnostic = lsc#diagnostics#underCursor()
  if has_key(l:diagnostic, 'message')
    let l:max_width = &columns - 1 " Avoid edge of terminal
    let l:has_ruler = &ruler &&
        \ (&laststatus == 0 || (&laststatus == 1 && winnr('$') < 2))
    if l:has_ruler | let l:max_width -= 18 | endif
    if &showcmd | let l:max_width -= 11 | endif
    let l:message = strtrans(l:diagnostic.message)
    if strdisplaywidth(l:message) > l:max_width
      let l:max_width -= 1 " 1 character for ellipsis
      let l:truncated = strcharpart(l:message, 0, l:max_width)
      " Trim by character until a satisfactory display width.
      while strdisplaywidth(l:truncated) > l:max_width
        let l:truncated = strcharpart(l:truncated, 0, strchars(l:truncated) - 1)
      endwhile
      echo l:truncated."\u2026"
    else
      echo l:message
    endif
  else
    echo ''
  endif
endfunction

function! lsc#cursor#onChangesFlushed() abort
  let l:mode = mode()
  if l:mode ==# 'n' || l:mode ==# 'no'
    call s:HighlightReferences(v:true)
  endif
endfunction

function! s:HighlightReferences(force_in_highlight) abort
  if exists('g:lsc_reference_highlights') && !g:lsc_reference_highlights
    return
  endif
  if !s:CanHighlightReferences() | return | endif
  if !a:force_in_highlight &&
      \ exists('w:lsc_references') &&
      \ lsc#cursor#isInReference(w:lsc_references) >= 0
    return
  endif
  if has_key(s:pending, &filetype) && s:pending[&filetype]
    return
  endif
  let s:highlights_request += 1
  let l:params = lsc#params#documentPosition()
  " TODO handle multiple servers
  let l:server = lsc#server#forFileType(&filetype)[0]
  let s:pending[&filetype] = l:server.request('textDocument/documentHighlight',
      \ l:params, funcref('<SID>HandleHighlights',
      \   [s:highlights_request, getcurpos(), bufnr('%'), &filetype]))
endfunction

function! s:CanHighlightReferences() abort
  for l:server in lsc#server#current()
    if l:server.capabilities.referenceHighlights
      return v:true
    endif
  endfor
  return v:false
endfunction

function! s:HandleHighlights(request_number, old_pos, old_buf_nr,
    \ request_filetype, highlights) abort
  if !has_key(s:pending, a:request_filetype) || !s:pending[a:request_filetype]
    return
  endif
  let s:pending[a:request_filetype] = v:false
  if bufnr('%') != a:old_buf_nr | return | endif
  if a:request_number != s:highlights_request | return | endif
  call lsc#cursor#clean()
  if empty(a:highlights) | return | endif
  call map(a:highlights, {_, reference -> s:ConvertReference(reference)})
  call sort(a:highlights, function('<SID>CompareRange'))
  if lsc#cursor#isInReference(a:highlights) == -1
    if a:old_pos != getcurpos()
      call s:HighlightReferences(v:true)
    endif
    return
  endif

  let w:lsc_references = a:highlights
  let w:lsc_reference_matches = []
  for l:reference in a:highlights
    let l:match = matchaddpos('lscReference', l:reference.ranges, -5)
    call add(w:lsc_reference_matches, l:match)
  endfor
endfunction

function! lsc#cursor#clean() abort
  let s:pending[&filetype] = v:false
  if exists('w:lsc_reference_matches')
    for l:current_match in w:lsc_reference_matches
      silent! call matchdelete(l:current_match)
    endfor
    unlet w:lsc_reference_matches
    unlet w:lsc_references
  endif
endfunction

" Returns the index of the reference the cursor is positioned in, or -1 if it is
" not in any reference.
function! lsc#cursor#isInReference(references) abort
  let l:line = line('.')
  let l:col = col('.')
  let l:idx = 0
  for l:reference in a:references
    for l:range in l:reference.ranges
      if l:line == l:range[0]
          \ && l:col >= l:range[1]
          \ && l:col < l:range[1] + l:range[2]
        return l:idx
      endif
    endfor
    let l:idx += 1
  endfor
  return -1
endfunction

function! s:ConvertReference(reference) abort
  return {'ranges': lsc#convert#rangeToHighlights(a:reference.range)}
endfunction

function! s:CompareRange(r1, r2) abort
  let l:line_1 = a:r1.ranges[0][0]
  let l:line_2 = a:r2.ranges[0][0]
  if l:line_1 != l:line_2 | return l:line_1 > l:line_2 ? 1 : -1 | endif
  let l:col_1 = a:r1.ranges[0][1]
  let l:col_2 = a:r2.ranges[0][1]
  return l:col_1 - l:col_2
endfunction
