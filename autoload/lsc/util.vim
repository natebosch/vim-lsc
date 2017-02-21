" Run `command` in all windows, keeping old open window.
function! lsc#util#winDo(command) abort
  let current_window = winnr()
  execute 'keepjumps noautocmd windo '.a:command
  execute 'keepjumps noautocmd '.current_window.'wincmd w'
endfunction

function! lsc#util#documentUri() abort
  return 'file://'.expand('%:p')
endfunction

function! lsc#util#documentPath(uri) abort
  return substitute(a:uri, '^file://', '', 'v')
endfunction

" Returns a funcref which is the result of first calling `inner` and then using
" the result as the argument to `outer`. `inner` may take any number of
" arguments, but `outer` must  take a single argument.
"
" For examples lsc#util#compose(g, f) returns a function (args) => g(f(args)).
function! lsc#util#compose(outer, inner) abort
  let data = {'funcs': [a:outer, a:inner]}
  function data.composed(...) abort
    let Outer = self['funcs'][0]
    let Inner = self['funcs'][1]
    let result = call(Inner, a:000)
    return call(Outer, [result])
  endfunction
  return data.composed
endfunction
