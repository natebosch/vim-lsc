function! lsc#cursor#onMove() abort
  let diagnostic = lsc#diagnostics#underCursor()
  if has_key(diagnostic, 'message')
    echo diagnostic.message
  else
    echo ''
  endif
endfunction
