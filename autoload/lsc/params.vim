function! lsc#params#textDocument(...) abort
  if a:0 >= 1
    let file_path = a:1
  else
    let file_path = expand('%:p')
  endif
  return {'textDocument': {'uri': lsc#uri#documentUri(file_path)}}
endfunction

function! lsc#params#documentPosition() abort
  return { 'textDocument': {'uri': lsc#uri#documentUri()},
      \ 'position': {'line': line('.') - 1, 'character': col('.') - 1}
      \ }
endfunction
