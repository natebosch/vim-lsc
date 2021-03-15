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
    let l:self._call_id += 1
    let l:message = s:Format(a:method, a:params, l:self._call_id)
    let l:self._callbacks[l:self._call_id] = [a:callback]
    call l:self._send(l:message)
  endfunction
  function! l:c.notify(method, params) abort
    let l:message = s:Format(a:method, a:params, v:null)
    cal lsc#util#shift(l:self._in, 10, l:message)
    call l:self._send(l:message)
  endfunction
  function! l:c.respond(id, result) abort
    call l:self._send({'id': a:id, 'result': a:result})
  endfunction
  function! l:c._send(message) abort
    call lsc#util#shift(l:self._in, 10, a:message)
    call l:self._channel.send(s:Encode(a:message))
  endfunction
  function! l:c._recieve(message) abort
    let l:self._buffer .= a:message
    if has_key(l:self, '_consume') | return | endif
    if s:Consume(l:self)
      let l:self._consume = timer_start(0,
          \ function('<SID>HandleTimer', [l:self]))
    endif
  endfunction
  let l:channel = lsc#channel#open(a:command, l:c._recieve, a:on_err, a:on_exit)
  if type(l:channel) == type(v:null)
    return v:null
  endif
  let l:c._channel = l:channel
  return l:c
endfunction

function! s:HandleTimer(server, ...) abort
  if s:Consume(a:server)
    let a:server._consume = timer_start(0,
        \ function('<SID>HandleTimer', [a:server]))
  else
    unlet a:server._consume
  endif
endfunction

function! s:Format(method, params, id) abort
  let l:message = {'method': a:method}
  if type(a:params) != type(v:null) | let l:message['params'] = a:params | endif
  if type(a:id) != type(v:null) | let l:message['id'] = a:id | endif
  return l:message
endfunction

" Prepend the JSON RPC headers and serialize to JSON.
function! s:Encode(message) abort
  let a:message['jsonrpc'] = '2.0'
  let l:encoded = json_encode(a:message)
  let l:length = len(l:encoded)
  return 'Content-Length: '.l:length."\r\n\r\n".l:encoded
endfunction

" Reads from the buffer for server_name and processes the message. Continues to
" process messages until the buffer is empty. Does nothing if a complete message
" is not available.
function! s:Consume(server) abort
  let l:message = a:server._buffer
  let l:end_of_header = stridx(l:message, "\r\n\r\n")
  if l:end_of_header < 0
    return v:false
  endif
  let l:headers = split(l:message[:l:end_of_header - 1], "\r\n")
  let l:message_start = l:end_of_header + len("\r\n\r\n")
  let l:message_end = l:message_start + s:ContentLength(l:headers)
  if len(l:message) < l:message_end
    " Wait for the rest of the message to get buffered
    return v:false
  endif
  let l:payload = l:message[l:message_start : l:message_end-1]
  let l:remaining_message = l:message[l:message_end : ]
  let a:server._buffer = l:remaining_message
  try
    if len(l:payload) > 0
      let l:content = json_decode(l:payload)
      if type(l:content) != type({})
        unlet l:content
        throw 1
      endif
    endif
  catch
    call lsc#message#error('Could not decode message: ['.l:payload.']')
  endtry
  if exists('l:content')
    call lsc#util#shift(a:server._out, 10, l:content)
    call timer_start(0, function('<SID>Dispatch',
        \ [l:content, a:server._on_message, a:server._callbacks]))
  endif
  return l:remaining_message !=# ''
endfunction

" Finds the header with 'Content-Length' and returns the integer value
function! s:ContentLength(headers) abort
  for l:header in a:headers
    if l:header =~? '^Content-Length'
      let l:parts = split(l:header, ':')
      let l:length = l:parts[1]
      if l:length[0] ==# ' ' | let l:length = l:length[1:] | endif
      return l:length + 0
    endif
  endfor
  return -1
endfunction

function! s:Dispatch(message, OnMessage, callbacks, ...) abort
  try
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
    elseif has_key(a:message, 'id')
      let l:call_id = a:message['id']
      if has_key(a:callbacks, l:call_id)
        let l:Callback = a:callbacks[l:call_id][0]
        unlet a:callbacks[l:call_id]
        call l:Callback(get(a:message, 'result', v:null))
      endif
    else
      call lsc#message#error('Unknown message type: '.string(a:message))
    endif
  catch
    call lsc#message#error('Error dispatching message: '.string(v:exception))
    let g:lsc_last_error = v:exception
    let g:lsc_last_throwpoint = v:throwpoint
    let g:lsc_last_error_message = a:message
  endtry
endfunction
