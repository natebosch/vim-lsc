function! lsc#search#workspaceSymbol(...) abort
  if a:0 >= 1
    let l:query = a:1
  else
    let l:query = input('Search Workspace For: ')
  endif
  call lsc#server#userCall('workspace/symbol', {'query': l:query},
      \ function('<SID>setQuickFixSymbols'))
endfunction

function! s:setQuickFixSymbols(results) abort
  if type(a:results) != v:t_list || len(a:results) == 0
    call lsc#message#show('No symbols found')
    return
  endif

  call map(a:results, {_, symbol -> lsc#convert#quickFixSymbol(symbol)})
  call sort(a:results, 'lsc#util#compareQuickFixItems')
  call setqflist(a:results)
  copen
endfunction
