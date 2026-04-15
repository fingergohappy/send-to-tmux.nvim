# SendToTmux Edit-Before-Send Design

Date: 2026-04-15
Status: approved in chat

## Summary

Add an edit-before-send workflow to `send-to-tmux.nvim` that opens the current
line or visual selection in a temporary floating editor. The editor is rendered
through `snacks.nvim`, and saving the buffer sends the edited content to the
selected tmux pane and closes the window.

This design keeps the main send path inside Neovim, avoids tmux popup process
management, and reuses the plugin's existing tmux target validation and send
logic.

## Goals

- Let users edit the text before it is sent to tmux.
- Keep the workflow inside the current Neovim session.
- Preserve the current `SendToTmux` and `SendToTmuxExec` behavior.
- Close the edit window immediately after a successful save/send.
- Keep the implementation optional so the existing plugin still works without
  `snacks.nvim`.

## Non-Goals

- Opening a real file on disk for editing.
- Persisting draft content across sessions.
- Running a separate `nvim` inside tmux.
- Replacing the existing non-edit send commands.

## User Experience

Two new commands will be added:

- `:SendToTmuxEdit`
- `:SendToTmuxEditExec`

Behavior:

1. The command resolves the source text the same way as the existing send
   commands: visual selection when applicable, otherwise the current line.
2. A floating edit window opens through `Snacks.win`.
3. The temporary buffer is pre-filled with the resolved text.
4. The user edits the text normally.
5. On `:w`, the plugin intercepts the save, sends the full buffer content to
   tmux, and closes the floating window on success.
6. On send failure, the window stays open and an error notification is shown.

`SendToTmuxEdit` will send without `Enter`.
`SendToTmuxEditExec` will send and then press `Enter`.

## Dependency Strategy

`snacks.nvim` is required only for the new edit commands. The existing
selection and send commands must continue to work without it.

Implications:

- If `snacks.nvim` is unavailable, `:SendToTmuxEdit` and
  `:SendToTmuxEditExec` will notify the user and abort.
- The plugin's documented minimum Neovim version can remain unchanged for the
  base feature set, but the new edit workflow must be documented as requiring a
  working `snacks.nvim` setup. Since `snacks.nvim` documents `Neovim >= 0.9.4`,
  that becomes the practical minimum for the edit workflow.

## Window and Buffer Design

The edit UI will use a temporary buffer displayed in a `Snacks.win` floating
window.

Buffer properties:

- `buftype = "acwrite"`
- `bufhidden = "wipe"`
- `swapfile = false`
- `modifiable = true`
- `filetype` inherited from the current buffer when available

This keeps the workflow lightweight and avoids creating temporary files,
handling cleanup on disk, or managing duplicate sends from file write
autocommands.

## Command and Internal API Shape

The existing code currently combines "resolve source text" and "send payload"
inside one local flow. This feature needs those concerns separated so the new
editor can reuse the same send path.

The internal structure should be refactored to:

- keep `get_text_to_send(opts)` for extracting current line / visual selection
- introduce a dedicated internal function for sending a supplied payload, such
  as `send_payload(text, send_enter)`
- keep `send_to_tmux(opts)` and `send_to_tmux_exec(opts)` as thin wrappers
- add matching wrappers for the edit workflow

The send-payload function should own:

- tmux installation checks
- selected target checks
- target existence revalidation
- calling `tmux.send_to_tmux`
- success and error notifications

This avoids logic drift between normal send and edit-before-send behavior.

## Save Interception

The temporary edit buffer will attach a buffer-local `BufWriteCmd` autocmd.

When the user runs `:w` inside the edit buffer:

1. Read all buffer lines.
2. Join them with `\n`.
3. Call the shared send-payload path with the appropriate `send_enter` mode.
4. If send succeeds:
   - mark the buffer as not modified
   - close the floating window
   - wipe the buffer
5. If send fails:
   - leave the window open
   - keep the buffer contents intact
   - surface the error through `vim.notify`

## Failure Handling

The edit command must fail early and clearly in these cases:

- tmux is not installed
- no target pane has been selected
- selected target pane no longer exists
- no source text is available
- `snacks.nvim` is not installed or does not expose the required window API

For send-time failures after the edit window opens, the content must remain in
place so the user can fix or retry without data loss.

## Testing Strategy

Add focused unit tests to the existing plenary test suite.

Coverage:

- opening edit mode seeds the temporary buffer with the expected text
- `SendToTmuxEdit` maps to `send_enter = false`
- `SendToTmuxEditExec` maps to `send_enter = true`
- saving the edit buffer calls the shared send-payload path
- successful save closes the window and clears the temporary buffer state
- failed save keeps the window open
- missing `snacks.nvim` surfaces an actionable error

Tests should stub the snacks window constructor rather than depending on a real
UI implementation.

## Documentation Changes

Update user-facing docs to cover:

- the two new commands
- the save-to-send workflow
- the optional `snacks.nvim` dependency
- the practical Neovim requirement for the edit workflow
- example keymaps if the project continues to document keymaps in the README

## Implementation Notes

The first iteration should stay narrow:

- no persistent drafts
- no configurable close behavior
- no tmux popup fallback
- no extra edit window actions beyond normal editing and `:w`

This keeps the feature aligned with the plugin's current small surface area and
reduces branching in the send logic.
