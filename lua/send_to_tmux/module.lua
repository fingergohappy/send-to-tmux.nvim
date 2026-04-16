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

---List tmux panes with metadata for target selection
---@return table[] targets
---@return string|nil error_msg
M.list_targets = function()
  local cmd = "tmux list-panes -a -F '#{window_index}\t#{pane_id}\t#{pane_current_command}\t#{pane_current_path}' 2>/dev/null"
  local handle = io.popen(cmd)
  if not handle then
    return {}, "Failed to list tmux panes"
  end

  local result = handle:read("*a")
  local ok = handle:close()
  if not ok then
    return {}, "Failed to list tmux panes"
  end

  local targets = {}
  for line in result:gmatch("[^\r\n]+") do
    local window_index, pane_id, process_name, path = line:match("([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)")
    if pane_id and pane_id ~= "" then
      table.insert(targets, {
        window_index = window_index ~= "" and window_index or "?",
        pane_id = pane_id,
        process_name = process_name ~= "" and process_name or "?",
        path = path ~= "" and path or "?",
      })
    end
  end

  return targets, nil
end

---Capture recent output from a tmux pane for preview
---@param target string
---@param opts? {include_escape_sequences?: boolean}
---@return string|nil preview
---@return string|nil error_msg
M.preview_target = function(target, opts)
  opts = opts or {}
  local flags = opts.include_escape_sequences and "-e -p" or "-p"
  local cmd = string.format("tmux capture-pane %s -S -200 -t '%s' 2>&1", flags, target)
  local handle = io.popen(cmd)
  if not handle then
    return nil, "Failed to capture tmux pane: " .. target
  end

  local result = handle:read("*a")
  local ok = handle:close()
  if not ok then
    return nil, "Failed to capture tmux pane: " .. target
  end

  return result, nil
end

---Get the current tmux pane id from the process environment
---@return string|nil
M.current_pane_id = function()
  local pane_id = os.getenv("TMUX_PANE")
  if not pane_id or pane_id == "" then
    return nil
  end
  if pane_id:sub(1, 1) ~= "%" then
    return "%" .. pane_id
  end
  return pane_id
end

---@param cmd string
---@return boolean
local function command_succeeded(cmd)
  local ok, _, status = os.execute(cmd)
  if ok == true then
    return true
  end
  if type(ok) == "number" then
    return ok == 0
  end
  return status == 0
end

---@param target string
---@param style string
---@return boolean success
---@return string|nil error_msg
local function set_pane_window_style(target, style)
  local commands = {
    string.format("tmux set-option -pt '%s' window-style '%s'", target, style),
    string.format("tmux set-option -pt '%s' window-active-style '%s'", target, style),
  }

  for _, cmd in ipairs(commands) do
    if not command_succeeded(cmd) then
      return false, "Failed to highlight tmux pane: " .. target
    end
  end

  return true, nil
end

---Temporarily highlight a tmux pane
---@param target string
---@param style string|nil
---@return boolean success
---@return string|nil error_msg
M.highlight_target = function(target, style)
  return set_pane_window_style(target, style or "bg=#223247")
end

---Clear the temporary highlight from a tmux pane
---@param target string
---@return boolean success
---@return string|nil error_msg
M.clear_target_highlight = function(target)
  local commands = {
    string.format("tmux set-option -u -pt '%s' window-style", target),
    string.format("tmux set-option -u -pt '%s' window-active-style", target),
  }

  for _, cmd in ipairs(commands) do
    if not command_succeeded(cmd) then
      return false, "Failed to clear tmux pane highlight: " .. target
    end
  end

  return true, nil
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

  return true, nil
end

---Send Enter to a tmux pane
---@param target string
---@return boolean success
---@return string|nil error_msg
M.send_enter = function(target)
  local enter_cmd = string.format("tmux send-keys -t '%s' Enter", target)
  if not command_succeeded(enter_cmd) then
    return false, "Failed to send Enter to pane: " .. target
  end
  return true, nil
end

---Focus the current tmux client on the target pane
---@param target string
---@return boolean success
---@return string|nil error_msg
M.focus_target = function(target)
  local handle = io.popen(string.format("tmux display-message -p -t '%s' '#{session_name}:#{window_index}' 2>&1", target))
  if not handle then
    return false, "Failed to resolve tmux session/window for pane: " .. target
  end

  local session_window = handle:read("*a"):gsub("%s+$", "")
  local display_ok = handle:close()
  if not display_ok or session_window == "" then
    return false, "Failed to resolve tmux session/window for pane: " .. target
  end

  local session_name = session_window:match("^(.-):")
  if not session_name or session_name == "" then
    return false, "Invalid tmux session/window for pane: " .. target
  end

  local commands = {
    string.format("tmux switch-client -t '%s'", session_name),
    string.format("tmux select-window -t '%s'", session_window),
    string.format("tmux select-pane -t '%s'", target),
  }

  for _, cmd in ipairs(commands) do
    if not command_succeeded(cmd) then
      return false, "Failed to focus tmux pane: " .. target
    end
  end

  return true, nil
end

return M
