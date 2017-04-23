function! lsc#reference#goToDefinition() abort
  call lsc#file#flushChanges()
  let s:goto_definition_id += 1
  let data = {'old_pos': getcurpos(),
      \ 'goto_definition_id': s:goto_definition_id}
  function data.trigger(result) abort
    if !s:isGoToValid(self.old_pos, self.goto_definition_id)
      echom 'GoTODefinition skipped'
      return
    endif
    if type(a:result) == type(v:null)
      call lsc#util#error('No definition found')
      return
    endif
    if type(a:result) == type([])
      let location = a:result[0]
    else
      let location = a:result
    endif
    let file = lsc#util#documentPath(location.uri)
    let line = location.range.start.line + 1
    let character = location.range.start.character + 1
    call s:goTo(file, line, character)
  endfunction
  let params = { 'textDocument': {'uri': lsc#util#documentUri()},
      \ 'position': {'line': line('.') - 1, 'character': col('.') - 1}
      \ }
  call lsc#server#call(&filetype, 'textDocument/definition',
      \ params, data.trigger)
endfunction

if !exists('s:initialized')
  let s:goto_definition_id = 1
  let s:initialized = v:true
endif

function! s:isGoToValid(old_pos, goto_definition_id) abort
  return a:goto_definition_id == s:goto_definition_id &&
      \ a:old_pos == getcurpos()
endfunction

function! s:goTo(file, line, character) abort
  if a:file != expand('%:p')
    let relative_path = fnamemodify(a:file, ":~:.")
    exec 'edit '.relative_path
  endif
  call cursor(a:line, a:character)
endfunction
