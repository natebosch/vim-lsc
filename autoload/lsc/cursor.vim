if !exists('s:initialized')
  let s:initialized = v:true
  let s:highlights_request = 0
  let s:pending = {}
endif

function! lsc#cursor#onMove() abort
  call lsc#cursor#showDiagnostic()
  call s:HighlightReferences(v:false)
endfunction

function! lsc#cursor#onWinLeave() abort
  call lsc#cursor#clean()
endfunction

function! lsc#cursor#onWinEnter() abort
  call s:HighlightReferences(v:false)
endfunction

function! lsc#cursor#insertEnter() abort
  call lsc#cursor#clean()
endfunction

function! lsc#cursor#showDiagnostic() abort
  let l:diagnostic = lsc#diagnostics#underCursor()
  if has_key(l:diagnostic, 'message')
    let l:max_width = &columns - 18
    let l:message = strtrans(l:diagnostic.message)
    if strdisplaywidth(l:message) > l:max_width
      let l:truncated = strcharpart(l:message, 0, l:max_width)
      " Trim by character until a satisfactory display width.
      while strdisplaywidth(l:truncated) > l:max_width
        let l:truncated = strcharpart(l:truncated, 0, strchars(l:truncated) - 1)
      endwhile
      echo l:truncated.'...'
    else
      echo l:message
    endif
  else
    echo ''
  endif
endfunction

function! lsc#cursor#onChangesFlushed() abort
  let mode = mode()
  if mode == 'n' || mode == 'no'
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
  let s:pending[&filetype] = v:true
  let s:highlights_request += 1
  let params = lsc#params#documentPosition()
  call lsc#server#call(&filetype, 'textDocument/documentHighlight', params,
      \ funcref('<SID>HandleHighlights',
      \ [s:highlights_request, getcurpos(), bufnr('%'), &filetype]))
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
  for reference in a:highlights
    let match = matchaddpos('lscReference', reference.ranges, -5)
    call add(w:lsc_reference_matches, match)
  endfor
endfunction

function! lsc#cursor#clean() abort
  let s:pending[&filetype] = v:false
  if exists('w:lsc_reference_matches')
    for current_match in w:lsc_reference_matches
      silent! call matchdelete(current_match)
    endfor
    unlet w:lsc_reference_matches
    unlet w:lsc_references
  endif
endfunction

" Returns the index of the reference the cursor is positioned in, or -1 if it is
" not in any reference.
function! lsc#cursor#isInReference(references) abort
  let line = line('.')
  let col = col('.')
  let idx = 0
  for reference in a:references
    for range in reference.ranges
      if line == range[0] && col >= range[1] && col < range[1] + range[2]
        return idx
      endif
    endfor
    let idx += 1
  endfor
  return -1
endfunction

function! s:ConvertReference(reference) abort
  return {'ranges': lsc#convert#rangeToHighlights(a:reference.range)}
endfunction

function! s:CompareRange(r1, r2) abort
  let line_1 = a:r1.ranges[0][0]
  let line_2 = a:r2.ranges[0][0]
  if line_1 != line_2 | return line_1 > line_2 ? 1 : -1 | endif
  let col_1 = a:r1.ranges[0][1]
  let col_2 = a:r2.ranges[0][1]
  return col_1 - col_2
endfunction
