" Computes a simplistic diff between [old] and [new].
"
" Returns a dict with keys `range`, `rangeLength`, and `text` matching the LSP
" definition of `TextDocumentContentChangeEvent`.
"
" Finds a single change between the common prefix, and common postfix.
function! lsc#diff#compute(old, new) abort
  let start = s:FirstDifference(a:old, a:new)
  if strlen(a:old) <= start
    let start = strlen(a:old)
    let end_inclusive = -1
  else
    let end_inclusive = s:LastDifference(a:old[start:], a:new[start:])
  endif

  " End is exclusive, using positive offsets
  let end = strlen(a:old) + end_inclusive + 1

  let end_new = strlen(a:new) + end_inclusive + 1

  let text = start == end_new ? '' : a:new[start:end_new-1]

  return { 'range': s:Range(a:old, start, end),
      \ 'rangeLength': end - start,
      \ 'text': text
      \}
endfunction

function! s:FirstDifference(old, new) abort
  let length = min([strlen(a:old), strlen(a:new)])
  let i = 0
  while i < length
    if a:old[i:i] !=# a:new[i:i] | break | endif
    let i += 1
  endwhile
  return i
endfunction

function! s:LastDifference(old, new) abort
  let length = min([strlen(a:old), strlen(a:new)])
  let i = -1
  while i >= -1 * length
    if a:old[i:i] !=# a:new[i:i] | break | endif
    let i -= 1
  endwhile
  return i
endfunction

function! s:OffsetToPosition(text, offset) abort
  if a:offset == 0 | return [0, 0] | endif
  let prefix = a:text[:a:offset - 1]
  let parts = split(prefix, "\n")
  if prefix[-1:-1] == "\n"
    return [len(parts), 0]
  else
    return [len(parts) - 1, len(parts[-1])]
  endif
endfunction

function! s:Range(text, start, end) abort
  let start_range = s:OffsetToPosition(a:text, a:start)
  let end_range = s:OffsetToPosition(a:text, a:end)
  return {'start': {'line': start_range[0], 'character': start_range[1]},
      \   'end': {'line': end_range[0], 'character': end_range[1]}}
endfunction
