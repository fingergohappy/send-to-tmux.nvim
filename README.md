# send-to-tmux.nvim

A Neovim plugin for sending text content to tmux panes.

一个 Neovim 插件，用于发送内容到 tmux

## Features

- Select tmux target (session:window.pane)
- Send current line or visual selection to tmux pane
- Validates tmux installation and target existence
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

**`:SendToTmuxSelectTarget [target]`**

Select tmux target to send text to. The target format is: `session:window.pane` (e.g., "0:3.1" for session 0, window 3, pane 1)

Example:
```vim
:SendToTmuxSelectTarget 0:1.0
```

If no target is provided, you will be prompted to enter one.

**`:SendToTmux`**

Send the current line or visual selection to the previously selected tmux target.

Example:
```vim
" In normal mode, sends current line
:SendToTmux

" In visual mode, sends selected text
:'<,'>SendToTmux
```

### Workflow

1. Select a tmux target using `:SendToTmuxSelectTarget`
2. Send text to the target using `:SendToTmux` (in normal or visual mode)

## Configuration

### Basic Setup

You can optionally configure a default target:

```lua
require("send_to_tmux").setup({
  default_target = "0:1.0",  -- Optional default tmux target
})
```

### Key Bindings

#### Using lazy.nvim

```lua
{
  "fingergohappy/send-to-tmux.nvim",
  event = "VeryLazy",
  cmd = { "SendToTmuxSelectTarget", "SendToTmux" },
  opts = {},
  keys = {
    -- Send text in both normal and visual mode
    { "<leader>t", mode = { "n", "v" }, "<cmd>SendToTmux<cr>", desc = "Send to tmux" },
    -- Select target
    { "<leader>T", "<cmd>SendToTmuxSelectTarget<cr>", desc = "Select tmux target" },
  },
}
```

#### Manual Key Bindings

```lua
-- Normal mode: send current line
vim.keymap.set("n", "<leader>t", "<cmd>SendToTmux<cr>", { desc = "Send current line to tmux" })

-- Visual mode: send selected text  
vim.keymap.set("v", "<leader>t", "<cmd>SendToTmux<cr>", { desc = "Send selected text to tmux" })

-- Select target
vim.keymap.set("n", "<leader>T", "<cmd>SendToTmuxSelectTarget<cr>", { desc = "Select tmux target" })
```

#### Important Notes

1. **Mode Specification**: The `SendToTmux` command works in both normal and visual modes, but key bindings need to be set for each mode separately.

2. **Leader Key**: Make sure your leader key is set:
   ```lua
   vim.g.mapleader = " "  -- Space as leader key
   ```

3. **Command Availability**: The plugin registers these commands:
   - `:SendToTmuxSelectTarget` - Select tmux target
   - `:SendToTmux` - Send text to selected target

## Requirements

- Neovim >= 0.8.0
- tmux

## How It Works

**SendToTmuxSelectTarget**:
- Checks if tmux is installed
- Validates target format
- Checks if target exists
- Saves target in plugin state

**SendToTmux**:
1. Checks if tmux is installed
2. Checks if target is set (if not, shows error)
3. Checks if current line/selection has content (if not, shows error)
4. Validates that target still exists
5. Sends the selected content or current line to the tmux pane using `tmux send-keys`

## License

MIT
