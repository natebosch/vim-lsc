function! lsc#params#textDocument() abort
  return {'textDocument': {'uri': lsc#uri#documentUri()}}
endfunction

function! lsc#params#documentPosition() abort
  return { 'textDocument': {'uri': lsc#uri#documentUri()},
      \ 'position': {
      \   'line': line('.') - 1,
      \   'character': lsc#util#currentChar() - 1
      \ }
      \}
endfunction
function! lsc#params#documentRange() abort
  return { 'textDocument': {'uri': lsc#uri#documentUri()},
      \ 'range': {
      \   'start': {
      \     'line': line('.') - 1,
      \     'character': lsc#util#currentChar() - 1,
      \    },
      \  'end': {'line': line('.') - 1, 'character': lsc#util#currentChar()}},
      \}
endfunction
