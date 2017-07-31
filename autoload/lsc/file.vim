if !exists('s:initialized')
  " file path -> file version
  let s:file_versions = {}
endif

" Send a 'didOpen' message for all open files of type `filetype` if they aren't
" already tracked.
function! lsc#file#trackAll(filetype) abort
  for buffer in getbufinfo({'loaded': v:true})
    if getbufvar(buffer.bufnr, '&filetype') != a:filetype | continue | endif
    call s:DidOpen(buffer.name)
  endfor
endfunction

" Run language servers for this filetype if they aren't already running and send
" the 'didOpen' message.
function! lsc#file#onOpen() abort
  call lsc#server#start(&filetype)
  call lsc#config#mapKeys()
  call s:DidOpen(expand('%:p'))
endfunction

" Send the 'didOpen' message for a file if it isn't already tracked.
function! s:DidOpen(file_path) abort
  if has_key(s:file_versions, a:file_path) | return | endif
  let bufnr = bufnr(a:file_path)
  if !bufloaded(bufnr) | return | endif
  let s:file_versions[a:file_path] = 1
  let buffer_content = join(getbufline(bufnr, 1, '$'), "\n")
  let filetype = getbufvar(bufnr, '&filetype')
  let params = {'textDocument':
      \   {'uri': lsc#util#documentUri(a:file_path),
      \    'languageId': filetype,
      \    'version': s:file_versions[a:file_path],
      \    'text': buffer_content
      \   }
      \ }
  call lsc#server#call(filetype, 'textDocument/didOpen', params)
endfunction

" Mark all files of type `filetype` as untracked.
function! lsc#file#clean(filetype) abort
  for buffer in getbufinfo({'loaded': v:true})
    if getbufvar(buffer.bufnr, '&filetype') != a:filetype | continue | endif
    if has_key(s:file_versions, buffer.name)
      unlet s:file_versions[buffer.name]
    endif
  endfor
endfunction

function! lsc#file#onChange() abort
  if exists('b:lsc_flush_timer')
    call timer_stop(b:lsc_flush_timer)
  endif
  let b:lsc_flush_timer =
      \ timer_start(500, 'lsc#file#flushChanges', {'repeat': 1})
endfunction

" Changes are flushed after 500ms of inactivity or before leaving the buffer.
function! lsc#file#flushChanges(...) abort
  if !exists('b:lsc_flush_timer')
    return
  endif
  let file_path = expand('%:p')
  if !has_key(s:file_versions, file_path) | return | endif
  let s:file_versions[file_path] += 1
  call timer_stop(b:lsc_flush_timer)
  unlet b:lsc_flush_timer
  let buffer_content = join(getline(1, '$'), "\n")
  let params = {'textDocument':
      \   {'uri': lsc#util#documentUri(),
      \    'version': s:file_versions[file_path],
      \   },
      \ 'contentChanges': [{'text': buffer_content}],
      \ }
  call lsc#server#call(&filetype, 'textDocument/didChange', params)
endfunction

function! lsc#file#version() abort
  return get(s:file_versions, expand('%:p'), '')
endfunction
