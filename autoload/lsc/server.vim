if !exists('s:initialized')
  " channel id -> server name
  let s:server_names = {}
  " server name -> server info.
  "
  " Server name defaults to the command string.
  "
  " Info contains:
  " - status. Possible statuses are:
  "   [starting, running, exiting, restarting, exited, unexpected exit, failed]
  " - buffer. String received from the server but not processed yet.
  " - channel. The communication channel
  " - calls. The last 10 calls made to the server
  " - messages. The last 10 messages from the server
  " - init_result. The response to the initialization call
  " - filetypes. List of filetypes handled by this server.
  let s:servers = {}
  let s:initialized = v:true
endif

function! lsc#server#start(filetype) abort
  call s:Start(g:lsc_server_commands[a:filetype])
endfunction

function! lsc#server#status(filetype) abort
  if !has_key(g:lsc_server_commands, a:filetype) | return '' | endif
  let command = g:lsc_server_commands[a:filetype]
  if !has_key(s:servers, command) | return 'unknown' | endif
  return s:servers[command]['status']
endfunction

function! lsc#server#servers() abort
  return s:servers
endfunction

function! lsc#server#kill(file_type) abort
  let command = g:lsc_server_commands[a:file_type]
  if !has_key(s:servers, command) | return | endif
  call lsc#server#call(a:file_type, 'shutdown', '')
  call lsc#server#call(a:file_type, 'exit', '')
  let s:servers[command]['status'] = 'exiting'
endfunction

function! lsc#server#restart() abort
  let command = g:lsc_server_commands[&filetype]
  let server_info = s:servers[command]
  let old_status = server_info.status
  if old_status == 'starting' || old_status == 'running'
    call lsc#server#kill(&filetype)
    let server_info.status = 'restarting'
  else
    call s:Start(command)
  endif
endfunction

" A server call explicitly initiated by the user for the current buffer.
"
" Expects the call to succeed and shows an error if it does not.
function! lsc#server#userCall(method, params, callback) abort
  let result = lsc#server#call(&filetype, a:method, a:params, a:callback)
  if !result
    call lsc#message#error('Failed to call '.a:method)
    call lsc#message#error('Server status: '.lsc#server#status(&filetype))
  endif
endfunction

" Call a method on the language server for `file_type`.
"
" Formats a message calling `method` with parameters `params`. If called with 4
" arguments the fourth should be a funcref which will be called when the server
" returns a result for this call.
function! lsc#server#call(file_type, method, params, ...) abort
  if a:0 >= 1
    let [call_id, message] = lsc#protocol#formatRequest(a:method, a:params)
    call lsc#dispatch#registerCallback(call_id, a:1)
  else
    let message = lsc#protocol#formatNotification(a:method, a:params)
  endif
  if a:0 >= 2
    let override_initialize = a:2
  else
    let override_initialize = v:false
  endif
  let command = g:lsc_server_commands[a:file_type]
  if !has_key(s:servers, command) | return v:false | endif
  let server_info = s:servers[command]
  if server_info.status != 'running' && !override_initialize
    return v:false
  endif
  let channel = server_info.channel
  if ch_status(channel) != 'open' | return v:false | endif
  call ch_sendraw(channel, message)
  let stored_call = {'method': a:method, 'params': a:params}
  if exists('l:call_id') | let stored_call.call_id = call_id | endif
  call lsc#util#shift(server_info.calls, 10, stored_call)
  return v:true
endfunction

" Start a language server using `command` if it isn't already running.
function! s:Start(command) abort
  if has_key(s:servers, a:command) && has_key(s:servers[a:command], 'channel')
    return
  endif

  if a:command =~? ':'
    let channel_options = {'mode': 'raw', 'callback': 'lsc#server#callback'}
    let channel = ch_open(a:command, channel_options)
  else
    let job_options = {'in_io': 'pipe', 'in_mode': 'raw',
        \ 'out_io': 'pipe', 'out_mode': 'raw', 'out_cb': 'lsc#server#callback',
        \ 'exit_cb': 'lsc#server#onExit'}
    let job = job_start(a:command, job_options)
    let channel = job_getchannel(job)
  endif
  let server = {
      \ 'status': 'starting',
      \ 'buffer': '',
      \ 'channel': channel,
      \ 'calls': [],
      \ 'messages': [],
      \ 'filetypes': s:FileTypesForServer(a:command),
      \}
  let s:servers[a:command] = server
  let ch_id = ch_info(channel)['id']
  let s:server_names[ch_id] = a:command
  function! OnInitialize(init_result) closure abort
    let server.init_result = a:init_result
    let server.status = 'running'
    if type(a:init_result) == v:t_dict
      call s:CheckCapabilities(a:init_result, server)
    endif
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
      \ 'rootUri': lsc#uri#documentUri(getcwd()),
      \ 'capabilities': s:client_capabilities,
      \ 'trace': trace_level
      \}
  call lsc#server#call(&filetype, 'initialize',
      \ params, function('OnInitialize'), v:true)
