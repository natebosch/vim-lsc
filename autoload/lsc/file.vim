if !exists('s:initialized')
  let s:initialized = v:true
  " file path -> file version
  let s:file_versions = {}
  " file path -> file content
  let s:file_content = {}
  " file path -> flush timer
  let s:flush_timers = {}
  " filetype -> boolean
  let s:allowed_incremental_sync = {}
endif

" Send a 'didOpen' message for all open files of type `filetype` if they aren't
" already tracked.
function! lsc#file#trackAll(filetype) abort
  for buffer in getbufinfo({'loaded': v:true})
    if getbufvar(buffer.bufnr, '&filetype') != a:filetype | continue | endif
    call s:FlushChanges(buffer.name, a:filetype)
  endfor
endfunction

" Run language servers for this filetype if they aren't already running and
" flush file changes.
function! lsc#file#onOpen() abort
  call lsc#server#start(&filetype)
  call lsc#config#mapKeys()
  call s:FlushChanges(expand('%:p'), &filetype)
endfunction

function! lsc#file#onClose(file_path) abort
  let full_path = fnamemodify(a:file_path, ':p')
  let params = {'textDocument': {'uri': lsc#uri#documentUri(full_path)}}
  call lsc#server#call(&filetype, 'textDocument/didClose', params)
  if has_key(s:file_versions, full_path)
    unlet s:file_versions[full_path]
  endif
  if has_key(s:file_content, full_path)
    unlet s:file_content[full_path]
  endif
endfunction

" Flushes changes for the current buffer.
function! lsc#file#flushChanges() abort
  call s:FlushIfChanged(expand('%:p'), &filetype)
endfunction

" Send the 'didOpen' message for a file.
function! s:DidOpen(file_path) abort
  let bufnr = bufnr(a:file_path)
  if !bufloaded(bufnr) | return | endif
  if !getbufvar(bufnr, '&modifiable') | return | endif
  let buffer_content = getbufline(bufnr, 1, '$')
  let filetype = getbufvar(bufnr, '&filetype')
  let params = {'textDocument':
      \   {'uri': lsc#uri#documentUri(a:file_path),
      \    'languageId': filetype,
      \    'version': 1,
      \    'text': join(buffer_content, "\n")
      \   }
      \ }
  if lsc#server#call(filetype, 'textDocument/didOpen', params)
    let s:file_versions[a:file_path] = 1
    if s:AllowIncrementalSync(filetype)
      let s:file_content[a:file_path] = buffer_content
    endif
  endif
endfunction

" Mark all files of type `filetype` as untracked.
function! lsc#file#clean(filetype) abort
  for buffer in getbufinfo({'loaded': v:true})
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
    let filetype = getbufvar(file_path, '&filetype')
  else
    let file_path = expand('%:p')
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
  let buffer_vars = getbufvar(a:file_path, '')
  if has_key(s:flush_timers, a:file_path)
    call timer_stop(s:flush_timers[a:file_path])
    unlet s:flush_timers[a:file_path]
  endif
  let buffer_content = getbufline(a:file_path, 1, '$')
  let allow_incremental = s:AllowIncrementalSync(a:filetype)
  if allow_incremental
    let change = lsc#diff#compute(s:file_content[a:file_path], buffer_content)
  else
    let change = {'text': join(buffer_content, "\n")}
  endif
  let params = {'textDocument':
      \   {'uri': lsc#uri#documentUri(a:file_path),
      \    'version': s:file_versions[a:file_path],
      \   },
      \ 'contentChanges': [change],
      \ }
  call lsc#server#call(a:filetype, 'textDocument/didChange', params)
  if allow_incremental
    let s:file_content[a:file_path] = buffer_content
  endif
endfunction

function! lsc#file#version() abort
  return get(s:file_versions, expand('%:p'), '')
endfunction

function! lsc#file#enableIncrementalSync(filetype) abort
  let s:allowed_incremental_sync[a:filetype] = v:true
endfunction

function! s:AllowIncrementalSync(filetype) abort
  return exists('g:lsc_enable_incremental_sync')
      \ && g:lsc_enable_incremental_sync
      \ && get(s:allowed_incremental_sync, a:filetype, v:false)
endfunction
