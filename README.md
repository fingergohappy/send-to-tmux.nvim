# send-to-tmux.nvim

A Neovim plugin for sending text content to tmux panes.

一个 Neovim 插件，用于发送内容到 tmux

## Features

- Select tmux pane by `pane_id`
- Send current line or visual selection to tmux pane
- Validates tmux installation and pane existence
- Simple and intuitive commands

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "fingergohappy/send-to-tmux.nvim",
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

If no target is provided, you will be prompted to enter one.

**`:SendToTmux`**

Send the current line or visual selection to the previously selected tmux pane
without pressing `Enter`.

**`:SendToTmuxExec`**

Send the current line or visual selection to the previously selected tmux pane
and then press `Enter`.

Example:
```vim
" In normal mode, sends current line without executing
:SendToTmux

" In visual mode, sends selected text without executing
:'<,'>SendToTmux

" Send and execute
:SendToTmuxExec
```

### Workflow

1. Select a tmux pane ID using `:SendToTmuxSelectTarget`
2. Use `:SendToTmux` to paste without executing
3. Use `:SendToTmuxExec` to paste and press `Enter`

## Configuration

### Basic Setup

You can optionally configure a default pane ID:

```lua
require("send_to_tmux").setup({
  default_target = "7",  -- Optional default tmux pane ID
})
```

### Paste Behavior

This plugin sends content through tmux paste buffers for both single-line and
multiline sends.

`:SendToTmux` pastes only. `:SendToTmuxExec` pastes and then issues a final
`Enter`.

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

### Key Bindings

#### Using lazy.nvim

```lua
{
  "fingergohappy/send-to-tmux.nvim",
  event = "VeryLazy",
  cmd = { "SendToTmuxSelectTarget", "SendToTmux", "SendToTmuxExec" },
  opts = {},
  keys = {
    -- Send text without executing
    { "<leader>tt", mode = { "n", "v" }, "<cmd>SendToTmux<cr>", desc = "Send to tmux" },
    -- Send text and execute
    { "<leader>te", mode = { "n", "v" }, "<cmd>SendToTmuxExec<cr>", desc = "Send to tmux and execute" },
    -- Select target
    { "<leader>T", "<cmd>SendToTmuxSelectTarget<cr>", desc = "Select tmux pane ID" },
  },
}
```

#### Manual Key Bindings

```lua
-- Normal mode: send current line without executing
vim.keymap.set("n", "<leader>tt", "<cmd>SendToTmux<cr>", { desc = "Send current line to tmux" })

-- Visual mode: send selected text without executing
vim.keymap.set("v", "<leader>tt", "<cmd>SendToTmux<cr>", { desc = "Send selected text to tmux" })

-- Send and execute
vim.keymap.set("n", "<leader>te", "<cmd>SendToTmuxExec<cr>", { desc = "Send current line to tmux and execute" })
vim.keymap.set("v", "<leader>te", "<cmd>SendToTmuxExec<cr>", { desc = "Send selected text to tmux and execute" })

-- Select target
vim.keymap.set("n", "<leader>T", "<cmd>SendToTmuxSelectTarget<cr>", { desc = "Select tmux pane ID" })
```

#### Important Notes

1. **Mode Specification**: Both `SendToTmux` and `SendToTmuxExec` work in normal and visual modes, but key bindings need to be set for each mode separately.

2. **Leader Key**: Make sure your leader key is set:
   ```lua
   vim.g.mapleader = " "  -- Space as leader key
   ```

3. **Command Availability**: The plugin registers these commands:
   - `:SendToTmuxSelectTarget` - Select tmux pane ID
   - `:SendToTmux` - Send text to selected pane without executing
   - `:SendToTmuxExec` - Send text to selected pane and execute

## Requirements

- Neovim >= 0.8.0
- tmux

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

**SendToTmuxExec**:
1. Follows the same flow as `SendToTmux`
2. Sends `Enter` after pasting the content

## License

MIT
