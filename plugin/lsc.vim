"if exists("g:loaded_lsc")
"  finish
"endif
"let g:loaded_lsc = 1

" File tracking {{{1

" Tracked Types {{{2
let g:lsc_tracked_types = ['vim']

" autocmds {{{2

augroup FileTracking
  autocmd!
  autocmd BufWinEnter,TabEnter * call UpdateDisplayedHighlights()
augroup END

" UpdateDisplayedHighlights {{{2
"
" Update highlighting in all windows. A window may have opened, or changed to a
" new buffer, or we may have changed tabs and the highlighting is stale.
function! UpdateDisplayedHighlights() abort
  call WinDo('call UpdateHighlighting()')
endfunction

" Diagnostics {{{1

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

" HighlightDiagnostics {{{2
"
" Adds a match to the a highlight group for each diagnostics severity level.
"
" diagnostics: A list of dictionaries. Only the 'severity' and 'range' keys are
" used. See https://git.io/vXiUB
function! HighlightDiagnostics(diagnostics) abort
  call ClearHighlights()
  for diagnostic in a:diagnostics
    if diagnostic.severity == 1
      let group = 'lscDiagnosticError'
    elseif diagnostic.severity == 2
      let group = 'lscDiagnosticWarning'
    elseif diagnostic.severity == 3
      let group = 'lscDiagnosticInfo'
    elseif diagnostic.severity == 4
      let group = 'lscDiagnosticHint'
    endif
    call add(w:lsc_diagnostic_matches, matchaddpos(group, [diagnostic.range]))
  endfor
endfunction

" ClearHighlights {{{2
"
" Remove any diagnostic highlights in this window.
function! ClearHighlights() abort
  if !exists('w:lsc_diagnostic_matches')
    let w:lsc_diagnostic_matches = []
  endif
  for current_match in w:lsc_diagnostic_matches
    silent! call matchdelete(current_match)
  endfor
  let w:lsc_diagnostic_matches = []
endfunction

" FileDiagnostics {{{2
"
" Finds the diagnostics, if any, for the given file.
function! FileDiagnostics(file_path) abort
  if !exists('g:lsc_file_diagnostics')
    let g:lsc_file_diagnostics = {}
  endif
  if !has_key(g:lsc_file_diagnostics, a:file_path)
    let g:lsc_file_diagnostics[a:file_path] = []
  endif
  return g:lsc_file_diagnostics[a:file_path]
endfunction

" SetFileDiagnostics {{{2
"
" Stores `diagnostics` associated with `file_path`.
function! SetFileDiagnostics(file_path, diagnostics) abort
  if !exists('g:lsc_file_diagnostics')
    let g:lsc_file_diagnostics = {}
  endif
  let g:lsc_file_diagnostics[a:file_path] = a:diagnostics
  call WinDo("call UpdateHighlighting()")
endfunction

" UpdateHighlighting {{{2
"
" Reset the highlighting for this window.
function! UpdateHighlighting() abort
  if index(g:lsc_tracked_types, &filetype) < 0
    call ClearHighlights()
  else
    call HighlightDiagnostics(FileDiagnostics(expand('%:p')))
  endif
endfunction!

" Utilities {{{1

" WinDo {{{2
"
" Run `command` in all windows, keeping old open window.
function! WinDo(command) abort
  let current_window = winnr()
  execute 'windo ' . a:command
  execute current_window . 'wincmd w'
endfunction
