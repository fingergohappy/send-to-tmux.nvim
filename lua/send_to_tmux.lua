-- main module file
local tmux = require("send_to_tmux.module")

---@class Config
---@field default_target string|nil Default tmux target
local config = {
  default_target = nil,
}

---@class SendToTmuxModule
local M = {}

---@type Config
M.config = config

-- Plugin state to store the selected tmux target
local state = {
  target = nil,
}

---Setup function for the plugin
---@param args Config?
M.setup = function(args)
  M.config = vim.tbl_deep_extend("force", M.config, args or {})

  -- Set default_target if provided (tmux will validate)
  if M.config.default_target then
    state.target = M.config.default_target
  end
end

---Select tmux target
---@param target string|nil The tmux target in format "session:window.pane" (e.g., "0:3.1")
M.select_target = function(target)
  -- Check if tmux is installed
  if not tmux.is_tmux_installed() then
    vim.notify("tmux is not installed", vim.log.levels.ERROR)
    return
  end

  -- If no target provided, prompt user for input
  if not target or target == "" then
    vim.ui.input({
      prompt = "Enter tmux target (format: session:window.pane, e.g., 0:3.1): ",
    }, function(input)
      if input and input ~= "" then
        M.select_target(input)
      end
    end)
    return
  end

  -- Check if target exists (tmux will validate format)
  if not tmux.target_exists(target) then
    vim.notify("Target does not exist: " .. target, vim.log.levels.ERROR)
    return
  end

  -- Save target to state
  state.target = target
  vim.notify("Tmux target set to: " .. target, vim.log.levels.INFO)
end

---Get selected text or current line
---@return string|nil text The selected text or current line
local function get_text_to_send()
  local mode = vim.fn.mode()

  if mode == "v" or mode == "V" or mode == "" then
    -- Visual mode: get selected text
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    local start_line = start_pos[2]
    local end_line = end_pos[2]
    local start_col = start_pos[3]
    local end_col = end_pos[3]

    -- Handle single line selection
    if start_line == end_line then
      local line = vim.fn.getline(start_line)
      -- Ensure start_col <= end_col
      if start_col > end_col then
        start_col, end_col = end_col, start_col
      end
      return line:sub(start_col, end_col)
    end

    -- Handle multi-line selection
    local lines_result = vim.fn.getline(start_line, end_line)
    if type(lines_result) == "string" then
      -- Single line case (should not happen here due to earlier check)
      return lines_result:sub(start_col, end_col)
    end

    local lines = lines_result
    if #lines == 0 then
      return nil
    end

    -- Adjust first and last lines for column selection
    -- Ensure start_col <= end_col for proper substring
    if start_col > end_col then
      start_col, end_col = end_col, start_col
    end
    lines[1] = lines[1]:sub(start_col)
    lines[#lines] = lines[#lines]:sub(1, end_col)

    return table.concat(lines, "\n")
  else
    -- Normal mode: get current line
    local line = vim.fn.getline(".")
    return line
  end
end

---Send text to tmux
M.send_to_tmux = function()
  -- Check if tmux is installed
  if not tmux.is_tmux_installed() then
    vim.notify("tmux is not installed", vim.log.levels.ERROR)
    return
  end

  -- Check if target is set
  if not state.target then
    vim.notify("No tmux target selected. Use :SendToTmuxSelectTarget first", vim.log.levels.ERROR)
    return
  end

  -- Get text to send
  local text = get_text_to_send()

  if not text or text == "" then
    vim.notify("No text to send", vim.log.levels.ERROR)
    return
  end

  -- Check if target still exists
  if not tmux.target_exists(state.target) then
    vim.notify("Target no longer exists: " .. state.target, vim.log.levels.ERROR)
    return
  end

  -- Send to tmux
  local success, err = tmux.send_to_tmux(state.target, text)

  if not success then
    vim.notify("Failed to send to tmux: " .. (err or "unknown error"), vim.log.levels.ERROR)
  else
    vim.notify("Text sent to tmux target: " .. state.target, vim.log.levels.INFO)
  end
end

---Get current target
---@return string|nil
M.get_target = function()
  return state.target
end

return M
