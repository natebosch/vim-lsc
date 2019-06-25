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

vim-lsc is compatible with vim 8, and neovim.

Note: When using neovim be sure to use `set shortmess-=F` to avoid suppressing
error messages from this plugin.

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

Most interactive features are triggered by commands. You can use
`g:lsc_auto_map` to have them automatically mapped for the buffers which have a
language server enabled. You can use the default mappings by setting it to
`v:true`, or specify your own mappings in a dict.

Most keys take strings or lists of strings which are the keys bound to that
command in normal mode. The `'ShowHover'` key can also be `v:true` in which case
it sets `keywordprg` instead of a keybind (`keywordprg` maps `K`). The
'Completion' key sets a completion function for manual invocation, and should be
either `'completefunc'` or `'omnifunc'` (see `:help complete-functions`).

```viml
" Use all the defaults (recommended):
let g:lsc_auto_map = v:true

" Apply the defaults with a few overrides:
let g:lsc_auto_map = {'defaults': v:true, 'FindReferences': '<leader>r'}

" Setting a value to a blank string leaves that command unmapped:
let g:lsc_auto_map = {'defaults': v:true, 'FindImplementations': ''}

" ... or set only the commands you want mapped without defaults.
" Complete default mappings are:
let g:lsc_auto_map = {
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

Run `:LSClientAllDiagnostics` to populate, and maintain, a list of all
diagnostics across the project in the quickfix list.

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

Disable autocomplete with `let g:lsc_enable_autocomplete = v:false`. A
completion function is available at `lsc#complete#complete` (set to
`completefunc` if applying the default keymap). This is synchronous and has a
cap of 5 seconds to wait for the server to respond. It can be used whether
autocomplete is enabled or not.

### Reference Highlights

If the server supports the `textDocument/documentHighlight` call references to
the element under the cursor throughout the document will be highlighted.
Disable with `let g:lsc_reference_highlights = v:false` or customize the
highlighting with the group `lscReference`. Use `<c-n>`
(`:LSClientNextReference`) or `<c-p>` (`:LSClientPReviousReference`) to jump to
other reference to the currently highlighted element.

### Jump to definition

While the cursor is on any identifier call `LSClientGoToDefinition` (`<C-]>` if
using the default mappings) to jump to the location of the definition. If the
cursor moves before the server responds the response will be ignored.

### Find references

While the cursor is on any identifier call `LSClientFindReferences` (`gr` if
using the default mappings) to populate the quickfix list with usage locations.

### Find implementations

While the cursor is on any identifier call `LSClientFindImplementations` (`gI`
if using the default mappings) to populate the quickfix list with implementation
locations.

### Document Symbols

Call `LSClientDocumentSymbol` (`go` if using the default mappings) to populate
the quickfix list with the locations of all symbols in that document.

### Workspace Symbol Search

Call `LSClientWorkspaceSymbol` with a no arguments, or with a single String
argument. (`gS` if using the default mappings) to query the server for symbols
matching a search string. Results will populate the quickfix list.

### Hover

While the cursor is on any identifier call `LSClientShowHover` (`K` if using the
default mappings, bound through `keywordprg`) to request hover text and show it
in a preview window.
Override the direction of the split by setting `g:lsc_preview_split_direction`
to either `'below'` or `'above'`. Quickly close the preview without switching
buffers with `<c-w><c-z>`. See `:help preview-window`.

### Code Actions

Call `LSClientFindCodeActions` (`ga` if using the default mappings) to look for
code actions available at the cursor location and run one by entering the number
of the chosen action.

### Signature help

Call `LSClientSignatureHelp` (`<C-m>` if using the default mappings) to get help while writing
a function call. The currently active parameter is highlighted with the group
`lscCurrentParameter`.
