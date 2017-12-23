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
      call lsc#message#show('Actions ignored')
      return
    endif
    if type(a:result) != v:t_list || len(a:result) == 0
      call lsc#message#show('No actions available')
      return
    endif
    let choices = ['Choose an action:']
    let idx = 0
    while idx < len(a:result)
      call add(choices, string(idx+1).' - '.a:result[idx]['title'])
      let idx += 1
    endwhile
    let choice = inputlist(choices)
    if choice > 0
      call lsc#server#userCall('workspace/executeCommand',
          \ {'command': a:result[choice - 1]['command'],
          \ 'arguments': a:result[choice - 1]['arguments']},
          \ {_->0})
    endif
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

" Applies a workspace edit and returns `v:true` if it was successful.
function! lsc#edit#apply(params) abort
  if !exists('g:lsc_enable_apply_edit')
      \ || !g:lsc_enable_apply_edit
      \ || !has_key(a:params.edit, 'changes')
    return v:false
  endif
  let changes = a:params.edit.changes
  " Only applying changes in open files for now
  for uri in keys(changes)
    if lsc#uri#documentPath(uri) != expand('%:p')
      call lsc#message#error('Can only apply edits in the current buffer')
      return v:false
    endif
  endfor
  for [uri, edits] in items(changes)
    for edit in edits
      " Expect edit is in current buffer
      call s:Apply(edit)
    endfor
  endfor
  return v:true
endfunction

" Apply a `TextEdit` to the current buffer.
function! s:Apply(edit) abort
  let old_paste = &paste
  set paste
  if s:IsEmptyRange(a:edit.range)
    let command = printf('%dG%d|i%s',
        \ a:edit.range.start.line + 1,
        \ a:edit.range.start.character + 1,
        \ a:edit.newText
        \)
  else
    " `back` handles end-exclusive range
    let back = 'h'
    if a:edit.range.end.character == 0
      let back = 'k$'
    endif
    let command = printf('%dG%d|v%dG%d|%sc%s',
        \ a:edit.range.start.line + 1,
        \ a:edit.range.start.character + 1,
        \ a:edit.range.end.line + 1,
        \ a:edit.range.end.character + 1,
        \ back,
        \ a:edit.newText
        \)
  endif
  execute 'normal!' command
  let &paste = old_paste
endfunction

function! s:IsEmptyRange(range) abort
  return a:range.start.line == a:range.end.line &&
      \ a:range.start.character == a:range.end.character
endfunction
