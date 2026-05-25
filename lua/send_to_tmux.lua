-- main module file
local tmux = require("send_to_tmux.module")

---@class Config
---@field default_target string|nil Default tmux pane ID
---@field bracketed_paste boolean Enable tmux bracketed paste when supported
---@field auto_enter_on_send boolean Send Enter after successful sends
---@field auto_focus_on_send boolean Focus the target pane after successful sends
---@field edit_send_key string|false Buffer-local send key for edit windows, false or empty disables
local config = {
  default_target = nil,
  bracketed_paste = true,
  auto_enter_on_send = false,
  auto_focus_on_send = false,
  edit_send_key = "<C-s>",
}

---@class SendToTmuxModule
local M = {}

---@type Config
M.config = config

-- Plugin state to store the selected tmux pane ID
local state = {
  target = nil,
}

---@param target string
---@return string
local function normalize_pane_id(target)
  if vim.startswith(target, "%") then
    return target
  end

  return "%" .. target
end

---@return table|nil
local function get_snacks()
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks then
    return snacks
  end
  return nil
end

---@param text string
---@return integer
local function count_preview_lines(text)
  local _, count = text:gsub("\n", "\n")
  return count + 1
end

---@param win integer
---@param line integer
local function scroll_preview_to_bottom(win, line)
  vim.schedule(function()
    if not vim.api.nvim_win_is_valid(win) then
      return
    end
    pcall(vim.api.nvim_win_set_cursor, win, { math.max(line, 1), 0 })
    vim.api.nvim_win_call(win, function()
      pcall(vim.cmd, "normal! zb")
    end)
  end)
end

---@param ctx table
local function render_target_preview(ctx)
  if not ctx.item or not ctx.item.pane_id then
    local buf = ctx.preview:scratch()
    ctx.preview:set_title(ctx.item and ctx.item.display_text or "tmux window")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
    return
  end

  local preview_text = ctx.item.preview_ansi_text or ctx.item.preview_text or "(pane is empty)"
  local buf = ctx.preview:scratch()
  local line_count = ctx.item.pos and ctx.item.pos[1] or count_preview_lines(preview_text)

  ctx.preview:set_title(ctx.item.pane_id or "tmux pane")
  ctx.preview:wo({
    number = false,
    relativenumber = false,
    statuscolumn = "",
    signcolumn = "no",
    wrap = false,
    linebreak = false,
    breakindent = false,
    cursorline = false,
  })

  local Job = require("snacks.util.job")
  Job.new(buf, { "cat" }, {
    output = preview_text:gsub("\n", "\r\n"),
    ansi = true,
  })

  scroll_preview_to_bottom(ctx.win, line_count)
end

---@param value string|nil
---@return string
local function target_field(value)
  return value and value ~= "" and value or "?"
end

---@param target table
---@return string
local function target_window_label(target)
  return string.format(
    "%s:%s %s",
    target_field(target.session_name),
    target_field(target.window_index),
    target_field(target.window_name)
  )
end

---@param target table
---@return string
local function target_window_key(target)
  return target_field(target.session_name) .. "\t" .. target_field(target.window_id)
end

---@param target table
---@param window_item table
---@param window_label string
---@return table
local function build_target_picker_item(target, window_item, window_label)
  local display_text =
    string.format("%s  %s  %s", target.pane_id, target_field(target.process_name), target_field(target.path))
  local item = {
    session_name = target.session_name,
    window_id = target.window_id,
    window_index = target.window_index,
    window_name = target.window_name,
    window_label = window_label,
    pane_id = target.pane_id,
    process_name = target.process_name,
    path = target.path,
    parent = window_item,
    text = string.format("%s  %s", window_label, display_text),
    display_text = display_text,
  }

  if tmux.preview_target then
    local preview_text, preview_err = tmux.preview_target(target.pane_id, {
      include_escape_sequences = true,
    })
    if preview_text then
      preview_text = preview_text:gsub("%s+$", "")
    end

    local text = (preview_text and preview_text ~= "") and preview_text or (preview_err or "(pane is empty)")
    item.preview_text = text
    item.preview_ansi_text = text
    item.pos = { count_preview_lines(text), 0 }
  end

  return item
