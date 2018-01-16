function! lsc#convert#rangeToHighlights(range) abort
  let start = a:range.start
  let end = a:range.end
  if end.line > start.line
    let ranges =[[
        \ start.line + 1,
        \ start.character + 1,
        \ 99
        \]]
    " Renders strangely until a `redraw!` if lines are mixed with line ranges
    call extend(ranges, map(range(start.line + 2, end.line), {_, l->[l,0,99]}))
    call add(ranges, [
        \ end.line + 1,
        \ 1,
        \ end.character
        \])
  else
    let ranges = [[
        \ start.line + 1,
        \ start.character + 1,
        \ end.character - start.character]]
  endif
  return ranges
endfunction
