function! lsc#convert#rangeToHighlights(range) abort
  let l:start = a:range.start
  let l:end = a:range.end
  if l:end.line > l:start.line
    let l:ranges =[[
        \ l:start.line + 1,
        \ l:start.character + 1,
        \ 99]]
    " Matches render wrong until a `redraw!` if lines are mixed with ranges
    let l:line_hacks = map(range(l:start.line + 2, l:end.line), {_, l->[l,0,99]})
    call extend(l:ranges, l:line_hacks)
    call add(l:ranges, [
        \ l:end.line + 1,
        \ 1,
        \ l:end.character])
  else
    let l:ranges = [[
        \ l:start.line + 1,
        \ l:start.character + 1,
        \ l:end.character - l:start.character]]
  endif
  return l:ranges
endfunction

" Convert an LSP SymbolInformation to a quick fix item.
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
" 'filename': The file path of the symbol's location
" 'lnum': line number
" 'col': column number
" 'text': "SymbolName" [kind] (in containerName)?
function! lsc#convert#quickFixSymbol(symbol) abort
  let l:item = {'lnum': a:symbol.location.range.start.line + 1,
      \ 'col': a:symbol.location.range.start.character + 1,
      \ 'filename': lsc#uri#documentPath(a:symbol.location.uri)}
  let l:text = '"'.a:symbol.name.'"'
  if !empty(a:symbol.kind)
    let l:text .= ' ['.lsc#convert#symbolKind(a:symbol.kind).']'
  endif
  let l:containerName = get(a:symbol, 'containerName', '')
  if !empty(l:containerName)
    let l:text .= ' in '.l:containerName
  endif
  let l:item.text = l:text
  return l:item
endfunction

function! lsc#convert#symbolKind(kind) abort
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
