function! lsc#message#show(message, ...) abort
  call s:Echo('echo', a:message, get(a:, 1, 'Log'))
endfunction

function! lsc#message#log(message, ...) abort
  call s:Echo('echom', a:message, get(a:, 1, 'Log'))
endfunction

function! lsc#message#error(message) abort
  call lsc#message#log(a:message, 'Error')
endfunction

function! s:Echo(echo_cmd, message, level) abort
  let [level, hl_group] = s:Level(a:level)
  exec 'echohl '.hl_group
  exec a:echo_cmd.' "[lsc:'.level.'] ".a:message'
  echohl None
endfunction

function! s:Level(level) abort
  if type(a:level) == v:t_number
    if a:level == 1
      return ['Error', 'lscDiagnosticError']
    elseif a:level == 2
      return ['Warning', 'lscDiagnosticWarning']
    elseif a:level == 3
      return ['Info', 'lscDiagnosticInfo']
    endif
    return ['Log', 'None'] " Level 4 or unmatched
  endif
  if a:level == 'Error'
    return ['Error', 'lscDiagnosticError']
  elseif a:level == 'Warning'
    return ['Warning', 'lscDiagnosticWarning']
  elseif a:level == 'Info'
    return ['Info', 'lscDiagnosticInfo']
  endif
  return ['Log', 'None'] " 'Log' or unmatched
endfunction
