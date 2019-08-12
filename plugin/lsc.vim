if exists('g:loaded_lsc')
  finish
endif
let g:loaded_lsc = 1

if !exists('g:lsc_servers_by_filetype')
  " filetype -> server name
  let g:lsc_servers_by_filetype = {}
endif
if !exists('g:lsc_enable_autocomplete')
  let g:lsc_enable_autocomplete = v:true
endif
if !exists('g:lsc_auto_completeopt')
  let g:lsc_auto_completeopt = v:true
endif
if !exists('g:lsc_enable_snippet_support')
  let g:lsc_enable_snippet_support = v:false
endif

command! LSClientGoToDefinitionSplit
    \ call lsc#reference#goToDefinition(<q-mods>, 1)
command! LSClientGoToDefinition
    \ call lsc#reference#goToDefinition(<q-mods>, 0)
command! LSClientFindReferences call lsc#reference#findReferences()
command! LSClientNextReference call lsc#reference#findNext(1)
command! LSClientPreviousReference call lsc#reference#findNext(-1)
command! LSClientFindImplementations call lsc#reference#findImplementations()
command! -nargs=? LSClientShowHover call lsc#reference#hover()
command! LSClientDocumentSymbol call lsc#reference#documentSymbols()
command! -nargs=? LSClientWorkspaceSymbol
    \ call lsc#search#workspaceSymbol(<args>)
command! -nargs=? LSClientFindCodeActions
    \ call lsc#edit#findCodeActions(lsc#edit#filterActions(<args>))
command! LSClientAllDiagnostics call lsc#diagnostics#showInQuickFix()
command! LSClientLineDiagnostics call lsc#diagnostics#echoForLine()
command! LSClientSignatureHelp call lsc#signaturehelp#getSignatureHelp()
command! LSClientRestartServer call <SID>IfEnabled('lsc#server#restart')
command! LSClientDisable call lsc#server#disable()
command! LSClientEnable call lsc#server#enable()

if !exists('g:lsc_enable_apply_edit') || g:lsc_enable_apply_edit
  command! -nargs=? LSClientRename call lsc#edit#rename(<args>)
endif


" Returns the status of the language server for the current filetype or empty
" string if it is not configured.
function! LSCServerStatus() abort
  return lsc#server#status(&filetype)
endfunction

" RegisterLanguageServer
"
" Registers a command as the server to start the first time a file with type
" filetype is seen. As long as the server is running it won't be restarted on
" subsequent appearances of this file type. If the server exits it will be
" restarted the next time a window or tab is entered with this file type.
function! RegisterLanguageServer(filetype, config) abort
  call lsc#server#register(a:filetype, a:config)
  for buffer in getbufinfo({'bufloaded': v:true})
    if getbufvar(buffer.bufnr, '&filetype') == a:filetype
      call lsc#server#start(a:filetype)
      return
    endif
  endfor
endfunction

augroup LSC
  autocmd!
  " Some state which is logically owned by a buffer is attached to the window in
  " practice and needs to be manage manually:
  "
  " 1. Diagnostic highlights
  " 2. Diagnostic location list
  "
  " The `BufEnter` event indicates most times when the buffer <-> window
  " relationship can change. There are some exceptions where this event is not
  " fired such as `:split` and `:lopen` so `WinEnter` is used as a fallback with
  " a block to ensure it only happens once.
  autocmd BufEnter * call LSCEnsureCurrentWindowState()
  autocmd WinEnter * call timer_start(1, function('<SID>OnWinEnter'))

  " Window local state is only correctly maintained for the current tab.
  autocmd TabEnter * call lsc#util#winDo('call LSCEnsureCurrentWindowState()')

  autocmd BufNewFile,BufReadPost * call <SID>OnOpen()
  autocmd TextChanged,TextChangedI,CompleteDone *
      \ call <SID>IfEnabled('lsc#file#onChange')
  autocmd BufLeave * call <SID>IfEnabled('lsc#file#flushChanges')
  autocmd BufUnload * call <SID>OnClose()
  autocmd BufWritePost * call <SID>OnWrite()

  autocmd CursorMoved * call <SID>IfEnabled('lsc#cursor#onMove')
  autocmd WinLeave * call <SID>IfEnabled('lsc#cursor#onWinLeave')
  autocmd WinEnter * call <SID>IfEnabled('lsc#cursor#onWinEnter')
  autocmd InsertEnter * call <SID>IfEnabled('lsc#cursor#insertEnter')
  autocmd User LSCOnChangesFlushed
      \ call <SID>IfEnabled('lsc#cursor#onChangesFlushed')

  autocmd TextChangedI * call <SID>IfEnabled('lsc#complete#textChanged')
  autocmd InsertCharPre * call <SID>IfEnabled('lsc#complete#insertCharPre')

  autocmd VimLeave * call lsc#server#exit()
