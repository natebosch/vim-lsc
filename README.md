# Vim Language Server Client

This is an experiment with building a partial replacement for plugins like
YouCompleteMe. Eventually I hope to have it communicate with a language server
following the [language server protocol][]

[language server protocol]: https://github.com/Microsoft/language-server-protocol

Don't expect this to do anything useful for a while.

## Testing server communication and diagnostic highlighting

The communication example is built with the assumption that it can call
arbitrary methods with arbitrary parameters. The repo `dart-language-server` has
a demo_server which fills this purpose.

- Open any file in vim
- `:source plugin/lsc.vim`
- `:call RegisterLanguageServer(&filetype, 'dart
  ../dart-language-server/bin/demo_server.dart')`
- Anything which makes a buffer with this file type become visible will launch
  the server. `edit`, `split`, etc
- The demo server will be notified of the contents of the file character by
  character as you type. If any line contains the word `error` it should be
  highlighted as a diagnostic.
- Quit vim and the server will be signaled to exit.
- Messages sent and received were logged in `/tmp/wirelog.txt`
