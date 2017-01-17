"if exists("g:loaded_lsc")
"  finish
"endif
"let g:loaded_lsc = 1

" Configuration {{{1

" Map from file_type -> [command]
if !exists('g:lsc_server_commands')
  let g:lsc_server_commands = {}
endif

" RegisterLanguagServer {{{3
"
" Registers a command as the server to start the first time a file with type
" file_type is seen. As long as the server is running it won't be restarted on
" subsequent appearances of this file type. If the server exits it will be
" restarted the next time a window or tab is entered with this file type.
function! RegisterLanguageServer(file_type, command) abort
  if !has_key(g:lsc_server_commands, a:file_type)
    let g:lsc_server_commands[a:file_type] = []
  endif
  let type_commands = g:lsc_server_commands[a:file_type]
  if index(type_commands, a:command) >= 0
    return
  endif
  call add(type_commands, a:command)
endfunction

" Server State {{{1

" Map from command -> job
if !exists('g:lsc_running_servers')
  let g:lsc_running_servers = {}
endif

" Map from command -> [call]
if !exists('g:lsc_buffered_calls')
  let g:lsc_buffered_calls = {}
endif

" Map from channel id -> received message
if !exists('g:lsc_channel_buffers')
  let g:lsc_channel_buffers = {}
endif

" RunLanguageServer {{{2
function! RunLanguageServer(command) abort
  if has_key(g:lsc_running_servers, a:command)
    " Server is already running
    return
  endif
  let job_options = {'in_io': 'pipe', 'in_mode': 'raw',
      \ 'out_io': 'pipe', 'out_mode': 'raw',
      \ 'out_cb': 'ChannelCallback', 'exit_cb': 'JobExit'}
  let job = job_start(a:command, job_options)
  let g:lsc_running_servers[a:command] = job
  let channel = job_getchannel(job)
  let ch_id = ch_info(channel)['id']
  let g:lsc_channel_buffers[ch_id] = ''
  if has_key(g:lsc_buffered_calls, a:command)
    for buffered_call in g:lsc_buffered_calls[a:command]
      call ch_sendraw(channel, buffered_call)
    endfor
    unlet g:lsc_buffered_calls[a:command]
  endif
endfunction

" KillServer {{{2
function! KillServers(file_type) abort
  call CallMethod(a:file_type, 'shutdown', '')
  call CallMethod(a:file_type, 'exit', '')
endfunction

" CallMethod {{{2
"
" Call an random method against `server_command` as a test that the
" communication is working
function! CallMethod(file_type, method, params) abort
  if !has_key(g:lsc_server_commands, a:file_type)
    echo 'No servers configured for '.a:file_type
  endif
  let call = FormatMessage(a:method, a:params)
  for command in g:lsc_server_commands[a:file_type]
    if !has_key(g:lsc_running_servers, command)
      call BufferCall(command, call)
      continue
    endif
    let job = g:lsc_running_servers[command]
    if job_status(job) != 'run'
      continue
    endif
    let channel = job_getchannel(job)
    if ch_status(channel) != 'open'
      continue
    endif
    call ch_sendraw(channel, call)
  endfor
endfunction

" BufferCall {{{2
function! BufferCall(command, call) abort
  if !has_key(g:lsc_buffered_calls, a:command)
    let g:lsc_buffered_calls[a:command] = []
  endif
  call add(g:lsc_buffered_calls[a:command], a:call)
endfunction

" FormatMessage {{{2
"
" Format a json rpc string calling `method` with serialized `params` and
" prepend the headers for the language server protocol std io pipe format. Uses
" a monotonically increasing message id.
function! FormatMessage(method, params) abort
  let s:lsc_last_id= get(s:, 'lsc_last_id', 0) + 1
  let message = {'jsonrpc': '2.0', 'id': s:lsc_last_id, 'method': a:method}
  if type(a:params) != 1 || a:params != ''
    let message['params'] = a:params
  endif
  let encoded = json_encode(message)
  let length = len(encoded)
  return "Content-Length:".length."\r\n\r\n".encoded
endfunction

" ChannelCallback {{{2
"
" Append to the buffer for the channel and try to consume a message.
function! ChannelCallback(channel, message) abort
  let ch_id = ch_info(a:channel)['id']
  let g:lsc_channel_buffers[ch_id] .= a:message
  call ConsumeMessage(ch_id)
endfunction

" ContentLength {{{2
"
" Finds the header with 'Content-Length' and returns the integer value
function! ContentLength(headers) abort
  for header in a:headers
    if header =~? '^Content-Length'
      let parts = split(header, ':')
      return parts[1] + 0
    endif
  endfor
  return -1
endfunction

