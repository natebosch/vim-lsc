function! lsc#params#textDocument() abort
  return {'textDocument': {'uri': lsc#uri#documentUri()}}
endfunction

if exists('*charcol')
  function! lsc#params#documentPosition() abort
    return { 'textDocument': {'uri': lsc#uri#documentUri()},
        \ 'position': {'line': line('.') - 1, 'character': charcol('.') - 1}
        \ }
  endfunction
  function! lsc#params#documentRange() abort
    return { 'textDocument': {'uri': lsc#uri#documentUri()},
        \ 'range': {
          \   'start': {'line': line('.') - 1, 'character': charcol('.') - 1},
          \   'end': {'line': line('.') - 1, 'character': charcol('.')}},
          \ }
  endfunction
else
  " TODO - this is broken following multibyte characters.
  function! lsc#params#documentPosition() abort
    return { 'textDocument': {'uri': lsc#uri#documentUri()},
        \ 'position': {'line': line('.') - 1, 'character': col('.') - 1}
        \ }
  endfunction
  function! lsc#params#documentRange() abort
    return { 'textDocument': {'uri': lsc#uri#documentUri()},
        \ 'range': {
          \   'start': {'line': line('.') - 1, 'character': col('.') - 1},
          \   'end': {'line': line('.') - 1, 'character': col('.')}},
          \ }
  endfunction
endif
