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
  " - capabilities. Configuration for client/server interaction.
  " - filetypes. List of filetypes handled by this server.
  " - logs. The last 100 logs from `window/logMessage`.
  " - config. Config dict. Contains:
  "   - name: Same as the key into `s:servers`
  "   - command: Executable
  "   - enabled: (optional) Whether the server should be started.
  "   - message_hooks: (optional) Functions call to override params
  "   - workspace_config: (optional) Arbitrary data to send as
  "     `workspace/didChangeConfiguration` settings on startup.
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
    call a:server._channel.notify('exit', v:null) " Don't block on server status
    if a:OnExit != v:null | call a:OnExit() | endif
  endfunction
  call a:server.request('shutdown', v:null, function('Exit'))
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
  " TODO handle multiple servers
  let l:server = lsc#server#forFileType(&filetype)[0]
  let result = l:server.request(a:method, a:params, a:callback)
  if !result
    call lsc#message#error('Failed to call '.a:method)
    call lsc#message#error('Server status: '.lsc#server#status(&filetype))
  endif
endfunction

" Start `server` if it isn't already running.
function! s:Start(server) abort
  if has_key(a:server, '_channel')
    " Server is already running
    return
  endif
  let l:command = a:server.config.command
  let a:server._channel = lsc#protocol#open(l:command,
      \ function('<SID>Dispatch', [a:server]),
      \ a:server.on_err, a:server.on_exit)
  if type(a:server._channel) == type(v:null)
    let a:server.status = 'failed'
    return
  endif
  function! OnInitialize(init_result) closure abort
    let a:server.status = 'running'
    call a:server.notify('initialized', {})
    if type(a:init_result) == type({}) && has_key(a:init_result, 'capabilities')
      let a:server.capabilities =
          \ lsc#capabilities#normalize(a:init_result.capabilities)
    endif
    if has_key(a:server.config, 'workspace_config')
      call a:server.notify('workspace/didChangeConfiguration', {
          \ 'settings': a:server.config.workspace_config
          \})
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
  let l:params = {'processId': getpid(),
      \ 'rootUri': lsc#uri#documentUri(getcwd()),
      \ 'capabilities': s:ClientCapabilities(),
      \ 'trace': trace_level
      \}
  call a:server._initialize(l:params, function('OnInitialize'))
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
  if type(a:config) == type('')
    let config = {'command': a:config, 'name': a:config}
  elseif type(a:config) == type([])
    let config = {'command': a:config, 'name': string(a:config)}
  else
    if type(a:config) != type({})
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
      \ 'logs': [],
      \ 'filetypes': [a:filetype],
      \ 'config': config,
      \ 'capabilities': lsc#capabilities#defaults()
      \}
  function server.request(method, params, callback) abort
    if self.status != 'running' | return v:false | endif
    let l:params = lsc#config#messageHook(self, a:method, a:params)
    if l:params is lsc#config#skip() | return v:false | endif
    call self._channel.request(a:method, l:params, a:callback)
    return v:true
  endfunction
  function server.notify(method, params) abort
    if self.status != 'running' | return v:false | endif
    let l:params = lsc#config#messageHook(self, a:method, a:params)
    if l:params is lsc#config#skip() | return v:false | endif
    call self._channel.notify(a:method, l:params)
    return v:true
  endfunction
  function server.respond(id, result) abort
    call self._channel.respond(a:id, a:result)
  endfunction
  function server._initialize(params, callback) abort
    let l:params = lsc#config#messageHook(self, 'initialize', a:params)
    call self._channel.request('initialize', l:params, a:callback)
  endfunction
  function server.on_err(message) abort
    if self.status == 'starting'
        \ || !has_key(self.config, 'suppress_stderr')
        \ || !self.config.suppress_stderr
      call lsc#message#error('StdErr from '.self.config.name.': '.a:message)
    endif
  endfunction
  function server.on_exit() abort
    unlet self._channel
    let l:old_status = self.status
    if l:old_status == 'starting'
      let self.status= 'failed'
      call lsc#message#error('Failed to initialize server: '.self.config.name)
    elseif l:old_status == 'exiting'
      let self.status= 'exited'
    elseif l:old_status == 'running'
      let self.status = 'unexpected exit'
      call lsc#message#error('Command exited unexpectedly: '.self.config.name)
    endif
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

function! s:Dispatch(server, method, params, id) abort
  if a:method ==? 'textDocument/publishDiagnostics'
    let file_path = lsc#uri#documentPath(a:params['uri'])
    call lsc#diagnostics#setForFile(file_path, a:params['diagnostics'])
  elseif a:method ==? 'window/showMessage'
    call lsc#message#show(a:params['message'], a:params['type'])
  elseif a:method ==? 'window/showMessageRequest'
    let l:response =
        \ lsc#message#showRequest(a:params['message'], a:params['actions'])
    call a:server.respond(a:id, l:response)
  elseif a:method ==? 'window/logMessage'
    if lsc#config#shouldEcho(a:server, a:params.type)
      call lsc#message#log(a:params.message, a:params.type)
    endif
    call lsc#util#shift(a:server.logs, 100,
        \ {'message': a:params.message, 'type': a:params.type})
  elseif a:method ==? 'window/progress'
    if has_key(a:params, 'message')
      let l:full = a:params['title'] . a:params['message']
      call lsc#message#show('Progress ' . l:full)
    elseif has_key(a:params, 'done')
      call lsc#message#show('Finished ' . a:params['title'])
    else
      call lsc#message#show('Starting ' . a:params['title'])
    endif
  elseif a:method ==? 'workspace/applyEdit'
    let l:applied = lsc#edit#apply(a:params.edit)
    let l:response = {'applied': l:applied}
    call a:server.respond(a:id, l:response)
  elseif a:method =~? '\v^\$'
    call lsc#config#handleNotification(a:server, a:method, a:params)
  else
    echom 'Got notification: ' . a:method .
        \ ' params: ' . string(a:params)
  endif
endfunction
