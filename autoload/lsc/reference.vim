let s:popup_id = 0

function! lsc#reference#goToDeclaration(mods, issplit) abort
  call lsc#file#flushChanges()
  call lsc#server#userCall('textDocument/declaration',
      \ lsc#params#documentPosition(),
      \ lsc#util#gateResult('GoTo',
      \   function('<SID>GoTo', ['declaration', a:mods, a:issplit])))
endfunction

function! lsc#reference#goToDefinition(mods, issplit) abort
  call lsc#file#flushChanges()
  call lsc#server#userCall('textDocument/definition',
      \ lsc#params#documentPosition(),
      \ lsc#util#gateResult('GoTo',
      \   function('<SID>GoTo', ['definition', a:mods, a:issplit])))
endfunction

function! s:GoTo(label, mods, issplit, result) abort
  if type(a:result) == type(v:null) ||
      \ (type(a:result) == type([]) && len(a:result) == 0)
    call lsc#message#error('No'. a:label .'found')
    return
  endif
  if type(a:result) == type([]) && (a:label ==# 'declaration' || len(a:result) == 1)
    let l:location = a:result[0]
  elseif type(a:result) == type([]) && len(a:result) > 2
    call s:setQuickFixLocations('Definitions', a:result)
    call copen()
  else
    let l:location = a:result
  endif
  if exists('l:location')
    let l:file = lsc#uri#documentPath(l:location.uri)
    let l:line = l:location.range.start.line + 1
    let l:character = l:location.range.start.character + 1
    let l:dotag = &tagstack && exists('*gettagstack') && exists('*settagstack')
    if l:dotag
      let l:from = [bufnr('%'), line('.'), col('.'), 0]
      let l:tagname = expand('<cword>')
      let l:stack = gettagstack()
      if l:stack.curidx > 1
        let l:stack.items = l:stack.items[0:l:stack.curidx-2]
      else
        let l:stack.items = []
      endif
      let l:stack.items += [{'from': l:from, 'tagname': l:tagname}]
      let l:stack.curidx = len(l:stack.items)
      call settagstack(win_getid(), l:stack)
    endif
    call s:goTo(l:file, l:line, l:character, a:mods, a:issplit)
    if l:dotag
      let l:curidx = gettagstack().curidx + 1
      call settagstack(win_getid(), {'curidx': l:curidx})
    endif
  endif
endfunction

function! lsc#reference#findReferences() abort
  call lsc#file#flushChanges()
  let l:params = lsc#params#documentPosition()
  let l:params.context = {'includeDeclaration': v:true}
  call lsc#server#userCall('textDocument/references', l:params,
      \ function('<SID>setQuickFixLocations', ['references']))
endfunction

function! lsc#reference#findImplementations() abort
  call lsc#file#flushChanges()
  call lsc#server#userCall('textDocument/implementation',
      \ lsc#params#documentPosition(),
      \ function('<SID>setQuickFixLocations', ['implementations']))
endfunction

function! s:setQuickFixLocations(label, results) abort
  if empty(a:results)
    call lsc#message#show('No '.a:label.' found')
    return
  endif
  call map(a:results, {_, ref -> s:QuickFixItem(ref)})
  call sort(a:results, 'lsc#util#compareQuickFixItems')
  call setqflist(a:results)
  copen
endfunction

" Convert an LSP Location to a item suitable for the vim quickfix list.
"
" Both representations are dictionaries.
"
" Location:
" 'uri': file:// URI
" 'range': {'start': {'line', 'character'}, 'end': {'line', 'character'}}
"
" QuickFix Item: (as used)
" 'filename': file path if file is not open
" 'lnum': line number
" 'col': column number
" 'text': The content of the referenced line
"
" LSP line and column are zero-based, vim is one-based.
function! s:QuickFixItem(location) abort
  let l:item = {'lnum': a:location.range.start.line + 1,
      \ 'col': a:location.range.start.character + 1}
  let l:file_path = lsc#uri#documentPath(a:location.uri)
  let l:item.filename = fnamemodify(l:file_path, ':.')
  let l:bufnr = lsc#file#bufnr(l:file_path)
  if l:bufnr != -1 && bufloaded(l:bufnr)
    let l:item.text = getbufline(l:bufnr, l:item.lnum)[0]
  else
    let l:item.text = readfile(l:file_path, '', l:item.lnum)[l:item.lnum - 1]
  endif
  return l:item
