# Vim Language Server Client

This is an experiment with building a partial replacement for plugins like
YouCompleteMe communicating with a language server following the [language
server protocol][]

[language server protocol]: https://github.com/Microsoft/language-server-protocol

This client has not been tested against a wide range of servers so there may be
protocol bugs.

## Installation

Install with your method of choice. If you don't have a preference check out
[vim-plug][]. Install a language server and ensure it is executable from your
`$PATH`.

[vim-plug]:https://github.com/junegunn/vim-plug

## Configuration

Map a filetype to the command that starts the language server for that filetype
in your `vimrc`. I also recommend mapping shortcuts to the go to definition and
find references commands.

```viml
let g:lsc_server_commands = {'dart': 'dart_language_server'}

nnoremap gd :LSClientGoToDefinition<CR>
nnoremap gr :LSClientFindReferences<CR>
```

To disable autocomplete in favor of manual completion also add

```viml
let g:lsc_enable_autocomplete = v:false
set completefunc=lsc#complete#complete
```

## Features

The protocol does not require that every language server supports every feature
so support may vary.

All communication with the server is asynchronous and will not block the editor.
For requests that trigger an action the response might be silently ignored if it
can no longer be used - you can abort most operations that are too slow by
moving the cursor.

### Diagnostics

Errors, warnings, and hints reported by the server are highlighted in the buffer.
When the cursor is on a line with a diagnostic the message will be displayed. If
there are multiple diagnostics on a line the one closest to the cursor will be
displayed.

Diagnostics are also reported in the location list for each window which has the
buffer open.

### Autocomplete

When more than 3 word characters or a '.' are typed a request for autocomplete
suggestions is sent to the server. If the server responds before the cursor
moves again the options will be provided using vim's built in completion.

Note: By default `completeopt` includes `preview` and completion items include
documentation in the preview window. Close the window after completion with
`<c-w><c-z>` or disable with `set completeopt-=preview`. To automatically close
the documentation window use the following:

```viml
autocmd CompleteDone * silent! pclose
```

Disable autocomplete with `let g:lsc_enable_autocomplete = v:false`. When using
manual completion the `completefunc` may have no results if completion is
requested before the server responds with suggestions.

### Jump to definition

While the cursor is on any identifier call `LSClientGoToDefinition` to jump to
the location of the definition. If the cursor moves before the server responds
the response will be ignored.

### Find references

While the cursor is on any identifier call `LSClientFindReferences` to populate
the quickfix list with usage locations.
