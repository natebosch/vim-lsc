" Use InsertCharPre to reliably know what is typed, but don't send the
" completion request until the file reflects the inserted character. Track typed
" characters in `s:next_char` and use CursorMovedI to act on the change.
"
" Every typed character can potentially start a completion request:
" - "Trigger" characters (as specified during initialization) always start a
"   completion request when they are typed
" - Characters that match '\w' start a completion in words of at least length 3

function! lsc#complete#insertCharPre() abort
  let s:next_char = v:char
endfunction

function! lsc#complete#textChanged() abort
  if &paste | return | endif
  if !g:lsc_enable_autocomplete | return | endif
  " This may be <BS> or similar if not due to a character typed
  if empty(s:next_char) | return | endif
  call s:typedCharacter()
  let s:next_char = ''
endfunction

function! s:typedCharacter() abort
  if s:isTrigger(s:next_char) || s:isCompletable()
    call s:startCompletion(v:true)
  endif
endfunction

if !exists('s:initialized')
  let s:next_char = ''
  let s:initialized = v:true
endif

" Clean state associated with a server.
function! lsc#complete#clean(filetype) abort
  for buffer in getbufinfo({'bufloaded': v:true})
    if getbufvar(buffer.bufnr, '&filetype') != a:filetype | continue | endif
    call setbufvar(buffer.bufnr, 'lsc_is_completing', v:false)
  endfor
endfunction

function! s:isTrigger(char) abort
  for l:server in lsc#server#current()
    if index(l:server.capabilities.completion.triggerCharacters, a:char) >= 0
      return v:true
    endif
  endfor
  return v:false
endfunction

augroup LscCompletion
  autocmd!
  autocmd CompleteDone * let b:lsc_is_completing = v:false
      \ | silent! unlet b:lsc_completion | let s:next_char = ''
augroup END

" Whether the cursor follows a minimum count of  word characters, and completion
" isn't already in progress.
"
" Minimum length can be configured with `g:lsc_autocomplete_length`.
function! s:isCompletable() abort
  if exists('b:lsc_is_completing') && b:lsc_is_completing
    return v:false
  endif
  if s:next_char !~# '\w' | return v:false | endif
  let l:cur_col = col('.')
  let l:min_length = exists('g:lsc_autocomplete_length') ?
      \ g:lsc_autocomplete_length : 3
  if l:min_length == v:false | return v:false | endif
  if l:cur_col < (l:min_length + 1) | return v:false | endif
  let word = getline('.')[l:cur_col - (l:min_length + 1):l:cur_col - 2]
  return word =~# '^\w*$'
endfunction

function! s:startCompletion(isAuto) abort
  let b:lsc_is_completing = v:true
  call lsc#file#flushChanges()
  let l:params = lsc#params#documentPosition()
  " TODO handle multiple servers
  let l:server = lsc#server#forFileType(&filetype)[0]
  call l:server.request('textDocument/completion', l:params,
      \ lsc#util#gateResult('Complete',
      \     function('<SID>OnResult', [a:isAuto]),
      \     function('<SID>OnSkip', [bufnr('%')])))
endfunction

function! s:OnResult(isAuto, completion) abort
  let l:items = []
  if type(a:completion) == type([])
    let l:items = a:completion
  elseif type(a:completion) == type({})
    let l:items = a:completion.items
  endif
  if (a:isAuto)
    call s:SuggestCompletions(l:items)
  else
    let b:lsc_completion = l:items
  endif
endfunction

function! s:OnSkip(bufnr, completion) abort
  call setbufvar(a:bufnr, 'lsc_is_completing', v:false)
endfunction

function! s:SuggestCompletions(items) abort
  if mode() !=# 'i' || len(a:items) == 0
    let b:lsc_is_completing = v:false
    return
  endif
  let l:start = s:FindStart(a:items)
  let l:base = l:start != col('.')
      \ ? getline('.')[start - 1:col('.') - 2]
      \ : ''
  let l:completion_items = s:CompletionItems(l:base, a:items)
  call s:SetCompleteOpt()
  if exists('#User#LSCAutocomplete')
    doautocmd <nomodeline> User LSCAutocomplete
  endif
  call complete(start, l:completion_items)
