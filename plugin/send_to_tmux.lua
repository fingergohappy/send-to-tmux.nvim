-- Register user commands
local send_to_tmux = require("send_to_tmux")

-- Add help tag for documentation
if vim.fn.isdirectory(vim.fn.stdpath("data") .. "/site/doc") == 1 then
  vim.cmd("helptags " .. vim.fn.stdpath("data") .. "/site/doc")
end

-- Command to select tmux target
vim.api.nvim_create_user_command("SendToTmuxSelectTarget", function(opts)
  send_to_tmux.select_target(opts.args)
end, {
  nargs = "?",
  desc = "Select tmux target (format: session:window.pane, e.g., 0:3.1)",
})

-- Command to send text to tmux
vim.api.nvim_create_user_command("SendToTmux", function()
  send_to_tmux.send_to_tmux()
end, {
  range = true,
  desc = "Send selected text or current line to tmux target",
})
