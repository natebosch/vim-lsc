" Use InsertCharPre to reliably know what is typed, but don't send the
" completion request until the file reflects the inserted character. Track typed
" characters in `s:next_char` and use CursorMovedI to act on the change.
"
" Every typed character can potentially start a completion request:
" - "Trigger" characters (.) always start a completion request when they are
"   typed
" - Characters that match '\w' start a completion in words of at least length 3

function! lsc#complete#insertCharPre() abort
  let s:next_char = v:char
endfunction

function! lsc#complete#textChanged() abort
  if &paste | return | endif
  " This may be <BS> or similar if not due to a character typed
  if empty(s:next_char) | return | endif
  call s:typedCharacter()
  let s:next_char = ''
endfunction

function! s:typedCharacter() abort
  if s:isTrigger(s:next_char) || (s:isCompletable() && !s:completion_waiting)
    call s:startCompletion()
  else
    let s:completion_canceled = v:true
  endif
endfunction

if !exists('s:initialized')
  let s:next_char = ''
  let s:completion_waiting = v:false
  let s:completion_id = 1
  let s:completion_canceled = v:false
  let s:initialized = v:true
endif

" TODO: Make this customizable
function! s:isTrigger(char) abort
  return a:char == '.'
endfunction

" TODO: Make this customizable
" Whether the cursor follows at least 3 alphanumeric characters
function! s:isCompletable() abort
  if s:next_char !~ '\w' | return v:false | endif
  let cur_col = col('.')
  if cur_col < 4 | return v:false | endif
  let word = getline('.')[cur_col - 4:cur_col - 2]
  return word =~ '^\w*$'
endfunction

function! s:cancelCompletion() abort
  let s:canceled_completions[s:completion_id] = v:true
endfunction

" Whether the completion should still go through.
"
" - A new completion has not been started
" - Cursor position hasn't changed
" - Completion was not canceled
" TODO: Allow cursor position to change some
function! s:isCompletionValid(old_pos, completion_id) abort
  return a:completion_id == s:completion_id &&
      \ a:old_pos == getcurpos() &&
      \ !s:completion_canceled
endfunction

function! s:startCompletion() abort
  let s:completion_id += 1
  let s:completion_canceled = v:false
  let s:completion_waiting = v:true
  let data = {'old_pos': getcurpos(), 'completion_id': s:completion_id}
  function data.trigger(completions)
    if s:isCompletionValid(self.old_pos, self.completion_id)
      let s:completion_waiting = v:false
      call s:SuggestCompletions(a:completions)
    endif
  endfunction
  call s:SearchCompletions(data.trigger)
endfunction

function! s:SuggestCompletions(completions) abort
  " TODO: Popup the completion menu
  echom 'Would suggestion completions: '.string(a:completions)
endfunction

" Returns a funcref which takes 0 or more ignored arguments, and calls `func`
" with a the arguments `args`.
function! s:apply(func, args) abort
  " Its important that a:func is *not* a direct value in the map. If it was then
  " `self` inside that function would be `data` when it is called, instead of
  " whatever it would be otherwise.
  let data = {'data': [a:func, a:args]}
  function data.trigger(...) abort
    let Func = self.data[0]
    let args = self.data[1]
    call call(Func, args)
  endfunction
  return data.trigger
endfunction

" Flush file contents and call the server to request completions for the current
" cursor position.
function! s:SearchCompletions(onFound) abort
  call lsc#file#flushChanges()
  let params = { 'textDocument': {'uri': lsc#util#documentUri()},
      \ 'position': {'line': line('.') - 1, 'character': col('.') - 1}
      \ }
  call lsc#server#call(&filetype, 'textDocument/completion', params,
      \ lsc#util#compose(a:onFound, function('<SID>labelsOnly')))
endfunction

function! s:labelsOnly(completion_result) abort
  if type(a:completion_result) == type([])
    let completion_items = a:completion_result
  else
    let completion_items = a:completion_result.items
  endif
  call map(completion_items, 'v:val.label')
  return completion_items
endfunction