endfunction

function! s:SetCompleteOpt() abort
  if type(g:lsc_auto_completeopt) == type('')
    " Set completeopt locally exactly like the user wants
    execute 'setl completeopt='.g:lsc_auto_completeopt
  elseif (type(g:lsc_auto_completeopt) == type(v:true)
      \ || type(g:lsc_auto_completeopt) == type(0))
      \ && g:lsc_auto_completeopt
    " Set the options that impact behavior for autocomplete use cases without
    " touching other like `preview`
    setl completeopt-=longest
    setl completeopt+=menu,menuone,noinsert,noselect
  endif
endfunction

function! lsc#complete#complete(findstart, base) abort
  if !exists('b:lsc_completion')
    let l:searchStart = reltime()
    call s:startCompletion(v:false)
    let l:timeout = get(g:, 'lsc_complete_timeout', 5)
    while !exists('b:lsc_completion')
        \ && reltimefloat(reltime(l:searchStart)) <= l:timeout
      sleep 100m
    endwhile
    if !exists('b:lsc_completion')
      return -1
    endif
  endif
  if a:findstart
    if len(b:lsc_completion) == 0
      unlet b:lsc_completion
      return -3
    endif
    return  s:FindStart(b:lsc_completion) - 1
  else
    return s:CompletionItems(a:base, b:lsc_completion)
  endif
endfunction

" Finds the 1-based index of the first character in the completion.
function! s:FindStart(completion_items) abort
  for l:item in a:completion_items
    if has_key(l:item, 'textEdit')
        \ && type(l:item.textEdit) == type({})
      return l:item.textEdit.range.start.character + 1
    endif
  endfor
  return s:GuessCompletionStart()
endfunction

" Finds the 1-based index of the character after the last non word character
" behind the cursor.
function! s:GuessCompletionStart() abort
  let search = col('.') - 2
  let line = getline('.')
  while search > 0
    let char = line[search]
    if char !~# '\w'
      return search + 2
    endif
    let search -= 1
  endwhile
  return 1
endfunction

" Filter and convert LSP completion items into the format used by vim.
"
" a:base is the portion of the portion of the word typed so far, matching the
" argument to `completefunc` the second time it is called.
"
" If a non-empty base is passed, only the items which contain the base somewhere
" whithin the completion will be used. Preference is given first to the
" completions which match by a case-sensitive prefix, then by case-insensitive
" prefix, then case-insensitive substring.
function! s:CompletionItems(base, lsp_items) abort
  let l:prefix_case_matches = []
  let l:prefix_matches = []
  let l:substring_matches = []

  let l:prefix_base = '^'.a:base

  for l:lsp_item in a:lsp_items
    let l:vim_item = s:CompletionItemWord(l:lsp_item)
    if l:vim_item.word =~# l:prefix_base
      call add(l:prefix_case_matches, l:vim_item)
    elseif l:vim_item.word =~? l:prefix_base
      call add(l:prefix_matches, l:vim_item)
    elseif l:vim_item.word =~? a:base
      call add(l:substring_matches, l:vim_item)
    else
      continue
    endif
    call s:FinishItem(l:lsp_item, l:vim_item)
  endfor

  return l:prefix_case_matches + l:prefix_matches + l:substring_matches
endfunction