" ConsumeMessage {{{2
"
" Reads from the buffer for ch_id and processes the message. If multiple
" messages are available consumes the first and then recurses. Does nothing if
" a complete message is not available.
function! ConsumeMessage(ch_id) abort
  let message = g:lsc_channel_buffers[a:ch_id]
  let end_of_header = stridx(message, "\r\n\r\n")
  if end_of_header < 0
    return
  endif
  let headers = split(message[:end_of_header], "\r\n")
  let message_start = end_of_header + len("\r\n\r\n")
  let message_end = message_start + ContentLength(headers)
  if len(message) < message_end
    " Wait for the rest of the message to get buffered
    return
  endif
  let payload = message[message_start:message_end-1]
  let g:lsc_channel_buffers[a:ch_id] = message[message_end:]
  try
    let content = json_decode(payload)
  catch
    echom 'Could not decode message: '.payload
    let content = {}
  endtry
  call HandleMessage(content)
  let remaining_message = message[message_end:]
  let g:lsc_channel_buffers[a:ch_id] = remaining_message
  if remaining_message != ''
    call ConsumeMessage(a:ch_id)
  endif
endfunction

" HandleMessage {{{2
"
" Take action based on a parsed message.
function! HandleMessage(message) abort
  if has_key(a:message, 'method')
    if a:message['method'] ==? 'textDocument/publishDiagnostics'
      let params = a:message['params']
      let file_path = substitute(params['uri'], '^file://', '', 'v')
      call SetFileDiagnostics(file_path, params['diagnostics'])
    else
      echom 'Got notification: '.a:message['method'].
          \ ' params: '.string(a:message['params'])
    endif
  elseif has_key(a:message, 'error')
    echom 'Got error: '.string(a:message['error'])
  elseif has_key(a:message, 'result')
    " Ignore responses?
  else
    echom 'Unknown message type: '.string(a:message)
  endif
endfunction

" JobExit {{{2
"
" Clean up stored state about a running server.
function! JobExit(job, status) abort
  let channel = job_getchannel(a:job)
  let ch_id = ch_info(channel)['id']
  unlet g:lsc_channel_buffers[ch_id]
  for command in keys(g:lsc_running_servers)
    if g:lsc_running_servers[command] == a:job
      unlet g:lsc_running_servers[command]
      return
    endif
  endfor
endfunction

" File Tracking {{{1

" State {{{2

" Map from file path -> file version
if !exists('g:lsc_file_versions')
  let g:lsc_file_versions = {}
endif

" FileVersion {{{3
"
" A monotonically increasing number for each open file.
function! FileVersion(file_path)
  if !has_key(g:lsc_file_versions, a:file_path)
    let g:lsc_file_versions[a:file_path] = 0
  endif
  let file_version = g:lsc_file_versions[a:file_path] + 1
  let g:lsc_file_versions[a:file_path] = file_version
  return file_version
endfunction

" auto commands {{{2
augroup LscFileTracking
  autocmd!
  autocmd BufWinEnter,TabEnter,WinEnter * call HandleFileVisible()
  autocmd BufNewFile,BufReadPost * call HandleFileOpen()
  autocmd TextChanged,TextChangedI * call HandleFileChanged()
  autocmd BufLeave * call FlushFileChanges()
  autocmd VimLeave * call HandleVimQuit()
augroup END

" HandleFileVisible {{{2
"
" Called whenever a file becomes visible. Updates highlights in case they
" changed while the file was in the background, and runs the language server in
" case this is the first time we are seeing the file type.
function! HandleFileVisible() abort
  call UpdateDisplayedHighlights()
  if has_key(g:lsc_server_commands, &filetype)
    for server_command in g:lsc_server_commands[&filetype]
      call RunLanguageServer(server_command)
    endfor
  endif
endfunction

" HandleFileOpen {{{2
function! HandleFileOpen() abort
  if !has_key(g:lsc_server_commands, &filetype)
    return
  endif
  let file_path = expand('%:p')
  let buffer_content = join(getline(1, '$'), "\n")
  let params = {'textDocument':
      \   {'uri': 'file://'.file_path,
      \    'languageId': &filetype,
      \    'version': FileVersion(file_path),
      \    'text': buffer_content
      \   }
      \ }
  call CallMethod(&filetype, 'textDocument/didOpen', params)
endfunction

" From file path to a timer triggering a flush of changes to the language server
if !exists('g:lsc_changed_files')
  let g:lsc_changed_files = {}
endif

" HandleFileChanged {{{2
function! HandleFileChanged() abort
  if !has_key(g:lsc_server_commands, &filetype)
    return
  endif
  let file_path = expand('%:p')
  if has_key(g:lsc_changed_files, file_path)
    call timer_stop(g:lsc_changed_files[file_path])
  endif
  let g:lsc_changed_files[file_path] =
      \ timer_start(500, 'FlushFileChanges', {'repeat': 1})
endfunction

