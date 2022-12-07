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

function! lsc#server#start(server) abort
  call s:Start(a:server)
endfunction

function! lsc#server#status(filetype) abort
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
  let l:pending = []
  for l:server in values(s:servers)
    if s:Kill(l:server, 'exiting',
        \ funcref('<SID>OnExit', [l:server.config.name, l:pending]))
      call add(l:pending, l:server.config.name)
    endif
  endfor
  let l:reported = []
  while len(l:pending) > 0 && reltimefloat(reltime(l:exit_start)) <= 5.0
     if reltimefloat(reltime(l:exit_start)) >= 1.0 && l:pending != l:reported
      echo 'Waiting for language server exit: '.join(l:pending, ', ')
      let l:reported = copy(l:pending)
     endif
    sleep 100m
  endwhile
  return len(l:pending) == 0
endfunction

function! s:OnExit(server_name, pending) abort
  call remove(a:pending, index(a:pending, a:server_name))
endfunction

" Request a 'shutdown' then 'exit'.
"
" Calls `OnExit` after the exit is requested. Returns `v:false` if no request
" was made because the server is not currently running.
function! s:Kill(server, status, OnExit) abort
  return a:server.request('shutdown', v:null,
      \ funcref('<SID>HandleShutdownResponse', [a:server, a:status, a:OnExit]),
      \ {'sync': v:true})
endfunction

function! s:HandleShutdownResponse(server, status, OnExit, result) abort
  let a:server.status = a:status
  if has_key(a:server, '_channel')
    " An early exit still could have remove the channel.
    " The status has been updated so `a:server.notify` would bail
    call a:server._channel.notify('exit', v:null)
  endif
  if a:OnExit != v:null | call a:OnExit() | endif
endfunction

function! lsc#server#restart() abort
  let l:server_name = g:lsc_servers_by_filetype[&filetype]
  let l:server = s:servers[l:server_name]
  let l:old_status = l:server.status
  if l:old_status ==# 'starting' || l:old_status ==# 'running'
    call s:Kill(l:server, 'restarting', v:null)
  else
    call s:Start(l:server)
  endif
endfunction

" A server call explicitly initiated by the user for the current buffer.
"
" Expects the call to succeed and shows an error if it does not.
function! lsc#server#userCall(method, params, callback) abort
  " TODO handle multiple servers
  let l:server = lsc#server#forFileType(&filetype)[0]
  let l:result = l:server.request(a:method, a:params, a:callback)
  if !l:result
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
  let a:server.status = 'starting'
  let a:server._channel = lsc#protocol#open(l:command,
      \ function('<SID>Dispatch', [a:server]),
      \ a:server.on_err, a:server.on_exit)
  if type(a:server._channel) == type(v:null)
    let a:server.status = 'failed'
    return
  endif
  if exists('g:lsc_trace_level') &&
      \ index(['off', 'messages', 'verbose'], g:lsc_trace_level) >= 0
    let l:trace_level = g:lsc_trace_level
  else
    let l:trace_level = 'off'
  endif
  let l:params = {'processId': getpid(),
      \ 'clientInfo': {'name': 'vim-lsc'},
      \ 'rootUri': lsc#uri#documentUri(lsc#file#cwd()),
      \ 'capabilities': s:ClientCapabilities(),
      \ 'trace': l:trace_level
      \}
  call a:server._initialize(l:params, funcref('<SID>OnInitialize', [a:server]))
endfunction

function! s:OnInitialize(server, init_result) abort
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
  call lsc#file#trackAll(a:server)
endfunction

" Missing value means no support
function! s:ClientCapabilities() abort
  let l:applyEdit = v:false
  if !exists('g:lsc_enable_apply_edit') || g:lsc_enable_apply_edit
    let l:applyEdit = v:true
  endif
  return {
    \ 'workspace': {
    \   'applyEdit': l:applyEdit,
    \   'configuration': v:true,
    \ },
    \ 'textDocument': {
    \   'synchronization': {
    \     'willSave': v:false,
    \     'willSaveWaitUntil': v:false,
    \     'didSave': v:false,
    \   },
    \   'completion': {
    \     'completionItem': {
    \       'snippetSupport': g:lsc_enable_snippet_support,
    \       'deprecatedSupport': v:true,
    \       'tagSupport': {
    \         'valueSet': [1],
    \       },
    \      },
    \   },
    \   'definition': {'dynamicRegistration': v:false},
    \   'codeAction': {
    \     'codeActionLiteralSupport': {
    \       'codeActionKind': {'valueSet': ['quickfix', 'refactor', 'source']}
    \     }
    \   },
    \   'hover': {'contentFormat': ['plaintext', 'markdown']},
    \   'signatureHelp': {'dynamicRegistration': v:false},
    \   'publishDiagnostics': v:true,
    \ }
    \}
endfunction

function! lsc#server#filetypeActive(filetype) abort
  let l:server = s:servers[g:lsc_servers_by_filetype[a:filetype]]
  return get(l:server.config, 'enabled', v:true)
endfunction

function! lsc#server#disable() abort
  if !has_key(g:lsc_servers_by_filetype, &filetype)
    return v:false
  endif
  let l:server = s:servers[g:lsc_servers_by_filetype[&filetype]]
  let l:server.config.enabled = v:false
  call s:Kill(l:server, 'disabled', v:null)
