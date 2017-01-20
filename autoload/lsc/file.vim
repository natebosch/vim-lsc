" Run language servers for this filetype if they aren't already running and send
" the 'didOpen' message.
function! lsc#file#onOpen() abort
  call lsc#server#start(&filetype)
  let file_path = expand('%:p')
  let buffer_content = join(getline(1, '$'), "\n")
  let params = {'textDocument':
      \   {'uri': 'file://'.file_path,
      \    'languageId': &filetype,
      \    'version': <SID>FileVersion(file_path),
      \    'text': buffer_content
      \   }
      \ }
  call lsc#server#call(&filetype, 'textDocument/didOpen', params)
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
  call timer_stop(b:lsc_flush_timer)
  unlet b:lsc_flush_timer
  let file_path = expand('%:p')
  let buffer_content = join(getline(1, '$'), "\n")
  let params = {'textDocument':
      \   {'uri': 'file://'.file_path,
      \    'version': <SID>FileVersion(file_path),
      \   },
      \ 'contentChanges': [{'text': buffer_content}],
      \ }
  call lsc#server#call(&filetype, 'textDocument/didChange', params)
endfunction

" file path -> file version
let s:file_versions = {}

" A monotonically increasing number for each open file.
function! s:FileVersion(file_path)
  let s:file_versions[a:file_path] = get(s:file_versions, a:file_path, 0) + 1
  return s:file_versions[a:file_path]
endfunction
