if exists('g:lsc_registered_commands') | finish | endif
let g:lsc_registered_commands = 1

if !exists('g:lsc_server_commands') | finish | endif

for [l:filetype, l:config] in items(g:lsc_server_commands)
  call RegisterLanguageServer(l:filetype, l:config)
endfor