augroup END

" Set window local state only if this is a brand new window which has not
" already been initialized for LSC.
"
" This function must be called on a delay since critical values like
" `expand('%')` and `&filetype` are not correctly set when the event fires. The
" delay means that in the cases where `BufWinEnter` actually runs this will run
" later and do nothing.
function! s:OnWinEnter(timer) abort
  if exists('w:lsc_window_initialized')
    return
  endif
  call LSCEnsureCurrentWindowState()
endfunction

" Update or clear state local to the current window.
function! LSCEnsureCurrentWindowState() abort
  let w:lsc_window_initialized = v:true
  if !has_key(g:lsc_servers_by_filetype, &filetype)
    if exists('w:lsc_diagnostic_matches')
      call lsc#highlights#clear()
    endif
    if exists('w:lsc_diagnostics_version')
      call lsc#diagnostics#clear()
    endif
    if exists('w:lsc_reference_matches')
      call lsc#cursor#clean()
    endif
    return
  endif
  call lsc#diagnostics#updateLocationList(lsc#file#fullPath())
  call lsc#highlights#update()
  call lsc#cursor#onWinEnter()
endfunction

" Run `function` if LSC is enabled for the current filetype.
"
" This should only be used for the autocommands which are known to only fire for
" the current buffer where '&filetype' can be trusted.
function! s:IfEnabled(function, ...) abort
  if !has_key(g:lsc_servers_by_filetype, &filetype) | return | endif
  if !lsc#server#filetypeActive(&filetype) | return | endif
  call call(a:function, a:000)
endfunction

function! s:OnOpen() abort
  if !has_key(g:lsc_servers_by_filetype, &filetype) | return | endif
  call lsc#config#mapKeys()
  if !lsc#server#filetypeActive(&filetype) | return | endif
  call lsc#file#onOpen()
endfunction

function! s:OnClose() abort
  let l:filetype = getbufvar(str2nr(expand('<abuf>')), '&filetype')
  if !has_key(g:lsc_servers_by_filetype, l:filetype) | return | endif
  if !lsc#server#filetypeActive(l:filetype) | return | endif
  let l:full_path = expand('<afile>:p')
  call lsc#file#onClose(l:full_path, l:filetype)
endfunction

function! s:OnWrite() abort
  let l:filetype = getbufvar(str2nr(expand('<abuf>')), '&filetype')
  if !has_key(g:lsc_servers_by_filetype, l:filetype) | return | endif
  if !lsc#server#filetypeActive(l:filetype) | return | endif
  let l:full_path = expand('<afile>:p')
  call lsc#file#onWrite(l:full_path, l:filetype)
endfunction

" Highlight groups {{{2
if !hlexists('lscDiagnosticError')
  highlight link lscDiagnosticError Error
endif
if !hlexists('lscDiagnosticWarning')
  highlight link lscDiagnosticWarning SpellBad
endif
if !hlexists('lscDiagnosticInfo')
  highlight link lscDiagnosticInfo SpellCap
endif
if !hlexists('lscDiagnosticHint')
  highlight link lscDiagnosticHint SpellCap
endif
if !hlexists('lscReference')
  highlight link lscReference CursorColumn
endif
if !hlexists('lscCurrentParameter')
  highlight link lscCurrentParameter CursorColumn
endif
