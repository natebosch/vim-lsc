if !exists('s:initialized')
  let s:initialized = v:true
  let s:default_maps = {
      \ 'GoToDefinition': '<C-]>',
      \ 'GoToDefinitionSplit': ['<C-W>]', '<C-W><C-]>'],
      \ 'FindReferences': 'gr',
      \ 'NextReference': '<C-n>',
      \ 'PreviousReference': '<C-p>',
      \ 'FindImplementations': 'gI',
      \ 'FindCodeActions': 'ga',
      \ 'Rename': 'gR',
      \ 'ShowHover': v:true,
      \ 'DocumentSymbol': 'go',
      \ 'WorkspaceSymbol': 'gS',
      \ 'SignatureHelp': 'gm',
      \ 'Completion': 'completefunc',
      \}
  let s:skip_marker = {}
endif

function! s:ApplyDefaults(config) abort
  if type(a:config) == type(v:true) || type(a:config) == type(0)
    return s:default_maps
  endif
  if type(a:config) != type({})
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
      \ || (type(g:lsc_auto_map) == type(v:true) && !g:lsc_auto_map)
      \ || (type(g:lsc_auto_map) == type(0) && !g:lsc_auto_map)
    return
  endif
  let l:maps = s:ApplyDefaults(g:lsc_auto_map)
  if type(l:maps) != type({})
    call lsc#message#error('g:lsc_auto_map must be a bool or dict')
    return
  endif

  for l:command in [
      \ 'GoToDefinition',
      \ 'GoToDefinitionSplit',
      \ 'FindReferences',
      \ 'NextReference',
      \ 'PreviousReference',
      \ 'FindImplementations',
      \ 'FindCodeActions',
      \ 'ShowHover',
      \ 'DocumentSymbol',
      \ 'WorkspaceSymbol',
      \ 'SignatureHelp',
      \] + (get(g:, 'lsc_enable_apply_edit', 1) ? ['Rename'] : [])
    let l:lhs = get(l:maps, l:command, [])
    if type(l:lhs) != type('') && type(l:lhs) != type([])
      continue
    endif
    for l:m in type(l:lhs) == type([]) ? l:lhs : [l:lhs]
      execute 'nnoremap <buffer>'.l:m.' :LSClient'.l:command.'<CR>'
    endfor
  endfor
  if has_key(l:maps, 'Completion') &&
      \ type(l:maps['Completion']) == type('') &&
      \ len(l:maps['Completion']) > 0
    execute 'setlocal '.l:maps['Completion'].'=lsc#complete#complete'
  endif
  if has_key(l:maps, 'ShowHover')
    let l:show_hover = l:maps['ShowHover']
    if type(l:show_hover) == type(v:true) || type(l:show_hover) == type(0)
      if l:show_hover
        setlocal keywordprg=:LSClientShowHover
      endif
    endif
  endif
endfunction

" Wraps [Callback] with a function that will first translate a result through a
" user provided translation.
function! lsc#config#responseHook(server, method, Callback) abort
  if !has_key(a:server.config, 'response_hooks') | return a:Callback | endif
  let l:hooks = a:server.config.response_hooks
  if !has_key(l:hooks, a:method) | return a:Callback | endif
  let l:Hook = l:hooks[a:method]
  return {result -> a:Callback(l:Hook(result))}
endfunction

function! lsc#config#messageHook(server, method, params) abort
  if !has_key(a:server.config, 'message_hooks') | return a:params | endif
  let l:hooks = a:server.config.message_hooks
  if !has_key(l:hooks, a:method) | return a:params | endif
  let l:Hook = l:hooks[a:method]
  if type(l:Hook) == type({_->_})
    return s:RunHookFunction(l:Hook, a:method, a:params)
  elseif type(l:Hook) == type({})
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
  let l:resolved = s:ResolveHookDict(a:hook, a:method, a:params)
  for l:key in keys(l:resolved)
    let a:params[l:key] = l:resolved[l:key]
  endfor
  return a:params
endfunction

" If any key at any level within [hook] is a function, run it with [method] and
" [params] as arguments.
function! s:ResolveHookDict(hook, method, params) abort
  if !s:HasFunction(a:hook) | return a:hook | endif
  let l:copied = deepcopy(a:hook)
  for l:key in keys(a:hook)
    if type(a:hook[l:key]) == type({})
      let l:copied[l:key] = s:ResolveHookDict(a:hook[l:key], a:method, a:params)
    elseif type(a:hook[l:key]) == type({_->_})
      let l:Func = a:hook[l:key]
      let l:copied[l:key] = Func(a:method, a:params)
    endif
  endfor
  return l:copied
endfunction

function! s:HasFunction(hook) abort
  for l:Value in values(a:hook)
    if type(l:Value) == type({}) && s:HasFunction(l:Value)
      return v:true
    elseif type(l:Value) == type({_->_})
      return v:true
    endif
  endfor
  return v:false
endfunction

" Whether a message of type [type] should be echoed
"
" By default messages are shown at "Info" or higher, this can be overrided per
" server.
function! lsc#config#shouldEcho(server, type) abort
  let l:threshold = 3
  if has_key(a:server.config, 'log_level')
    if type(a:server.config.log_level) == type(0)
      let l:threshold = a:server.config.log_level
    else
      let l:config = a:server.config.log_level
      if l:config ==# 'Error'
        let l:threshold = 1
      elseif l:config ==# 'Warning'
        let l:threshold = 2
      elseif l:config ==# 'Info'
        let l:threshold = 3
      elseif l:config ==# 'Log'
        let l:threshold = 4
      endif
    endif
  endif
  return a:type <= l:threshold
endfunction

" A maker from returns from "message_hook" functions indicating that a call
" should not be made.
function! lsc#config#skip() abort
  return s:skip_marker
endfunction

function! lsc#config#handleNotification(server, method, params) abort
  if !has_key(a:server.config, 'notifications') | return | endif
  let l:hooks = a:server.config.notifications
  if !has_key(l:hooks, a:method) | return | endif
  let l:Hook = l:hooks[a:method]
  if type(l:Hook) != type({_->_})
    call lsc#message#error('Notification handlers must be functions: '.a:method)
    unlet l:hooks[a:method]
    return
  endif
  try
    call l:Hook(a:method, a:params)
  catch
    call lsc#message#error('Failed to run callback for '.a:method.
        \': '.v:exception)
  endtry
endfunction
