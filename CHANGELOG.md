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
