# send-to-tmux.nvim

A Neovim plugin for sending text content to tmux panes.

一个 Neovim 插件，用于发送内容到 tmux

## Demo

Demo video: https://youtu.be/qWd8vv11Yvc

## Features

- Select tmux pane by `pane_id`
- Send current line or visual selection to tmux pane
- Optionally send `Enter` or auto-focus the target pane after successful sends
- Edit current line or visual selection in a `snacks.nvim` floating window before sending
- Edit the current file:line reference before sending
- Validates tmux installation and pane existence
- Simple and intuitive commands

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "fingergohappy/send-to-tmux.nvim",
  dependencies = {
    "folke/snacks.nvim", -- required for edit-before-send commands
  },
  config = function()
    require("send_to_tmux").setup()
  end,
}
```

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
  "fingergohappy/send-to-tmux.nvim",
  config = function()
    require("send_to_tmux").setup()
  end,
}
```

## Usage

### Commands

**`:SendToTmuxSelectTarget [pane_id]`**

Select tmux pane to send text to. You can enter tmux `pane_id` without `%` (e.g. `7`), and the plugin will normalize it to `%7`.

Example:
```vim
:SendToTmuxSelectTarget 7
```

If no target is provided, the plugin opens a `snacks.nvim` picker when
available and shows:

- `window_index`
- `pane_id`
- `process_name`

You can type to filter and then confirm the pane you want. The picker also
shows a right-side preview with recent pane output captured through
`tmux capture-pane -e -p -S -200`. The preview keeps wrapping disabled,
scrolls to the newest output, and preserves ANSI colors when tmux provides
them. The pane running the current Neovim instance is filtered out using the
`TMUX_PANE` environment variable, and moving through the picker temporarily
highlights the hovered tmux pane itself.

If `snacks.nvim` is not available, it falls back to a simple input prompt.

**`:SendToTmux`**

Send the current line or visual selection to the previously selected tmux pane.
If auto-enter is enabled, a final `Enter` is sent after the text.

**`:SendToTmuxEdit`**

Open the current line or visual selection in a `snacks.nvim` floating window.
Run `:w` inside that window to send the edited content to the selected tmux
pane and close the window.

**`:SendToTmuxEditRefLine`**

Build a `file:line` reference for the current location, open it in a
`snacks.nvim` floating window, then run `:w` inside that window to send the
edited reference to the selected tmux pane and close the window. When used with
a visual Ex range, it creates a `file:start-end` reference. Paths are relative
to the git project root when possible.

**`:SendToTmuxAutoEnter [on|off|toggle]`**

Control whether successful sends automatically issue an extra `Enter`.

**`:SendToTmuxAutoFocus [on|off|toggle]`**

Control whether successful sends automatically switch the tmux client to the
target pane.

Example:
```vim
" In normal mode, sends current line
:SendToTmux

" In visual mode, sends selected text
:'<,'>SendToTmux

" Edit before sending
:SendToTmuxEdit

" Edit a file:line reference before sending
:SendToTmuxEditRefLine

" Edit a file:line-range reference from visual selection
:'<,'>SendToTmuxEditRefLine

" Enable auto-enter after successful sends
:SendToTmuxAutoEnter on

" Toggle auto-focus after successful sends
:SendToTmuxAutoFocus
```

### Workflow

1. Select a tmux pane ID using `:SendToTmuxSelectTarget`
2. Use `:SendToTmux` to send the current line or selection
3. Use `:SendToTmuxEdit` when you want to review and edit the text before it is sent
4. Use `:SendToTmuxEditRefLine` when you want to send an editable `file:line` reference instead of the selected text
5. Use `:SendToTmuxAutoEnter` and `:SendToTmuxAutoFocus` to control post-send behavior

## Configuration

### Basic Setup

You can optionally configure a default pane ID:

```lua
require("send_to_tmux").setup({
  default_target = "7",  -- Optional default tmux pane ID
  auto_enter_on_send = false,
  auto_focus_on_send = false,
})
```

### Paste Behavior

This plugin sends content through tmux paste buffers for both single-line and
multiline sends.

`:SendToTmux` pastes the text. Use `auto_enter_on_send` if you want sends to
issue a final `Enter`, and `auto_focus_on_send` if you want successful sends to
switch to the target pane.

By default, it asks tmux to use bracketed paste when the target application has
requested it, which helps preserve indentation in interactive shells such as
IPython:

```lua
require("send_to_tmux").setup({
  bracketed_paste = true, -- default: true
})
```

If you do not want tmux to request bracketed paste, you can disable it:

```lua
require("send_to_tmux").setup({
  bracketed_paste = false,
})
```

Auto-enter and auto-focus:

```lua
require("send_to_tmux").setup({
  auto_enter_on_send = false, -- default: false
  auto_focus_on_send = false, -- default: false
})
```

### Key Bindings

#### Using lazy.nvim

