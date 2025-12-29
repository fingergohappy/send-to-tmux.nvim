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

---Check if a tmux target exists
---@param target string The tmux target
---@return boolean
M.target_exists = function(target)
  -- Use tmux command to check if target exists
  local cmd = string.format("tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null")
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

---Send text to tmux target
---@param target string The tmux target in format "session:window.pane"
---@param text string The text to send
---@return boolean success
---@return string|nil error_msg
M.send_to_tmux = function(target, text)
  if not M.is_tmux_installed() then
    return false, "tmux is not installed"
  end

  if not M.target_exists(target) then
    return false, "Target does not exist: " .. target
  end

  -- Escape single quotes in the text
  local escaped_text = text:gsub("'", "'\\''")

  -- Send the text to tmux
  local cmd = string.format("tmux send-keys -t '%s' -l '%s'", target, escaped_text)
  local handle = io.popen(cmd .. " 2>&1")

  if handle then
    local result = handle:read("*a")
    local success = handle:close()

    if not success then
      return false, "Failed to send to tmux: " .. result
    end

    -- Send Enter key
    local enter_cmd = string.format("tmux send-keys -t '%s' Enter", target)
    os.execute(enter_cmd)

    return true, nil
  end

  return false, "Failed to execute tmux command"
end

return M
