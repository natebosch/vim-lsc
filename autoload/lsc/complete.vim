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
    let b:lsc_is_completing = v:true
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

augroup LscCompletion
  autocmd!
  autocmd CompleteDone * let b:lsc_is_completing = v:false
augroup END

" TODO: Make this customizable
" Whether the cursor follows at least 3 word characters, and completion isn't
" already in progress.
function! s:isCompletable() abort
  if exists('b:lsc_is_completing') && b:lsc_is_completing
    return v:false
  endif
  if s:next_char !~ '\w' | return v:false | endif
  let cur_col = col('.')
  if cur_col < 4 | return v:false | endif
  let word = getline('.')[cur_col - 4:cur_col - 2]
  return word =~ '^\w*$'
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
    let s:completion_waiting = v:false
    if s:isCompletionValid(self.old_pos, self.completion_id)
      call s:SuggestCompletions(a:completions)
    else
      let b:lsc_is_completing = v:false
    endif
  endfunction
  call s:SearchCompletions(data.trigger)
endfunction

function! s:SuggestCompletions(completion) abort
  if mode() != 'i' || len(a:completion.items) == 0 | return | endif
  let start = s:FindStart(a:completion)
  let suggestions = a:completion.items
  setl completeopt-=longest
  setl completeopt+=menu,menuone,noinsert,noselect
  call complete(start + 1, suggestions)
endfunction

function! s:FindStart(completion) abort
  if has_key(a:completion, 'start_col')
    return a:completion.start_col
  endif
  return s:GuessCompletionStart()
endfunction

" Finds the last non word character
function! s:GuessCompletionStart()
  let search = col('.') - 2
  let line = getline('.')
  while search > 0
    let char = line[search]
    if char !~ '\w'
      return search + 1
    endif
    let search -= 1
  endwhile
  " TODO: ??? completion at the beginning of the line?
  return 0
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
  return {'items' : completion_items}
endfunction
