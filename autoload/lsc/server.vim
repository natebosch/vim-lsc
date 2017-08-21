if !exists('s:initialized')
  " channel id -> received message
  let s:channel_buffers = {}
  " command -> job
  let s:running_servers = {}
  " command -> status. Possible statuses are:
  " [starting, running, exiting, restarting, exited, unexpected exit, failed]
  let s:server_statuses = {}
  let s:initialized = v:true
endif

function! lsc#server#start(filetype) abort
  call <SID>StartByCommand(g:lsc_server_commands[a:filetype])
endfunction

function! lsc#server#status(filetype) abort
  if !has_key(g:lsc_server_commands, a:filetype) | return '' | endif
  let command = g:lsc_server_commands[a:filetype]
  if !has_key(s:server_statuses, command) | return 'unknown' | endif
  return s:server_statuses[command]
endfunction

function! lsc#server#kill(file_type) abort
  call lsc#server#call(a:file_type, 'shutdown', '')
  call lsc#server#call(a:file_type, 'exit', '')
  let s:server_statuses[g:lsc_server_commands[&filetype]] = 'exiting'
endfunction

function! lsc#server#restart() abort
  let command = g:lsc_server_commands[&filetype]
  let old_status = s:server_statuses[command]
  if old_status == 'starting' || old_status == 'running'
    call lsc#server#kill(&filetype)
    let s:server_statuses[command] = 'restarting'
  else
    call s:StartByCommand(command)
  endif
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
      \ (s:server_statuses[command] != 'running' && !override_initialize)
    return v:false
  endif
  let job = s:running_servers[command]
  if job_status(job) != 'run' | return v:false | endif
  let channel = job_getchannel(job)
  if ch_status(channel) != 'open' | return v:false | endif
  call ch_sendraw(channel, message)
  return v:true
endfunction

function! lsc#server#readBuffer(ch_id) abort
  return s:channel_buffers[a:ch_id]
endfunction

function! lsc#server#setBuffer(ch_id, message) abort
  let s:channel_buffers[a:ch_id] = a:message
endfunction

function! lsc#server#getBuffers() abort
  return s:channel_buffers
endfunction

" Start a language server using `command` if it isn't already running.
function! s:StartByCommand(command) abort
  if has_key(s:running_servers, a:command) | return | endif

  let job_options = {'in_io': 'pipe', 'in_mode': 'raw',
      \ 'out_io': 'pipe', 'out_mode': 'raw',
      \ 'out_cb': 'lsc#server#channelCallback', 'exit_cb': 'lsc#server#onExit'}
  let job = job_start(a:command, job_options)
  let s:running_servers[a:command] = job
  let s:server_statuses[a:command] = 'starting'
  let channel = job_getchannel(job)
  let ch_id = ch_info(channel)['id']
  let s:channel_buffers[ch_id] = ''
  function! OnInitialize(params) closure abort
    " TODO: Check capabilities?
    if has_key(a:params, 'capabilities')
      let capabilities = a:params['capabilities']
      if has_key(capabilities, 'completionProvider')
        let completion_provider = capabilities['completionProvider']
        if has_key(completion_provider, 'triggerCharacters')
          let trigger_characters = completion_provider['triggerCharacters']
          for filetype in keys(g:lsc_server_commands)
            if g:lsc_server_commands[filetype] != a:command | continue | endif
            call lsc#complete#setTriggers(filetype, trigger_characters)
          endfor
        endif
      endif
    endif
    let s:server_statuses[a:command] = 'running'
    for filetype in keys(g:lsc_server_commands)
      if g:lsc_server_commands[filetype] != a:command | continue | endif
      call lsc#file#trackAll(filetype)
    endfor
  endfunction
  if exists('g:lsc_trace_level') &&
      \ index(['off', 'messages', 'verbose'], g:lsc_trace_level) >= 0
    let trace_level = g:lsc_trace_level
  else
    let trace_level = 'off'
  endif
  let params = {'processId': getpid(),
      \ 'rootUri': 'file://'.getcwd(),
      \ 'capabilities': s:client_capabilities,
      \ 'trace': trace_level
      \}
  call lsc#server#call(&filetype, 'initialize',
      \ params, function('OnInitialize'), v:true)
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
  let old_status = s:server_statuses[a:command]
  if old_status == 'starting'
    let s:server_statuses[a:command] = 'failed'
    call lsc#util#error('Failed to initialize server: '.a:command)
  elseif old_status == 'exiting'
    let s:server_statuses[a:command] = 'exited'
  elseif old_status == 'running'
    let s:server_statuses[a:command] = 'unexpected exit'
  endif
  for filetype in keys(g:lsc_server_commands)
    if g:lsc_server_commands[filetype] != a:command | continue | endif
    call lsc#complete#clean(filetype)
    call lsc#diagnostics#clean(filetype)
    call lsc#file#clean(filetype)
  endfor
  if old_status == 'restarting'
    call <SID>StartByCommand(a:command)
  endif
endfunction

" Append to the buffer for the channel and try to consume a message.
function! lsc#server#channelCallback(channel, message) abort
  let ch_id = ch_info(a:channel)['id']
  let s:channel_buffers[ch_id] .= a:message
  call lsc#protocol#consumeMessage(ch_id)
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
