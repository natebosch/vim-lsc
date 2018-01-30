let s:default_maps = {
    \ 'GoToDefinition': '<C-]>',
    \ 'FindReferences': 'gr',
    \ 'FindCodeActions': 'ga',
    \ 'Rename': 'gR',
    \ 'ShowHover': 'K',
    \ 'DocumentSymbol': 'go',
    \ 'Completion': 'completefunc',
    \}

function! lsc#config#mapKeys() abort
  if !exists('g:lsc_auto_map')
      \ || (type(g:lsc_auto_map) == v:t_bool && !g:lsc_auto_map)
      \ || (type(g:lsc_auto_map) == v:t_number && !g:lsc_auto_map)
    return
  endif
  let maps = g:lsc_auto_map
  if type(maps) == v:t_bool || type(maps) == v:t_number
    let maps = s:default_maps
  endif
  if type(maps) != v:t_dict
    call lsc#message#error('g:lsc_auto_map must be a bool or dict')
    return
  endif

  for command in [
      \ 'GoToDefinition',
      \ 'FindReferences',
      \ 'DocumentSymbol',
      \ 'ShowHover',
      \ 'FindCodeActions',
      \]
    if has_key(maps, command)
      execute 'nnoremap <buffer>'.maps[command].' :LSClient'.command.'<CR>'
    endif
  endfor
  if exists('g:lsc_enable_apply_edit') && g:lsc_enable_apply_edit
    if has_key(maps, 'Rename')
      execute 'nnoremap <buffer>'.maps['Rename'].' :LSClientRename<CR>'
    endif
  endif
  if !g:lsc_enable_autocomplete && has_key(maps, 'Completion')
    execute 'setlocal '.maps['Completion'].'=lsc#complete#complete'
  endif
endfunction

function! lsc#config#messageHook(server, method, params) abort
  if !has_key(a:server.config, 'message_hooks') | return a:params | endif
  let hooks = a:server.config.message_hooks
  if !has_key(hooks, a:method) | return a:params | endif
  let hook = hooks[a:method]
  if type(hook) == v:t_func
    return s:RunHookFunction(hook, a:method, a:params)
  elseif type(hook) == v:t_dict
    return s:MergeHookDict(hook, a:method, a:params)
  else
    call lsc#message#error('Message hook must be a function or a dict. '.
        \' Invalid config for '.a:method)
    return a:params
  endif
endfunction

function! s:RunHookFunction(Hook, method, params) abort
  try
    return a:Hook(a:method, a:params)
  catch
    call lsc#message#error('Failed to run message hook for '.a:method.
        \': '.v:exception)
    return a:params
  endtry
endfunction

function! s:MergeHookDict(hook, method, params) abort
  let resolved = s:ResolveHookDict(a:hook, a:method, a:params)
  for key in keys(resolved)
    let a:params[key] = resolved[key]
  endfor
  return a:params
endfunction

" If any key at any level within [hook] is a function, run it with [method] and
" [params] as arguments.
function! s:ResolveHookDict(hook, method, params) abort
  if !s:HasFunction(a:hook) | return a:hook | endif
  let copied = deepcopy(a:hook)
  for key in keys(a:hook)
    if type(a:hook[key]) == v:t_dict
      let copied[key] = s:ResolveHookDict(a:hook[key], a:method, a:params)
    elseif type(a:hook[key]) == v:t_func
      let Func = a:hook[key]
      let copied[key] = Func(a:method, a:params)
    endif
  endfor
  return copied
endfunction

function! s:HasFunction(hook) abort
  for Value in values(a:hook)
    if type(Value) == v:t_dict && s:HasFunction(Value)
      return v:true
    elseif type(Value) == v:t_func
      return v:true
    endif
  endfor
  return v:false
endfunction
