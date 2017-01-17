# Vim Language Server Client

This is an experiment with building a partial replacement for plugins like
YouCompleteMe communicating with a language server following the [language
server protocol][]

[language server protocol]: https://github.com/Microsoft/language-server-protocol

In theory any language server should be compatible - but this is not being
built against any reference implementation so there may be protocol bugs. The
only implementation which supported for now is the [dart language server][]
implemented alongside the plugin.

[dart language server]: https://github.com/natebosch/dart_language_server

## Testing server communication and diagnostic highlighting

- Install the dart language server
- Open any file in vim
- `:source plugin/lsc.vim`
- `:call RegisterLanguageServer('dart', 'dart_language_server')`
- Open a buffer with the file type 'dart'.
- Enter any invalid Dart code. You should see errors highlighted.
- Quit vim and the server will be signaled to exit.
