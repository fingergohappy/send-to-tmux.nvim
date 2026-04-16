-- Register user commands
local send_to_tmux = require("send_to_tmux")

-- Add help tag for documentation
if vim.fn.isdirectory(vim.fn.stdpath("data") .. "/site/doc") == 1 then
  vim.cmd("helptags " .. vim.fn.stdpath("data") .. "/site/doc")
end

-- Command to select tmux pane ID
vim.api.nvim_create_user_command("SendToTmuxSelectTarget", function(opts)
  send_to_tmux.select_target(opts.args)
end, {
  nargs = "?",
  desc = "Select tmux pane ID (e.g. 7)",
})

-- Command to send text to tmux
vim.api.nvim_create_user_command("SendToTmux", function(opts)
  send_to_tmux.send_to_tmux(opts)
end, {
  range = true,
  desc = "Send selected text or current line to tmux pane",
})

-- Command to edit text in a floating window before sending to tmux
vim.api.nvim_create_user_command("SendToTmuxEdit", function(opts)
  send_to_tmux.send_to_tmux_edit(opts)
end, {
  range = true,
  desc = "Edit selected text or current line before sending to tmux pane",
})

-- Command to edit the current file:line reference before sending to tmux
vim.api.nvim_create_user_command("SendToTmuxEditRefLine", function(opts)
  send_to_tmux.send_to_tmux_edit_ref_line(opts)
end, {
  range = true,
  desc = "Edit current file:line reference before sending to tmux pane",
})

-- Command to control whether Enter is sent automatically after successful sends
vim.api.nvim_create_user_command("SendToTmuxAutoEnter", function(opts)
  send_to_tmux.set_auto_enter(opts.args)
end, {
  nargs = "?",
  complete = function()
    return { "on", "off", "toggle" }
  end,
  desc = "Toggle auto-enter after successful sends",
})

-- Command to control whether tmux focus switches to the target pane after successful sends
vim.api.nvim_create_user_command("SendToTmuxAutoFocus", function(opts)
  send_to_tmux.set_auto_focus(opts.args)
end, {
  nargs = "?",
  complete = function()
    return { "on", "off", "toggle" }
  end,
  desc = "Toggle auto-focus to the target pane after successful sends",
})
