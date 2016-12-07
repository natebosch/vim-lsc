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

- Open `plugin/lsc.vim`
- `:source %`
- `:call RegisterLanguageServer(&filetype, 'dart
  ../dart-language-server/bin/demo_server.dart')`
- `call CallMethod('dart ../dart-language-server/bin/demo_server.dart')`
- In another terminal, `cat /tmp/wirelog.txt`. You should also see a message in
  vim with the response
- `call KillServer('dart ../dart-language-server/bin/demo_server.dart')`
- You should see more output in `/tmp/wirelog.txt` and more messages in vim

## Testing diagnostic highlighting

File diagnostics can be set per file and will be highlighting in all windows
displaying that file.

- Open `plugin/lsc.vim`
- `:source %`
- Register the `&filetype` as above. Only registered filetypes get highlighting.
- `:call RegisterLanguageServer(&filetype, 'arbitrary string')`
- `:call SetFileDiagnostics(expand('%:p'), [{'severity': 1, 'range': [4, 1, 3]},
  {'severity': 2, 'range': [20, 1, 4]}])`
- Change buffers/windows/tabs. Every time the file is visible it will have
  highlighting