endfunction

function! lsc#server#enable() abort
  if !has_key(g:lsc_servers_by_filetype, &filetype)
    return v:false
  endif
  let l:server = s:servers[g:lsc_servers_by_filetype[&filetype]]
  let l:server.config.enabled = v:true
  call s:Start(l:server)
endfunction

function! lsc#server#register(filetype, config) abort
  let l:languageId = a:filetype
  if type(a:config) == type('')
    let l:config = {'command': a:config, 'name': a:config}
  elseif type(a:config) == type([])
    let l:config = {'command': a:config, 'name': string(a:config)}
  else
    if type(a:config) != type({})
      throw 'Server configuration must be an executable or a dict'
    endif
    let l:config = a:config
    if !has_key(l:config, 'command')
      throw 'Server configuration must have a "command" key'
    endif
    if !has_key(l:config, 'name')
      let l:config.name = string(l:config.command)
    endif
    if has_key(l:config, 'languageId')
      let l:languageId = l:config.languageId
    endif
  endif
  let g:lsc_servers_by_filetype[a:filetype] = l:config.name
  if has_key(s:servers, l:config.name)
    let l:server = s:servers[l:config.name]
    call add(l:server.filetypes, a:filetype)
    let l:server.languageId[a:filetype] = l:languageId
    return l:server
  endif
  let l:initial_status = 'not started'
  if !get(l:config, 'enabled', v:true)
    let l:initial_status = 'disabled'
  endif
  let l:server = {
      \ 'status': l:initial_status,
      \ 'logs': [],
      \ 'filetypes': [a:filetype],
      \ 'languageId': {},
      \ 'config': l:config,
      \ 'capabilities': lsc#capabilities#defaults()
      \}
  let l:server.languageId[a:filetype] = l:languageId
  function! l:server.request(method, params, callback, ...) abort
    if l:self.status !=# 'running' | return v:false | endif
    let l:params = lsc#config#messageHook(l:self, a:method, a:params)
    if l:params is lsc#config#skip() | return v:false | endif
    let l:Callback = lsc#config#responseHook(l:self, a:method, a:callback)
    let l:options = a:0 > 0 ? a:1 : {}
    call l:self._channel.request(a:method, l:params, l:Callback, l:options)
    return v:true
  endfunction
  function! l:server.notify(method, params) abort
    if l:self.status !=# 'running' | return v:false | endif
    let l:params = lsc#config#messageHook(l:self, a:method, a:params)
    if l:params is lsc#config#skip() | return v:false | endif
    call l:self._channel.notify(a:method, l:params)
    return v:true
  endfunction
  function! l:server.respond(id, result) abort
    call l:self._channel.respond(a:id, a:result)
  endfunction
  function! l:server._initialize(params, callback) abort
    let l:params = lsc#config#messageHook(l:self, 'initialize', a:params)
    call l:self._channel.request('initialize', l:params, a:callback, {})
  endfunction
  function! l:server.on_err(message) abort
    if get(l:self.config, 'suppress_stderr', v:false) | return | endif
    call lsc#message#error('StdErr from '.l:self.config.name.': '.a:message)
  endfunction
  function! l:server.on_exit() abort
    unlet l:self._channel
    let l:old_status = l:self.status
    if l:old_status ==# 'starting'
      let l:self.status= 'failed'
      let l:message = 'Failed to initialize server "'.l:self.config.name.'".'
      if l:self.config.name != string(l:self.config.command)
        let l:message .= ' Failing command is: '.string(l:self.config.command)
      endif
      call lsc#message#error(l:message)
    elseif l:old_status ==# 'exiting'
      let l:self.status= 'exited'
    elseif l:old_status ==# 'running'
      let l:self.status = 'unexpected exit'
      call lsc#message#error('Command exited unexpectedly: '.l:self.config.name)
    endif
    for l:filetype in l:self.filetypes
      call lsc#complete#clean(l:filetype)
      call lsc#diagnostics#clean(l:filetype)
      call lsc#file#clean(l:filetype)
      call lsc#cursor#clean()
    endfor
    if l:old_status ==# 'restarting'
      call s:Start(l:self)
    endif
  endfunction
  function! l:server.find_config(item) abort
    if !has_key(l:self.config, 'workspace_config') | return v:null | endif
    if !has_key(a:item, 'section') || empty(a:item.section)
      return l:self.config.workspace_config
    endif
    let l:config = l:self.config.workspace_config
    for l:part in split(a:item.section, '\.')
      if !has_key(l:config, l:part)
        return v:null
      else
        let l:config = l:config[l:part]
      endif
    endfor
    return l:config
  endfunction
  let s:servers[l:config.name] = l:server
  return l:server
endfunction

function! s:Dispatch(server, method, params, id) abort
  if a:method ==? 'textDocument/publishDiagnostics'
    let l:file_path = lsc#uri#documentPath(a:params['uri'])
    call lsc#diagnostics#setForFile(l:file_path, a:params['diagnostics'])
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
  elseif a:method ==? 'workspace/configuration'
    let l:items = a:params.items
    let l:response = map(l:items, {_, item -> a:server.find_config(item)})
    call a:server.respond(a:id, l:response)
  elseif a:method =~? '\v^\$'
    call lsc#config#handleNotification(a:server, a:method, a:params)
  endif
endfunction
