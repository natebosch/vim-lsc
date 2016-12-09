# Vim Language Server Client

This is an experiment with building a partial replacement for plugins like
YouCompleteMe. Eventually I hope to have it communicate with a language server
following the [language server protocol][]

[language server protocol]: https://github.com/Microsoft/language-server-protocol

Don't expect this to do anything useful for a while.

## Testing Server communication

The communication example is built with the assumption that it can call
arbitrary methods with arbitrary parameters. The repo `dart-language-server` has
a demo_server which fills this purpose.

- Open any file in vim
- `:source plugin/lsc.vim`
- `:call RegisterLanguageServer(&filetype, 'dart
  ../dart-language-server/bin/demo_server.dart')`
- Anything which makes a buffer with this file type become visible will launch
  the server. `edit`, `split`, etc
- `:call CallMethod(&filetype, 'random_ints', {'count': 10})`
- In another terminal, `cat /tmp/wirelog.txt`. You should also see a message in
  vim with the response
- `:call CallMethod(&filetype, 'start_notifications', '')`
- You should see a notification message every 3 seconds
- `:call CallMethod(&filetype, 'stop_notifications', '')`
- `:call KillServers(&filetype)`
- You should see more output in `/tmp/wirelog.txt` and the process should exit

## Testing diagnostic highlighting

File diagnostics can be set per file and will be highlighting in all windows
displaying that file.

- Open `plugin/lsc.vim`
- `:source %`
- Register the `&filetype` as above. Only registered filetypes get highlighting.
- `:call RegisterLanguageServer(&filetype, 'dart
  ../dart-language-server/bin/demo_server.dart')`
- `:call SetFileDiagnostics(expand('%:p'), [{'severity': 1, 'range': [4, 1, 3]},
  {'severity': 2, 'range': [20, 1, 4]}])`
- Change buffers/windows/tabs. Every time the file is visible it will have
  highlighting, including if it shows up in multiple windows simultaneously
