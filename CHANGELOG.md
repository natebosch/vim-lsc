# 0.1.1-dev

- Call initialize first for better protocol compliance
- Use a relative path where possible when jumping to definition
- Only display 'message' field for errors
- Bug Fix: Less likely to delete inserted text when trying to complete
- Bug Fix: More likely to try to complete when not following a '.'

# 0.1.0

Experimental first release - there are protocol bugs, for instance this does not
call the required `initialize` method. Only known to work with the
`dart_language_server` implementation.

Supports:
- Diagnostic highlights
- Autocomplete suggestions
- Jump to definition
