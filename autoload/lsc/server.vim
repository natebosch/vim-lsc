" channel id -> received message
let s:channel_buffers = {}
" command -> [call]
let s:buffered_calls = {}
" command -> job
let s:running_servers = {}

function! lsc#server#start(filetype) abort
  for server_command in g:lsc_server_commands[a:filetype]
    call <SID>RunCommand(server_command)
  endfor
endfunction

function! lsc#server#kill(file_type) abort
  call lsc#server#call(a:file_type, 'shutdown', '')
  call lsc#server#call(a:file_type, 'exit', '')
endfunction

function! lsc#server#call(file_type, method, params) abort
  let call = lsc#protocol#format(a:method, a:params)
  for command in g:lsc_server_commands[a:file_type]
    if !has_key(s:running_servers, command)
      call <SID>BufferCall(command, call)
      continue
    endif
    let job = s:running_servers[command]
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

function! lsc#server#readBuffer(ch_id) abort
  return s:channel_buffers[a:ch_id]
endfunction

function! lsc#server#setBuffer(ch_id, message) abort
  let s:channel_buffers[a:ch_id] = a:message
endfunction

function! s:RunCommand(command) abort
  if has_key(s:running_servers, a:command)
    " Server is already running
    return
  endif
  let job_options = {'in_io': 'pipe', 'in_mode': 'raw',
      \ 'out_io': 'pipe', 'out_mode': 'raw',
      \ 'out_cb': 'lsc#server#channelCallback', 'exit_cb': 'lsc#server#onExit'}
  let job = job_start(a:command, job_options)
  let s:running_servers[a:command] = job
  let channel = job_getchannel(job)
  let ch_id = ch_info(channel)['id']
  let s:channel_buffers[ch_id] = ''
  if has_key(s:buffered_calls, a:command)
    for buffered_call in s:buffered_calls[a:command]
      call ch_sendraw(channel, buffered_call)
    endfor
    unlet s:buffered_calls[a:command]
  endif
endfunction

" Clean up stored state about a running server.
function! lsc#server#onExit(job, status) abort
  let channel = job_getchannel(a:job)
  let ch_id = ch_info(channel)['id']
  unlet s:channel_buffers[ch_id]
  for command in keys(s:running_servers)
    if s:running_servers[command] == a:job
      unlet s:running_servers[command]
      return
    endif
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
