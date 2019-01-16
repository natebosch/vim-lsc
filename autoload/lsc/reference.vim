function! lsc#reference#goToDefinition() abort
  call lsc#file#flushChanges()
  call lsc#server#userCall('textDocument/definition',
      \ lsc#params#documentPosition(),
      \ lsc#util#gateResult('GoToDefinition', function('<SID>GoToDefinition')))
endfunction

function! s:GoToDefinition(result) abort
  if type(a:result) == type(v:null) ||
      \ (type(a:result) == v:t_list && len(a:result) == 0)
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
  if exists('*gettagstack') && exists('*settagstack')
    let from = [bufnr('%'), line('.'), col('.'), 0]
    let tagname = expand('<cword>')
    let winid = win_getid()
    call settagstack(winid, {'items': [{'from': from, 'tagname': tagname}]}, 'a')
    call settagstack(winid, {'curidx': len(gettagstack(winid)['items']) + 1})
  endif
  call s:goTo(file, line, character)
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

function! s:goTo(file, line, character) abort
  if a:file != lsc#file#fullPath()
    let relative_path = fnamemodify(a:file, ':~:.')
    exec 'edit '.relative_path
    " 'edit' already left a jump
    call cursor(a:line, a:character)
    redraw
  else
    " Move with 'G' to ensure a jump is left
    exec 'normal! '.a:line.'G'.a:character.'|'
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
  if type(contents) == v:t_list
    let contents = contents[0]
  endif
  if type(contents) == v:t_dict
    let contents = contents.value
  endif
  let lines = split(contents, "\n")
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