" FlushFileChanges {{{2
"
" Send file changes to the language server for any files which have changed
" since the last time this function ran.
function! FlushFileChanges(...) abort
  let file_path = expand('%:p')
  if !has_key(g:lsc_changed_files, file_path)
    return
  endif
  call timer_stop(g:lsc_changed_files[file_path])
  unlet g:lsc_changed_files[file_path]
  let buffer_content = join(getline(1, '$'), "\n")
  let params = {'textDocument':
      \   {'uri': 'file://'.file_path,
      \    'version': FileVersion(file_path),
      \   },
      \ 'contentChanges': [{'text': buffer_content}],
      \ }
  call CallMethod(&filetype, 'textDocument/didChange', params)
endfunction

" HandleVimQuit {{{2
"
" Exit all open language servers.
function! HandleVimQuit() abort
  for file_type in keys(g:lsc_server_commands)
    echom 'Killing for '.file_type
    call KillServers(file_type)
  endfor
endfunction

" Diagnostics {{{1

" Highlight groups {{{2
if !hlexists('lscDiagnosticError')
  highlight link lscDiagnosticError Error
endif
if !hlexists('lscDiagnosticWarning')
  highlight link lscDiagnosticWarning SpellBad
endif
if !hlexists('lscDiagnosticInfo')
  highlight link lscDiagnosticInfo SpellBad
endif
if !hlexists('lscDiagnosticHint')
  highlight link lscDiagnosticHint SpellBad
endif

" UpdateDisplayedHighlights {{{2
"
" Update highlighting in all windows. A window may have opened, or changed to a
" new buffer, or we may have changed tabs and the highlighting is stale.
function! UpdateDisplayedHighlights() abort
  call WinDo('call UpdateHighlighting()')
endfunction

" HighlightDiagnostics {{{2
"
" Adds a match to the a highlight group for each diagnostics severity level.
"
" diagnostics: A list of dictionaries. Only the 'severity' and 'range' keys are
" used. See https://git.io/vXiUB
function! HighlightDiagnostics(diagnostics) abort
  " TODO perhaps a bit excessive to always readd matches? Maybe keep a version
  " of the diagnostics?
  call ClearHighlights()
  for diagnostic in a:diagnostics
    let group = SeverityGroup(diagnostic.severity)
    let line = diagnostic.range.start.line + 1
    let character = diagnostic.range.start.character + 1
    let length = diagnostic.range.end.character + 1 - character
    let range = [line, character, length]
    call add(w:lsc_diagnostic_matches, matchaddpos(group, [range]))
  endfor
endfunction

" SeverityGroup {{{2
"
" Finds the highlight group given a diagnostic severity level
function! SeverityGroup(severity) abort
    if a:severity == 1
      return 'lscDiagnosticError'
    elseif a:severity == 2
      return 'lscDiagnosticWarning'
    elseif a:severity == 3
      return 'lscDiagnosticInfo'
    elseif a:severity == 4
      return 'lscDiagnosticHint'
    endif
endfunction

" ClearHighlights {{{2
"
" Remove any diagnostic highlights in this window.
function! ClearHighlights() abort
  if !exists('w:lsc_diagnostic_matches')
    let w:lsc_diagnostic_matches = []
  endif
  for current_match in w:lsc_diagnostic_matches
    silent! call matchdelete(current_match)
  endfor
  let w:lsc_diagnostic_matches = []
endfunction

" FileDiagnostics {{{2
"
" Finds the diagnostics, if any, for the given file.
function! FileDiagnostics(file_path) abort
  if !exists('g:lsc_file_diagnostics')
    let g:lsc_file_diagnostics = {}
  endif
  if !has_key(g:lsc_file_diagnostics, a:file_path)
    let g:lsc_file_diagnostics[a:file_path] = []
  endif
  return g:lsc_file_diagnostics[a:file_path]
endfunction

" SetFileDiagnostics {{{2
"
" Stores `diagnostics` associated with `file_path`.
function! SetFileDiagnostics(file_path, diagnostics) abort
  if !exists('g:lsc_file_diagnostics')
    let g:lsc_file_diagnostics = {}
  endif
  let g:lsc_file_diagnostics[a:file_path] = a:diagnostics
  " TODO use setloclist() to add diagnostics
  call WinDo("call UpdateHighlighting()")
endfunction

" UpdateHighlighting {{{2
"
" Reset the highlighting for this window.
function! UpdateHighlighting() abort
  if !has_key(g:lsc_server_commands, &filetype)
    call ClearHighlights()
  else
    call HighlightDiagnostics(FileDiagnostics(expand('%:p')))
  endif
endfunction!

" Utilities {{{1

" WinDo {{{2
"
" Run `command` in all windows, keeping old open window.
function! WinDo(command) abort
  let current_window = winnr()
  execute 'windo ' . a:command
  execute current_window . 'wincmd w'
endfunction
