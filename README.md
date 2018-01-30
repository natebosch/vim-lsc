# Vim Language Server Client

Adds language-aware tooling to vim by communicating with a language server
following the [language server protocol][]. For more information see
[langserver.org][].

[language server protocol]: https://github.com/Microsoft/language-server-protocol
[langserver.org]: http://langserver.org/

This client has not been tested against a wide range of servers so there may be
protocol bugs.

## Installation

Install with your plugin management method of choice. If you don't have a
preference check out [vim-plug][]. Install a language server and ensure it is
executable from your `$PATH`.

vim-lsc should work with vim 8.0, it is not compatible with neovim.

[vim-plug]:https://github.com/junegunn/vim-plug

## Configuration

Map a filetype to the command that starts the language server for that filetype
in your `vimrc`.

```viml
let g:lsc_server_commands = {'dart': 'dart_language_server'}
```

To disable autocomplete in favor of manual completion also add

```viml
let g:lsc_enable_autocomplete = v:false
```

Most interactive features are triggered by commands, you can map keys to these
commands, or use `g:lsc_auto_map` to have them automatically mapped for the
buffers which have a language server enabled. You can use the default mappings
by setting it to `v:true`, or specify your own mappings in a dict. The
`'Complete'` key will set a completion function only if
`g:lsc_enable_autocomplete` is false.

```viml
let g:lsc_auto_map = v:true " Use defaults
" ... or set only the keys you want mapped, defaults are:
let g:lsc_auto_map = {
    \ 'GoToDefinition': '<C-]>',
    \ 'FindReferences': 'gr',
    \ 'FindCodeActions': 'ga',
    \ 'DocumentSymbol': 'go',
    \ 'ShowHover': 'K',
    \ 'Completion': 'completefunc',
    \}
```

During the initialization call LSP supports a `trace` argument which configures
logging on the server. Set this with `g:lsc_trace_level`. Valid values are
`'off'`, `'messages'`, or `'verbose'`. Defaults to `'off'`.

## Features

The protocol does not require that every language server supports every feature
so support may vary.

All communication with the server is asynchronous and will not block the editor.
For requests that trigger an action the response might be silently ignored if it
can no longer be used - you can abort most operations that are too slow by
moving the cursor.

The client can be temporarily disabled for a session with `LSClientDisable` and
re-enabled with `LSClientEnable`. At any time the server can be exited and
restarted with `LSClientRestartServer` - this sends a request for the server to
exit rather than kill it's process so a completely unresponsive server should be
killed manually instead.

### Diagnostics

Errors, warnings, and hints reported by the server are highlighted in the buffer.
When the cursor is on a line with a diagnostic the message will be displayed. If
there are multiple diagnostics on a line the one closest to the cursor will be
displayed.

Diagnostics are also reported in the location list for each window which has the
buffer open.

### Autocomplete

When more than 3 word characters or a trigger character are typed a request for
autocomplete suggestions is sent to the server. If the server responds before
the cursor moves again the options will be provided using vim's built in
completion.

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

While the cursor is on any identifier call `LSClientGoToDefinition` (`<C-]>` if
using the default mappings) to jump to the location of the definition. If the
cursor moves before the server responds the response will be ignored.

### Find references

While the cursor is on any identifier call `LSClientFindReferences` (`gr` if
using the default mappings) to populate the quickfix list with usage locations.

### Document Symbols

In any enabled buffer call `LSClientDocumentSymbol` (`go` if using the default
mappings) to populate the quickfix list with the locations of all symbols in
that document.

### Hover

While the cursor is on any identifier call `LSClientShowHover` (`K` if using the
default mappings) to request hover text and show it in a preview window.
Override the direction of the split by setting `g:lsc_preview_split_direction`
to either `'below'` or `'above'`.

### Code Actions (experimental)

While this is still experimental it is opt-in. Add
`let g:lsc_enable_apply_edit = v:true` to allow edits to files (since these are
the most likely result of code actions). Call `LSClientFindCodeActions` (`ga` if
using the default mappings) to look for code actions available at the cursor
location.

Support is very limited for now. Edits can only be applied in the active buffer
to prevent.
