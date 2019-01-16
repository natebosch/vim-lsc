if !exists('s:initialized')
  let s:current_parameter = ''
  let s:initialized = v:true
endif

function! lsc#signaturehelp#getSignatureHelp() abort
  call lsc#file#flushChanges()
  let params = lsc#params#documentPosition()
  call lsc#server#call(&filetype, 'textDocument/signatureHelp', params,
      \ lsc#util#gateResult('SignatureHelp', function('<SID>ShowSignatureHelp')))
endfunction

function! s:HighlightCurrentParameter() abort
  execute 'match lscCurrentParameter /\V' . s:current_parameter . '/'
endfunction

function! s:ShowSignatureHelp(signatureHelp)

  let signatures = []
  if has_key(a:signatureHelp, 'signatures')
    if type(a:signatureHelp.signatures) == v:t_list
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
