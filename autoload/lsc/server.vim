if !exists('s:initialized')
  " channel id -> received message
  let s:channel_buffers = {}
  " command -> [call]
  let s:buffered_calls = {}
  " command -> job
  let s:running_servers = {}
  let s:initialized_servers = []
  let s:initialized = v:true
endif

function! lsc#server#start(filetype) abort
  if <SID>RunCommand(g:lsc_server_commands[a:filetype])
    call lsc#file#trackAll(a:filetype)
  endif
endfunction

function! lsc#server#kill(file_type) abort
  call lsc#server#call(a:file_type, 'shutdown', '')
  call lsc#server#call(a:file_type, 'exit', '')
endfunction

" Call a method on the language server for `file_type`.
"
" Formats a message calling `method` with parameters `params`. If called with 4
" arguments the fourth should be a funcref which will be called when the server
" returns a result for this call.
function! lsc#server#call(file_type, method, params, ...) abort
  let [call_id, message] = lsc#protocol#format(a:method, a:params)
  if a:0 >= 1
    call lsc#dispatch#registerCallback(call_id, a:1)
  endif
  if a:0 >= 2
    let override_initialize = a:2
  else
    let override_initialize = v:false
  endif
  let command = g:lsc_server_commands[a:file_type]
  if !has_key(s:running_servers, command) ||
      \ (index(s:initialized_servers, command) < 0 && !override_initialize)
    call s:BufferCall(command, message)
    return
  endif
  let job = s:running_servers[command]
  if job_status(job) != 'run' | return | endif
  let channel = job_getchannel(job)
  if ch_status(channel) != 'open' | return | endif
  call ch_sendraw(channel, message)
endfunction

function! lsc#server#readBuffer(ch_id) abort
  return s:channel_buffers[a:ch_id]
endfunction

function! lsc#server#setBuffer(ch_id, message) abort
  let s:channel_buffers[a:ch_id] = a:message
endfunction

" Start a language server using `command` if it isn't already running.
"
" Returns v:true if the server was started, or v:false if it was already
" running.
function! s:RunCommand(command) abort
  if has_key(s:running_servers, a:command) | return v:false | endif

  let job_options = {'in_io': 'pipe', 'in_mode': 'raw',
      \ 'out_io': 'pipe', 'out_mode': 'raw',
      \ 'out_cb': 'lsc#server#channelCallback', 'exit_cb': 'lsc#server#onExit'}
  let job = job_start(a:command, job_options)
  let s:running_servers[a:command] = job
  let channel = job_getchannel(job)
  let ch_id = ch_info(channel)['id']
  let s:channel_buffers[ch_id] = ''
  let data = {'command': a:command, 'channel': channel}
  function data.onInitialize(params) abort
    " TODO: Check capabilities?
    call add(s:initialized_servers, self.command)
    if has_key(s:buffered_calls, self.command)
      for buffered_call in s:buffered_calls[self.command]
        call ch_sendraw(self.channel, buffered_call)
      endfor
      unlet s:buffered_calls[self.command]
    endif
  endfunction
  let params = {'processId': getpid(),
      \ 'rootUri': 'file://'.getcwd(),
      \ 'capabilities': s:client_capabilities,
      \ 'trace': 'off'
      \}
  call lsc#server#call(&filetype, 'initialize',
      \ params, data.onInitialize, v:true)
  return v:true
endfunction

" Find the command for `job` and clean up it's state
function! lsc#server#onExit(job, status) abort
  let channel = job_getchannel(a:job)
  let ch_id = ch_info(channel)['id']
  unlet s:channel_buffers[ch_id]
  for command in keys(s:running_servers)
    if s:running_servers[command] == a:job
      call s:OnCommandExit(command)
      return
    endif
  endfor
endfunction

" Clean up stored state about a running server.
function! s:OnCommandExit(command) abort
  unlet s:running_servers[a:command]
  let initialize = index(s:initialized_servers, a:command)
  if initialize >= 0
    call remove(s:initialized_servers, initialize)
  endif
  for filetype in keys(g:lsc_server_commands)
    if g:lsc_server_commands[filetype] != a:command | continue | endif
    call lsc#complete#clean(filetype)
    call lsc#diagnostics#clean(filetype)
    call lsc#file#clean(filetype)
  endfor
endfunction

" Append to the buffer for the channel and try to consume a message.
function! lsc#server#channelCallback(channel, message) abort
  let ch_id = ch_info(a:channel)['id']
  let s:channel_buffers[ch_id] .= a:message
  call lsc#protocol#consumeMessage(ch_id)
endfunction

function! s:BufferCall(command, call) abort
  if !has_key(s:buffered_calls, a:command)
    let s:buffered_calls[a:command] = []
  endif
  call add(s:buffered_calls[a:command], a:call)
endfunction

" Supports no workspace capabilities - missing value means no support
let s:client_capabilities = {
    \ 'workspace': {},
    \ 'textDocument': {
    \   'synchronization': {
    \     'willSave': v:false,
    \     'willSaveWaitUntil': v:false,
    \     'didSave': v:false,
    \   },
    \   'completion': {
    \     'snippetSupport': v:false,
    \   },
    \   'definition': {'dynamicRegistration': v:false},
    \ }
    \}
