" Returns a client specific view of capabilities.
"
" Capabilities are filtered down to those this client cares about, and
" strucutured to direclty answer the questions we have rather than use the LSP
" types.
function! lsc#capabilities#normalize(capabilities) abort
  let l:normalized = lsc#capabilities#defaults()
  if has_key(a:capabilities, 'completionProvider') &&
      \ type(a:capabilities.completionProvider) != type(v:null)
    let l:completion_provider = a:capabilities.completionProvider
    if has_key(l:completion_provider, 'triggerCharacters')
      let l:normalized.completion.triggerCharacters =
          \ l:completion_provider['triggerCharacters']
    endif
  endif
  if has_key(a:capabilities, 'textDocumentSync')
    let l:text_document_sync = a:capabilities['textDocumentSync']
    let l:incremental = v:false
    if type(l:text_document_sync) == type({})
      if has_key(l:text_document_sync, 'change')
        let l:incremental = l:text_document_sync['change'] == 2
      endif
      let l:normalized.textDocumentSync.sendDidSave =
          \ has_key(l:text_document_sync, 'save')
    else
      let l:incremental = l:text_document_sync == 2
    endif
    let l:normalized.textDocumentSync.incremental = l:incremental
  endif
  let l:document_highlight_provider =
      \ get(a:capabilities, 'documentHighlightProvider', v:false)
  if type(l:document_highlight_provider) == type({})
    let l:normalized.referenceHighlights = v:true
  else
    let l:normalized.referenceHighlights = l:document_highlight_provider
  endif
  if has_key(a:capabilities, 'workspace')
    let l:workspace = a:capabilities.workspace
    if has_key(l:workspace, 'workspaceFolders')
      let l:workspace_folders = l:workspace.workspaceFolders
      if has_key(l:workspace_folders, 'changeNotifications')
        if type(l:workspace_folders.changeNotifications) == type(v:true)
          let l:normalized.workspace.didChangeWorkspaceFolders =
              \ l:workspace_folders.changeNotifications
        else
          " Does not handle deregistration
          let l:normalized.workspace.didChangeWorkspaceFolders = v:true
        endif
      endif
    endif
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
      \ 'workspace': {
      \   'didChangeWorkspaceFolders': v:false,
      \ },
      \}
endfunction
