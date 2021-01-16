scriptencoding utf-8

function! TestDiff() abort
  " First and last lines swapped
  call s:TestDiff(
      \ [0,0,2,3], 11, "baz\nb╵r\nfoo",
      \ "foo\nb╵r\nbaz",
      \ "baz\nb╵r\nfoo"
      \ )

  " First line changed
  call s:TestDiff(
      \ [0,1,0,2], 1, 'n',
      \ "foo\nbar\nbaz",
      \ "fno\nbar\nbaz"
      \ )

  " Middle line changed
  call s:TestDiff(
      \ [1,0,1,3], 3, 'new',
      \ "foo\nb╵r\nbaz",
      \ "foo\nnew\nbaz"
      \ )

  " Last line changed
  call s:TestDiff(
      \ [2,1,2,2], 1, 'n',
      \ "foo\nbar\nbaz",
      \ "foo\nbar\nbnz"
      \ )

  " Middle characters changed
  call s:TestDiff(
      \ [1,1,1,2], 1, 'x',
      \ "foo\nb╵r\nbaz",
      \ "foo\nbxr\nbaz"
      \ )

  " End of line changed
  call s:TestDiff(
      \ [1,1,1,3], 2, 'y',
      \ "foo\nb╵r\nbaz",
      \ "foo\nby\nbaz"
      \ )

  " End of file changed
  call s:TestDiff(
      \ [2,1,2,3], 2, 'y',
      \ "foo\nb╵r\nbaz",
      \ "foo\nb╵r\nby")

  " Characters inserted
  call s:TestDiff(
      \ [1,1,1,1], 0, 'e',
      \ "foo\nb╵r\nbaz",
      \ "foo\nbe╵r\nbaz"
      \ )

  " Characters inserted at beginning
  call s:TestDiff(
      \ [0,0,0,0], 0, 'a',
      \ "foo\nb╵r\nbaz",
      \ "afoo\nb╵r\nbaz"
      \ )

  " Line inserted
  call s:TestDiff(
      \ [1,0,1,0], 0, "more\n",
      \ "foo\nb╵r\nbaz",
      \ "foo\nmore\nb╵r\nbaz"
      \ )

  " Line inserted at end
  " It's important this appears to *prefix* the newline
  call s:TestDiff(
      \ [2,3,2,3], 0, "\nanother",
      \ "foo\nb╵r\nbaz",
      \ "foo\nb╵r\nbaz\nanother"
      \ )

  " Line inserted at beginning
  call s:TestDiff(
      \ [0,0,0,0], 0, "line\n",
      \ "foo\nb╵r\nbaz",
      \ "line\nfoo\nb╵r\nbaz"
      \ )

  " Line inserted at beginning with same leading characters
  call s:TestDiff(
      \ [0,3,0,3], 0, "line\n// ",
      \ "// foo\n// b╵r\n// baz",
      \ "// line\n// foo\n// b╵r\n// baz"
      \ )

  " Change spanning lines
  call s:TestDiff(
      \ [0,2,2,1], 7, "r\nmany\nlines\nsp",
      \ "foo\nb╵r\nbaz",
      \ "for\nmany\nlines\nspaz"
      \ )

  " Delete within a line
  call s:TestDiff(
      \ [1,1,1,2], 1, '',
      \ "ab\ncde\nfghi",
      \ "ab\nce\nfghi"
      \ )

  " Delete across a line
  call s:TestDiff(
      \ [1,1,2,1], 4, '',
      \ "foo\nb╵r\nqux",
      \ "foo\nbux",
      \ )

  " Delete entire line
  call s:TestDiff(
      \ [1,0,2,0], 4, '',
      \ "foo\nb╵r\nqux",
      \ "foo\nqux",
      \ )

  " Delete multiple lines
  call s:TestDiff(
      \ [1,0,3,0], 8, '',
      \ "foo\nb╵r\nbaz\nqux",
      \ "foo\nqux",
      \ )

  " Delete with repeated substring
  call s:TestDiff(
      \ [0, 4, 0, 6], 2, '',
      \ 'ABABAB',
      \ 'ABAB')

  " Delete at beginning
  call s:TestDiff(
      \ [0, 0, 0, 1], 1, '',
      \ "foo\nb╵r\nbaz",
      \ "oo\nb╵r\nbaz")

  " Delete line at beginning
  call s:TestDiff(
      \ [0, 0, 1, 0], 4, '',
      \ "foo\nb╵r\nbaz",
      \ "b╵r\nbaz")

  " Delete line at beginning with same leading characters
  call s:TestDiff(
      \ [0, 3, 1, 3], 7, '',
      \ "// foo\n// b╵r\n// baz",
      \ "// b╵r\n// baz")

  " Delete lines at beginning with same leading characters
  call s:TestDiff(
      \ [0, 3, 2, 3], 14, '',
      \ "// foo\n// b╵r\n// baz",
      \ '// baz')

  " Delete at end
  call s:TestDiff(
      \ [2, 2, 2, 3], 1, '',
      \ "foo\nb╵r\nbaz",
      \ "foo\nb╵r\nba")

  " Delete lines at end
  call s:TestDiff(
      \ [0, 3, 2, 3], 8, '',
      \ "foo\nb╵r\nbaz",
      \ 'foo')

  " Handles multiple blank lines
  call s:TestDiff(
      \ [5,1,5,2], 1, 'x',
      \ "\n\n\n\nfoo\nb╵r\nbaz",
      \ "\n\n\n\nfoo\nbxr\nbaz"
      \ )

  " File becomes empty
  call s:TestDiff(
      \ [0,0,1,0], 5, '',
      \ 'line',
      \ '')

  " File Starts empty
  call s:TestDiff(
      \ [0,0,0,0], 0, "line\n",
      \ '',
      \ 'line')

  " File is identical
  " Would be better to not send a change, but an arbitrary empty change is OK
  call s:TestDiff(
      \ [2,3,2,3], 0, '',
      \ "foo\nbar\nbaz",
      \ "foo\nbar\nbaz")

  " Starts and ends empty
  call s:TestDiff(
      \ [0,0,0,0], 0, '',
      \ '',
      \ '')
endfunction

function! s:TestDiff(range, length, text, old, new) abort
  let l:start = {'line': a:range[0], 'character': a:range[1]}
  let l:end = {'line': a:range[2], 'character': a:range[3]}
  let l:old = empty(a:old) ? [] : split(a:old, "\n", v:true)
  let l:new = empty(a:new) ? [] : split(a:new, "\n", v:true)
  let l:result = lsc#diff#compute(l:old, l:new)
  call assert_equal({'start': l:start}, {'start': l:result.range.start})
  call assert_equal({'end': l:end}, {'end': l:result.range.end})
  call assert_equal({'length': a:length}, {'length': l:result.rangeLength})
  call assert_equal({'text': a:text}, {'text': l:result.text})
endfunction

function! s:RunTest(test)
  let v:errors = []
  silent! call lsc#diff#not_a_function()

  call function(a:test)()

  if len(v:errors) > 0
    for l:error in v:errors
      echoerr l:error
    endfor
  else
    echom 'No errors in: '.a:test
  endif
endfunction

function! s:RunTests(...)
  for l:test in a:000
    call s:RunTest(l:test)
  endfor
endfunction

messages clear
call s:RunTests('TestDiff')
