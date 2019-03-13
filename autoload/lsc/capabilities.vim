" Returns a client specific view of capabilities.
"
" Capabilities are filtered down to those this client cares about, and
" strucutured to direclty answer the questions we have rather than use the LSP
" types.
function! lsc#capabilities#normalize(capabilities) abort
  let l:normalized = lsc#capabilities#defaults()
  if has_key(a:capabilities, 'completionProvider')
    let l:completion_provider = a:capabilities['completionProvider']
    if has_key(l:completion_provider, 'triggerCharacters')
      let l:normalized.completion.triggerCharacters =
          \ l:completion_provider['triggerCharacters']
    endif
  endif
  if has_key(a:capabilities, 'textDocumentSync')
    let l:text_document_sync = a:capabilities['textDocumentSync']
    let l:incremental = v:false
    let l:send_did_save = v:true
    if type(l:text_document_sync) == v:t_dict
      if has_key(l:text_document_sync, 'change')
        let l:incremental = l:text_document_sync['change'] == 2
      endif
      if !has_key(l:text_document_sync, 'save')
        let l:send_did_save = v:false
      endif
    else
      let l:incremental = l:text_document_sync == 2
    endif
    let l:normalized.textDocumentSync.incremental = l:incremental
    let l:normalized.textDocumentSync.sendDidSave = l:send_did_save
  endif
  if has_key(a:capabilities, 'documentHighlightProvider')
    let l:normalized.referenceHighlights =
        \ a:capabilities.documentHighlightProvider
  endif
  return l:normalized
endfunction

function! lsc#capabilities#defaults() abort
  return {
      \ 'completion': {'triggerCharacters': []},
      \ 'textDocumentSync': {
      \   'incremental': v:false,
      \   'sendDidSave': v:false,
      \ },
      \ 'referenceHighlights': v:false,
      \}
endfunction
