function! lsc#workspace#byMarker(markers) abort
  return function('<SID>FindByMarkers', [a:markers])
endfunction

function! s:FindByMarkers(markers, file_path) abort
  for l:path in s:ParentDirectories(a:file_path)
    if s:ContainsAny(l:path, a:markers) | return l:path | endif
  endfor
  return fnamemodify(a:file_path, ':h')
endfunction

" Whether `path` contains any children from `markers`.
function! s:ContainsAny(path, markers) abort
  for l:marker in a:markers
    if l:marker[-1:] ==# '/'
      if isdirectory(a:path.'/'.l:marker) | return v:true | endif
    else
      if filereadable(a:path.'/'.l:marker) | return v:true | endif
    endif
  endfor
  return v:false
endfunction

" Returns a list of the parents of the current file up to a root directory.
function! s:ParentDirectories(file_path) abort
  let l:dirs = []
  let l:current_dir = fnamemodify(a:file_path, ':h')
  let l:parent = fnamemodify(l:current_dir, ':h')
  while l:parent != l:current_dir
    call add(l:dirs, l:current_dir)
    let l:current_dir = l:parent
    let l:parent = fnamemodify(l:parent, ':h')
  endwhile
  call add(l:dirs, l:current_dir)
  return l:dirs
endfunction
