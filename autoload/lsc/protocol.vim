function! lsc#protocol#open(command, on_message, on_err, on_exit) abort
  let l:c = {
      \ '_call_id': 0,
      \ '_in': [],
      \ '_out': [],
      \ '_buffer': '',
      \ '_on_message': a:on_message,
      \ '_callbacks': {},
      \}
  function! l:c.request(method, params, callback) abort
    let self._call_id += 1
    let l:message = s:Format(a:method, a:params, self._call_id)
    let self._callbacks[self._call_id] = [a:callback]
    call self._send(l:message)
  endfunction
  function! l:c.notify(method, params) abort
    let l:message = s:Format(a:method, a:params, v:null)
    cal lsc#util#shift(self._in, 10, l:message)
    call self._send(l:message)
  endfunction
  function! l:c.respond(id, result) abort
    call self._send({'id': a:id, 'result': a:result})
  endfunction
  function! l:c._send(message) abort
    call lsc#util#shift(self._in, 10, a:message)
    call self._channel.send(s:Encode(a:message))
  endfunction
  function! l:c._recieve(message) abort
    let self._buffer .= a:message
    while s:Consume(self) | endwhile
  endfunction
  let l:channel = lsc#channel#open(a:command, l:c._recieve, a:on_err, a:on_exit)
  if type(l:channel) == type(v:null)
    return v:null
  endif
  let l:c._channel = l:channel
  return l:c
endfunction

function! s:Format(method, params, id) abort
  let message = {'method': a:method}
  if type(a:params) != type(v:null) | let message['params'] = a:params | endif
  if type(a:id) != type(v:null) | let message['id'] = a:id | endif
  return message
endfunction

" Prepend the JSON RPC headers and serialize to JSON.
function! s:Encode(message) abort
  let a:message['jsonrpc'] = '2.0'
  let encoded = json_encode(a:message)
  let length = len(encoded)
  return 'Content-Length: '.length."\r\n\r\n".encoded
endfunction

" Reads from the buffer for server_name and processes the message. Continues to
" process messages until the buffer is empty. Does nothing if a complete message
" is not available.
function! s:Consume(server) abort
  let message = a:server._buffer
  let end_of_header = stridx(message, "\r\n\r\n")
  if end_of_header < 0
    return v:false
  endif
  let headers = split(message[:end_of_header - 1], "\r\n")
  let l:message_start = end_of_header + len("\r\n\r\n")
  let l:message_end = l:message_start + s:ContentLength(headers)
  if len(message) < l:message_end
    " Wait for the rest of the message to get buffered
    return v:false
  endif
  let payload = message[l:message_start : l:message_end-1]
  let remaining_message = message[l:message_end : ]
  let a:server._buffer = remaining_message
  try
    let content = json_decode(payload)
    if type(content) != type({}) | throw 1 | endif
  catch
    call lsc#message#error('Could not decode message: '.payload)
  endtry
  if exists('l:content')
    call lsc#util#shift(a:server._out, 10, content)
    try
      call s:Dispatch(content, a:server._on_message, a:server._callbacks)
    catch
      call lsc#message#error('Error dispatching message: '.string(v:exception))
      let g:lsc_last_error = v:exception
      let g:lsc_last_throwpoint = v:throwpoint
      let g:lsc_last_error_message = content
    endtry
  endif
  return remaining_message !=# ''
endfunction

" Finds the header with 'Content-Length' and returns the integer value
function! s:ContentLength(headers) abort
  for header in a:headers
    if header =~? '^Content-Length'
      let parts = split(header, ':')
      let length = parts[1]
      if length[0] ==# ' ' | let length = length[1:] | endif
      return length + 0
    endif
  endfor
  return -1
endfunction

function! s:Dispatch(message, OnMessage, callbacks) abort
  if has_key(a:message, 'method')
    let l:method = a:message.method
    let l:params = has_key(a:message, 'params') ? a:message.params : v:null
    let l:id = has_key(a:message, 'id') ? a:message.id : v:null
    call a:OnMessage(l:method, l:params, l:id)
  elseif has_key(a:message, 'error')
    let l:error = a:message.error
    let l:message = has_key(l:error, 'message') ?
        \ l:error.message :
        \ string(l:error)
    call lsc#message#error(l:message)
  elseif has_key(a:message, 'result')
    let l:call_id = a:message['id']
    if has_key(a:callbacks, l:call_id)
      let l:Callback = a:callbacks[l:call_id][0]
      unlet a:callbacks[l:call_id]
      call l:Callback(a:message['result'])
    endif
  elseif has_key(a:message, 'id') && has_key(a:callbacks, a:message.id)
    let l:call_id = a:message['id']
    let l:Callback = a:callbacks[l:call_id][0]
    unlet a:callbacks[l:call_id]
    call l:Callback(v:null)
  else
    call lsc#message#error('Unknown message type: '.string(a:message))
  endif
endfunction
