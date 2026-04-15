---@class TmuxModule
local M = {}

---Check if tmux is installed
---@return boolean
M.is_tmux_installed = function()
  local handle = io.popen("which tmux 2>/dev/null")
  if handle then
    local result = handle:read("*a")
    handle:close()
    return result ~= ""
  end
  return false
end

---Check if a tmux pane ID exists
---@param target string The tmux pane ID
---@return boolean
M.target_exists = function(target)
  local cmd = "tmux list-panes -a -F '#{pane_id}' 2>/dev/null"
  local handle = io.popen(cmd)
  if handle then
    local result = handle:read("*a")
    handle:close()

    -- Check if target exists in the list
    for line in result:gmatch("[^\r\n]+") do
      if line == target then
        return true
      end
    end
  end
  return false
end

---Send text to a tmux pane
---@param target string The tmux pane ID (e.g. "%7")
---@param text string The text to send
---@param opts table|nil
---@return boolean success
---@return string|nil error_msg
M.send_to_tmux = function(target, text, opts)
  if not M.is_tmux_installed() then
    return false, "tmux is not installed"
  end

  if not M.target_exists(target) then
    return false, "Pane ID does not exist: " .. target
  end

  opts = opts or {}
  local use_bracketed_paste = opts.bracketed_paste ~= false
  local send_enter = opts.send_enter == true
  local load_handle = io.popen("tmux load-buffer -b send-to-tmux - 2>&1", "w")
  if not load_handle then
    return false, "Failed to load tmux buffer"
  end

  load_handle:write(text)
  local load_ok, load_reason = load_handle:close()
  if not load_ok then
    return false, "Failed to load tmux buffer: " .. tostring(load_reason)
  end

  local paste_flags = use_bracketed_paste and "-p -r" or "-r"
  local paste_cmd = string.format("tmux paste-buffer %s -t '%s' -b send-to-tmux -d", paste_flags, target)
  local paste_handle = io.popen(paste_cmd .. " 2>&1")
  if not paste_handle then
    return false, "Failed to execute tmux paste-buffer"
  end

  local paste_result = paste_handle:read("*a")
  local paste_ok = paste_handle:close()
  if not paste_ok then
    return false, "Failed to paste tmux buffer: " .. paste_result
  end

  if send_enter then
    -- Send Enter key as the final submit action after pasting.
    local enter_cmd = string.format("tmux send-keys -t '%s' Enter", target)
    os.execute(enter_cmd)
  end

  return true, nil
end

return M
