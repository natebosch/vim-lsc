" Functions related to the wire format of the LSP

if !exists('s:lsc_last_id')
  let s:lsc_last_id = 0
endif

" Format a json rpc string calling `method` with serialized `params` and prepend
" the headers for the language server protocol std io pipe format. Uses a
" monotonically increasing message id.
"
" Returns [Id, formatted message]
function! lsc#protocol#format(method, params) abort
  let s:lsc_last_id += 1
  let message = {'jsonrpc': '2.0', 'id': s:lsc_last_id, 'method': a:method}
  if type(a:params) != 1 || a:params != ''
    let message['params'] = a:params
  endif
  let encoded = json_encode(message)
  let length = len(encoded)
  return [s:lsc_last_id, "Content-Length: ".length."\r\n\r\n".encoded]
endfunction

" Reads from the buffer for ch_id and processes the message. Continues to
" process messages until the buffer is empty. Does nothing if a complete message
" is not available.
function! lsc#protocol#consumeMessage(ch_id) abort
  while s:consumeMessage(a:ch_id) | endwhile
endfunction

function! s:consumeMessage(ch_id) abort
  let message = lsc#server#readBuffer(a:ch_id)
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
  try
    let content = json_decode(payload)
    if type(content) != v:t_dict | throw 1 | endif
  catch
    call lsc#util#error('Could not decode message: '.payload)
  endtry
  if exists('l:content') | call lsc#dispatch#message(content) | endif
  let remaining_message = message[message_end:]
  call lsc#server#setBuffer(a:ch_id, remaining_message)
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
