"if exists("g:loaded_lsc")
"  finish
"endif
"let g:loaded_lsc = 1

" file_type -> [command]
if !exists('g:lsc_server_commands')
  let g:lsc_server_commands = {}
endif

" RegisterLanguagServer {{{3
"
" Registers a command as the server to start the first time a file with type
" file_type is seen. As long as the server is running it won't be restarted on
" subsequent appearances of this file type. If the server exits it will be
" restarted the next time a window or tab is entered with this file type.
function! RegisterLanguageServer(file_type, command) abort
  if !has_key(g:lsc_server_commands, a:file_type)
    let g:lsc_server_commands[a:file_type] = []
  endif
  let type_commands = g:lsc_server_commands[a:file_type]
  if index(type_commands, a:command) >= 0
    return
  endif
  call add(type_commands, a:command)
endfunction

augroup LSC
  autocmd!
  autocmd BufWinEnter,TabEnter,WinEnter,WinLeave *
      \ call <SID>IfEnabled('lsc#highlights#updateDisplayed')
  autocmd BufNewFile,BufReadPost * call <SID>IfEnabled('lsc#file#onOpen')
  autocmd TextChanged,TextChangedI,CompleteDone *
      \ call <SID>IfEnabled('lsc#file#onChange')
  autocmd BufLeave * call <SID>IfEnabled('lsc#file#onLeave')
  autocmd CursorMoved * call <SID>IfEnabled('lsc#cursor#onMove')
  autocmd TextChangedI * call <SID>IfEnabled('lsc#complete#textChanged')
  autocmd InsertCharPre * call <SID>IfEnabled('lsc#complete#insertCharPre')
  autocmd VimLeave * call <SID>OnVimQuit()
augroup END

" Run `function` if LSC is enabled for the current filetype.
function! s:IfEnabled(function) abort
  if has_key(g:lsc_server_commands, &filetype)
    exec 'call '.a:function.'()'
  endif
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
