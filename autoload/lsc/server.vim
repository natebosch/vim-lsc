if !exists('s:initialized')
  " channel id -> server name
  let s:servers_by_channel = {}
  " server name -> server info.
  "
  " Server name defaults to the command string.
  "
  " Info contains:
  " - status. Possible statuses are:
  "   [disabled, not started,
  "    starting, running, restarting,
  "    exiting,  exited, unexpected exit, failed]
  " - buffer. String received from the server but not processed yet.
  " - channel. The communication channel
  " - calls. The last 10 calls made to the server
  " - messages. The last 10 messages from the server
  " - init_result. The response to the initialization call
  " - filetypes. List of filetypes handled by this server.
  " - config. Config dict. Contains:
  "   - name: Same as the key into `s:servers`
  "   - command: Executable
  "   - enabled: (optional) Whether the server should be started.
  "   - message_hooks: (optional) Functions call to override params
  let s:servers = {}
  let s:initialized = v:true
endif

function! lsc#server#start(filetype) abort
  " Expect filetype is registered
  let server = s:servers[g:lsc_servers_by_filetype[a:filetype]]
  call s:Start(server)
endfunction

function! lsc#server#status(filetype) abort
  if !has_key(g:lsc_servers_by_filetype, a:filetype) | return '' | endif
  return s:servers[g:lsc_servers_by_filetype[a:filetype]].status
endfunction

function! lsc#server#servers() abort
  return s:servers
endfunction

function! lsc#server#kill(filetype) abort
  if !has_key(g:lsc_servers_by_filetype, a:filetype) | return | endif
  call lsc#server#call(a:filetype, 'shutdown', v:null)
  call lsc#server#call(a:filetype, 'exit', v:null)
  let s:servers[g:lsc_servers_by_filetype[a:filetype]].status = 'exiting'
endfunction

function! lsc#server#restart() abort
  let server_name = g:lsc_servers_by_filetype[&filetype]
  let server = s:servers[server_name]
  let old_status = server.status
  if old_status == 'starting' || old_status == 'running'
    call lsc#server#kill(&filetype)
    let server.status = 'restarting'
  else
    call s:Start(server)
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

" Call a method on the language server for `filetype`.
"
" Formats a message calling `method` with parameters `params`. If called with 4
" arguments the fourth should be a funcref which will be called when the server
" returns a result for this call.
"
" If the server has a configured `message_hook` for `method` it will be run to
" adjust `params`.
function! lsc#server#call(filetype, method, params, ...) abort
  if !has_key(g:lsc_servers_by_filetype, a:filetype) | return v:false | endif
  let server = s:servers[g:lsc_servers_by_filetype[a:filetype]]
  if server.status != 'running' && !(a:0 >= 2 && a:2)
      return v:false
  endif
  let params = lsc#config#messageHook(server, a:method, a:params)
  " If there is a callback this is a request
  if a:0 >= 1
    let [call_id, message] = lsc#protocol#formatRequest(a:method, l:params)
    call lsc#dispatch#registerCallback(call_id, a:1)
  else
    let message = lsc#protocol#formatNotification(a:method, l:params)
  endif
  return server.send(message)
endfunction

" Start a language server using `command` if it isn't already running.
function! s:Start(server) abort
  if has_key(a:server, 'channel')
    " Server is already running
    return
  endif
  let command = a:server.config.command
  if command =~# '[^:]\+:\d\+'
    let channel_options = {'mode': 'raw', 'callback': 'lsc#server#callback'}
    let channel = ch_open(command, channel_options)
  else
    let job_options = {'in_io': 'pipe', 'in_mode': 'raw',
        \ 'out_io': 'pipe', 'out_mode': 'raw', 'out_cb': 'lsc#server#callback',
        \ 'err_io': 'pipe', 'err_mode': 'nl', 'err_cb': 'lsc#server#errCallback',
        \ 'exit_cb': 'lsc#server#onExit'}
    let job = job_start(command, job_options)
    let channel = job_getchannel(job)
  endif
  let a:server.channel = channel
  let a:server.buffer = ''
  let ch_id = ch_info(channel)['id']
  let s:servers_by_channel[ch_id] = a:server.config.name
  function! OnInitialize(init_result) closure abort
    let a:server.init_result = a:init_result
    let a:server.status = 'running'
    if type(a:init_result) == v:t_dict
      call s:CheckCapabilities(a:init_result, a:server)
    endif
    for filetype in a:server.filetypes
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
      \ 'capabilities': s:ClientCapabilities(),
      \ 'trace': trace_level
      \}
  call lsc#server#call(&filetype, 'initialize',
      \ params, function('OnInitialize'), v:true)
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
  let server_name = s:servers_by_channel[ch_id]
  unlet s:servers_by_channel[ch_id]
  call s:OnExit(server_name)