" Normalize the multiple potential fields which may convey the text to insert
" from the LSP item into a vim formatted completion.
function! s:CompletionItemWord(lsp_item) abort
  let l:item = {'abbr': a:lsp_item.label, 'icase': 1, 'dup': 1}
  if has_key(a:lsp_item, 'textEdit')
      \ && type(a:lsp_item.textEdit) == type({})
      \ && has_key(a:lsp_item.textEdit, 'newText')
    let l:item.word = a:lsp_item.textEdit.newText
  elseif has_key(a:lsp_item, 'insertText')
      \ && !empty(a:lsp_item.insertText)
    let l:item.word = a:lsp_item.insertText
  else
    let l:item.word = a:lsp_item.label
  endif
  if has_key(a:lsp_item, 'insertTextFormat') && a:lsp_item.insertTextFormat == 2
    let l:item.user_data = json_encode({
          \ 'snippet': l:item.word,
          \ 'snippet_trigger': l:item.word
          \ })
    let l:item.word = a:lsp_item.label
  endif
  return l:item
endfunction

" Fill out the non-word fields of the vim completion item from an LSP item.
"
" Deprecated suggestions get a strike-through on their `abbr`.
" The `kind` field is translated from LSP numeric values into a single letter
" vim kind identifier.
" The `menu` and `info` vim fields are normalized from the `detail` and
" `documentation` LSP fields.
function! s:FinishItem(lsp_item, vim_item) abort
  if get(a:lsp_item, 'deprecated', v:false) ||
      \ index(get(a:lsp_item, 'tags', []), 1) >=0
    let a:vim_item.abbr =
        \ substitute(a:vim_item.word, '.', "\\0\<char-0x0336>", 'g')
  endif
  if has_key(a:lsp_item, 'kind')
    let a:vim_item.kind = s:CompletionItemKind(a:lsp_item.kind)
  endif
  if has_key(a:lsp_item, 'detail') && a:lsp_item.detail != v:null
    let detail_lines = split(a:lsp_item.detail, "\n")
    if len(detail_lines) > 0
      let a:vim_item.menu = detail_lines[0]
      let a:vim_item.info = a:lsp_item.detail
    endif
  endif
  if has_key(a:lsp_item, 'documentation')
    let documentation = a:lsp_item.documentation
    if has_key(a:vim_item, 'info')
      let a:vim_item.info .= "\n\n"
    else
      let a:vim_item.info = ''
    endif
    if type(documentation) == type('')
      let a:vim_item.info .= documentation
    elseif type(documentation) == type({}) && has_key(documentation, 'value')
      let a:vim_item.info .= documentation.value
    endif
  endif
endfunction

function! s:CompletionItemKind(lsp_kind) abort
  if a:lsp_kind == 1
    return 'Text'
  elseif a:lsp_kind == 2
    return 'Method'
  elseif a:lsp_kind == 3
    return 'Function'
  elseif a:lsp_kind == 4
    return 'Constructor'
  elseif a:lsp_kind == 5
    return 'Field'
  elseif a:lsp_kind == 6
    return 'Variable'
  elseif a:lsp_kind == 7
    return 'Class'
  elseif a:lsp_kind == 8
    return 'Interface'
  elseif a:lsp_kind == 9
    return 'Module'
  elseif a:lsp_kind == 10
    return 'Property'
  elseif a:lsp_kind == 11
    return 'Unit'
  elseif a:lsp_kind == 12
    return 'Value'
  elseif a:lsp_kind == 13
    return 'Enum'
  elseif a:lsp_kind == 14
    return 'Keyword'
  elseif a:lsp_kind == 15
    return 'Snippet'
  elseif a:lsp_kind == 16
    return 'Color'
  elseif a:lsp_kind == 17
    return 'File'
  elseif a:lsp_kind == 18
    return 'Reference'
  elseif a:lsp_kind == 19
    return 'Folder'
  elseif a:lsp_kind == 20
    return 'EnumMember'
  elseif a:lsp_kind == 21
    return 'Constant'
  elseif a:lsp_kind == 22
    return 'Struct'
  elseif a:lsp_kind == 23
    return 'Event'
  elseif a:lsp_kind == 24
    return 'Operator'
  elseif a:lsp_kind == 25
    return 'TypeParameter'
  else
    return ''
  endif
endfunction
