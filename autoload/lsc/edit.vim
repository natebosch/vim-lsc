function! lsc#edit#findCodeActions(...) abort
  if a:0 > 0
    let ActionFilter = a:1
  else
    let ActionFilter = function("<SID>ActionMenu")
  endif
  call lsc#file#flushChanges()
  call lsc#server#userCall('textDocument/codeAction',
      \ s:TextDocumentRangeParams(),
      \ lsc#util#gateResult('CodeActions', function('<SID>SelectAction'),
      \     v:null, [ActionFilter]))
endfunction

function! s:SelectAction(result, action_filter) abort
  if type(a:result) != v:t_list || len(a:result) == 0
    call lsc#message#show('No actions available')
    return
  endif
  let choice = a:action_filter(a:result)
  if type(choice) == v:t_dict
    call lsc#server#userCall('workspace/executeCommand',
        \ {'command': choice['command'],
        \ 'arguments': choice['arguments']},
        \ {_->0})
  endif
endfunction

" TODO - handle visual selection for range
function! s:TextDocumentRangeParams() abort
  return { 'textDocument': {'uri': lsc#uri#documentUri()},
      \ 'range': {
      \   'start': {'line': line('.') - 1, 'character': col('.') - 1},
      \   'end': {'line': line('.') - 1, 'character': col('.')}},
      \ 'context': {'diagnostics':
      \    lsc#diagnostics#forLine(expand('%:p'), line('.'))}
      \}
endfunction

function! s:ActionMenu(actions)
  let choices = ['Choose an action:']
  let idx = 0
  while idx < len(a:actions)
    call add(choices, string(idx+1).' - '.a:actions[idx]['title'])
    let idx += 1
  endwhile
  let choice = inputlist(choices)
  if choice > 0
    return a:actions[choice - 1]
  endif
  return v:false
endfunction

function! lsc#edit#rename(...) abort
  call lsc#file#flushChanges()
  if a:0 >= 1
    let new_name = a:1
  else
    let new_name = input('Enter a new name: ')
  endif
  let params = s:TextDocumentPositionParams()
  let params.newName = new_name
  call lsc#server#userCall('textDocument/rename', params,
      \ lsc#util#gateResult('Rename', function('lsc#edit#apply')))
endfunction

function! s:TextDocumentPositionParams() abort
  return { 'textDocument': {'uri': lsc#uri#documentUri()},
      \ 'position': {'line': line('.') - 1, 'character': col('.') - 1}
      \ }
endfunction

" Applies a workspace edit and returns `v:true` if it was successful.
function! lsc#edit#apply(workspace_edit) abort
  if (exists('g:lsc_enable_apply_edit')
      \ && !g:lsc_enable_apply_edit)
      \ || !has_key(a:workspace_edit, 'changes')
    return v:false
  endif
  let view = winsaveview()
  let old_paste = &paste
  set paste
  let alternate=@#
  let old_buffer = bufnr('%')

  call s:ApplyAll(a:workspace_edit.changes)

  if old_buffer != bufnr('%') | execute 'buffer' old_buffer | endif
  if len(alternate) > 0 | let @#=alternate | endif
  let &paste = old_paste
  call winrestview(view)
  return v:true
endfunction

function! s:ApplyAll(changes) abort
  for [uri, edits] in items(a:changes)
    let l:file_path = lsc#uri#documentPath(uri)
    let l:bufnr = bufnr(l:file_path)
    let l:cmd = 'keepjumps keepalt'
    if l:bufnr !=# -1
      let l:cmd .= ' b '.l:bufnr
    else
      let l:cmd .= ' edit '.l:file_path
    endif
    for edit in sort(edits, '<SID>CompareEdits')
      let l:cmd .= ' | execute "keepjumps normal! '.s:Apply(edit).'"'
    endfor
    try
      let l:was_paste = &paste
      set paste
      execute l:cmd
    finally
      let &paste = l:was_paste
    endtry
    call lsc#file#onChange(l:file_path)
  endfor
endfunction

" Find the command to apply a `TextEdit`.
function! s:Apply(edit) abort
  if s:IsEmptyRange(a:edit.range)
    if a:edit.range.start.character >= len(getline(a:edit.range.start.line + 1))
      let l:insert = 'a'
    else
      let l:insert = 'i'
    endif
    return printf('%dG%d|%s%s',
        \ a:edit.range.start.line + 1,
        \ a:edit.range.start.character + 1,
        \ l:insert,
        \ a:edit.newText
        \)
  else
    " `back` handles end-exclusive range
    let l:back = a:edit.range.end.character == 0 ? 'k$' : 'h'
    return printf('%dG%d|v%dG%d|%sc%s',
        \ a:edit.range.start.line + 1,
        \ a:edit.range.start.character + 1,
        \ a:edit.range.end.line + 1,
        \ a:edit.range.end.character + 1,
        \ l:back,
        \ a:edit.newText
        \)
  endif
endfunction

function! s:IsEmptyRange(range) abort
  return a:range.start.line == a:range.end.line &&
      \ a:range.start.character == a:range.end.character
endfunction

" Orders edits such that those later in the document appear earlier, and inserts
" at a given index always appear after an edit that starts at that index.
" Assumes that edits have non-overlapping ranges.
function! s:CompareEdits(e1, e2) abort
  if a:e1.range.start.line != a:e2.range.start.line
    return a:e2.range.start.line - a:e1.range.start.line
  endif
  if a:e1.range.start.character != a:e2.range.start.character
    return a:e2.range.start.character - a:e1.range.start.character
  endif
  return !s:IsEmptyRange(a:e1.range) ? -1
      \ : s:IsEmptyRange(a:e2.range) ? 0 : 1
endfunction
