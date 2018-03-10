if !exists('s:initialized')
  let s:initialized = v:true
  let s:highlights_pending = v:false
  let s:highlights_request = 0
  let s:highlight_support = {}
endif

function! lsc#cursor#onMove() abort
  call s:ShowDiagnostic()
  call s:HighlightReferences()
endfunction

function! lsc#cursor#onWinLeave() abort
  "TODO - Clear matches but don't forget them - if nothing changes when we
  "reenter they should still be valid
  call lsc#cursor#clearReferenceHighlights()
endfunction

function! lsc#cursor#onWinEnter() abort
  "TODO - Recreate matches if we have them, or call if we don't
endfunction

function! lsc#cursor#onChange() abort
  "TODO -  Reload references? highlights might be wrong...
  "force even if in a highlight
endfunction

function! lsc#cursor#insertEnter() abort
  call lsc#cursor#clearReferenceHighlights()
endfunction

function! lsc#cursor#enableReferenceHighlights(filetype)
  let s:highlight_support[a:filetype] = v:true
endfunction

function! s:ShowDiagnostic() abort
  let diagnostic = lsc#diagnostics#underCursor()
  if has_key(diagnostic, 'message')
    let max_width = &columns - 18
    let message = substitute(diagnostic.message, '\n', '\\n', 'g')
    if len(message) > max_width
      echo message[:max_width].'...'
    else
      echo message
    endif
  else
    echo ''
  endif
endfunction

function! s:HighlightReferences() abort
  if exists('g:lsc_reference_highlights') && !g:lsc_reference_highlights
    return
  endif
  if !has_key(s:highlight_support, &filetype) | return | endif
  if exists('w:lsc_reference_highlights') &&
      \ s:InHighlight(w:lsc_reference_highlights)
    return
  endif
  if s:highlights_pending | return | endif
  let s:highlights_pending = v:true
  let s:highlights_request += 1
  let params = { 'textDocument': {'uri': lsc#uri#documentUri()},
      \ 'position': {'line': line('.') - 1, 'character': col('.') - 1}
      \ }
  call lsc#server#call(&filetype, 'textDocument/documentHighlight', params,
      \ funcref('<SID>HandleHighlights', [s:highlights_request, getcurpos()]))
endfunction

function! s:HandleHighlights(request_number, old_pos, highlights) abort
  "TODO - What if we're in the wrong buffer?
  if !s:highlights_pending | return | endif
  let s:highlights_pending = v:false
  if a:request_number != s:highlights_request | return | endif
  call lsc#cursor#clearReferenceHighlights()
  if empty(a:highlights) | return | endif
  call map(a:highlights, {_, reference -> s:ConvertReference(reference)})
  if !s:InHighlight(a:highlights)
    if a:old_pos != getcurpos()
      call s:HighlightReferences()
    endif
    return
  endif

  let w:lsc_reference_highlights = a:highlights
  let w:lsc_reference_matches = []
  for reference in a:highlights
    let match = matchaddpos('lscReference', reference.ranges, -5)
    call add(w:lsc_reference_matches, match)
  endfor
endfunction

function! lsc#cursor#clearReferenceHighlights() abort
  let s:highlights_pending = v:false
  if exists('w:lsc_reference_matches')
    for current_match in w:lsc_reference_matches
      silent! call matchdelete(current_match)
    endfor
    unlet w:lsc_reference_matches
    unlet w:lsc_reference_highlights
  endif
endfunction

function! lsc#cursor#clean() abort
  " TODO: Needs to be specific to the server
  let s:highlights_pending = v:false
endfunction

function! s:InHighlight(highlights) abort
  let line = line('.')
  let col = col('.')
  for reference in a:highlights
    for range in reference.ranges
      if line == range[0] && col >= range[1] && col < range[1] + range[2]
        return v:true
      endif
    endfor
  endfor
  return v:false
endfunction

function! s:ConvertReference(reference) abort
  return {'ranges': lsc#convert#rangeToHighlights(a:reference.range)}
endfunction
