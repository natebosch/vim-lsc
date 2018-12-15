if !exists('s:initialized')
  let s:initialized = v:true
  let s:highlights_request = 0
  let s:highlight_support = {}
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

function! lsc#cursor#enableReferenceHighlights(filetype)
  let s:highlight_support[a:filetype] = v:true
endfunction

" Given a single-line string, returns a potentially multi-line string that
" fits within the given maximum width.
" Adapted from https://vi.stackexchange.com/a/4930
function! WrapText(text, width)
  let l:height = 1
  let l:line = ''
  let l:ret  = ''
  for word in split(a:text)
    if len(l:line) + len(word) + 1 > a:width
      if len(l:ret)
        let l:ret .= "\n"
        let l:height += 1
      endif
      let l:ret .=  l:line
      let l:line = ''
    endif
    if len (l:line)
      let l:line .= ' '
    endif
    let l:line .= strtrans(word)
  endfor
  let l:ret .= "\n" . l:line
  return {"message": l:ret, "height": l:height}
endfunction

" Given a message substring and a base {message:string,height:number}
" dictionary, returns a new dictionary with the line wrapped to the maximum
" editor column width.
function! AddLine(message, fromIdx, toIdx, base) abort
  let l:max_width = &columns - 5
  let l:length = a:toIdx - a:fromIdx
  let l:line = strcharpart(a:message, a:fromIdx, l:length)
  if strdisplaywidth(l:line) > l:max_width
    " Line doesn't fit within the editor column width so we wrap it.
    let l:wrapped = WrapText(l:line, l:max_width)
    let l:transformed = TransformMessage(l:wrapped["message"], 0)
    let l:newMessage = l:transformed["message"] . a:base["message"]
    let l:newHeight = l:transformed["height"] + a:base["height"]
    return { "message": l:newMessage, "height": l:newHeight }
  else
    let l:newMessage = strtrans(l:line) . "\n" . a:base["message"]
    let l:newHeight = 1 + a:base["height"]
    return { "message": l:newMessage, "height": l:newHeight }
  endif
endfunction

" Given a multi-line string where lines exceed the editor width,
" returns a new dictionary {message:string,height:number} with
" a new message that has been line wrapped to display within the
" editor width and the new length of the message.
function! TransformMessage(message, fromIdx) abort
  let l:newlineIdx = stridx(a:message, "\n", a:fromIdx)
  if l:newlineIdx < 0
    let l:toIdx = strchars(a:message)
    let l:base = {"message": "", "height": 1}
    return AddLine(a:message, a:fromIdx, l:toIdx, l:base)
  else
    let l:base = TransformMessage(a:message, l:newlineIdx + 1)
    return AddLine(a:message, a:fromIdx, l:newlineIdx, l:base)
  endif
endfunction

function! lsc#cursor#showDiagnostic() abort
  let l:diagnostic = lsc#diagnostics#underCursor()
  if has_key(l:diagnostic, 'message')
    let l:result = TransformMessage(l:diagnostic.message, 0)
    let &cmdheight = l:result["height"]
    echo l:result["message"]
  else
    let &cmdheight = 1
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
  if !has_key(s:highlight_support, &filetype) | return | endif
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
  let params = { 'textDocument': {'uri': lsc#uri#documentUri()},
      \ 'position': {'line': line('.') - 1, 'character': col('.') - 1}
      \ }
  call lsc#server#call(&filetype, 'textDocument/documentHighlight', params,
      \ funcref('<SID>HandleHighlights',
      \ [s:highlights_request, getcurpos(), bufnr('%'), &filetype]))
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
