function! lsc#edit#findCodeActions(...) abort
  if a:0 > 0
    let ActionFilter = a:1
  else
    let ActionFilter = function('<SID>ActionMenu')
  endif
  call lsc#file#flushChanges()
  let params = lsc#params#documentRange()
  let params.context = {'diagnostics':
      \ lsc#diagnostics#forLine(lsc#file#fullPath(), line('.'))}
  call lsc#server#userCall('textDocument/codeAction', params,
      \ lsc#util#gateResult('CodeActions', function('<SID>SelectAction'),
      \     v:null, [ActionFilter]))
endfunction

function! s:SelectAction(result, action_filter) abort
  if type(a:result) != type([]) || len(a:result) == 0
    call lsc#message#show('No actions available')
    return
  endif
  let l:choice = a:action_filter(a:result)
  if type(l:choice) == type({})
    if has_key(l:choice, 'command') && type(l:choice.command) == type('')
      call s:ExecuteCommand(l:choice)
    else
      if has_key(l:choice, 'edit') && type(l:choice.edit) == type({})
        call lsc#edit#apply(l:choice.edit)
      endif
      if has_key(l:choice, 'command') && type(l:choice.command) == type({})
        call s:ExecuteCommand(l:choice.command)
      endif
    endif
  endif
endfunction

function! s:ExecuteCommand(command) abort
  call lsc#server#userCall('workspace/executeCommand',
      \ {'command': a:command.command,
      \ 'arguments': a:command.arguments},
      \ {_->0})
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

function! s:FilteredActionMenu(filter, actions) abort
  call filter(a:actions, {idx, val -> val.title =~ a:filter})
  if empty(a:actions)
    call lsc#message#show('No actions available matching '.a:filter)
    return v:false
  endif
  if len(a:actions) == 1 | return a:actions[0] | endif
  return s:ActionMenu(a:actions)
endfunction

function! s:ActionMenu(actions) abort
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
    for edit in sort(edits, '<SID>CompareEdits')
      let l:cmd .= ' | execute "keepjumps normal! '.s:Apply(edit).'"'
    endfor
    execute l:cmd
    if !&hidden | execute 'update' | endif
    call lsc#file#onChange(l:file_path)
  endfor
endfunction

" Find the command to apply a `TextEdit`.
function! s:Apply(edit) abort
  let l:new_text = substitute(a:edit.newText, '"', '\\"', 'g')
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
        \ l:new_text
        \)
  else
    return printf('%dG%d|v%dG%d|c%s',
        \ a:edit.range.start.line + 1,
        \ a:edit.range.start.character + 1,
        \ a:edit.range.end.line + 1,
        \ a:edit.range.end.character + 1,
        \ l:new_text
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