endfunction

" Clean up stored state about a running server.
function! s:OnExit(server_name) abort
  let server = s:servers[a:server_name]
  unlet server.channel
  let old_status = server.status
  if old_status == 'starting'
    let server.status= 'failed'
    call lsc#message#error('Failed to initialize server: '.a:server_name)
    if server.buffer !=# ''
      call lsc#message#error('Last received: '.server.buffer)
    endif
  elseif old_status == 'exiting'
    let server.status= 'exited'
  elseif old_status == 'running'
    let server.status = 'unexpected exit'
    call lsc#message#error('Command exited unexpectedly: '.a:server_name)
  endif
  unlet server.buffer
  for filetype in server.filetypes
    call lsc#complete#clean(filetype)
    call lsc#diagnostics#clean(filetype)
    call lsc#file#clean(filetype)
  endfor
  if old_status == 'restarting'
    call s:Start(server)
  endif
endfunction

" Append to the buffer for the channel and try to consume a message.
function! lsc#server#callback(channel, message) abort
  let ch_id = ch_info(a:channel)['id']
  let server_name = s:servers_by_channel[ch_id]
  let server_info = s:servers[server_name]
  let server_info.buffer .= a:message
  call lsc#protocol#consumeMessage(server_info)
endfunction

function! lsc#server#errCallback(channel,  message) abort
  let ch_id = ch_info(a:channel)['id']
  let server_name = s:servers_by_channel[ch_id]
  call lsc#message#error('StdErr from '.server_name.': '.a:message)
endfunction

" Missing value means no support
function! s:ClientCapabilities() abort
  let applyEdit = v:false
  if exists('g:lsc_enable_apply_edit') && g:lsc_enable_apply_edit
    let applyEdit = v:true
  endif
  return {
    \ 'workspace': {
    \   'applyEdit': applyEdit,
    \   },
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
endfunction

function! lsc#server#filetypeActive(filetype) abort
  let server = s:servers[g:lsc_servers_by_filetype[a:filetype]]
  return !has_key(server.config, 'enabled') || server.config.enabled
endfunction

function! lsc#server#disable()
  if !has_key(g:lsc_servers_by_filetype, &filetype)
    return v:false
  endif
  let server = s:servers[g:lsc_servers_by_filetype[&filetype]]
  let server.config.enabled = v:false
  call lsc#server#kill(&filetype)
  let server.status = 'disabled'
endfunction

function! lsc#server#enable()
  if !has_key(g:lsc_servers_by_filetype, &filetype)
    return v:false
  endif
  let server = s:servers[g:lsc_servers_by_filetype[&filetype]]
  let server.config.enabled = v:true
  call s:Start(server)
endfunction

function! lsc#server#register(filetype, config) abort
  if type(a:config) == v:t_string
    let config = {'command': a:config, 'name': a:config}
  else
    if type(a:config) != v:t_dict
      throw 'Server configuration msut be an executable or a dic'
    endif
    let config = a:config
    if !has_key(config, 'command')
      throw 'Server configuration must have a "command" key'
    endif
    if !has_key(config, 'name')
      let config.name = config.command
    endif
  endif
  let g:lsc_servers_by_filetype[a:filetype] = config.name
  if has_key(s:servers, config.name)
    call add(s:servers[config.name].filetypes, a:filetype)
    return
  endif
  let initial_status = 'not started'
  if has_key(config, 'enabled') && !config.enabled
    let initial_status = 'disabled'
  endif
  let server = {
      \ 'status': initial_status,
      \ 'calls': [],
      \ 'messages': [],
      \ 'filetypes': [a:filetype],
      \ 'config': config,
      \ 'send_buffer': '',
      \}
  function server.send(message) abort
    if ch_status(self.channel) != 'open' | return v:false | endif
    call lsc#util#shift(self.calls, 10, a:message)
    let self.send_buffer .= lsc#protocol#encode(a:message)
    call self.flush(v:null)
    return v:true
  endfunction
  function server.flush(_) abort
    if len(self.send_buffer) <= 1024
      call ch_sendraw(self.channel, self.send_buffer)
      let self.send_buffer = ''
    else
      let to_send = self.send_buffer[:1023]
      let self.send_buffer = self.send_buffer[1024:]
      call ch_sendraw(self.channel, to_send)
      call timer_start(0, self.flush)
    endif
  endfunction
  let s:servers[config.name] = server
endfunction
