function! lsc#filterReferenceCalls(options) abort
  let l:Filter = lsc#filterLocations(a:options)
  return {'textDocument/references': l:Filter,
      \'textDocument/implementation': l:Filter}
endfunction

" Returns a function that will intercept results which are lists of Locations
" and filter them by URI.
function! lsc#filterLocations(options) abort
  if has_key(a:options, 'include')
    let l:Include = s:Include(a:options.include)
  endif
  if has_key(a:options, 'exclude')
    let l:Exclude = s:Include(a:options.exclude)
  endif
  function LocationFilter(method, results) closure abort
    if type(a:results) != v:t_list || len(a:results) == 0
      return a:results
    endif
    if exists('l:Include')
      call filter(a:results, l:Include)
    endif
    if exists('l:Exclude')
      call filter(a:results, {idx, element -> !l:Exclude(idx, element)})
    endif
    return a:results
  endfunction
  return function('LocationFilter')
endfunction

function! s:Include(include) abort
  if type(a:include) == v:t_string
    return {idx, element -> element.uri =~# a:include}
  endif
  function IsIncluded(idx, element) closure abort
    for l:search in a:include
      if a:element.uri =~# l:search
        return v:true
      endif
    endfor
    return v:false
  endfunction
  return function('IsIncluded')
endfunction
