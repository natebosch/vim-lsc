if !exists('s:initialized')
  let s:initialized = v:true
  " file path -> file version
  let s:file_versions = {}
  " file path -> file content
  let s:file_content = {}
  " file path -> flush timer
  let s:flush_timers = {}
  " full file path -> buffer name
  let s:normalized_paths = {}
endif

" Send a 'didOpen' message for all open buffers with a tracked file type for a
" running server.
function! lsc#file#trackAll(server) abort
  for l:buffer in getbufinfo({'bufloaded': v:true})
    if !getbufvar(l:buffer.bufnr, '&modifiable') | continue | endif
    if  l:buffer.name =~# '\vfugitive:///' | continue | endif
    let l:filetype = getbufvar(l:buffer.bufnr, '&filetype')
    if index(a:server.filetypes, l:filetype) < 0 | continue | endif
    call lsc#file#track(a:server, l:buffer, l:filetype)
  endfor
endfunction

function! lsc#file#track(server, buffer, filetype) abort
  let l:file_path = lsc#file#normalize(a:buffer.name)
  call s:DidOpen(a:server, a:buffer.bufnr, l:file_path, a:filetype)
endfunction

" Run language servers for this filetype if they aren't already running and
" flush file changes.
function! lsc#file#onOpen() abort
  let l:file_path = lsc#file#fullPath()
  if has_key(s:file_versions, l:file_path)
    call lsc#file#flushChanges()
  else
    let l:bufnr = bufnr('%')
    for l:server in lsc#server#forFileType(&filetype)
      if !get(l:server.config, 'enabled', v:true) | continue | endif
      if l:server.status ==# 'running'
        call s:DidOpen(l:server, l:bufnr, l:file_path, &filetype)
      else
        call lsc#server#start(l:server, l:file_path)
      endif
    endfor
  endif
endfunction

