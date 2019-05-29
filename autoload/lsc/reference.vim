function! lsc#reference#goToDefinition(mods, issplit) abort
  call lsc#file#flushChanges()
  call lsc#server#userCall('textDocument/definition',
      \ lsc#params#documentPosition(),
      \ lsc#util#gateResult('GoToDefinition',
      \   function('<SID>GoToDefinition', [a:mods, a:issplit])))
endfunction

function! s:GoToDefinition(mods, issplit, result) abort
  if type(a:result) == type(v:null) ||
      \ (type(a:result) == type([]) && len(a:result) == 0)
    call lsc#message#error('No definition found')
    return
  endif
  if type(a:result) == type([])
    let location = a:result[0]
  else
    let location = a:result
  endif
  let file = lsc#uri#documentPath(location.uri)
  let line = location.range.start.line + 1
  let character = location.range.start.character + 1
  let dotag = &tagstack && exists('*gettagstack') && exists('*settagstack')
  if dotag
    let from = [bufnr('%'), line('.'), col('.'), 0]
    let tagname = expand('<cword>')
    let stack = gettagstack()
    if stack.curidx > 1
      let stack.items = stack.items[0:stack.curidx-2]
    else
      let stack.items = []
    endif
    let stack.items += [{'from': from, 'tagname': tagname}]
    let stack.curidx = len(stack.items)
    call settagstack(win_getid(), stack)
  endif
  call s:goTo(file, line, character, a:mods, a:issplit)
  if dotag
    let curidx = gettagstack().curidx + 1
    call settagstack(win_getid(), {'curidx': curidx})
  endif
endfunction

function! lsc#reference#findReferences() abort
  call lsc#file#flushChanges()
  let params = lsc#params#documentPosition()
  let params.context = {'includeDeclaration': v:true}
  call lsc#server#userCall('textDocument/references', params,
      \ function('<SID>setQuickFixLocations', ['references']))
endfunction

function! lsc#reference#findImplementations() abort
  call lsc#file#flushChanges()
  call lsc#server#userCall('textDocument/implementation',
      \ lsc#params#documentPosition(),
      \ function('<SID>setQuickFixLocations', ['implementations']))
endfunction

function! s:setQuickFixLocations(label, results) abort
  if empty(a:results)
    call lsc#message#show('No '.a:label.' found')
    return
  endif
  call map(a:results, {_, ref -> s:QuickFixItem(ref)})
  call sort(a:results, 'lsc#util#compareQuickFixItems')
  call setqflist(a:results)
  copen
endfunction

" Convert an LSP Location to a item suitable for the vim quickfix list.
"
" Both representations are dictionaries.
"
" Location:
" 'uri': file:// URI
" 'range': {'start': {'line', 'character'}, 'end': {'line', 'character'}}
"
" QuickFix Item: (as used)
" 'filename': file path if file is not open
" 'lnum': line number
" 'col': column number
" 'text': The content of the referenced line
"
" LSP line and column are zero-based, vim is one-based.
function! s:QuickFixItem(location) abort
  let item = {'lnum': a:location.range.start.line + 1,
      \ 'col': a:location.range.start.character + 1}
  let file_path = lsc#uri#documentPath(a:location.uri)
  let item.filename = fnamemodify(file_path, ':.')
  let bufnr = lsc#file#bufnr(file_path)
  if bufnr != -1 && bufloaded(bufnr)
    let item.text = getbufline(bufnr, item.lnum)[0]
  else
    let item.text = readfile(file_path, '', item.lnum)[item.lnum - 1]
  endif
  return item
endfunction

function! s:goTo(file, line, character, mods, issplit) abort
  let prev_buf = bufnr('%')
  if a:issplit || a:file !=# lsc#file#fullPath()
    let cmd = 'edit'
    if a:issplit
      let cmd = lsc#file#bufnr(a:file) == -1 ? 'split' : 'sbuffer'
    endif
    let relative_path = fnamemodify(a:file, ':~:.')
    exec a:mods cmd fnameescape(relative_path)
  endif
  if prev_buf != bufnr('%')
    " switching buffers already left a jump
    " Set curswant manually to work around vim bug
    call cursor([a:line, a:character, 0, virtcol([a:line, a:character])])
    redraw
  else
    " Move with 'G' to ensure a jump is left
    exec 'normal! '.a:line.'G'
    " Set curswant manually to work around vim bug
    call cursor([0, a:character, 0, virtcol([a:line, a:character])])
  endif
endfunction

function! lsc#reference#hover() abort
  call lsc#file#flushChanges()
  let params = lsc#params#documentPosition()
  call lsc#server#userCall('textDocument/hover', params,
      \ function('<SID>showHover'))
endfunction

function! s:showHover(result) abort
  if empty(a:result) || empty(a:result.contents)
    echom 'No hover information'
    return
  endif
  let contents = a:result.contents
  if type(contents) != type([])
    let contents = [contents]
  endif
  let lines = []
  for item in contents
    if type(item) == type({})
      let l:lines += split(item.value, "\n")
    else
      let l:lines += split(item, "\n")
    endif
  endfor
  call lsc#util#displayAsPreview(lines, function('lsc#util#noop'))
endfunction

" Request a list of symbols in the current document and populate the quickfix
" list.
function! lsc#reference#documentSymbols() abort
  call lsc#file#flushChanges()
  call lsc#server#userCall('textDocument/documentSymbol',
      \ lsc#params#textDocument(),
      \ function('<SID>setQuickFixSymbols'))
endfunction

function! s:setQuickFixSymbols(results) abort
  if empty(a:results)
    call lsc#message#show('No symbols found')
    return
  endif

  call map(a:results, {_, symbol -> lsc#convert#quickFixSymbol(symbol)})
  call sort(a:results, 'lsc#util#compareQuickFixItems')
  call setqflist(a:results)
  copen
endfunction


" If the server supports `textDocument/documentHighlight` and they are enabled,
" use the active highlights to move the cursor to the next or previous referene
" in the same document to the symbol under the cursor.
function! lsc#reference#findNext(direction) abort
  if exists('w:lsc_references')
    let idx = lsc#cursor#isInReference(w:lsc_references)
    if idx != -1 &&
        \ idx + a:direction >= 0 &&
        \ idx + a:direction < len(w:lsc_references)
      let target = w:lsc_references[idx + a:direction].ranges[0][0:1]
    endif
  endif
  if !exists('l:target')
    return
  endif
  " Move with 'G' to ensure a jump is left
  exec 'normal! '.target[0].'G'.target[1].'|'
endfunction
