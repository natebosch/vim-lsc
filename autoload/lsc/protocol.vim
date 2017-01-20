" Functions related to the wire format of the LSP

if !exists('s:lsc_last_id')
  let s:lsc_last_id = 0
endif

" Format a json rpc string calling `method` with serialized `params` and prepend
" the headers for the language server protocol std io pipe format. Uses a
" monotonically increasing message id.
function! lsc#protocol#format(method, params) abort
  let s:lsc_last_id += 1
  let message = {'jsonrpc': '2.0', 'id': s:lsc_last_id, 'method': a:method}
  if type(a:params) != 1 || a:params != ''
    let message['params'] = a:params
  endif
  let encoded = json_encode(message)
  let length = len(encoded)
  return "Content-Length:".length."\r\n\r\n".encoded
endfunction

" Reads from the buffer for ch_id and processes the message. If multiple
" messages are available consumes the first and then recurses. Does nothing if
" a complete message is not available.
function! lsc#protocol#consumeMessage(ch_id) abort
  let message = lsc#server#readBuffer(a:ch_id)
  let end_of_header = stridx(message, "\r\n\r\n")
  if end_of_header < 0
    return
  endif
  let headers = split(message[:end_of_header], "\r\n")
  let message_start = end_of_header + len("\r\n\r\n")
  let message_end = message_start + <SID>ContentLength(headers)
  if len(message) < message_end
    " Wait for the rest of the message to get buffered
    return
  endif
  let payload = message[message_start:message_end-1]
  try
    let content = json_decode(payload)
  catch
    echom 'Could not decode message: '.payload
    let content = {}
  endtry
  call lsc#dispatch#message(content)
  let remaining_message = message[message_end:]
  call lsc#server#setBuffer(a:ch_id, remaining_message)
  if remaining_message != ''
    call lsc#protocol#consumeMessage(a:ch_id)
  endif
endfunction

" Finds the header with 'Content-Length' and returns the integer value
function! s:ContentLength(headers) abort
  for header in a:headers
    if header =~? '^Content-Length'
      let parts = split(header, ':')
      return parts[1] + 0
    endif
  endfor
  return -1
endfunction
