function! lsc#channel#open(command, Callback, ErrCallback, OnExit) abort
  let l:c = s:Channel()
  if type(a:command) == v:t_string && a:command =~# '[^:]\+:\d\+'
    if !exists('*ch_open')
      call lsc#message#error('No support for sockets for '.a:command)
      return v:null
    endif
    let l:channel_options = {'mode': 'raw',
        \ 'callback': {_, message -> a:Callback(message)},
        \ 'close_cb': {_ -> a:OnExit()}}
    call s:WrapVim(ch_open(a:command, l:channel_options), l:c)
    return l:c
  endif
  if exists('*job_start')
    let l:job_options = {'in_io': 'pipe', 'in_mode': 'raw',
        \ 'out_io': 'pipe', 'out_mode': 'raw',
        \ 'out_cb': {_, message -> a:Callback(message)},
        \ 'err_io': 'pipe', 'err_mode': 'nl',
        \ 'err_cb': {_, message -> a:ErrCallback(message)},
        \ 'exit_cb': {_, __ -> a:OnExit()}}
    let l:job = job_start(a:command, l:job_options)
    call s:WrapVim(job_getchannel(l:job), l:c)
    return l:c
  elseif exists('*jobstart')
    let l:job_options = {
        \ 'on_stdout': {_, data, __ -> a:Callback(join(data, "\n"))},
        \ 'on_stderr': {_, data, __ -> a:ErrCallback(join(data, "\n"))},
        \ 'on_exit': {_, __, ___ -> a:OnExit()}}
    let l:job = jobstart(a:command, l:job_options)
    call s:WrapNeovim(l:job, l:c)
    return l:c
  else
    call lsc#message#error('No support for starting jobs')
  endif
endfunction

function! s:Channel() abort
  let l:c = {'send_buffer': ''}

  function l:c.send(message) abort
    let self.send_buffer .= a:message
    call self.__flush()
  endfunction

  function l:c.__flush(...) abort
    if len(self.send_buffer) <= 1024
      call self._send(self.send_buffer)
      let self.send_buffer = ''
    else
      let l:to_send = self.send_buffer[:1023]
      let self.send_buffer = self.send_buffer[1024:]
      call self._send(l:to_send)
      call timer_start(0, self.__flush)
    endif
  endfunction

  return l:c
endfunction

function! s:WrapVim(vim_channel, c) abort
  let a:c._channel = a:vim_channel
  function a:c._send(data) abort
    call ch_sendraw(self._channel, a:data)
  endfunction
endfunction

function! s:WrapNeovim(nvim_job, c) abort
  let a:c['_job'] = a:nvim_job
  function a:c._send(data) abort
    call jobsend(self._job, a:data)
  endfunction
endfunction
