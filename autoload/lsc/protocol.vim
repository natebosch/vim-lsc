" Functions related to the wire format of the LSP

if !exists('s:lsc_last_id')
  let s:lsc_last_id = 0
endif

" Create a dictionary for the request calling `method` with parameters `params`
" and the next availalbe ID.
"
" Returns [ID, message dictionary]
function! lsc#protocol#formatRequest(method, params) abort
  let s:lsc_last_id += 1
  let message = s:Format(a:method, a:params, s:lsc_last_id)
  return [s:lsc_last_id, message]
endfunction

" Create a dictionary for the notification calling `method` with parameters
" `params`.
"
" Like `formatRequest` but without the 'id' field.
" Returns [formatted message, message dictionary]
function! lsc#protocol#formatNotification(method, params) abort
  return s:Format(a:method, a:params, v:null)
endfunction

" Create a dictionary for the response to a call.
function! lsc#protocol#formatResponse(id, result) abort
  return {'id': a:id, 'result': a:result}
endfunction

function! s:Format(method, params, id) abort
  let message = {'method': a:method}
  if type(a:params) != type(v:null) | let message['params'] = a:params | endif
  if type(a:id) != type(v:null) | let message['id'] = a:id | endif
  return message
endfunction

" Prepend the JSON RPC headers and serialize to JSON.
function! lsc#protocol#encode(message) abort
  let a:message['jsonrpc'] = '2.0'
  let encoded = json_encode(a:message)
  let length = len(encoded)
  return "Content-Length: ".length."\r\n\r\n".encoded
endfunction

" Reads from the buffer for server_name and processes the message. Continues to
" process messages until the buffer is empty. Does nothing if a complete message
" is not available.
function! lsc#protocol#consumeMessage(server) abort
  while s:consumeMessage(a:server) | endwhile
endfunction

function! s:consumeMessage(server) abort
  let message = a:server.buffer
  let end_of_header = stridx(message, "\r\n\r\n")
  if end_of_header < 0
    return v:false
  endif
  let headers = split(message[:end_of_header - 1], "\r\n")
  let message_start = end_of_header + len("\r\n\r\n")
  let message_end = message_start + <SID>ContentLength(headers)
  if len(message) < message_end
    " Wait for the rest of the message to get buffered
    return v:false
  endif
  let payload = message[message_start:message_end-1]
  let remaining_message = message[message_end:]
  let a:server.buffer = remaining_message
  try
    let content = json_decode(payload)
    if type(content) != v:t_dict | throw 1 | endif
  catch
    call lsc#message#error('Could not decode message: '.payload)
  endtry
  if exists('l:content')
    call lsc#util#shift(a:server.messages, 10, content)
    try
      call lsc#dispatch#message(a:server, content)
    catch
      call lsc#message#error('Error dispatching message: '.string(v:exception))
      let g:lsc_last_error = v:exception
      let g:lsc_last_throwpoint = v:throwpoint
      let g:lsc_last_error_message = content
    endtry
  endif
  return remaining_message != ''
endfunction

" Finds the header with 'Content-Length' and returns the integer value
function! s:ContentLength(headers) abort
  for header in a:headers
    if header =~? '^Content-Length'
      let parts = split(header, ':')
      let length = parts[1]
      if length[0] == ' ' | let length = length[1:] | endif
      return length + 0
    endif
  endfor
  return -1
endfunction
