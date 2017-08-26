let s:default_maps = {
    \ 'GoToDefinition': '<C-]>',
    \ 'FindReferences': 'gr',
    \ 'ShowHover': 'K',
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

  for command in ['GoToDefinition', 'FindReferences', 'ShowHover']
    if has_key(maps, command)
      execute 'nnoremap <buffer>'.maps[command].' :LSClient'.command.'<CR>'
    endif
  endfor
  if !g:lsc_enable_autocomplete && has_key(maps, 'Completion')
    execute 'setlocal '.maps['Completion'].'=lsc#complete#complete'
  endif
endfunction
