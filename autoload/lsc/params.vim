function! lsc#params#textDocument() abort
  return {'textDocument': {'uri': lsc#uri#documentUri()}}
endfunction

function! lsc#params#documentPosition() abort
  return { 'textDocument': {'uri': lsc#uri#documentUri()},
      \ 'position': {'line': line('.') - 1, 'character': col('.') - 1}
      \ }
endfunction

function! lsc#params#documentRange(usingRange) abort
  let l:mode = mode()
  let l:start = a:usingRange ? getpos("'<") : getpos('.')
  let l:end = a:usingRange ? getpos("'>") : getpos('.')
  " Fallback if range marks didn't exist
  let l:start = l:start[1] == 0 ? getpos('.') : l:start
  let l:end = l:end[1] == 0 ? getpos('.') : l:end
  return { 'textDocument': {'uri': lsc#uri#documentUri()},
      \ 'range': {
      \   'start': {'line': l:start[1] - 1, 'character': l:start[2] - 1},
      \   'end': {'line': l:end[1] - 1, 'character': l:end[2]}},
      \ }
endfunction
