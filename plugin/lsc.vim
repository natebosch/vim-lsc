if exists("g:loaded_lsc")
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

command! LSClientGoToDefinition call lsc#reference#goToDefinition()
command! LSClientFindReferences call lsc#reference#findReferences()
command! LSClientNextReference call lsc#reference#findNext(1)
command! LSClientPreviousReference call lsc#reference#findNext(-1)
command! LSClientFindImplementations call lsc#reference#findImplementations()
command! LSClientShowHover call lsc#reference#hover()
command! LSClientDocumentSymbol call lsc#reference#documentSymbols()
command! -nargs=? LSClientWorkspaceSymbol
    \ call lsc#search#workspaceSymbol(<args>)
command! LSClientFindCodeActions call lsc#edit#findCodeActions()
command! LSClientAllDiagnostics call lsc#diagnostics#showInQuickFix()
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
  for buffer in getbufinfo({'loaded': v:true})
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
  autocmd BufUnload * call <SID>IfEnabled('lsc#file#onClose', expand("<afile>"))

  autocmd CursorMoved * call <SID>IfEnabled('lsc#cursor#onMove')
  autocmd WinLeave * call <SID>IfEnabled('lsc#cursor#onWinLeave')
  autocmd WinEnter * call <SID>IfEnabled('lsc#cursor#onWinEnter')
  autocmd InsertEnter * call <SID>IfEnabled('lsc#cursor#insertEnter')
  autocmd User LSCOnChangesFlushed
      \ call <SID>IfEnabled('lsc#cursor#onChangesFlushed')

  autocmd TextChangedI * call <SID>IfEnabled('lsc#complete#textChanged')
  autocmd InsertCharPre * call <SID>IfEnabled('lsc#complete#insertCharPre')

  autocmd VimLeave * call <SID>OnVimQuit()
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
  call lsc#diagnostics#updateLocationList(expand('%:p'))
  call lsc#highlights#update()
  call lsc#cursor#onWinEnter()
endfunction

" Run `function` if LSC is enabled for the current filetype.
function! s:IfEnabled(function, ...) abort
  if !has_key(g:lsc_servers_by_filetype, &filetype) | return | endif
  if !lsc#server#filetypeActive(&filetype) | return | endif
  call call(a:function, a:000)
endfunction

" Exit all open language servers.
function! s:OnVimQuit() abort
  for file_type in keys(g:lsc_servers_by_filetype)
    call lsc#server#kill(file_type)
  endfor
endfunction

function! s:OnOpen() abort
  if !has_key(g:lsc_servers_by_filetype, &filetype) | return | endif
  call lsc#config#mapKeys()
  if !lsc#server#filetypeActive(&filetype) | return | endif
  call lsc#file#onOpen()
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
