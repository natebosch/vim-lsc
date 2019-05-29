if !exists('s:initialized')
  let s:current_parameter = ''
  let s:initialized = v:true
endif

function! lsc#signaturehelp#getSignatureHelp() abort
  call lsc#file#flushChanges()
  let l:params = lsc#params#documentPosition()
  " TODO handle multiple servers
  let l:server = lsc#server#forFileType(&filetype)[0]
  call l:server.request('textDocument/signatureHelp', l:params,
      \ lsc#util#gateResult('SignatureHelp', function('<SID>ShowHelp')))
endfunction

function! s:HighlightCurrentParameter() abort
  execute 'match lscCurrentParameter /\V' . s:current_parameter . '/'
endfunction

function! s:ShowHelp(signatureHelp) abort
  let signatures = []
  if has_key(a:signatureHelp, 'signatures')
    if type(a:signatureHelp.signatures) == type([])
      let signatures = a:signatureHelp.signatures
    endif
  endif

  if len(signatures) == 0
    return
  endif

  let active_signature = 0
  if has_key(a:signatureHelp, 'activeSignature')
    let active_signature = a:signatureHelp.activeSignature
    if active_signature >= len(signatures)
      let active_signature = 0
    endif
  endif

  let signature = get(signatures, active_signature)

  if !has_key(signature, 'label')
    return
  endif

  if has_key(a:signatureHelp, 'activeParameter')
    let active_parameter = a:signatureHelp.activeParameter
    if active_parameter < len(signature.parameters)
        \ && has_key(signature.parameters[active_parameter], 'label')
      let s:current_parameter = signature.parameters[active_parameter].label
    endif
  endif

  call lsc#util#displayAsPreview([signature.label], function('<SID>HighlightCurrentParameter'))

endfunction
