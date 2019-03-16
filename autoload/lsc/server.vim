if !exists('s:initialized')
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
  " - channel. The communication channel. See `channel.vim`
  " - calls. The last 10 calls made to the server
  " - messages. The last 10 messages from the server
  " - capabilities. Configuration for client/server interaction.
  " - filetypes. List of filetypes handled by this server.
  " - logs. The last 100 logs from `window/logMessage`.
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

" Returns a list of the servers for the current filetype.
"
" For now there will only ever be 1 or no values in this list.
function! lsc#server#current() abort
  return lsc#server#forFileType(&filetype)
endfunction

" Returns a list of the servers for [filetype].
"
" For now there will only ever be 1 or no values in this list.
function! lsc#server#forFileType(filetype) abort
  if !has_key(g:lsc_servers_by_filetype, a:filetype) | return [] | endif
  return [s:servers[g:lsc_servers_by_filetype[a:filetype]]]
endfunction

" Wait for all running servers to shut down with a 5 second timeout.
function! lsc#server#exit() abort
  let l:exit_start = reltime()
  let l:pending = 0
  function! OnExit() closure abort
    let l:pending -= 1
  endfunction
  for l:server in values(s:servers)
    if s:Kill(l:server, 'exiting', function('OnExit'))
      let l:pending += 1
    endif
  endfor
  while l:pending > 0 && reltimefloat(reltime(l:exit_start)) <= 5.0
    sleep 100m
  endwhile
  return l:pending <= 0
endfunction

" Request a 'shutdown' then 'exit'.
"
" Calls `OnExit` after the exit is requested. Returns `v:false` if no request
" was made because the server is not currently running.
function! s:Kill(server, status, OnExit) abort
  function! Exit(result) closure abort
    let a:server.status = a:status
    call s:Call(a:server, 'exit', v:null, v:true)
    if a:OnExit != v:null | call a:OnExit() | endif
  endfunction
  return s:Call(a:server, 'shutdown', v:null, function('Exit'))
endfunction

function! lsc#server#restart() abort
  let l:server_name = g:lsc_servers_by_filetype[&filetype]
  let l:server = s:servers[l:server_name]
  let l:old_status = l:server.status
  if l:old_status == 'starting' || l:old_status == 'running'
    call s:Kill(l:server, 'restarting', v:null)
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
  return call('<SID>Call', [l:server, a:method, a:params] + a:000)
endfunction

function! s:Call(server, method, params, ...) abort
  if a:server.status != 'running' && !(a:0 >= 2 && a:2)
      return v:false
  endif
  let params = lsc#config#messageHook(a:server, a:method, a:params)
  " If there is a callback this is a request
  if a:0 >= 1
    let [call_id, message] = lsc#protocol#formatRequest(a:method, l:params)
    call lsc#dispatch#registerCallback(call_id, a:1)
  else
    let message = lsc#protocol#formatNotification(a:method, l:params)
  endif
  return a:server.send(message)
endfunction

" Start `server` if it isn't already running.
function! s:Start(server) abort
  if has_key(a:server, 'channel')
    " Server is already running
    return
  endif
  let l:command = a:server.config.command
  let a:server.buffer = ''
  let a:server.channel = lsc#channel#open(l:command, a:server.callback,
      \ a:server.err_callback, a:server.on_exit)
  function! OnInitialize(init_result) closure abort
    let a:server.status = 'running'
    call s:Call(a:server, 'initialized', {})
    if type(a:init_result) == v:t_dict && has_key(a:init_result, 'capabilities')
      let a:server.capabilities =
          \ lsc#capabilities#normalize(a:init_result.capabilities)
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
  call s:Call(a:server, 'initialize',
      \ params, function('OnInitialize'), v:true)
endfunction

" Missing value means no support
function! s:ClientCapabilities() abort
  let applyEdit = v:false
  if !exists('g:lsc_enable_apply_edit') || g:lsc_enable_apply_edit
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
    \     'completionItem': {
    \       'snippetSupport': g:lsc_enable_snippet_support,
    \      },
    \   },
    \   'definition': {'dynamicRegistration': v:false},
    \   'codeAction': {
    \     'codeActionLiteralSupport': {
    \       'codeActionKind': {'valueSet': ['quickfix', 'refactor', 'source']}
    \     }
    \   },
    \   'signatureHelp': {'dynamicRegistration': v:false},
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
  let l:server = s:servers[g:lsc_servers_by_filetype[&filetype]]
  let l:server.config.enabled = v:false
  call s:Kill(l:server, 'disabled', v:null)
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
  elseif type(a:config) == v:t_list
    let config = {'command': a:config, 'name': string(a:config)}
  else
    if type(a:config) != v:t_dict
      throw 'Server configuration must be an executable or a dict'
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
      \ 'logs': [],
      \ 'filetypes': [a:filetype],
      \ 'config': config,
      \ 'send_buffer': '',
      \ 'capabilities': lsc#capabilities#defaults()
      \}
  function server.send(message) abort
    if !has_key(self, 'channel') | return v:false | endif
    call lsc#util#shift(self.calls, 10, a:message)
    call self.channel.send(lsc#protocol#encode(a:message))
    return v:true
  endfunction
  function server.callback(message) abort
    let self.buffer .= a:message
    call lsc#protocol#consumeMessage(self)
  endfunction
  function server.log(message, type) abort
    if lsc#config#shouldEcho(self, a:type)
      call lsc#message#log(a:message, a:type)
    endif
    call lsc#util#shift(self.logs, 100, {'message': a:message, 'type': a:type})
  endfunction
  function server.err_callback(message) abort
    if self.status == 'starting'
        \ || !has_key(self.config, 'suppress_stderr')
        \ || !self.config.suppress_stderr
      call lsc#message#error('StdErr from '.self.config.name.': '.a:message)
    endif
  endfunction
  function server.on_exit() abort
    unlet self.channel
    let l:old_status = self.status
    if l:old_status == 'starting'
      let self.status= 'failed'
      call lsc#message#error('Failed to initialize server: '.self.config.name)
      if self.buffer !=# ''
        call lsc#message#error('Last received: '.self.buffer)
      endif
    elseif l:old_status == 'exiting'
      let self.status= 'exited'
    elseif l:old_status == 'running'
      let self.status = 'unexpected exit'
      call lsc#message#error('Command exited unexpectedly: '.self.config.name)
    endif
    unlet self.buffer
    for filetype in self.filetypes
      call lsc#complete#clean(filetype)
      call lsc#diagnostics#clean(filetype)
      call lsc#file#clean(filetype)
      call lsc#cursor#clean()
    endfor
    if l:old_status == 'restarting'
      call s:Start(self)
    endif
  endfunction
  let s:servers[config.name] = server
endfunction
