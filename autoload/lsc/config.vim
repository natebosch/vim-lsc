let s:default_maps = {
    \ 'GoToDefinition': '<C-]>',
    \ 'FindReferences': 'gr',
    \ 'NextReference': '<C-n>',
    \ 'PreviousReference': '<C-p>',
    \ 'FindImplementations': 'gI',
    \ 'FindCodeActions': 'ga',
    \ 'Rename': 'gR',
    \ 'ShowHover': 'K',
    \ 'DocumentSymbol': 'go',
    \ 'WorkspaceSymbol': 'gS',
    \ 'Completion': 'completefunc',
    \}

function! s:ApplyDefaults(config) abort
  if type(a:config) == v:t_bool || type(a:config) == v:t_number
    return s:default_maps
  endif
  if type(a:config) != v:t_dict
      \ || !has_key(a:config, 'defaults')
      \ || !a:config.defaults
    return a:config
  endif
  let l:merged = deepcopy(s:default_maps)
  for l:pair in items(a:config)
    if l:pair[0] ==# 'defaults' | continue | endif
    if empty(l:pair[1])
      unlet l:merged[l:pair[0]]
    else
      let l:merged[l:pair[0]] = l:pair[1]
    endif
  endfor
  return l:merged
endfunction

function! lsc#config#mapKeys() abort
  if !exists('g:lsc_auto_map')
      \ || (type(g:lsc_auto_map) == v:t_bool && !g:lsc_auto_map)
      \ || (type(g:lsc_auto_map) == v:t_number && !g:lsc_auto_map)
    return
  endif
  let l:maps = s:ApplyDefaults(g:lsc_auto_map)
  if type(l:maps) != v:t_dict
    call lsc#message#error('g:lsc_auto_map must be a bool or dict')
    return
  endif

  for command in [
      \ 'GoToDefinition',
      \ 'FindReferences',
      \ 'NextReference',
      \ 'PreviousReference',
      \ 'FindImplementations',
      \ 'DocumentSymbol',
      \ 'WorkspaceSymbol',
      \ 'ShowHover',
      \ 'FindCodeActions',
      \]
    if has_key(l:maps, command)
      execute 'nnoremap <buffer>'.l:maps[command].' :LSClient'.command.'<CR>'
    endif
  endfor
  if !exists('g:lsc_enable_apply_edit') || g:lsc_enable_apply_edit
    if has_key(l:maps, 'Rename')
      execute 'nnoremap <buffer>'.l:maps['Rename'].' :LSClientRename<CR>'
    endif
  endif
  if has_key(l:maps, 'Completion')
    execute 'setlocal '.l:maps['Completion'].'=lsc#complete#complete'
  endif
endfunction

function! lsc#config#messageHook(server, method, params) abort
  if !has_key(a:server.config, 'message_hooks') | return a:params | endif
  let hooks = a:server.config.message_hooks
  if !has_key(hooks, a:method) | return a:params | endif
  let l:Hook = hooks[a:method]
  if type(l:Hook) == v:t_func
    return s:RunHookFunction(l:Hook, a:method, a:params)
  elseif type(l:Hook) == v:t_dict
    return s:MergeHookDict(l:Hook, a:method, a:params)
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
