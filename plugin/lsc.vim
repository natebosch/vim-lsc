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

if !exists('g:lsc_running_serverst')
  " Map from command -> channel
  let g:lsc_running_servers = {}
  " Map from job -> command
  let g:lsc_running_jobs = {}
endif

" RunLanguageServer {{{2
function! RunLanguageServer(command) abort
  if has_key(g:lsc_running_servers, a:command)
    return
  endif
  let job_options = {'in_io': 'pipe', 'in_mode': 'raw',
      \ 'out_io': 'pipe', 'out_mode': 'raw',
      \ 'out_cb': 'ChannelCallback',
      \ 'close_cb': 'ChannelClose', 'exit_cb': 'JobExit'}
  let job = job_start(a:command, job_options)
  let pid = job_info(job)['process']
  let channel = job_getchannel(job)
  let g:lsc_running_jobs[pid] = a:command
  let g:lsc_running_servers[a:command] = channel
endfunction

" KillServer {{{2
function! KillServer(server_command) abort
  if !has_key(g:lsc_running_servers, a:server_command)
    return
  endif
  let channel = g:lsc_running_servers[a:server_command]
  call ch_sendraw(channel, '\xA')
  call ch_close(channel)
endfunction

" CallMethod {{{2
"
" Call an random method against `server_command` as a test that the
" communication is working
function! CallMethod(server_command) abort
  if !has_key(g:lsc_running_servers, a:server_command)
    return
  endif
  let channel = g:lsc_running_servers[a:server_command]
  call ch_sendraw(channel, FormatMessage('bar', {}))
endfunction

" FormatMessage {{{2
"
" Format a json rpc string calling `method` with serialized `params` and
" prepend the headers for the language server protocol std io pipe format. Uses
" a monotonically increasing message id.
function! FormatMessage(method, params) abort
  let s:lsc_last_id= get(s:, 'lsc_last_id', 0) + 1
  let message = {'jsonrpc': '2.0', 'id': s:lsc_last_id,
      \ 'method': a:method, 'params': a:params}
  let encoded = json_encode(message)
  let length = len(encoded)
  return "Content-Length:".length."\r\n\r\n".encoded
endfunction

" ChannelCallback {{{2
"
" Called when there is data available from a message server. Since no
" interesting functionality is implemented in my demo server, just echom to
" show communication.
function! ChannelCallback(channel, message) abort
  echom 'Message: '.a:message
endfunction

" ChannelClose {{{2
"
" Print out any remaining data in the channel and a message stating the channel
" was closed.
function! ChannelClose(arg) abort
  while ch_status(a:arg) == 'buffered'
    echom 'Channel Close Message: '.ch_read(a:arg)
  endwhile
  echom 'Channel Closed'
endfunction

" JobExit {{{2
"
" Clean up stored state about a running server.
function! JobExit(job, status) abort
  let pid = job_info(a:job)['process']
  let command = g:lsc_running_jobs[pid]
  unlet g:lsc_running_jobs[pid]
  unlet g:lsc_running_servers[command]
endfunction

" File Tracking {{{1

" auto commands {{{2
augroup LscFileTracking
  autocmd!
  autocmd BufWinEnter,TabEnter,WinEnter * call HandleFileVisible()
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
  call ClearHighlights()
  for diagnostic in a:diagnostics
    let group = SeverityGroup(diagnostic.severity)
    echom 'Highlighting to '.group
    call add(w:lsc_diagnostic_matches, matchaddpos(group, [diagnostic.range]))
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
