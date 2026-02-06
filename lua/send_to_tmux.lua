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

---@param mode string
---@return boolean
local function is_visual_mode(mode)
  return mode == "v" or mode == "V" or mode == "\22"
end

---@param lines string[]
---@return string|nil
local function join_lines(lines)
  if not lines or #lines == 0 then
    return nil
  end
  return table.concat(lines, "\n")
end

---@param yank_last_selection boolean
---@return string|nil
local function yank_visual_to_text(yank_last_selection)
  local view = vim.fn.winsaveview()
  local reg_before = vim.fn.getreginfo("z")

  local ok = pcall(function()
    if yank_last_selection then
      vim.cmd([[silent normal! gv"zy]])
    else
      vim.cmd([[silent normal! "zy]])
    end
  end)

  local reg_after = vim.fn.getreginfo("z")
  vim.fn.setreg("z", reg_before.regcontents or {}, reg_before.regtype or "v")
  vim.fn.winrestview(view)

  if not ok then
    return nil
  end

  return join_lines(reg_after.regcontents)
end

---@param opts table
---@return boolean
local function last_visual_marks_match_range(opts)
  if not opts or not opts.line1 or not opts.line2 then
    return false
  end

  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_line = start_pos[2]
  local end_line = end_pos[2]
  local min_line = math.min(start_line, end_line)
  local max_line = math.max(start_line, end_line)
  return min_line == opts.line1 and max_line == opts.line2
end

---@param opts table|nil
---@return string|nil text The selected text or current line
local function get_text_to_send(opts)
  local mode = vim.fn.mode()

  if is_visual_mode(mode) then
    return yank_visual_to_text(false)
  end

  -- When called as a ranged Ex command (e.g. :'<,'>SendToTmux) we're no longer
  -- in visual mode; reselect the last visual area and yank it.
  if opts and opts.range and opts.range ~= 0 then
    local lines = vim.api.nvim_buf_get_lines(0, opts.line1 - 1, opts.line2, false)

    if last_visual_marks_match_range(opts) then
      local text = yank_visual_to_text(true)
      if text and text ~= "" then
        return text
      end
    end

    return join_lines(lines)
  end

  return vim.fn.getline(".")
end

---Send text to tmux
---@param opts table|nil
M.send_to_tmux = function(opts)
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
  local text = get_text_to_send(opts)

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
