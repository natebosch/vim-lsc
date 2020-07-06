function! lsc#edit#findCodeActions(...) abort
  if a:0 > 0
    let ActionFilter = a:1
  else
    let ActionFilter = function('<SID>ActionMenu')
  endif
  call lsc#file#flushChanges()
  let params = lsc#params#documentRange()
  let params.context = {'diagnostics':
      \ lsc#diagnostics#forLine(lsc#file#fullPath(), line('.') - 1)}
  call lsc#server#userCall('textDocument/codeAction', params,
      \ lsc#util#gateResult('CodeActions',
      \     function('<SID>SelectAction', [ActionFilter])))
endfunction

function! s:SelectAction(ActionFilter, result) abort
  if type(a:result) != type([]) || len(a:result) == 0
    call lsc#message#show('No actions available')
    return
  endif
  call a:ActionFilter(a:result, function('<SID>ExecuteCommand'))
endfunction

function! s:ExecuteCommand(choice) abort
  if has_key(a:choice, 'command')
    let l:command = type(a:choice.command) == type('') ?
        \ a:choice : a:choice.command
    call lsc#server#userCall('workspace/executeCommand',
        \ {'command': l:command.command,
        \ 'arguments': l:command.arguments},
        \ {_->0})
  elseif has_key(a:choice, 'edit') && type(a:choice.edit) == type({})
    call lsc#edit#apply(a:choice.edit)
  endif
endfunction

" Returns a function which can filter actions against a patter and select when
" exactly 1 matches or show a menu for the matching actions.
function! lsc#edit#filterActions(...) abort
  if a:0 >= 1
    return function('<SID>FilteredActionMenu', [a:1])
  else
    return function('<SID>ActionMenu')
  endif
endfunction

function! s:FilteredActionMenu(filter, actions, OnSelected) abort
  call filter(a:actions, {idx, val -> val.title =~ a:filter})
  if empty(a:actions)
    call lsc#message#show('No actions available matching '.a:filter)
    return v:false
  endif
  if len(a:actions) == 1
    call a:OnSelected(a:actions[0])
  else
    call s:ActionMenu(a:actions, a:OnSelected)
  endif
endfunction

function! s:ActionMenu(actions, OnSelected) abort
  if has_key(g:, 'LSC_action_menu')
    call g:LSC_action_menu(a:actions, a:OnSelected)
    return
  endif
  let choices = ['Choose an action:']
  let idx = 0
  while idx < len(a:actions)
    call add(choices, string(idx+1).' - '.a:actions[idx]['title'])
    let idx += 1
  endwhile
  let choice = inputlist(choices)
  if choice > 0
    call a:OnSelected(a:actions[choice - 1])
  endif
endfunction

function! lsc#edit#rename(...) abort
  call lsc#file#flushChanges()
  if a:0 >= 1
    let new_name = a:1
  else
    let new_name = input('Enter a new name: ')
  endif
  if l:new_name =~# '\v^\s*$'
    echo "\n"
    call lsc#message#error('Name can not be blank')
    return
  endif
  let params = lsc#params#documentPosition()
  let params.newName = new_name
  call lsc#server#userCall('textDocument/rename', params,
      \ lsc#util#gateResult('Rename', function('lsc#edit#apply')))
endfunction

" Applies a workspace edit and returns `v:true` if it was successful.
function! lsc#edit#apply(workspace_edit) abort
  if (exists('g:lsc_enable_apply_edit')
      \ && !g:lsc_enable_apply_edit)
      \ || (!has_key(a:workspace_edit, 'changes') && !has_key(a:workspace_edit, 'documentChanges'))
    return v:false
  endif
  let view = winsaveview()
  let alternate=@#
  let old_buffer = bufnr('%')
  let old_paste = &paste
  let old_selection = &selection
  let old_virtualedit = &virtualedit
  set paste
  set selection=exclusive
  set virtualedit=onemore


  if (!has_key(a:workspace_edit, 'documentChanges'))
    let l:changes = a:workspace_edit.changes
  else
    let l:changes = {}
    for l:textDocumentEdit in a:workspace_edit.documentChanges
      let l:changes[l:textDocumentEdit.textDocument.uri] = l:textDocumentEdit.edits
    endfor
  endif

  try
    call s:ApplyAll(l:changes)
  finally
    if len(alternate) > 0 | let @#=alternate | endif
    if old_buffer != bufnr('%') | execute 'buffer' old_buffer | endif
    let &paste = old_paste
    let &selection = old_selection
    let &virtualedit = old_virtualedit
    call winrestview(view)
  endtry
  return v:true
endfunction

function! s:ApplyAll(changes) abort
  for [uri, edits] in items(a:changes)
    let l:file_path = lsc#uri#documentPath(uri)
    let l:bufnr = lsc#file#bufnr(l:file_path)
    let l:cmd = 'keepjumps keepalt'
    if l:bufnr !=# -1
      let l:cmd .= ' b '.l:bufnr
    else
      let l:cmd .= ' edit '.l:file_path
    endif
    call sort(l:edits, '<SID>CompareEdits')
    for l:idx in range(0, len(l:edits) - 1)
      let l:cmd .= ' | silent execute "keepjumps normal! '
      let l:cmd .= s:Apply(l:edits[l:idx])
      let l:cmd .= '\<C-r>=l:edits['.string(l:idx).'].newText\<cr>"'
    endfor
    execute l:cmd
    if !&hidden | update | endif
    call lsc#file#onChange(l:file_path)
  endfor
endfunction

" Find the normal mode commands to prepare for inserting the text in [edit].
"
" For inserts, moves the cursor and uses an `a` or `i` to append or insert.
" For replacements, selects the text with `v` and then `c` to change.
function! s:Apply(edit) abort
  if s:IsEmptyRange(a:edit.range)
    if a:edit.range.start.character >= len(getline(a:edit.range.start.line + 1))
      let l:insert = 'a'
    else
      let l:insert = 'i'
    endif
    return printf('%s%s',
        \ s:GoToChar(a:edit.range.start),
        \ l:insert,
        \)
  else
    return printf('%sv%sc',
        \ s:GoToChar(a:edit.range.start),
        \ s:GoToChar(a:edit.range.end),
        \)
  endif
endfunction

function! s:IsEmptyRange(range) abort
  return a:range.start.line == a:range.end.line &&
      \ a:range.start.character == a:range.end.character
endfunction

" Find the normal mode commands to go to [pos]
function! s:GoToChar(pos) abort
  let l:cmd = ''
  let l:cmd .= printf('%dG', a:pos.line + 1)
  if a:pos.character == 0
    let l:cmd .= '0'
  else
    let l:cmd .= printf('0%dl', a:pos.character)
  endif
  return l:cmd
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
