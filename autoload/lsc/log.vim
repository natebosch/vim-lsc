function! lsc#log#create(name) abort
  let l:l = {
      \ 'name': a:name,
      \ '_buf': s:Create(a:name),
      \}
  function l:l.append(message) abort
    call appendbufline(self._buf, '$', a:message)
  endfunction
  function l:l.show() abort
    execute 'sbuffer '.string(self._buf)
  endfunction
  return l:l
endfunction

function! s:Create(name) abort
  let l:buffer = bufnr('lsc_log_'.a:name, v:true)
  call setbufvar(l:buffer, '&buftype', 'nofile')
  call setbufvar(l:buffer, '&bufhidden', 'hide')
  call setbufvar(l:buffer, '&swapfile', 0)
  call setbufvar(l:buffer, '&buflisted', 0)
  return l:buffer
endfunction
