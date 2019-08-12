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

" Send a 'didOpen' message for all open files of type `filetype` if they aren't
" already tracked.
function! lsc#file#trackAll(filetype) abort
  for buffer in getbufinfo({'bufloaded': v:true})
    if getbufvar(buffer.bufnr, '&filetype') != a:filetype | continue | endif
    call s:FlushChanges(lsc#file#normalize(buffer.name), a:filetype)
  endfor
endfunction

" Run language servers for this filetype if they aren't already running and
" flush file changes.
function! lsc#file#onOpen() abort
  call lsc#server#start(&filetype)
  call lsc#config#mapKeys()
  call s:FlushChanges(lsc#file#fullPath(), &filetype)
endfunction

function! lsc#file#onClose(full_path, filetype) abort
  let l:params = {'textDocument': {'uri': lsc#uri#documentUri(a:full_path)}}
  for l:server in lsc#server#forFileType(a:filetype)
    call l:server.notify('textDocument/didClose', l:params)
  endfor
  if has_key(s:file_versions, a:full_path)
    unlet s:file_versions[a:full_path]
  endif
  if has_key(s:file_content, a:full_path)
    unlet s:file_content[a:full_path]
  endif
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
function! s:DidOpen(file_path) abort
  let l:bufnr = lsc#file#bufnr(a:file_path)
  if !bufloaded(l:bufnr) | return | endif
  if !getbufvar(l:bufnr, '&modifiable') | return | endif
  let buffer_content = getbufline(l:bufnr, 1, '$')
  let filetype = getbufvar(l:bufnr, '&filetype')
  let l:params = {'textDocument':
      \   {'uri': lsc#uri#documentUri(a:file_path),
      \    'languageId': filetype,
      \    'version': 1,
      \    'text': join(buffer_content, "\n")
      \   }
      \ }
  " TODO handle multiple servers
  let l:success = v:false
  for l:server in lsc#server#forFileType(l:filetype)
    let l:success = l:server.notify('textDocument/didOpen', l:params)
  endfor
  if l:success
    let s:file_versions[a:file_path] = 1
    if s:AllowIncrementalSync(filetype)
      let s:file_content[a:file_path] = buffer_content
    endif
    doautocmd <nomodeline> User LSCOnChangesFlushed
  endif
endfunction

" Mark all files of type `filetype` as untracked.
function! lsc#file#clean(filetype) abort
  for buffer in getbufinfo({'bufloaded': v:true})
    if getbufvar(buffer.bufnr, '&filetype') != a:filetype | continue | endif
    if has_key(s:file_versions, buffer.name)
      unlet s:file_versions[buffer.name]
      if has_key(s:file_content, buffer.name)
        unlet s:file_content[buffer.name]
      endif
    endif
  endfor
endfunction

function! lsc#file#onChange(...) abort
  if a:0 >= 1
    let file_path = a:1
    let filetype = getbufvar(lsc#file#bufnr(file_path), '&filetype')
  else
    let file_path = lsc#file#fullPath()
    let filetype = &filetype
  endif
  if has_key(s:flush_timers, file_path)
    call timer_stop(s:flush_timers[file_path])
  endif
  let s:flush_timers[file_path] =
      \ timer_start(500,
      \   {_->s:FlushIfChanged(file_path, filetype)},
      \   {'repeat': 1})
endfunction

" Flushes only if `onChange` had previously been called for the file and the
" changes aren't yet flusehd.
function! s:FlushIfChanged(file_path, filetype) abort
  if has_key(s:flush_timers, a:file_path)
    call s:FlushChanges(a:file_path, a:filetype)
  endif
endfunction

" Changes are flushed after 500ms of inactivity or before leaving the buffer.
function! s:FlushChanges(file_path, filetype) abort
  if !has_key(s:file_versions, a:file_path)
    call s:DidOpen(a:file_path)
    return
  endif
  let s:file_versions[a:file_path] += 1
  if has_key(s:flush_timers, a:file_path)
    call timer_stop(s:flush_timers[a:file_path])
    unlet s:flush_timers[a:file_path]
  endif
  let buffer_content = getbufline(lsc#file#bufnr(a:file_path), 1, '$')
  let allow_incremental = s:AllowIncrementalSync(a:filetype)
  if allow_incremental
    let change = lsc#diff#compute(s:file_content[a:file_path], buffer_content)
  else
    let change = {'text': join(buffer_content, "\n")}
  endif
  let l:params = {'textDocument':
      \   {'uri': lsc#uri#documentUri(a:file_path),
      \    'version': s:file_versions[a:file_path],
      \   },
      \ 'contentChanges': [change],
      \ }
  " TODO handle multiple servers
  for l:server in lsc#server#forFileType(a:filetype)
    call l:server.notify('textDocument/didChange', l:params)
  endfor
  if allow_incremental
    let s:file_content[a:file_path] = buffer_content
  endif
  doautocmd <nomodeline> User LSCOnChangesFlushed
endfunction

function! lsc#file#version() abort
  return get(s:file_versions, lsc#file#fullPath(), '')
endfunction

function! s:AllowIncrementalSync(filetype) abort
  if (exists('g:lsc_enable_incremental_sync')
      \ && !g:lsc_enable_incremental_sync)
    return v:false
  endif
  for l:server in lsc#server#forFileType(a:filetype)
    if !l:server.capabilities.textDocumentSync.incremental
      return v:false
    endif
  endfor
  return v:true
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
  let l:file_path = expand('%:p')
  if l:file_path ==# expand('%')
    " Path could not be expanded due to pointing to a non-existent directory
    let l:file_path = lsc#file#normalize(getbufinfo('%')[0].name)
  endif
  return l:file_path
endfunction

" Like `bufnr()` but handles the case where a relative path was normalized
" against cwd.
function! lsc#file#bufnr(file_path) abort
  let l:bufnr = bufnr(a:file_path)
  if l:bufnr == -1 && has_key(s:normalized_paths, a:file_path)
    let l:bufnr = bufnr(s:normalized_paths[a:file_path])
  endif
  return l:bufnr
endfunction

" If `buffer_name` is relative, normalize it against `cwd`.
function! lsc#file#normalize(buffer_name) abort
  if a:buffer_name[0] ==# '/' | return a:buffer_name | endif
  let l:full_path = getcwd().'/'.a:buffer_name
  let s:normalized_paths[l:full_path] = a:buffer_name
  return l:full_path
endfunction
