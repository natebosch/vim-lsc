function! TestUriEncode() abort
  call assert_equal('file://foo/bar%20baz', lsc#uri#documentUri('foo/bar baz'))
  call assert_equal('file://foo/bar%23baz', lsc#uri#documentUri('foo/bar#baz'))
endfunction

function! TestUriDecode() abort
  call assert_equal('foo/bar baz', lsc#uri#documentPath('file://foo/bar%20baz'))
  call assert_equal('foo/bar#baz', lsc#uri#documentPath('file://foo/bar%23baz'))
endfunction

function! s:RunTest(test)
  let v:errors = []
  silent! call lsc#uri#not_a_function()

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

call s:RunTests('TestUriEncode', 'TestUriDecode')
