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

function! lsc#util#error(message) abort
  echohl Error
  echom '[lsc] '.a:message
  echohl None
endfunction

if !exists('s:initialized')
  let s:au_group_id = 0
  let s:callbacks = {}
  let s:initialized = v:true
endif

" Schedule [function] to be called once for [event]. The function will only be
" called if [event] fires for the current buffer. Callbacks cannot be canceled.
function! lsc#util#once(event, function) abort
  let s:au_group_id += 1
  let au_group = 'LSC_'.string(s:au_group_id)
  let s:callbacks[au_group] = [a:function]
  exec 'augroup '.au_group
  exec 'autocmd '.a:event.' <buffer> call <SID>Callback("'.au_group.'")'
  exec 'augroup END'
endfunction

function! s:Callback(group)
  exec 'autocmd! '.a:group
  exec 'augroup! '.a:group
  call s:callbacks[a:group][0]()
  unlet s:callbacks[a:group]
endfunction

" Returns the window IDs of the windows showing the buffer opened for
" [file_path].
function! lsc#util#windowsForFile(file_path) abort
  let bufinfo = getbufinfo(a:file_path)[0]
  return copy(bufinfo.windows)
endfunction
