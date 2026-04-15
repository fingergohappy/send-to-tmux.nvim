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
  desc = "Send selected text or current line to tmux pane without pressing Enter",
})

-- Command to send text to tmux and press Enter
vim.api.nvim_create_user_command("SendToTmuxExec", function(opts)
  send_to_tmux.send_to_tmux_exec(opts)
end, {
  range = true,
  desc = "Send selected text or current line to tmux pane and press Enter",
})
