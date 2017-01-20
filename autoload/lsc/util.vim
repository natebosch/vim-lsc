" Run `command` in all windows, keeping old open window.
function! lsc#util#winDo(command) abort
  let current_window = winnr()
  execute 'windo ' . a:command
  execute current_window . 'wincmd w'
endfunction