endfunction

function! s:goTo(file, line, character, mods, issplit) abort
  let l:prev_buf = bufnr('%')
  if a:issplit || a:file !=# lsc#file#fullPath()
    let l:cmd = 'edit'
    if a:issplit
      let l:cmd = lsc#file#bufnr(a:file) == -1 ? 'split' : 'sbuffer'
    endif
    let l:relative_path = fnamemodify(a:file, ':~:.')
    exec a:mods l:cmd fnameescape(l:relative_path)
  endif
  if l:prev_buf != bufnr('%')
    " switching buffers already left a jump
    " Set curswant manually to work around vim bug
    call cursor([a:line, a:character, 0, virtcol([a:line, a:character])])
    redraw
  else
    " Move with 'G' to ensure a jump is left
    exec 'normal! '.a:line.'G'
    " Set curswant manually to work around vim bug
    call cursor([0, a:character, 0, virtcol([a:line, a:character])])
  endif
endfunction

function! lsc#reference#hover() abort
  call lsc#file#flushChanges()
  let l:params = lsc#params#documentPosition()
  call lsc#server#userCall('textDocument/hover', l:params,
      \ function('<SID>showHover', [s:hasOpenHover()]))
endfunction

function! s:hasOpenHover() abort
  if s:popup_id == 0 | return v:false | endif
  if !exists('*nvim_win_get_config') && !exists('*popup_getoptions')
    return v:false
  endif
  if has('nvim')
    return nvim_win_is_valid(s:popup_id)
  endif
  return len(popup_getoptions(s:popup_id)) > 0
endfunction

function! s:showHover(force_preview, result) abort
  if empty(a:result) || empty(a:result.contents)
    echom 'No hover information'
    return
  endif
  let l:contents = a:result.contents
  if type(l:contents) != type([])
    let l:contents = [l:contents]
  endif
  let l:lines = []
  let l:filetype = 'markdown'
  for l:item in l:contents
    if type(l:item) == type({})
      let l:lines += split(l:item.value, "\n")
      if has_key(l:item, 'language')
        let l:filetype = l:item.language
      elseif has_key(l:item, 'kind')
        let l:filetype = l:item.kind ==# 'markdown' ? 'markdown' : 'text'
      endif
    else
      let l:lines += split(l:item, "\n")
    endif
  endfor
  let b:lsc_last_hover = l:lines
  if get(g:, 'lsc_hover_popup', v:true)
        \ && (exists('*popup_atcursor') || exists('*nvim_open_win'))
    call s:closeHoverPopup()
    if (a:force_preview)
      call lsc#util#displayAsPreview(l:lines, l:filetype,
          \ function('lsc#util#noop'))
    else
      call s:openHoverPopup(l:lines, l:filetype)
    endif
  else
    call lsc#util#displayAsPreview(l:lines, l:filetype,
        \ function('lsc#util#noop'))
  endif
endfunction

