if !exists('s:initialized')
  let s:find_actions_id = 1
  let s:initialized = v:true
endif

function! lsc#edit#findCodeActions() abort
  call lsc#file#flushChanges()
  let s:find_actions_id += 1
  let old_pos = getcurpos()
  let find_actions_id = s:find_actions_id
  function! SelectAction(result) closure abort
    if !s:isFindActionsValid(old_pos, find_actions_id)
      echom 'CodeActions skipped'
      return
    endif
    if type(a:result) == v:t_none ||
        \ (type(a:result) == v:t_list && len(a:result) == 0)
      call lsc#message#show('No actions available')
    endif
    for action in a:result
      echom 'I found an action: '.action['title']
    endfor
  endfunction
  call lsc#server#userCall('textDocument/codeAction',
      \ s:TextDocumentRangeParams(), function('SelectAction'))
endfunction

" TODO - handle visual selection for range
function! s:TextDocumentRangeParams() abort
  return { 'textDocument': {'uri': lsc#uri#documentUri()},
      \ 'range': {
      \   'start': {'line': line('.') - 1, 'character': col('.') - 1},
      \   'end': {'line': line('.') - 1, 'character': col('.')}},
      \ 'context': {'diagnostics': []}
      \}
endfunction

function! s:isFindActionsValid(old_pos, find_actions_id) abort
  return a:find_actions_id == s:find_actions_id &&
      \ a:old_pos == getcurpos()
endfunction