```lua
{
  "fingergohappy/send-to-tmux.nvim",
  event = "VeryLazy",
  dependencies = {
    "folke/snacks.nvim", -- required for edit-before-send commands
  },
  cmd = {
    "SendToTmuxSelectTarget",
    "SendToTmux",
    "SendToTmuxEdit",
    "SendToTmuxEditRefLine",
    "SendToTmuxAutoEnter",
    "SendToTmuxAutoFocus",
  },
  opts = {},
  keys = {
    -- Send text without executing
    { "<leader>tt", mode = { "n", "v" }, "<cmd>SendToTmux<cr>", desc = "Send to tmux" },
    -- Edit before sending
    { "<leader>te", mode = { "n", "v" }, "<cmd>SendToTmuxEdit<cr>", desc = "Edit before sending to tmux" },
    -- Edit current file:line reference before sending
    { "<leader>tr", mode = { "n", "v" }, "<cmd>SendToTmuxEditRefLine<cr>", desc = "Edit file:line reference before sending to tmux" },
  },
}
```

#### Manual Key Bindings

```lua
-- Normal mode: send current line without executing
vim.keymap.set("n", "<leader>tt", "<cmd>SendToTmux<cr>", { desc = "Send current line to tmux" })

-- Visual mode: send selected text without executing
vim.keymap.set("v", "<leader>tt", "<cmd>SendToTmux<cr>", { desc = "Send selected text to tmux" })

-- Edit before sending
vim.keymap.set("n", "<leader>te", "<cmd>SendToTmuxEdit<cr>", { desc = "Edit current line before sending to tmux" })
vim.keymap.set("v", "<leader>te", "<cmd>SendToTmuxEdit<cr>", { desc = "Edit selection before sending to tmux" })

-- Edit current file:line reference before sending
vim.keymap.set("n", "<leader>tr", "<cmd>SendToTmuxEditRefLine<cr>", { desc = "Edit file:line reference before sending to tmux" })
vim.keymap.set("v", "<leader>tr", "<cmd>SendToTmuxEditRefLine<cr>", { desc = "Edit file:line reference before sending to tmux" })
```

#### Important Notes

1. **Mode Specification**: `SendToTmux`, `SendToTmuxEdit`, and `SendToTmuxEditRefLine` work in normal and visual modes, but manual key bindings need to be set for each mode separately.

2. **Leader Key**: Make sure your leader key is set:
   ```lua
   vim.g.mapleader = " "  -- Space as leader key
   ```

3. **Command Availability**: The plugin registers these commands:
   - `:SendToTmuxSelectTarget` - Select tmux pane ID
   - `:SendToTmux` - Send text to selected pane without executing
   - `:SendToTmuxEdit` - Edit text in a `snacks.nvim` floating window before sending
   - `:SendToTmuxEditRefLine` - Edit the current file:line reference before sending
   - `:SendToTmuxAutoEnter` - Toggle whether successful sends also issue `Enter`
   - `:SendToTmuxAutoFocus` - Toggle whether successful sends focus the target pane

## Requirements

- Neovim >= 0.8.0
- tmux
- `snacks.nvim` for edit-before-send commands

### Edit Workflow Requirements

The edit-before-send commands depend on `snacks.nvim`, which currently
requires `Neovim >= 0.9.4`. The base send commands still work on the plugin's
documented minimum Neovim version.

### Target Picker

When `snacks.nvim` is installed, `:SendToTmuxSelectTarget` without arguments
opens a filterable picker instead of a plain input prompt. Each entry is shown
as:

```text
%7  nvim  /path/to/project
```

## How It Works

**SendToTmuxSelectTarget**:
- Checks if tmux is installed
- Checks if the pane ID exists
- Saves the pane ID in plugin state

**SendToTmux**:
1. Checks if tmux is installed
2. Checks if pane ID is set (if not, shows error)
3. Checks if current line/selection has content (if not, shows error)
4. Validates that the pane ID still exists
5. Loads the selected content into a tmux buffer and pastes it into the target pane
6. Optionally sends `Enter` and/or focuses the target pane after a successful send

**SendToTmuxEdit**:
1. Resolve the current line or visual selection
2. Open a temporary `acwrite` buffer in a `snacks.nvim` floating window
3. Let you edit the text in place
4. Send the full edited buffer content when you run `:w`
5. Close the floating window after a successful send

**SendToTmuxEditRefLine**:
1. Builds the current `file:line` reference from the current buffer path and cursor line
2. Uses the provided Ex range to build `file:start-end` when called as `:'<,'>SendToTmuxEditRefLine`
3. Makes the path relative to the git project root when possible
4. Opens the reference in the same temporary `snacks.nvim` edit window
5. Sends the edited reference when you run `:w`
6. Closes the floating window after a successful send

**SendToTmuxAutoEnter / SendToTmuxAutoFocus**:
1. Toggle runtime state in the plugin configuration
2. `auto_enter_on_send` sends `Enter` after successful sends
3. `auto_focus_on_send` switches to the target pane after successful sends
4. Focus runs after the send succeeds

## License

MIT
