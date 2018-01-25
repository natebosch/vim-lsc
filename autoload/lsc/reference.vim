function! lsc#reference#goToDefinition() abort
  call lsc#file#flushChanges()
  call lsc#server#userCall('textDocument/definition',
      \ lsc#params#documentPosition(),
      \ lsc#util#gateResult('GoToDefinition', function('<SID>GoToDefinition')))
endfunction

function! s:GoToDefinition(result) abort
  if type(a:result) == v:t_none ||
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
  call s:goTo(file, line, character)
endfunction

function! lsc#reference#findReferences() abort
  call lsc#file#flushChanges()
  let params = lsc#params#documentPosition()
  let params.context = {'includeDeclaration': v:true}
  call lsc#server#userCall('textDocument/references', params,
      \ function('<SID>setQuickFixReferences'))
endfunction

function! s:setQuickFixReferences(results) abort
  if empty(a:results)
    call lsc#message#show('No references found')
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
" 'bufnr': buffer number if the file is open in a buffer
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
  let bufnr = bufnr(file_path)
  if bufnr != -1 && bufloaded(bufnr)
    let item.text = getbufline(bufnr, item.lnum)[0]
  else
    let item.text = readfile(file_path, '', item.lnum)[item.lnum - 1]
  endif
  return item
endfunction

function! s:goTo(file, line, character) abort
  if a:file != expand('%:p')
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
  call lsc#util#displayAsPreview(lines)
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
  endif

  let file_path = lsc#uri#documentPath(a:results[0].location.uri)
  call map(a:results, {_, symbol -> s:QuickFixSymbol(bufnr(file_path), symbol)})
  call sort(a:results, 'lsc#util#compareQuickFixItems')
  call setqflist(a:results)
  copen
endfunction

" Conver an LSP SymbolInformation to a quick fix item.
"
" Both representations are dictionaries.
"
" SymbolInformation:
" 'location':
"   'uri': file:// URI
"   'range': {'start': {'line', 'characater'}, 'end': {'line', 'character'}}
" 'name': The symbol's name
" 'kind': Integer kind
" 'containerName': The element this symbol is inside
"
" QuickFix Item: (as used)
" 'bufnr': This buffer
" 'lnum': line number
" 'col': column number
" 'text': "SymbolName" [kind] (in containerName)?
function! s:QuickFixSymbol(bufnr, symbol) abort
  let item = {'lnum': a:symbol.location.range.start.line + 1,
      \ 'col': a:symbol.location.range.start.character + 1,
      \ 'bufnr': a:bufnr}
  let text = '"'.a:symbol.name.'"'
  if !empty(a:symbol.kind)
    let text .= ' ['.s:SymbolKind(a:symbol.kind).']'
  endif
  if !empty(a:symbol.containerName)
    let text .= ' in '.a:symbol.containerName
  endif
  let item.text = text
  return item
endfunction

function! s:SymbolKind(kind) abort
  if a:kind == 1
    return 'File'
  endif
  if a:kind == 2
    return 'Module'
  endif
  if a:kind == 3
    return 'Namespace'
  endif
  if a:kind == 4
    return 'Package'
  endif
  if a:kind == 5
    return 'Class'
  endif
  if a:kind == 6
    return 'Method'
  endif
  if a:kind == 7
    return 'Property'
  endif
  if a:kind == 8
    return 'Field'
  endif
  if a:kind == 9
    return 'Constructor'
  endif
  if a:kind == 10
    return 'Enum'
  endif
  if a:kind == 11
    return 'Interface'
  endif
  if a:kind == 12
    return 'Function'
  endif
  if a:kind == 13
    return 'Variable'
  endif
  if a:kind == 14
    return 'Constant'
  endif
  if a:kind == 15
    return 'String'
  endif
  if a:kind == 16
    return 'Number'
  endif
  if a:kind == 17
    return 'Boolean'
  endif
  if a:kind == 18
    return 'Array'
  endif
  if a:kind == 19
    return 'Object'
  endif
  if a:kind == 20
    return 'Key'
  endif
  if a:kind == 21
    return 'Null'
  endif
  if a:kind == 22
    return 'EnumMember'
  endif
  if a:kind == 23
    return 'Struct'
  endif
  if a:kind == 24
    return 'Event'
  endif
  if a:kind == 25
    return 'Operator'
  endif
  if a:kind == 26
    return 'TypeParameter'
  endif
endfunction
