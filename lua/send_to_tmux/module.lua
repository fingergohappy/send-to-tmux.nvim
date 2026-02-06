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
---@param opts table|nil
---@return boolean success
---@return string|nil error_msg
M.send_to_tmux = function(target, text, opts)
  if not M.is_tmux_installed() then
    return false, "tmux is not installed"
  end

  if not M.target_exists(target) then
    return false, "Target does not exist: " .. target
  end

  opts = opts or {}
  local use_bracketed_paste = opts.bracketed_paste ~= false
  local is_multiline = text:find("\n", 1, true) ~= nil

  if use_bracketed_paste and is_multiline then
    local esc = string.char(27)
    local payload = esc .. "[200~" .. text .. "\n" .. esc .. "[201~"

    local load_handle = io.popen("tmux load-buffer -b send-to-tmux - 2>&1", "w")
    if not load_handle then
      return false, "Failed to load tmux buffer"
    end

    load_handle:write(payload)
    local load_ok, load_reason = load_handle:close()
    if not load_ok then
      return false, "Failed to load tmux buffer: " .. tostring(load_reason)
    end

    local paste_cmd = string.format("tmux paste-buffer -t '%s' -b send-to-tmux -d", target)
    local paste_handle = io.popen(paste_cmd .. " 2>&1")
    if not paste_handle then
      return false, "Failed to execute tmux paste-buffer"
    end

    local paste_result = paste_handle:read("*a")
    local paste_ok = paste_handle:close()
    if not paste_ok then
      return false, "Failed to paste tmux buffer: " .. paste_result
    end

    -- Extra Enter to finish blocks (e.g. Python def/class)
    local enter_cmd = string.format("tmux send-keys -t '%s' Enter", target)
    os.execute(enter_cmd)

    return true, nil
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
