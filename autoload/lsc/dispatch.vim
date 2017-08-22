" Handle messages received from the server.
function! lsc#dispatch#message(message) abort
  if has_key(a:message, 'method')
    if a:message['method'] ==? 'textDocument/publishDiagnostics'
      let params = a:message['params']
      let file_path = lsc#util#documentPath(params['uri'])
      call lsc#diagnostics#setForFile(file_path, params['diagnostics'])
    else
      echom 'Got notification: '.a:message['method'].
          \ ' params: '.string(a:message['params'])
    endif
  elseif has_key(a:message, 'error')
    call s:handleError(a:message['error'])
  elseif has_key(a:message, 'result')
    let call_id = a:message['id']
    if has_key(s:callbacks, call_id)
      try
        call s:callbacks[call_id][0](a:message['result'])
      catch
        call lsc#util#error('Caught '.string(v:exception).
            \' while handling '.string(call_id))
        let g:lsc_last_error = v:exception
        let g:lsc_last_throwpoint = v:throwpoint
      endtry
      unlet s:callbacks[call_id]
    endif
  else
    echom 'Unknown message type: '.string(a:message)
  endif
endfunction

if !exists('s:callbacks')
  let s:callbacks = {}
endif

function! s:handleError(error) abort
  if has_key(a:error, 'message')
    let message = a:error['message']
  else
    let message = string(a:error)
  endif
  echom 'LSC Error!: '.message
endfunction

function! lsc#dispatch#registerCallback(id, callback) abort
  let s:callbacks[a:id] = [a:callback]
endfunction
