function! lsc#cursor#onMove() abort
  let diagnostic = lsc#diagnostics#underCursor()
  if has_key(diagnostic, 'message')
    let max_width = &columns - 18
    let message = substitute(diagnostic.message, '\n', '\\n', 'g')
    if len(message) > max_width
      echo message[:max_width].'...'
    else
      echo message
    endif
  else
    echo ''
  endif
endfunction
