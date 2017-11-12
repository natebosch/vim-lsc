" Computes a simplistic diff between [old] and [new].
"
" Old and new text are lists of lines as returned from `getline(1, '$')`.
"
" Returns a dict with keys `range`, `rangeLength`, and `text` matching the LSP
" definition of `TextDocumentContentChangeEvent`.
function! lsc#diff#compute(old, new) abort
  let start = s:FirstDifference(a:old, a:new, v:false)

  if len(a:old) <= start[0]
    " This is an insert at end, shift it to before the last newline
    let start = [len(a:old) - 1, len(a:old[-1])]
    let end_inclusive = [-1, -1]
  else
    let old_trail = a:old[start[0]+1:]
    let new_trail = a:new[start[0]+1:]
    if start[1] < len(a:old[start[0]])
      let old_trail = [a:old[start[0]][start[1]:]] + old_trail
      let new_trail = [a:new[start[0]][start[1]:]] + new_trail
    endif
    let end_inclusive = s:FirstDifference(old_trail, new_trail, v:true)
  endif

  " End is exclusive, using positive offsets
  let end = [len(a:old) + end_inclusive[0],
      \ strlen(a:old[end_inclusive[0]]) + end_inclusive[1] + 1]

  let end_new = [len(a:new) + end_inclusive[0],
      \ strlen(a:new[end_inclusive[0]]) + end_inclusive[1] + 1]

  let text = s:Extract(a:new, start, end_new)

  return { 'range': s:Range(start[0], start[1], end[0], end[1]),
      \ 'rangeLength': s:Length(a:old, start[0], start[1], end[0], end[1]),
      \ 'text': text
      \}
endfunction

" Finds the [line, column] of the first character which is different between
" [old] and [new].
"
" If [rev] is [v:true] searchs backwards and returns negative offsets.
function! s:FirstDifference(old, new, rev) abort
  let length = min([len(a:old), len(a:new)])
  let line = 0
  while line < length
    let index = a:rev ? -1 * line - 1 : line
    let old_line = a:old[index]
    let new_line = a:new[index]
    if old_line !=# new_line
      let result = [index, s:StringDiffChar(old_line, new_line, a:rev)]
      return result
    endif
    let line += 1
  endwhile
  let index = a:rev ? -1 * line : line
  let character = a:rev ? -1 * len(a:old[line-1]) - 1 : 0
  return [index, character]
endfunction

" Finds the index of the first character which is different between [old] and
" [new].
"
" If [rev] is [v:true] searchs backwards and returns a negative offset.
function! s:StringDiffChar(old, new, rev) abort
  let length = min([strlen(a:old), strlen(a:new)])
  let character = 0
  while character < length
    let index = a:rev ? -1 * character - 1 : character
    if a:old[index:index] !=# a:new[index:index]
      return index
    endif
    let character += 1
  endwhile
  return a:rev ? -1 * character - 1 : character
endfunction

" Translate from arguments to named keys.
function! s:Range(startline, startcol, endline, endcol) abort
  return {'start': {'line': a:startline, 'character': a:startcol},
      \   'end': {'line': a:endline, 'character': a:endcol}}
endfunction

" Calculate the length of a range within [lines].
function! s:Length(lines, startline, startcol, endline, endcol) abort
  if a:startline == a:endline | return a:endcol - a:startcol | endif
  let length = len(a:lines[a:startline]) + 1 - a:startcol
  let current_line = a:startline + 1
  while current_line < a:endline
    let length += len(a:lines[current_line]) + 1 | " +1 for \n
    let current_line += 1
  endwhile
  let length += a:endcol
  return length
endfunction

function! s:Extract(lines, start, end) abort
  if a:start == a:end | return '' | endif
  if a:start[0] == a:end[0]
    return a:lines[a:start[0]][a:start[1]:a:end[1]-1]
  endif
  let result = a:lines[a:start[0]][a:start[1]:]."\n"
  for line in a:lines[a:start[0]+1:a:end[0]-1]
    let result .= line."\n"
  endfor
  if a:end[1] > 0
    let result .= a:lines[a:end[0]][:a:end[1]-1]
  endif
  return result
endfunction
