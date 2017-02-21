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

## Installation

Install with your method of choice. If you don't have a preference check out
[vim-plug][]. Install a language server and ensure it is executable from your
`$PATH`.

[vim-plug]:https://github.com/junegunn/vim-plug

## Configuration

Map a filetype to the command that starts the language server for that filetype
in your `vimrc`. I also recommend a mapping to the function call to jump to
definition.

```vimscript
let g:lsc_server_commands = {'dart': ['dart_language_server']}

nnoremap gd :call lsc#reference#goToDefinition()<CR>
```

## Usage

Edit any file for a configured filetype. Errors and suggestions will show up as
you type. Call the `lsc#reference#goToDefinition()` function to jump to the
definition of the token under the cursor.
