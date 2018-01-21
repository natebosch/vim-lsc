function! TestDiff() abort
  " First and last lines swapped
  call s:TestDiff(
      \ [0,0,2,3], 11, "baz\nbar\nfoo",
      \ "foo\nbar\nbaz",
      \ "baz\nbar\nfoo"
      \ )

  " Middle line changed
  call s:TestDiff(
      \ [1,0,1,3], 3, 'new',
      \ "foo\nbar\nbaz",
      \ "foo\nnew\nbaz"
      \ )

  " Middle characters changed
  call s:TestDiff(
      \ [1,1,1,2], 1, 'x',
      \ "foo\nbar\nbaz",
      \ "foo\nbxr\nbaz"
      \ )

  " End of line changed
  call s:TestDiff(
      \ [1,1,1,3], 2, 'y',
      \ "foo\nbar\nbaz",
      \ "foo\nby\nbaz"
      \ )

  " End of file changed
  call s:TestDiff(
      \ [2,1,2,3], 2, 'y',
      \ "foo\nbar\nbaz",
      \ "foo\nbar\nby")

  " Characters inserted
  call s:TestDiff(
      \ [1,1,1,1], 0, 'e',
      \ "foo\nbar\nbaz",
      \ "foo\nbear\nbaz"
      \ )

  " Characters inserted at beginning
  call s:TestDiff(
      \ [0,0,0,0], 0, 'a',
      \ "foo\nbar\nbaz",
      \ "afoo\nbar\nbaz"
      \ )

  " Line inserted
  call s:TestDiff(
      \ [1,0,1,0], 0, "more\n",
      \ "foo\nbar\nbaz",
      \ "foo\nmore\nbar\nbaz"
      \ )

  " Line inserted at end
  " It's important this appears to *prefix* the newline
  call s:TestDiff(
      \ [2,3,2,3], 0, "\nanother",
      \ "foo\nbar\nbaz",
      \ "foo\nbar\nbaz\nanother"
      \ )

  " Line inserted at beginning
  call s:TestDiff(
      \ [0,0,0,0], 0, "line\n",
      \ "foo\nbar\nbaz",
      \ "line\nfoo\nbar\nbaz"
      \ )

  " Line inserted at beginning with same leading characters
  call s:TestDiff(
      \ [0,3,0,3], 0, "line\n// ",
      \ "// foo\n// bar\n// baz",
      \ "// line\n// foo\n// bar\n// baz"
      \ )

  " Change spanning lines
  call s:TestDiff(
      \ [0,2,2,1], 7, "r\nmany\nlines\nsp",
      \ "foo\nbar\nbaz",
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
      \ "foo\nbar\nqux",
      \ "foo\nbux",
      \ )

  " Delete entire line
  call s:TestDiff(
      \ [1,0,2,0], 4, '',
      \ "foo\nbar\nqux",
      \ "foo\nqux",
      \ )

  " Delete multiple lines
  call s:TestDiff(
      \ [1,0,3,0], 8, '',
      \ "foo\nbar\nbaz\nqux",
      \ "foo\nqux",
      \ )

  " Delete with repeated substring
  call s:TestDiff(
      \ [0, 4, 0, 6], 2, '',
      \ "ABABAB",
      \ "ABAB")

  " Delete at beginning
  call s:TestDiff(
      \ [0, 0, 0, 1], 1, '',
      \ "foo\nbar\nbaz",
      \ "oo\nbar\nbaz")

  " Delete line at beginning
  call s:TestDiff(
      \ [0, 0, 1, 0], 4, '',
      \ "foo\nbar\nbaz",
      \ "bar\nbaz")

  " Delete line at beginning with same leading characters
  call s:TestDiff(
      \ [0, 3, 1, 3], 7, '',
      \ "// foo\n// bar\n// baz",
      \ "// bar\n// baz")

  " Delete lines at beginning with same leading characters
  call s:TestDiff(
      \ [0, 3, 2, 3], 14, '',
      \ "// foo\n// bar\n// baz",
      \ "// baz")

  " Delete at end
  call s:TestDiff(
      \ [2, 2, 2, 3], 1, '',
      \ "foo\nbar\nbaz",
      \ "foo\nbar\nba")

  " Delete lines at end
  call s:TestDiff(
      \ [0, 3, 2, 3], 8, '',
      \ "foo\nbar\nbaz",
      \ "foo")

  " Handles multiple blank lines
  call s:TestDiff(
      \ [5,1,5,2], 1, 'x',
      \ "\n\n\n\nfoo\nbar\nbaz",
      \ "\n\n\n\nfoo\nbxr\nbaz"
      \ )
endfunction

function! s:TestDiff(range, length, text, old, new) abort
  let start = {'line': a:range[0], 'character': a:range[1]}
  let end = {'line': a:range[2], 'character': a:range[3]}
  let result = lsc#diff#compute(split(a:old, "\n", v:true),
      \ split(a:new, "\n", v:true))
  call assert_equal({'start': start}, {'start': result.range.start})
  call assert_equal({'end': end}, {'end': result.range.end})
  call assert_equal({'length': a:length}, {'length': result.rangeLength})
  call assert_equal({'text': a:text}, {'text': result.text})
endfunction

function! s:RunTest(test)
  let v:errors = []
  silent! call lsc#diff#not_a_function()

  call function(a:test)()

  if len(v:errors) > 0
    for error in v:errors
      echoerr error
    endfor
  else
    echom 'No errors in: '.a:test
  endif
endfunction

function! s:RunTests(...)
  for test in a:000
    call s:RunTest(test)
  endfor
endfunction

messages clear
call s:RunTests('TestDiff')
