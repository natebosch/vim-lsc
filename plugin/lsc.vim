"if exists("g:loaded_lsc")
"  finish
"endif
"let g:loaded_lsc = 1

" Diagnostics {{{

" Highlight groups {{{2
hi link lscDiagnosticError Error
hi link lscDiagnosticWarning Error
hi link lscDiagnosticInfo Error
hi link lscDiagnosticHint Error

" HighlightDiagnostics {{{2
"
" Adds a match to the a highlight group for each diagnostics severity level.
"
" diagnostics: A list of dictionaries. Only the 'severity' and 'range' keys are
" used. See https://git.io/vXiUB
function! HighlightDiagnostics(diagnostics) abort
  if !exists('w:lsc_diagnostic_matches')
    let w:lsc_diagnostic_matches = []
  endif
  for current_match in w:lsc_diagnostic_matches
    call matchdelete(current_match)
  endfor
let w:lsc_diagnostic_matches = []

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
