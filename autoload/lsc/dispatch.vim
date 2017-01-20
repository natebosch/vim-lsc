" Handle messages received from the server.
function! lsc#dispatch#message(message) abort
  if has_key(a:message, 'method')
    if a:message['method'] ==? 'textDocument/publishDiagnostics'
      let params = a:message['params']
      let file_path = substitute(params['uri'], '^file://', '', 'v')
      call lsc#diagnostics#setForFile(file_path, params['diagnostics'])
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
