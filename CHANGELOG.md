# 0.2.10-dev

- Add `:LSClientDocumentSymbol` command to populate the quickfix list with
  symbols in the current document.

# 0.2.9+1

- Fix error in calling function message hooks.

# 0.2.9

- Add an argument to `lsc#edit#findCodeActions` to pass a callback to choose an
  action.
- Save and restore window view when applying a workspace edit.
- Bug fix: Handle zero width edits at the end of a line.
- Add support for `textDocument/rename`.
- Support `TextEdit`s in non-current buffers.
- Add `lsc#diagnostics#count()`
- Add `:LSClientAllDiagnostics` which populates the quickfix list with
  diagnostics across all files that have been sent by any server.
- Bug fix: Don't make callback functions global.
- Reduce performance impact of a large number of files with empty diagnostics.
- Allow `message_hooks` values to be a `dict` which gets merged into `params`.
  Supports inner values which are functions that get called to resolve values.
- Support highlights for multi-line diagnostics.
- Split up large messages into chunks to avoid potential deadlocks where output
  buffer becomes full but it isn't read.
- Improve performance of incremental diff.
- Print messages received on stderr.
- Don't open an empty quickfix list when no references are found.
- Don't mask `hlsearch` with diagnostics.

# 0.2.8

- Don't track files which are not `modifiable`.
- Bug Fix: Fix jumping from quickfix item to files under home directory.
- Only update diagnostic under cursor when the change is for the current file.
- Add support for additional per-server config.
- Bug Fix: If using `g:lsc_enable_incremental_sync` correctly handles multiple
  blank lines in a row.
- Add support for overriding the `params` for certain methods.
- Bug Fix: Correct paths on Windows.
- Bug Fix: Allow restarting a server which failed to start initially.
- Add experimental support for `textDocument/codeActions` and
  `workspace/applyEdit`

# 0.2.7

- Add support for `TextDocumentSyncKind.Incremental`. There is a new setting
  called `g:lsc_enable_incremental_sync` which is defaulted to `v:false` to
  allow the client to attempt incremental syncs. This feature is experimental.
- Bug Fix: Use buffer filetype rather than current filetype when flushing file
  changes for background buffers.
- Update the diagnostic under the cursor when diagnostics change for the file.
- Bug Fix: Don't change diagnostic highlights while in visual mode.

# 0.2.6

- Send file updates after re-reading already open file. Fixes some cases where
  the server has a different idea of the file content than the editor.
- Avoid clearing and readding the same diagnostic matches each time diagnostics
  change in some other file.
- Avoid doing work on diagnostics for unopened files.
- Bug Fix: Use the correct diagnostics when updating the location list for
  windows other than the current window.
- Add `LSCServerStatus()` function which returns a string representing the state
  of the language server for the current filetype.
- `:LSCRestartServer` can now restart servers that failed, rather than just
  those which are currently running.
- Bug Fix: Always send `didOpen` calls with the content they have at the time of
  initialization rather than what they had when the buffer was read. Fixes some
  cases where an edit before the server is read would get lost.
- Bug Fix: Handle case where a `GoToDefinition` is an empty list rather than
  null.
- Bug Fix: Handle case where initialization call gets a null response.
- Bug Fix: Avoid breaking further callbacks when a message handler throws.
- Bug Fix: Handle `MarkedString` and `List<MarkedString>` results to
  `textDocument/hover` calls.
- Add experimental support for communicating over a TCP channel. Configure the
  command as a "host:port" pair.
- Bug Fix: Handle null completions response.
- Bug Fix: Don't include an 'id' field for messages which are notifications.
- Add support for `window/showMessage` and `window/logMessage`.
- Use `<nomodeline>` with `doautocmd`.
- Bug Fix: Check for `lsc_flush_timer` before stopping it.
- Show an error if a user triggered call fails.
- Bug Fix: URI encode file paths.

# 0.2.5

- Add autocmds `LSCAutocomplete` before firing completion, and `LSCShowPreview`
  after opening the preview window.
- Change Info and Hint diagnostic default highlight to `SpellCap`.
- Append diagnostic code to the message.

# 0.2.4

- Bug Fix: Handle completion items with empty detail.
- `LSClientShowHover` now reuses the window it already opened rather than
  closing it and splitting again to allow for maintaining layout.
- Add optional configuration `g:lsc_preview_split_direction` to override
  `splitbelow`.
- Add docs.

# 0.2.3

- `redraw` after jumping to definition in another file.
- Allow configuring trace level with `g:lsc_trace_level`. May be one of 'off',
  'messages', or 'verbose'. Defaults to 'off'.
- Bug fix: Avoid deep stack during large spikes of messages. Switch from
  recursion to a while loop.
- Add `LSClientDisable`, `LSClientEnable` to disable or re-enable the client
  for the current filetype during a session.
- Add `LSClientShowHover` to display hover information in a preview window.
- Add support for automatically mapping keys only in buffers for tracked
  filetypes.

# 0.2.2

- Completion Improvements:
  - Bug fix: Don't leave an extra character when completing after typing 3
    characters.
  - Filter completions after typing 3 characters.
  - Add configuration to disable autocomplete.
  - Bug Fix: Don't block future completion attempts after an empty suggestion
    list.
  - Use the `triggerCharacters` suggested by the server instead of `.`
    exclusively.
  - Use only the first line of suggestion detail in completion menu
- Bug Fix: Send and allow a space before header content.

# 0.2.1

- Handle language server restarts:
  - Clean up local state when a language server exits.
  - Call `didOpen` for all open files when a language server (re)starts.
- Add LSClientRestart command to restart the server for the current filetype.

# 0.2.0

- More detail in completion suggestions, doc comment in preview window.
- Sort diagnostics in location list.
- **Breaking**: Allow only 1 server command per filetype.
- Add commands for GoToDefinition and FindReferences
- Bug fix: Don't try to read lines from unreadable buffer.

# 0.1.3

- Bug fix: Newlines in diagnostics are replace with '\n' to avoid multiline
  messages
- Add support for `textDocument/references` request. References are shown in
  quickfix list.
- Bug fix: Support receiving diagnostics for files which are not opened in a
  buffer

# 0.1.2

- Bug fix: Leave a jump in the jumplist when moving to a definition in the same
  file
- Completion improvements:
  - Overwrite `completeopt` before completion for a better experience.
  - Avoid completion requests while already giving suggestions
  - Improve heuristics for start of completion range
  - Flush file changes after completion
- Bug fix: Don't change window highlights when in select mode
- Bug fix: Location list is cleared when switching to a non-tracked filetype,
  and kept up to date across windows and tabs showing the same buffer

# 0.1.1

- Call initialize first for better protocol compliance
- Use a relative path where possible when jumping to definition
- Only display 'message' field for errors
- Bug Fix: Less likely to delete inserted text when trying to complete
- Bug Fix: More likely to try to complete when not following a '.'
- Populate location list with diagnostics
- Bug fix: Don't try to 'edit' the current file

# 0.1.0

Experimental first release - there are protocol bugs, for instance this does not
call the required `initialize` method. Only known to work with the
`dart_language_server` implementation.

Supports:
- Diagnostic highlights
- Autocomplete suggestions
- Jump to definition
