function! lsc#cursor#onMove() abort
  let diagnostic = lsc#diagnostics#underCursor()
  if has_key(diagnostic, 'message')
    let max_width = &columns - 18
    if len(diagnostic.message) > max_width
      echo diagnostic.message[:max_width].'...'
    else
      echo diagnostic.message
    endif
  else
    echo ''
  endif
endfunction