endfunction

" Returns a list of filetypes handled by [server_name]
function! s:FileTypesForServer(server_name) abort
  return filter(keys(g:lsc_server_commands),
      \ {idx, val -> s:ServerForFileType(val) == a:server_name})
endfunction

" Returns the server name which handles [filetype]
function! s:ServerForFileType(filetype) abort
  " TODO - handle dictionaries
  " TODO - multiple servers?
  return g:lsc_server_commands[a:filetype]
endfunction

function! s:CheckCapabilities(init_results, server) abort
  " TODO: Check with more depth IE whether go to definition works
  if has_key(a:init_results, 'capabilities')
    let capabilities = a:init_results['capabilities']
    if has_key(capabilities, 'completionProvider')
      let completion_provider = capabilities['completionProvider']
      if has_key(completion_provider, 'triggerCharacters')
        let trigger_characters = completion_provider['triggerCharacters']
        for filetype in a:server.filetypes
          call lsc#complete#setTriggers(filetype, trigger_characters)
        endfor
      endif
    endif
    if has_key(capabilities, 'textDocumentSync')
      let text_document_sync = capabilities['textDocumentSync']
      let supports_incremental = v:false
      if type(text_document_sync) == v:t_dict
        if has_key(text_document_sync, 'change')
          let supports_incremental = text_document_sync['change'] == 2
        endif
      else
        let supports_incremental = text_document_sync == 2
      endif
      if supports_incremental
        for filetype in a:server.filetypes
          call lsc#file#enableIncrementalSync(filetype)
        endfor
      endif
    endif
  endif
endfunction

" Find the command for `job` and clean up it's state
function! lsc#server#onExit(job, status) abort
  let channel = job_getchannel(a:job)
  call lsc#server#onClose(channel)
endfunction

" Find the command for `channel` and clean up it's state
function! lsc#server#onClose(channel) abort
  let ch_id = ch_info(a:channel)['id']
  let server_name = s:server_names[ch_id]
  unlet s:server_names[ch_id]
  call s:OnExit(server_name)
endfunction

" Clean up stored state about a running server.
function! s:OnExit(server_name) abort
  let server_info = s:servers[a:server_name]
  unlet server_info.channel
  let old_status = server_info.status
  if old_status == 'starting'
    let server_info.status= 'failed'
    call lsc#message#error('Failed to initialize server: '.a:server_name)
    if server_info.buffer !=# ''
      call lsc#message#error('Last received: '.server_info.buffer)
    endif
  elseif old_status == 'exiting'
    let server_info.status= 'exited'
  elseif old_status == 'running'
    let server_info.status = 'unexpected exit'
    call lsc#message#error('Command exited unexpectedly: '.a:server_name)
  endif
  unlet server_info.buffer
  for filetype in keys(g:lsc_server_commands)
    if g:lsc_server_commands[filetype] != a:server_name | continue | endif
    call lsc#complete#clean(filetype)
    call lsc#diagnostics#clean(filetype)
    call lsc#file#clean(filetype)
  endfor
  if old_status == 'restarting'
    call s:Start(a:server_name)
  endif
endfunction

" Append to the buffer for the channel and try to consume a message.
function! lsc#server#callback(channel, message) abort
  let ch_id = ch_info(a:channel)['id']
  let server_name = s:server_names[ch_id]
  let server_info = s:servers[server_name]
  let server_info.buffer .= a:message
  call lsc#protocol#consumeMessage(server_info)
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