end

---@param targets table[]
---@return table[]
local function build_target_picker_items(targets)
  local items = {}
  local windows_by_key = {}

  for _, target in ipairs(targets) do
    local window_key = target_window_key(target)
    local window_item = windows_by_key[window_key]
    if not window_item then
      local window_label = target_window_label(target)
      window_item = {
        is_window = true,
        session_name = target_field(target.session_name),
        window_id = target_field(target.window_id),
        window_index = target_field(target.window_index),
        window_name = target_field(target.window_name),
        window_label = window_label,
        text = window_label,
        display_text = window_label,
      }
      windows_by_key[window_key] = window_item
      table.insert(items, window_item)
    end

    local pane_item = build_target_picker_item(target, window_item, window_item.window_label)
    if window_item.last_child then
      window_item.last_child.last = false
    end
    pane_item.last = true
    window_item.last_child = pane_item
    table.insert(items, pane_item)
  end

  for _, item in ipairs(items) do
    if item.is_window then
      item.last_child = nil
    end
  end

  return items
end

---@param snacks table
---@return fun(item: table, picker: table): table
local function target_picker_format(snacks)
  return function(item, picker)
    local ret = {}
    if item.parent and snacks.picker and snacks.picker.format and snacks.picker.format.tree then
      vim.list_extend(ret, snacks.picker.format.tree(item, picker))
    end
    ret[#ret + 1] = { item.display_text or item.text or "" }
    return ret
  end
end

---@return boolean opened
local function open_target_picker()
  local snacks = get_snacks()
  if not snacks or not snacks.picker or not snacks.picker.pick or not tmux.list_targets then
    return false
  end

  local targets, err = tmux.list_targets()
  if err then
    vim.notify(err, vim.log.levels.ERROR)
    return true
  end

  if not targets or #targets == 0 then
    vim.notify("No tmux panes found", vim.log.levels.WARN)
    return true
  end

  local current_pane_id = tmux.current_pane_id and tmux.current_pane_id() or nil
  local filtered_targets = {}
  for _, target in ipairs(targets) do
    if target.pane_id ~= current_pane_id then
      table.insert(filtered_targets, target)
    end
  end

  if #filtered_targets == 0 then
    vim.notify("No tmux panes found outside the current pane", vim.log.levels.WARN)
    return true
  end

  local items = build_target_picker_items(filtered_targets)

  local highlighted_pane_id

  local function clear_highlight()
    if not highlighted_pane_id or not tmux.clear_target_highlight then
      highlighted_pane_id = nil
      return
    end

    tmux.clear_target_highlight(highlighted_pane_id)
    highlighted_pane_id = nil
  end

  local function highlight_item(item)
    if not item or not item.pane_id or not tmux.highlight_target then
      clear_highlight()
      return
    end

    if highlighted_pane_id == item.pane_id then
      return
    end

    clear_highlight()

    local ok = tmux.highlight_target(item.pane_id)
    if ok then
      highlighted_pane_id = item.pane_id
    end
  end

  snacks.picker.pick(nil, {
    title = "Select tmux pane",
    items = items,
    matcher = {
      keep_parents = true,
      sort = false,
    },
    format = target_picker_format(snacks),
    preview = render_target_preview,
    layout = {
      preset = "default",
    },
    win = {
      preview = {
        wo = {
          number = false,
          relativenumber = false,
          statuscolumn = "",
          wrap = false,
          linebreak = false,
        },
      },
    },
    on_change = function(_, item)
      highlight_item(item)
    end,
    on_close = function()
      clear_highlight()
    end,
    confirm = function(picker, item)
      if not item or not item.pane_id then
        return
      end
      if picker and picker.close then
        picker:close()
      end
      M.select_target(item.pane_id)
    end,
  })

  return true
end

---Setup function for the plugin
---@param args Config?
M.setup = function(args)
  M.config = vim.tbl_deep_extend("force", M.config, args or {})

  -- Set default_target if provided (tmux will validate)
  if M.config.default_target then
    state.target = normalize_pane_id(M.config.default_target)
  end
end

---Select tmux pane ID
---@param target string|nil The tmux pane ID (e.g. "7" or "%7")
M.select_target = function(target)
  -- Check if tmux is installed
  if not tmux.is_tmux_installed() then
    vim.notify("tmux is not installed", vim.log.levels.ERROR)
    return
  end

  -- If no target provided, prompt user for input
  if not target or target == "" then
    if open_target_picker() then
      return
    end

    vim.ui.input({
      prompt = "Enter tmux pane ID (e.g. 7): ",
    }, function(input)
      if input and input ~= "" then
        M.select_target(input)
      end
    end)
    return
  end

  target = normalize_pane_id(target)

  -- Check if target exists (tmux will validate format)
  if not tmux.target_exists(target) then
    vim.notify("Pane ID does not exist: " .. target, vim.log.levels.ERROR)
    return
  end

  -- Save target to state
  state.target = target
  vim.notify("Tmux pane ID set to: " .. target, vim.log.levels.INFO)
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

---@return boolean success
local function validate_send_target()
  if not tmux.is_tmux_installed() then
    vim.notify("tmux is not installed", vim.log.levels.ERROR)
    return false
  end

  if not state.target then
    vim.notify("No tmux pane ID selected. Use :SendToTmuxSelectTarget first", vim.log.levels.ERROR)
    return false
  end

  if not tmux.target_exists(state.target) then
    vim.notify("Pane ID no longer exists: " .. state.target, vim.log.levels.ERROR)
    return false
  end

  return true
end

---@param text string|nil
---@return boolean success
local function send_payload(text)
  if not text or text == "" then
    vim.notify("No text to send", vim.log.levels.ERROR)
    return false
  end

  if not validate_send_target() then
    return false
  end

  local success, err = tmux.send_to_tmux(state.target, text, {
    bracketed_paste = M.config.bracketed_paste,
  })

  if not success then
    vim.notify("Failed to send to tmux: " .. (err or "unknown error"), vim.log.levels.ERROR)
    return false
  end

  if M.config.auto_enter_on_send and tmux.send_enter then
    local enter_ok, enter_err = tmux.send_enter(state.target)
    if not enter_ok then
      vim.notify("Text sent, but failed to send Enter: " .. (enter_err or "unknown error"), vim.log.levels.WARN)
    end
  end

  if M.config.auto_focus_on_send and tmux.focus_target then
    local focus_ok, focus_err = tmux.focus_target(state.target)
    if not focus_ok then
      vim.notify("Text sent, but failed to focus tmux pane: " .. (focus_err or "unknown error"), vim.log.levels.WARN)
    end
  end

  vim.notify("Text sent to tmux pane ID: " .. state.target, vim.log.levels.INFO)
  return true
end

---Send text to tmux
---@param opts table|nil
local function send_text(opts)
  local text = get_text_to_send(opts)
  send_payload(text)
end

---@param value string|nil
---@param current boolean
---@param label string
---@return boolean|nil
local function resolve_toggle(value, current, label)
  local action = value
  if action == nil or action == "" then
    action = "toggle"
  end

  if action == "on" then
    return true
  end
  if action == "off" then
    return false
  end
  if action == "toggle" then
    return not current
  end

  vim.notify("Invalid value for " .. label .. ": " .. tostring(value), vim.log.levels.ERROR)
  return nil
end

---@return string|nil
local function get_reference_path()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    vim.notify("Current buffer has no file path", vim.log.levels.WARN)
    return nil
  end

  local dir = vim.fn.fnamemodify(path, ":h")
  local git_root_result = vim.fn.systemlist({ "git", "-C", dir, "rev-parse", "--show-toplevel" })
  local git_root = git_root_result[1]
  if vim.v.shell_error == 0 and git_root and git_root ~= "" and path:sub(1, #git_root) == git_root then
    return path:sub(#git_root + 2)
  end

  return vim.fn.fnamemodify(path, ":.")
end

---@param opts table|nil
---@return integer start_line
---@return integer end_line
local function get_reference_lines(opts)
  if opts and opts.range and opts.range ~= 0 and opts.line1 and opts.line2 then
    return math.min(opts.line1, opts.line2), math.max(opts.line1, opts.line2)
  end

  if is_visual_mode(vim.fn.mode()) then
    local start_line = vim.fn.line("v")
    local end_line = vim.fn.line(".")
    return math.min(start_line, end_line), math.max(start_line, end_line)
  end

  local line = vim.fn.line(".")
  return line, line
end

---@param opts table|nil
---@return string|nil
local function get_reference_line(opts)
  local path = get_reference_path()
  if not path then
    return nil
  end

  local start_line, end_line = get_reference_lines(opts)
  if start_line == end_line then
    return path .. ":" .. start_line
  end

  return path .. ":" .. start_line .. "-" .. end_line
end

---@param text string
local function open_edit_window(text)
  local snacks = get_snacks()
  if not snacks or not snacks.win then
    vim.notify("snacks.nvim is required for SendToTmuxEdit", vim.log.levels.ERROR)
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  local lines = vim.split(text, "\n", { plain = true })
  local filetype = vim.bo[0].filetype

  vim.api.nvim_buf_set_name(buf, ("send-to-tmux://edit/%d"):format(buf))
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  vim.bo[buf].filetype = filetype
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modified = false

  local win

  local function send_and_close()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end

    local payload = join_lines(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    if not send_payload(payload) then
      return
    end

    if vim.api.nvim_buf_is_valid(buf) then
      vim.bo[buf].modified = false
    end
    if win and win.close then
      win:close()
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  win = snacks.win({
    buf = buf,
    enter = true,
    width = 0.7,
    height = 0.6,
    border = "rounded",
    title = "Send To Tmux Edit",
  })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = send_and_close,
  })

  local edit_send_key = M.config.edit_send_key
  if type(edit_send_key) == "string" and edit_send_key ~= "" then
    vim.keymap.set({ "n", "i" }, edit_send_key, function()
      if vim.fn.mode():sub(1, 1) == "i" then
        vim.cmd("stopinsert")
      end
      send_and_close()
    end, {
      buffer = buf,
      silent = true,
      desc = "Send edited text to tmux",
    })
  end
end

---Send text to tmux without pressing Enter
---@param opts table|nil
M.send_to_tmux = function(opts)
  send_text(opts)
end

---Open a temporary edit buffer before sending text to tmux without pressing Enter
---@param opts table|nil
M.send_to_tmux_edit = function(opts)
  local text = get_text_to_send(opts)
  if not validate_send_target() then
    return
  end
  if not text or text == "" then
    vim.notify("No text to send", vim.log.levels.ERROR)
    return
  end
  open_edit_window(text)
end

---Open a temporary edit buffer seeded with the current file:line reference
---@param opts table|nil
M.send_to_tmux_edit_ref_line = function(opts)
  if not validate_send_target() then
    return
  end

  local reference = get_reference_line(opts)
  if not reference then
    return
  end

  open_edit_window(reference)
end

---@param value string|nil
M.set_auto_enter = function(value)
  local next_value = resolve_toggle(value, M.config.auto_enter_on_send, "SendToTmuxAutoEnter")
  if next_value == nil then
    return
  end

  M.config.auto_enter_on_send = next_value
  vim.notify("Auto enter on send " .. (next_value and "enabled" or "disabled"), vim.log.levels.INFO)
end

---@param value string|nil
M.set_auto_focus = function(value)
  local next_value = resolve_toggle(value, M.config.auto_focus_on_send, "SendToTmuxAutoFocus")
  if next_value == nil then
    return
  end

  M.config.auto_focus_on_send = next_value
  vim.notify("Auto focus on send " .. (next_value and "enabled" or "disabled"), vim.log.levels.INFO)
end

---Get current target
---@return string|nil
M.get_target = function()
  return state.target
end

return M
