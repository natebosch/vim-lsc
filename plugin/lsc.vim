"if exists("g:loaded_lsc")
"  finish
"endif
"let g:loaded_lsc = 1

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
  if !exists('w:lsc_diagnostic_matches')
    let w:lsc_diagnostic_matches = []
  endif
  for current_match in w:lsc_diagnostic_matches
    silent! call matchdelete(current_match)
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
