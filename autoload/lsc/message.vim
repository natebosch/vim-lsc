function! lsc#message#show(message, ...) abort
  call s:Echo('echo', a:message, get(a:, 1, 'Log'))
endfunction

function! lsc#message#showRequest(message, actions) abort
  let l:options = [a:message]
  for l:index in range(len(a:actions))
    let l:title = get(a:actions, l:index)['title']
    call add(l:options, (l:index + 1) . ' - ' . l:title)
  endfor
  let l:result = inputlist(l:options)
  if l:result <= 0 || l:result - 1 > len(a:actions)
    return v:null
  else
    return get(a:actions, l:result - 1)
  endif
endfunction

function! lsc#message#log(message, type) abort
  call s:Echo('echom', a:message, a:type)
endfunction

function! lsc#message#error(message) abort
  call s:Echo('echom', a:message, 'Error')
endfunction

function! s:Echo(echo_cmd, message, level) abort
  let [l:level, l:hl_group] = s:Level(a:level)
  exec 'echohl '.l:hl_group
  exec a:echo_cmd.' "[lsc:'.l:level.'] ".a:message'
  echohl None
endfunction

function! s:Level(level) abort
  if type(a:level) == type(0)
    if a:level == 1
      return ['Error', 'lscDiagnosticError']
    elseif a:level == 2
      return ['Warning', 'lscDiagnosticWarning']
    elseif a:level == 3
      return ['Info', 'lscDiagnosticInfo']
    endif
    return ['Log', 'None'] " Level 4 or unmatched
  endif
  if a:level ==# 'Error'
    return ['Error', 'lscDiagnosticError']
  elseif a:level ==# 'Warning'
    return ['Warning', 'lscDiagnosticWarning']
  elseif a:level ==# 'Info'
    return ['Info', 'lscDiagnosticInfo']
  endif
  return ['Log', 'None'] " 'Log' or unmatched
endfunction