function! lsc#file#onClose(full_path, filetype) abort
  if has_key(s:file_versions, a:full_path)
    unlet s:file_versions[a:full_path]
  endif
  if has_key(s:file_content, a:full_path)
    unlet s:file_content[a:full_path]
  endif
  if !lsc#server#filetypeActive(a:filetype) | return | endif
  let l:params = {'textDocument': {'uri': lsc#uri#documentUri(a:full_path)}}
  for l:server in lsc#server#forFileType(a:filetype)
    call l:server.notify('textDocument/didClose', l:params)
  endfor
endfunction

" Send a `textDocument/didSave` notification if the server may be interested.
function! lsc#file#onWrite(full_path, filetype) abort
  let l:params = {'textDocument': {'uri': lsc#uri#documentUri(a:full_path)}}
  for l:server in lsc#server#forFileType(a:filetype)
    if !l:server.capabilities.textDocumentSync.sendDidSave | continue | endif
    call l:server.notify('textDocument/didSave', l:params)
  endfor
endfunction

" Flushes changes for the current buffer.
function! lsc#file#flushChanges() abort
  call s:FlushIfChanged(lsc#file#fullPath(), &filetype)
endfunction

" Send the 'didOpen' message for a file.
function! s:DidOpen(server, bufnr, file_path, filetype) abort
  let l:buffer_content = has_key(s:file_content, a:file_path)
      \ ? s:file_content[a:file_path]
      \ : getbufline(a:bufnr, 1, '$')
  let l:version = has_key(s:file_versions, a:file_path)
      \ ? s:file_versions[a:file_path]
      \ : 1
  let l:params = {'textDocument':
      \   {'uri': lsc#uri#documentUri(a:file_path),
      \    'version': l:version,
      \    'text': join(l:buffer_content, "\n")."\n",
      \    'languageId': a:server.languageId[a:filetype],
      \   }
      \ }
  if a:server.notify('textDocument/didOpen', l:params)
    call s:UpdateRoots(a:server, a:file_path)
    let s:file_versions[a:file_path] = l:version
    if get(g:, 'lsc_enable_incremental_sync', v:true)
        \ && a:server.capabilities.textDocumentSync.incremental
      let s:file_content[a:file_path] = l:buffer_content
    endif
    doautocmd <nomodeline> User LSCOnChangesFlushed
  endif
endfunction

function! s:UpdateRoots(server, file_path) abort
  if !has_key(a:server.config, 'WorkspaceRoot') | return | endif
  if !a:server.capabilities.workspace.didChangeWorkspaceFolders | return | endif
  try
    let l:root = a:server.config.WorkspaceRoot(a:file_path)
  catch
    return
  endtry
  if index(a:server.roots, l:root) >= 0 | return | endif
  call add(a:server.roots, l:root)
  let l:workspace_folders = {'event':
      \   {'added': [{
      \     'uri': lsc#uri#documentUri(l:root),
      \     'name': fnamemodify(l:root, ':.'),
      \     }],
      \    'removed': [],
      \   },
      \ }
  call a:server.notify('workspace/didChangeWorkspaceFolders',
      \ l:workspace_folders)
endfunction

" Mark all files of type `filetype` as untracked.
function! lsc#file#clean(filetype) abort
  for l:buffer in getbufinfo({'bufloaded': v:true})
    if getbufvar(l:buffer.bufnr, '&filetype') != a:filetype | continue | endif
    if has_key(s:file_versions, l:buffer.name)
      unlet s:file_versions[l:buffer.name]
      if has_key(s:file_content, l:buffer.name)
        unlet s:file_content[l:buffer.name]
      endif
    endif
  endfor
endfunction

function! lsc#file#onChange(...) abort
  if a:0 >= 1
    let l:file_path = a:1
    let l:filetype = getbufvar(lsc#file#bufnr(l:file_path), '&filetype')
  else
    let l:file_path = lsc#file#fullPath()
    let l:filetype = &filetype
  endif
  if has_key(s:flush_timers, l:file_path)
    call timer_stop(s:flush_timers[l:file_path])
  endif
  let s:flush_timers[l:file_path] =
      \ timer_start(get(g:, 'lsc_change_debounce_time', 500),
      \   {_->s:FlushIfChanged(file_path, filetype)},
      \   {'repeat': 1})
endfunction

" Flushes only if `onChange` had previously been called for the file and those
" changes aren't flushed yet, and the file is tracked by at least one server.
function! s:FlushIfChanged(file_path, filetype) abort
  " Buffer may not have any pending changes to flush.
  if !has_key(s:flush_timers, a:file_path) | return | endif
  " Buffer may not be tracked with a `didOpen` call by any server yet.
  if !has_key(s:file_versions, a:file_path) | return | endif
  let s:file_versions[a:file_path] += 1
  if has_key(s:flush_timers, a:file_path)
    call timer_stop(s:flush_timers[a:file_path])
    unlet s:flush_timers[a:file_path]
  endif
  let l:document_params = {'textDocument':
      \   {'uri': lsc#uri#documentUri(a:file_path),
      \    'version': s:file_versions[a:file_path],
      \   },
      \ }
  let l:current_content = getbufline(lsc#file#bufnr(a:file_path), 1, '$')
  for l:server in lsc#server#forFileType(a:filetype)
    if l:server.status !=# 'running' | continue | endif
    if l:server.capabilities.textDocumentSync.incremental
      if !exists('l:incremental_params')
        let l:old_content = s:file_content[a:file_path]
        let l:change = lsc#diff#compute(l:old_content, l:current_content)
        let s:file_content[a:file_path] = l:current_content
        let l:incremental_params = copy(l:document_params)
        let l:incremental_params.contentChanges = [l:change]
      endif
      let l:params = l:incremental_params
    else
      if !exists('l:full_params')
        let l:full_params = copy(l:document_params)
        let l:change = {'text': join(l:current_content, "\n")."\n"}
        let l:full_params.contentChanges = [l:change]
      endif
      let l:params = l:full_params
    endif
      call l:server.notify('textDocument/didChange', l:params)
  endfor
  doautocmd <nomodeline> User LSCOnChangesFlushed
endfunction

function! lsc#file#version() abort
  return get(s:file_versions, lsc#file#fullPath(), '')
endfunction

" The full path to the current buffer.
"
" The association between a buffer and full path may change if the file has not
" been written yet - this makes a best-effort attempt to get a full path anyway.
" In most cases if the working directory doesn't change this isn't harmful.
"
" Paths which do need to be manually normalized are stored so that the full path
" can be associated back to a buffer with `lsc#file#bufnr()`.
function! lsc#file#fullPath() abort
  let l:full_path = expand('%:p')
  if l:full_path ==# expand('%')
    " Path could not be expanded due to pointing to a non-existent directory
    let l:full_path = lsc#file#normalize(getbufinfo('%')[0].name)
  elseif has('win32')
    let l:full_path = s:os_normalize(l:full_path)
  endif
  return l:full_path
endfunction

" Like `bufnr()` but handles the case where a relative path was normalized
" against cwd.
function! lsc#file#bufnr(full_path) abort
  let l:bufnr = bufnr(a:full_path)
  if l:bufnr == -1 && has_key(s:normalized_paths, a:full_path)
    let l:bufnr = bufnr(s:normalized_paths[a:full_path])
  endif
  return l:bufnr
endfunction

" Normalize `original_path` for OS separators and relative paths, and store the
" mapping.
"
" The return value is always a full path, even if vim won't expand it with `:p`
" because it is in a non-existent directory. The original path is stored, keyed
" by the normalized path, so that it can be retrieved by `lsc#file#bufnr`.
function! lsc#file#normalize(original_path) abort
  let l:full_path = a:original_path
  if l:full_path !~# '^/\|\%([c-zC-Z]:[/\\]\)'
    let l:full_path = getcwd().'/'.l:full_path
  endif
  let l:full_path = s:os_normalize(l:full_path)
  let s:normalized_paths[l:full_path] = a:original_path
  return l:full_path
endfunction

function! lsc#file#compare(file_1, file_2) abort
  if a:file_1 == a:file_2 | return 0 | endif
  let l:cwd = '^'.s:os_normalize(getcwd())
  let l:file_1_in_cwd = a:file_1 =~# l:cwd
  let l:file_2_in_cwd = a:file_2 =~# l:cwd
  if l:file_1_in_cwd && !l:file_2_in_cwd | return -1 | endif
  if l:file_2_in_cwd && !l:file_1_in_cwd | return 1 | endif
  return a:file_1 > a:file_2 ? 1 : -1
endfunction

" `getcwd` with OS path normalization.
function! lsc#file#cwd() abort
  return s:os_normalize(getcwd())
endfunction

function! s:os_normalize(path) abort
  if has('win32') | return substitute(a:path, '\\', '/', 'g') | endif
  return a:path
endfunction