function! s:openHoverPopup(lines, filetype) abort
  if len(a:lines) == 0 | return | endif
  if has('nvim')
    let l:buf = nvim_create_buf(v:false, v:true)
    call nvim_buf_set_option(l:buf, 'synmaxcol', 0)
    if g:lsc_enable_popup_syntax
      call nvim_buf_set_option(l:buf, 'filetype', a:filetype)
    endif
    " Note, the +2s below will be used for padding around the hover text.
    let l:height = len(a:lines) + 2
    let l:width = 1
    " The maximum width of the floating window should not exceed 95% of the
    " screen width.
    let l:max_width = float2nr(&columns * 0.95)

    " Need to figure out the longest line and base the popup width on that.
    " Also increase the floating window 'height' if any lines are going to wrap.
    for l:val in a:lines
      let l:val_width = strdisplaywidth(l:val) + 2
      if l:val_width > l:max_width
        let l:height = l:height + (l:val_width / l:max_width)
        let l:val_width = l:max_width
      endif
      let l:width = l:val_width > l:width ? l:val_width : l:width
    endfor

    " Prefer an upward floating window, but if there is no space fallback to
    " a downward floating window.
    let l:current_position = getpos('.')
    let l:top_line_number = line('w0')
    if l:current_position[1] - l:top_line_number >= l:height
      " There is space to display the floating window above the current cursor
      " line.
      let l:vertical_alignment = 'S'
      let l:row = 0
    else
      " No space above, so we will float downward instead.
      let l:vertical_alignment = 'N'
      let l:row = 1
      " Truncate the float height so that the popup always floats below and
      " never overflows into and above the cursor line.
      let l:lines_above_cursor = l:current_position[1] - l:top_line_number
      if l:height > winheight(0) + 2 - l:lines_above_cursor
        let l:height = winheight(0) - l:lines_above_cursor
      endif
    endif

    let l:opts = {
          \ 'relative': 'cursor',
          \ 'anchor':  l:vertical_alignment . 'W',
          \ 'row': l:row,
          \ 'col': 1,
          \ 'width': l:width,
          \ 'height': l:height,
          \ 'style': 'minimal',
          \ }
    let s:popup_id = nvim_open_win(l:buf, v:false, l:opts)
    call nvim_win_set_option(s:popup_id, 'colorcolumn', '')
    " Add padding to the left and right of each text line.
    call map(a:lines, {_, val -> ' ' . val . ' '})
    call nvim_buf_set_lines(winbufnr(s:popup_id), 1, -1, v:false, a:lines)
    call nvim_buf_set_option(l:buf, 'modifiable', v:false)
    " Close the floating window upon a cursor move.
    " vint: -ProhibitAutocmdWithNoGroup
    " https://github.com/Kuniwak/vint/issues/285
    autocmd CursorMoved <buffer> ++once call s:closeHoverPopup()
    " vint: +ProhibitAutocmdWithNoGroup
    " Also close the floating window when focussed into with the escape key.
    call nvim_buf_set_keymap(l:buf, 'n', '<Esc>', ':close<CR>', {})
  else
    let s:popup_id = popup_atcursor(a:lines, {
          \ 'padding': [1, 1, 1, 1],
          \ 'border': [0, 0, 0, 0],
          \ 'moved': 'any',
          \ })
    if g:lsc_enable_popup_syntax
      call setbufvar(winbufnr(s:popup_id), '&filetype', a:filetype)
    endif
  end
endfunction

function! s:closeHoverPopup() abort
  if has('nvim')
    if win_id2win(s:popup_id) > 0 && nvim_win_is_valid(s:popup_id)
      call nvim_win_close(s:popup_id, v:true)
    endif
  else
    call popup_close(s:popup_id)
  end
  let s:popup_id = 0
endfunction

" Request a list of symbols in the current document and populate the quickfix
" list.
function! lsc#reference#documentSymbols() abort
  call lsc#file#flushChanges()
  call lsc#server#userCall('textDocument/documentSymbol',
      \ lsc#params#textDocument(),
      \ function('<SID>setQuickFixSymbols'))
endfunction

function! s:setQuickFixSymbols(results) abort
  if empty(a:results)
    call lsc#message#show('No symbols found')
    return
  endif

  call map(a:results, {_, symbol -> lsc#convert#quickFixSymbol(symbol)})
  call sort(a:results, 'lsc#util#compareQuickFixItems')
  call setqflist(a:results)
  copen
endfunction


" If the server supports `textDocument/documentHighlight` and they are enabled,
" use the active highlights to move the cursor to the next or previous referene
" in the same document to the symbol under the cursor.
function! lsc#reference#findNext(direction) abort
  if exists('w:lsc_references')
    let l:idx = lsc#cursor#isInReference(w:lsc_references)
    if l:idx != -1 &&
        \ l:idx + a:direction >= 0 &&
        \ l:idx + a:direction < len(w:lsc_references)
      let l:target = w:lsc_references[l:idx + a:direction].ranges[0][0:1]
    endif
  endif
  if !exists('l:target')
    return
  endif
  " Move with 'G' to ensure a jump is left
  exec 'normal! '.l:target[0].'G'.l:target[1].'|'
endfunction
