"if exists("g:loaded_lsc")
"  finish
"endif
"let g:loaded_lsc = 1

" file_type -> command
if !exists('g:lsc_server_commands')
  let g:lsc_server_commands = {}
endif
if !exists('g:lsc_enable_autocomplete')
  let g:lsc_enable_autocomplete = v:true
endif
if !exists('s:disabled_filetypes')
  let s:disabled_filetypes = {}
endif

command! LSClientGoToDefinition call lsc#reference#goToDefinition()
command! LSClientFindReferences call lsc#reference#findReferences()
command! LSClientShowHover call lsc#reference#hover()
command! LSClientRestartServer call <SID>IfEnabled('lsc#server#restart')
command! LSClientDisable call <SID>Disable()
command! LSClientEnable call <SID>Enable()

" RegisterLanguageServer
"
" Registers a command as the server to start the first time a file with type
" file_type is seen. As long as the server is running it won't be restarted on
" subsequent appearances of this file type. If the server exits it will be
" restarted the next time a window or tab is entered with this file type.
function! RegisterLanguageServer(file_type, command) abort
  if has_key(g:lsc_server_commands, a:file_type)
      \ && a:command != g:lsc_server_commands[a:file_type]
    throw 'Already have a server command for '.a:file_type
  endif
  let g:lsc_server_commands[a:file_type] = a:command
endfunction

augroup LSC
  autocmd!
  " Some state which is logically owned by a buffer is attached to the window in
  " practice and needs to be manage manually:
  "
  " 1. Diagnostic highlights
  " 2. Diagnostic location list
  "
  " The `BufWinEnter` event indicates most times when the buffer <-> window
  " relationship can change. There are some exceptions where this event is not
  " fired such as `:split` and `:lopen` so `WinEnter` is used as a fallback with
  " a block to ensure it only happens once.
  autocmd BufWinEnter * call LSCEnsureCurrentWindowState()
  autocmd WinEnter * call timer_start(1, function('<SID>OnWinEnter'))

  " Window local state is only correctly maintained for the current tab.
  autocmd TabEnter * call lsc#util#winDo('call LSCEnsureCurrentWindowState()')

  autocmd BufNewFile,BufReadPost * call <SID>IfEnabled('lsc#file#onOpen')
  autocmd TextChanged,TextChangedI,CompleteDone *
      \ call <SID>IfEnabled('lsc#file#onChange')
  autocmd BufLeave * call <SID>IfEnabled('lsc#file#flushChanges')

  autocmd CursorMoved * call <SID>IfEnabled('lsc#cursor#onMove')

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
  if !has_key(g:lsc_server_commands, &filetype)
    if exists('w:lsc_diagnostic_matches')
      call lsc#highlights#clear()
    endif
    if exists('w:lsc_diagnostics_version')
      call lsc#diagnostics#clear()
    endif
    return
  endif
  call lsc#highlights#update()
  call lsc#diagnostics#updateLocationList(expand('%:p'))
endfunction

" Run `function` if LSC is enabled for the current filetype.
function! s:IfEnabled(function) abort
  if has_key(g:lsc_server_commands, &filetype)
      \ && !has_key(s:disabled_filetypes, &filetype)
    exec 'call '.a:function.'()'
  endif
endfunction

function! s:Disable() abort
  let s:disabled_filetypes[&filetype] = v:true
  call lsc#server#kill(&filetype)
endfunction

function! s:Enable() abort
  silent! unlet s:disabled_filetypes[&filetype]
  call lsc#server#start(&filetype)
endfunction

" Exit all open language servers.
function! s:OnVimQuit() abort
  for file_type in keys(g:lsc_server_commands)
    call lsc#server#kill(file_type)
  endfor
endfunction

" Highlight groups {{{2
if !hlexists('lscDiagnosticError')
  highlight link lscDiagnosticError Error
endif
if !hlexists('lscDiagnosticWarning')
  highlight link lscDiagnosticWarning SpellBad
endif
if !hlexists('lscDiagnosticInfo')
  highlight link lscDiagnosticInfo SpellBad
endif
if !hlexists('lscDiagnosticHint')
  highlight link lscDiagnosticHint SpellBad
endif
