if !exists('s:initialized')
  let s:callback_gates = {}
  let s:au_group_id = 0
  let s:initialized = v:true
endif

" Run `command` in all windows, keeping old open window.
function! lsc#util#winDo(command) abort
  let l:current_window = winnr()
  execute 'keepjumps noautocmd windo '.a:command
  execute 'keepjumps noautocmd '.l:current_window.'wincmd w'
endfunction

" Compare two quickfix or location list items.
"
" Items are compared with priority order:
" filename > line > column > type (severity) > text
"
" filenames within cwd are always considered to have a lower sort than others.
function! lsc#util#compareQuickFixItems(i1, i2) abort
  let l:file_1 = s:QuickFixFilename(a:i1)
  let l:file_2 = s:QuickFixFilename(a:i2)
  if l:file_1 != l:file_2
    return lsc#file#compare(l:file_1, l:file_2)
  endif
  if a:i1.lnum != a:i2.lnum | return a:i1.lnum - a:i2.lnum | endif
  if a:i1.col != a:i2.col | return a:i1.col - a:i2.col | endif
  if has_key(a:i1, 'type') && has_key(a:i2, 'type') && a:i1.type != a:i2.type
    " Reverse order so high severity is ordered first
    return s:QuickFixSeverity(a:i2.type) - s:QuickFixSeverity(a:i1.type)
  endif
  return a:i1.text == a:i2.text ? 0 : a:i1.text > a:i2.text ? 1 : -1
endfunction

function! s:QuickFixSeverity(type) abort
  if a:type ==# 'E' | return 1
  elseif a:type ==# 'W' | return 2
  elseif a:type ==# 'I' | return 3
  elseif a:type ==# 'H' | return 4
  else | return 5
  endif
endfunction

function! s:QuickFixFilename(item) abort
  if has_key(a:item, 'filename')
    return a:item.filename
  endif
  return lsc#file#normalize(bufname(a:item.bufnr))
endfunction

" Populate a buffer with [lines] and show it as a preview window.
"
" If the __lsc_preview__ buffer was already showing, reuse it's window,
" otherwise split a window with a max height of `&previewheight`.
" After the content of the content of the preview window is set,
" `function` is called (the buffer is still the preview).
function! lsc#util#displayAsPreview(lines, filetype, function) abort
  let l:view = winsaveview()
  let l:alternate=@#
  call s:createOrJumpToPreview(s:countDisplayLines(a:lines, &previewheight))
  setlocal modifiable
  setlocal noreadonly
  %d
  call setline(1, a:lines)
  let &filetype = a:filetype
  call a:function()
  setlocal nomodifiable
  setlocal readonly
  wincmd p
  call winrestview(l:view)
  let @#=l:alternate
endfunction

" Approximates the number of lines it will take to display some text assuming an
" 80 character line wrap. Only counts up to `max`.
function! s:countDisplayLines(lines, max) abort
  let l:count = 0
  for l:line in a:lines
    if len(l:line) <= 80
      let l:count += 1
    else
      let l:count += float2nr(ceil(len(l:line) / 80.0))
    endif
    if l:count > a:max | return a:max | endif
  endfor
  return l:count
endfunction

function! s:createOrJumpToPreview(want_height) abort
  let l:windows = range(1, winnr('$'))
  call filter(l:windows, {_, win -> getwinvar(win, "&previewwindow") == 1})
  if len(l:windows) > 0
    execute string(l:windows[0]).' wincmd W'
    edit __lsc_preview__
    if winheight(l:windows[0]) < a:want_height
      execute 'resize '.a:want_height
    endif
  else
    if exists('g:lsc_preview_split_direction')
      let l:direction = g:lsc_preview_split_direction
    else
      let l:direction = ''
    endif
    execute l:direction.' '.string(a:want_height).'split __lsc_preview__'
    if exists('#User#LSCShowPreview')
      doautocmd <nomodeline> User LSCShowPreview
    endif
  endif
  set previewwindow
  set winfixheight
  setlocal bufhidden=hide
  setlocal nobuflisted
  setlocal buftype=nofile
  setlocal noswapfile
endfunction

" Adds [value] to the [list] and removes the earliest entry if it would make the
" list longer than [max_length]
function! lsc#util#shift(list, max_length, value) abort
  call add(a:list, a:value)
  if len(a:list) > a:max_length | call remove(a:list, 0) | endif
endfunction

function! lsc#util#gateResult(name, callback, ...) abort
  if !has_key(s:callback_gates, a:name)
    let s:callback_gates[a:name] = 0
  else
    let s:callback_gates[a:name] += 1
  endif
  let l:gate = s:callback_gates[a:name]
  let l:old_pos = getcurpos()
  if a:0 >= 1 && type(a:1) == type({_->_})
    let l:OnSkip = a:1
  else
    let l:OnSkip = v:false
  endif
  return function('<SID>Gated',
      \ [a:name, l:gate, l:old_pos, a:callback, l:OnSkip])
endfunction

function! s:Gated(name, gate, old_pos, on_call, on_skip, ...) abort
  if s:callback_gates[a:name] != a:gate ||
      \ a:old_pos != getcurpos()
    if type(a:on_skip) == type({_->_})
      call call(a:on_skip, a:000)
    endif
  else
    call call(a:on_call, a:000)
  endif
endfunction

function! lsc#util#noop() abort
endfunction

function! lsc#util#async(name, Callback) abort
  return funcref('<Sid>Async', [a:name, a:Callback])
endfunction

function! s:Async(name, Callback, ...) abort
  call timer_start(0, funcref('<SID>IgnoreArgs', [a:name, a:Callback, a:000]))
endfunction

function! s:IgnoreArgs(name, Callback, args, ...) abort
  try
    call call(a:Callback, a:args)
  catch
    call lsc#message#error('Error from '.a:name.': '.string(v:exception))
    let g:lsc_last_error = v:exception
    let g:lsc_last_throwpoint = v:throwpoint
    let g:lsc_last_error_callback = [a:Callback, a:args]
  endtry
endfunction
