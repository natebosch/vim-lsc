function! lsc#uri#documentUri(...) abort
  if a:0 >= 1
    let l:file_path = a:1
  else
    let l:file_path = lsc#file#fullPath()
  endif
  return s:filePrefix().s:EncodePath(l:file_path)
endfunction

function! lsc#uri#documentPath(uri) abort
  return s:DecodePath(substitute(a:uri, '^'.s:filePrefix(), '', 'v'))
endfunction

function! s:EncodePath(value) abort
  " shamelessly taken from Mr. T. Pope and adapted:
  " (https://github.com/tpope/vim-unimpaired/blob/master/plugin/unimpaired.vim#L461)
  " This follows the VIM License over at https://github.com/vim/vim/blob/master/LICENSE
  return substitute(iconv(a:value, "latin-1", 'utf-8'),
        \ '[^A-Za-z0-9_.~-]',
        \ '\=s:EncodeChar(submatch(0))', 'g')
endfunction

function! s:EncodeChar(char) abort
  let l:charcode = char2nr(a:char)
  return printf('%%%02x', l:charcode)
endfunction

function! s:DecodePath(value) abort
  " shamelessly taken from Mr. T. Pope and adapted:
  " (https://github.com/tpope/vim-unimpaired/blob/master/plugin/unimpaired.vim#L465-L466)
  " This follows the VIM License over at https://github.com/vim/vim/blob/master/LICENSE
  let str = substitute(
        \ substitute(
        \   substitute(a:value,'%0[Aa]\n$','%0A',''),
        \   '%0[Aa]',
        \   '\n',
        \   'g')
        \,'+',' ','g')
  return iconv(
        \ substitute(
        \   str,
        \   '%\(\x\x\)',
        \   '\=nr2char("0x".submatch(1))','g'),
        \ 'utf-8',
        \ 'latin1')
endfunction

function! s:filePrefix(...) abort
  if has('win32')
    return 'file:///'
  else
    return 'file://'
  endif
endfunction
