function! TestDiff() abort
  " First and last lines swapped
  call s:TestDiff(
      \ [0,0,2,3], 11, "baz\nbar\nfoo",
      \ ['foo', 'bar', 'baz'],
      \ ['baz', 'bar', 'foo']
      \ )

  " Middle line changed
  call s:TestDiff(
      \ [1,0,1,3], 3, 'new',
      \ ['foo', 'bar', 'baz'],
      \ ['foo', 'new', 'baz']
      \ )

  " Middle characters changed
  call s:TestDiff(
      \ [1,1,1,2], 1, 'x',
      \ ['foo', 'bar', 'baz'],
      \ ['foo', 'bxr', 'baz']
      \ )

  " End of line changed
  call s:TestDiff(
      \ [1,1,1,3], 2, 'y',
      \ ['foo', 'bar', 'baz'],
      \ ['foo', 'by', 'baz']
      \ )

  " End of file changed
  call s:TestDiff(
      \ [2,1,2,3], 2, 'y',
      \ ['foo', 'bar', 'baz'],
      \ ['foo', 'bar', 'by'])

  " Characters inserted
  call s:TestDiff(
      \ [1,1,1,1], 0, 'e',
      \ ['foo', 'bar', 'baz'],
      \ ['foo', 'bear', 'baz']
      \ )

  " Characters inserted at beginning
  call s:TestDiff(
      \ [0,0,0,0], 0, 'a',
      \ ['foo', 'bar', 'baz'],
      \ ['afoo', 'bar', 'baz']
      \ )

  " Line inserted
  call s:TestDiff(
      \ [1,0,1,0], 0, "more\n",
      \ ['foo', 'bar', 'baz'],
      \ ['foo', 'more', 'bar', 'baz']
      \ )

  " Line inserted at end
  call s:TestDiff(
      \ [2,3,2,3], 0, "\nanother",
      \ ['foo', 'bar', 'baz'],
      \ ['foo', 'bar', 'baz', 'another']
      \ )

  " Change spanning lines
  call s:TestDiff(
      \ [0,2,2,1], 7, "r\nmany\nlines\nsp",
      \ ['foo', 'bar', 'baz'],
      \ ['for', 'many', 'lines', 'spaz']
      \ )

  " Delete within a line
  call s:TestDiff(
      \ [1,1,1,2], 1, '',
      \ ['foo', 'bar', 'baz'],
      \ ['foo', 'br', 'baz']
      \ )

  " Delete across a line
  call s:TestDiff(
      \ [1,1,2,1], 4, '',
      \ ['foo', 'bar', 'qux'],
      \ ['foo', 'bux'],
      \ )

  " Delete entire line
  call s:TestDiff(
      \ [1,0,2,0], 4, '',
      \ ['foo', 'bar', 'qux'],
      \ ['foo', 'qux'],
      \ )

  " Delete multiple lines
  call s:TestDiff(
      \ [1,0,3,0], 8, '',
      \ ['foo', 'bar', 'baz', 'qux'],
      \ ['foo', 'qux'],
      \ )

  " Delete with repeated substring
  call s:TestDiff(
      \ [0, 4, 0, 6], 2, '',
      \ ['ABABAB'],
      \ ['ABAB'])

  " Delete at beginning
  call s:TestDiff(
      \ [0, 0, 0, 1], 1, '',
      \ ['foo', 'bar', 'baz'],
      \ ['oo', 'bar', 'baz'])

  " Delete at end
  call s:TestDiff(
      \ [2, 2, 2, 3], 1, '',
      \ ['foo', 'bar', 'baz'],
      \ ['foo', 'bar', 'ba'])
endfunction

function! s:TestDiff(range, length, text, old, new) abort
  let start = {'line': a:range[0], 'character': a:range[1]}
  let end = {'line': a:range[2], 'character': a:range[3]}
  let result = lsc#diff#compute(a:old, a:new)
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
endfunction!

function! s:RunTests(...)
  for test in a:000
    call s:RunTest(test)
  endfor
endfunction

call s:RunTests('TestDiff')
