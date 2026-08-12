describe("send_to_tmux.module", function()
  local original_popen
  local original_execute
  local original_getenv

  before_each(function()
    original_popen = io.popen
    original_execute = os.execute
    original_getenv = os.getenv
    package.loaded["send_to_tmux.module"] = nil
  end)

  after_each(function()
    io.popen = original_popen
    os.execute = original_execute
    os.getenv = original_getenv
    package.loaded["send_to_tmux.module"] = nil
  end)

  it("looks up tmux pane ids directly", function()
    local commands = {}

    io.popen = function(cmd)
      table.insert(commands, cmd)
      return {
        read = function()
          return "%7\n%8\n"
        end,
        close = function()
          return true
        end,
      }
    end

    local tmux = require("send_to_tmux.module")

    assert.is_true(tmux.target_exists("%7"))
    assert.are.equal("tmux list-panes -a -F '#{pane_id}' 2>/dev/null", commands[1])
  end)

  it("lists tmux panes with window metadata", function()
    local commands = {}

    io.popen = function(cmd)
      table.insert(commands, cmd)
      if
        cmd
        == "tmux list-panes -a -F '#{session_name}\t#{window_id}\t#{window_index}\t#{window_name}\t#{pane_id}\t#{pane_current_command}\t#{pane_current_path}' 2>/dev/null"
      then
        return {
          read = function()
            return "work\t@2\t2\teditor\t%7\tnvim\t/tmp/project\n\t\t\t\t%8\t\t\n"
          end,
          close = function()
            return true
          end,
        }
      end

      error("unexpected io.popen call: " .. cmd)
    end

    local tmux = require("send_to_tmux.module")
    local targets, err = tmux.list_targets()

    assert.is_nil(err)
    assert.are.same({
      {
        session_name = "work",
        window_id = "@2",
        window_index = "2",
        window_name = "editor",
        pane_id = "%7",
        process_name = "nvim",
        path = "/tmp/project",
      },
      {
        session_name = "?",
        window_id = "?",
        window_index = "?",
        window_name = "?",
        pane_id = "%8",
        process_name = "?",
        path = "?",
      },
    }, targets)
    assert.are.same({
      "tmux list-panes -a -F '#{session_name}\t#{window_id}\t#{window_index}\t#{window_name}\t#{pane_id}\t#{pane_current_command}\t#{pane_current_path}' 2>/dev/null",
    }, commands)
  end)

  it("uses tmux buffers for single-line sends without pressing Enter by default", function()
    local popen_calls = {}
    local writes = {}
    local executed = {}

    io.popen = function(cmd, mode)
      table.insert(popen_calls, { cmd = cmd, mode = mode })

      if cmd == "which tmux 2>/dev/null" then
        return {
          read = function()
            return "/opt/homebrew/bin/tmux\n"
          end,
          close = function()
            return true
          end,
        }
      end

      if cmd == "tmux list-panes -a -F '#{pane_id}' 2>/dev/null" then
        return {
          read = function()
            return "%7\n"
          end,
          close = function()
            return true
          end,
        }
      end

      if cmd == "tmux load-buffer -b send-to-tmux - 2>&1" then
        return {
          write = function(_, payload)
            table.insert(writes, payload)
          end,
          close = function()
            return true
          end,
        }
      end

      if cmd == "tmux paste-buffer -p -r -t '%7' -b send-to-tmux -d 2>&1" then
        return {
          read = function()
            return ""
          end,
          close = function()
            return true
          end,
        }
      end

      error("unexpected io.popen call: " .. cmd)
    end

    os.execute = function(cmd)
      table.insert(executed, cmd)
      return true
    end

    local tmux = require("send_to_tmux.module")
    local success, err = tmux.send_to_tmux("%7", "echo hi", { bracketed_paste = true })

    assert.is_true(success)
    assert.is_nil(err)
    assert.are.same({ "echo hi" }, writes)
    assert.are.same({
      { cmd = "which tmux 2>/dev/null", mode = nil },
      { cmd = "tmux list-panes -a -F '#{pane_id}' 2>/dev/null", mode = nil },
      { cmd = "tmux load-buffer -b send-to-tmux - 2>&1", mode = "w" },
      { cmd = "tmux paste-buffer -p -r -t '%7' -b send-to-tmux -d 2>&1", mode = nil },
    }, popen_calls)
    assert.are.same({}, executed)
  end)

  it("sends Enter to a tmux pane", function()
    local executed = {}

    io.popen = function(cmd)
      error("unexpected io.popen call: " .. cmd)
    end

    os.execute = function(cmd)
      table.insert(executed, cmd)
      return true
    end

    local tmux = require("send_to_tmux.module")
    local success, err = tmux.send_enter("%7")

    assert.is_true(success)
    assert.is_nil(err)
    assert.are.same({
      "tmux send-keys -t '%7' Enter",
    }, executed)
  end)

  it("focuses the tmux client on the target pane", function()
    local popen_calls = {}
    local executed = {}

    io.popen = function(cmd)
      table.insert(popen_calls, cmd)
      if cmd == "tmux display-message -p -t '%7' '#{session_name}:#{window_index}' 2>&1" then
        return {
          read = function()
            return "work:3\n"
          end,
          close = function()
            return true
          end,
        }
      end

      error("unexpected io.popen call: " .. cmd)
    end

    os.execute = function(cmd)
      table.insert(executed, cmd)
      return true
    end

    local tmux = require("send_to_tmux.module")
    local success, err = tmux.focus_target("%7")

    assert.is_true(success)
    assert.is_nil(err)
    assert.are.same({
      "tmux display-message -p -t '%7' '#{session_name}:#{window_index}' 2>&1",
    }, popen_calls)
    assert.are.same({
      "tmux switch-client -t 'work'",
      "tmux select-window -t 'work:3'",
      "tmux select-pane -t '%7'",
    }, executed)
  end)

  it("captures recent pane output for preview", function()
    local popen_calls = {}

    io.popen = function(cmd)
      table.insert(popen_calls, cmd)
      if cmd == "tmux capture-pane -p -S -200 -t '%7' 2>&1" then
        return {
          read = function()
            return "line 1\nline 2\n"
          end,
          close = function()
            return true
          end,
        }
      end

      error("unexpected io.popen call: " .. cmd)
    end

    local tmux = require("send_to_tmux.module")
    local preview, err = tmux.preview_target("%7")

    assert.are.equal("line 1\nline 2\n", preview)
    assert.is_nil(err)
    assert.are.same({
      "tmux capture-pane -p -S -200 -t '%7' 2>&1",
    }, popen_calls)
  end)

  it("captures recent pane output with escape sequences when requested", function()
    local popen_calls = {}

    io.popen = function(cmd)
      table.insert(popen_calls, cmd)
      if cmd == "tmux capture-pane -e -p -S -200 -t '%7' 2>&1" then
        return {
          read = function()
            return "\27[31mred\27[0m\n"
          end,
          close = function()
            return true
          end,
        }
      end

      error("unexpected io.popen call: " .. cmd)
    end

    local tmux = require("send_to_tmux.module")
    local preview, err = tmux.preview_target("%7", { include_escape_sequences = true })

    assert.are.equal("\27[31mred\27[0m\n", preview)
    assert.is_nil(err)
    assert.are.same({
      "tmux capture-pane -e -p -S -200 -t '%7' 2>&1",
    }, popen_calls)
  end)

  it("reads the current tmux pane id from the environment", function()
    os.getenv = function(name)
      if name == "TMUX_PANE" then
        return "%18"
      end
      return nil
    end

    local tmux = require("send_to_tmux.module")

    assert.are.equal("%18", tmux.current_pane_id())
  end)

  it("temporarily highlights and clears only the target pane body", function()
    local executed = {}

    os.execute = function(cmd)
      table.insert(executed, cmd)
      return true
    end

    local tmux = require("send_to_tmux.module")
    local highlight_ok, highlight_err = tmux.highlight_target("%7")
    local clear_ok, clear_err = tmux.clear_target_highlight("%7")

    assert.is_true(highlight_ok)
    assert.is_nil(highlight_err)
    assert.is_true(clear_ok)
    assert.is_nil(clear_err)
    assert.are.same({
      "tmux set-option -pt '%7' window-style 'bg=#223247'",
      "tmux set-option -pt '%7' window-active-style 'bg=#223247'",
      "tmux set-option -u -pt '%7' window-style",
      "tmux set-option -u -pt '%7' window-active-style",
    }, executed)
  end)

  it("omits bracketed paste when disabled", function()
    local paste_command

    io.popen = function(cmd, mode)
      if cmd == "which tmux 2>/dev/null" then
        return {
          read = function()
            return "/opt/homebrew/bin/tmux\n"
          end,
          close = function()
            return true
          end,
        }
      end

      if cmd == "tmux list-panes -a -F '#{pane_id}' 2>/dev/null" then
        return {
          read = function()
            return "%7\n"
          end,
          close = function()
            return true
          end,
        }
      end

      if cmd == "tmux load-buffer -b send-to-tmux - 2>&1" then
        return {
          write = function() end,
          close = function()
            return true
          end,
        }
      end

      if cmd:match("^tmux paste%-buffer") then
        paste_command = cmd
        return {
          read = function()
            return ""
          end,
          close = function()
            return true
          end,
        }
      end

      error("unexpected io.popen call: " .. cmd)
    end

    os.execute = function()
      return true
    end

    local tmux = require("send_to_tmux.module")
    local success, err = tmux.send_to_tmux("%7", "echo hi", { bracketed_paste = false })

    assert.is_true(success)
    assert.is_nil(err)
    assert.are.equal("tmux paste-buffer -r -t '%7' -b send-to-tmux -d 2>&1", paste_command)
  end)
end)

describe("send_to_tmux", function()
  local original_notify
  local original_input
  local original_mode
  local original_getline
  local original_snacks
  local original_buf
  local temp_buffers

  local function find_buf_keymap(buf, mode, lhs)
    local expected_lhs = lhs:lower()
    for _, keymap in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
      if keymap.lhs:lower() == expected_lhs then
        return keymap
      end
    end
    return nil
  end

  before_each(function()
    original_notify = vim.notify
    original_input = vim.ui.input
    original_mode = vim.fn.mode
    original_getline = vim.fn.getline
    original_snacks = package.loaded["snacks"]
    original_buf = vim.api.nvim_get_current_buf()
    temp_buffers = {}
    package.loaded["send_to_tmux"] = nil
    package.loaded["send_to_tmux.module"] = {
      is_tmux_installed = function()
        return true
      end,
      target_exists = function(target)
        return target == "%7" or target == "%8" or target == "%9" or target == "%10"
      end,
      send_to_tmux = function()
        return true
      end,
    }
  end)

  after_each(function()
    vim.notify = original_notify
    vim.ui.input = original_input
    vim.fn.mode = original_mode
    vim.fn.getline = original_getline
    package.loaded["snacks"] = original_snacks
    for _, buf in ipairs(temp_buffers) do
      if vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
    if vim.api.nvim_buf_is_valid(original_buf) then
      vim.api.nvim_set_current_buf(original_buf)
    end
    package.loaded["send_to_tmux"] = nil
    package.loaded["send_to_tmux.module"] = nil
  end)

  it("stores the selected pane id", function()
    local notifications = {}

    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end

    local send_to_tmux = require("send_to_tmux")

    send_to_tmux.select_target("%7")

    assert.are.equal("%7", send_to_tmux.get_target())
    assert.are.same({
      { msg = "Tmux pane ID set to: %7", level = vim.log.levels.INFO },
    }, notifications)
  end)

  it("normalizes pane ids without a percent prefix", function()
    local notifications = {}

    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end

    local send_to_tmux = require("send_to_tmux")

    send_to_tmux.select_target("7")

    assert.are.equal("%7", send_to_tmux.get_target())
    assert.are.same({
      { msg = "Tmux pane ID set to: %7", level = vim.log.levels.INFO },
    }, notifications)
  end)

  it("opens a window-grouped Snacks picker to choose a tmux pane when no target is provided", function()
    local picker_calls = {}
    local notifications = {}
    local tree_items = {}
    local formatted = {}
    local close_calls = 0
    local send_to_tmux = require("send_to_tmux")

    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end

    package.loaded["send_to_tmux.module"].list_targets = function()
      return {
        {
          session_name = "work",
          window_id = "@1",
          window_index = "1",
          window_name = "editor",
          pane_id = "%7",
          process_name = "nvim",
          path = "/tmp/project",
        },
        {
          session_name = "work",
          window_id = "@2",
          window_index = "2",
          window_name = "shell",
          pane_id = "%8",
          process_name = "zsh",
          path = "/tmp/shell-a",
        },
        {
          session_name = "work",
          window_id = "@2",
          window_index = "2",
          window_name = "shell",
          pane_id = "%9",
          process_name = "python",
          path = "/tmp/shell-b",
        },
        {
          session_name = "dev",
          window_id = "@1",
          window_index = "1",
          window_name = "api",
          pane_id = "%10",
          process_name = "node",
          path = "/tmp/api",
        },
      }
    end
    package.loaded["send_to_tmux.module"].current_pane_id = function()
      return "%7"
    end
    package.loaded["send_to_tmux.module"].preview_target = function(target)
      return string.format("\27[31mheader %s\27[0m\nbody %s\n", target, target)
    end

    package.loaded["snacks"] = {
      picker = {
        format = {
          tree = function(item)
            table.insert(tree_items, item.pane_id)
            return { { "TREE ", "Tree" } }
          end,
        },
        pick = function(_, opts)
          table.insert(picker_calls, opts)
          formatted.parent = opts.format(opts.items[1], {})
          formatted.child = opts.format(opts.items[2], {})
          opts.confirm({
            close = function()
              close_calls = close_calls + 1
            end,
          }, opts.items[2])
        end,
      },
    }

    send_to_tmux.select_target()

    assert.are.equal(1, #picker_calls)
    assert.is_function(picker_calls[1].preview)
    assert.is_function(picker_calls[1].format)
    assert.are.same({
      keep_parents = true,
      sort = false,
    }, picker_calls[1].matcher)
    assert.are.same({
      preset = "default",
    }, picker_calls[1].layout)
    assert.are.same({
      preview = {
        wo = {
          number = false,
          relativenumber = false,
          statuscolumn = "",
          wrap = false,
          linebreak = false,
        },
      },
    }, picker_calls[1].win)

    local items = picker_calls[1].items
    assert.are.equal(5, #items)
    assert.is_true(items[1].is_window)
    assert.is_nil(items[1].pane_id)
    assert.are.equal("work:2 shell", items[1].display_text)
    assert.are.equal("work:2 shell", items[1].text)
    assert.are.equal("%8", items[2].pane_id)
    assert.are.equal("%8  zsh  /tmp/shell-a", items[2].display_text)
    assert.is_true(items[2].text:find("work:2 shell", 1, true) ~= nil)
    assert.is_true(items[2].parent == items[1])
    assert.is_false(items[2].last)
    assert.are.equal("%9", items[3].pane_id)
    assert.is_true(items[3].parent == items[1])
    assert.is_true(items[3].last)
    assert.is_true(items[4].is_window)
    assert.are.equal("dev:1 api", items[4].display_text)
    assert.are.equal("%10", items[5].pane_id)
    assert.is_true(items[5].parent == items[4])
    assert.is_true(items[5].last)
    for _, item in ipairs(items) do
      assert.is_true(item.pane_id ~= "%7")
    end

    assert.are.same({
      { "work:2 shell" },
    }, formatted.parent)
    assert.are.same({
      { "TREE ", "Tree" },
      { "%8  zsh  /tmp/shell-a" },
    }, formatted.child)
    assert.are.same({ "%8" }, tree_items)
    assert.are.same({ 2, 0 }, items[2].pos)
    assert.are.equal("\27[31mheader %8\27[0m\nbody %8", items[2].preview_text)
    assert.are.equal("\27[31mheader %8\27[0m\nbody %8", items[2].preview_ansi_text)
    assert.are.equal(1, close_calls)
    assert.are.equal("%8", send_to_tmux.get_target())
    assert.are.same({
      { msg = "Tmux pane ID set to: %8", level = vim.log.levels.INFO },
    }, notifications)
  end)

  it("keeps the picker open when confirming a window parent item", function()
    local closed = false
    local notifications = {}
    local send_to_tmux = require("send_to_tmux")

    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end

    package.loaded["send_to_tmux.module"].list_targets = function()
      return {
        {
          session_name = "work",
          window_id = "@2",
          window_index = "2",
          window_name = "shell",
          pane_id = "%8",
          process_name = "zsh",
          path = "/tmp/shell",
        },
      }
    end

    package.loaded["snacks"] = {
      picker = {
        pick = function(_, opts)
          opts.confirm({
            close = function()
              closed = true
            end,
          }, opts.items[1])
        end,
      },
    }

    send_to_tmux.select_target()

    assert.is_nil(send_to_tmux.get_target())
    assert.is_false(closed)
    assert.are.same({}, notifications)
  end)

  it("highlights hovered pane items and ignores window parent items", function()
    local highlighted = {}
    local cleared = {}
    local picker_calls = {}
    local send_to_tmux = require("send_to_tmux")

    package.loaded["send_to_tmux.module"].list_targets = function()
      return {
        {
          session_name = "work",
          window_id = "@2",
          window_index = "2",
          window_name = "editor",
          pane_id = "%7",
          process_name = "nvim",
          path = "/tmp/project",
        },
        {
          session_name = "work",
          window_id = "@5",
          window_index = "5",
          window_name = "shell",
          pane_id = "%8",
          process_name = "python",
          path = "/tmp/other",
        },
      }
    end
    package.loaded["send_to_tmux.module"].preview_target = function(target)
      return string.format("pane %s\n", target)
    end
    package.loaded["send_to_tmux.module"].highlight_target = function(target)
      table.insert(highlighted, target)
      return true
    end
    package.loaded["send_to_tmux.module"].clear_target_highlight = function(target)
      table.insert(cleared, target)
      return true
    end

    package.loaded["snacks"] = {
      picker = {
        pick = function(_, opts)
          table.insert(picker_calls, opts)
          opts.on_change(nil, opts.items[1])
          opts.on_change(nil, opts.items[2])
          opts.on_change(nil, opts.items[3])
          opts.on_change(nil, opts.items[4])
          opts.on_change(nil, opts.items[4])
          opts.on_close(nil)
        end,
      },
    }

    send_to_tmux.select_target()

    assert.are.equal(1, #picker_calls)
    assert.are.same({ "%7", "%8" }, highlighted)
    assert.are.same({ "%7", "%8" }, cleared)
  end)

  it("sends without Enter for SendToTmux", function()
    local send_calls = {}
    local send_to_tmux = require("send_to_tmux")

    package.loaded["send_to_tmux.module"].send_to_tmux = function(target, text, opts)
      table.insert(send_calls, {
        target = target,
        text = text,
        opts = opts,
      })
      return true
    end

    vim.fn.mode = function()
      return "n"
    end
    vim.fn.getline = function()
      return "echo hi"
    end

    send_to_tmux.select_target("%7")
    send_to_tmux.send_to_tmux()

    assert.are.same({
      {
        target = "%7",
        text = "echo hi",
        opts = {
          bracketed_paste = true,
        },
      },
    }, send_calls)
  end)

  it("sends Enter after successful sends when auto-enter is enabled", function()
    local send_calls = {}
    local enter_calls = {}
    local send_to_tmux = require("send_to_tmux")

    package.loaded["send_to_tmux.module"].send_to_tmux = function(target, text, opts)
      table.insert(send_calls, {
        target = target,
        text = text,
        opts = opts,
      })
      return true
    end
    package.loaded["send_to_tmux.module"].send_enter = function(target)
      table.insert(enter_calls, target)
      return true
    end

    vim.fn.mode = function()
      return "n"
    end
    vim.fn.getline = function()
      return "echo hi"
    end

    send_to_tmux.select_target("%7")
    send_to_tmux.set_auto_enter("on")
    send_to_tmux.send_to_tmux()

    assert.are.same({
      {
        target = "%7",
        text = "echo hi",
        opts = {
          bracketed_paste = true,
        },
      },
    }, send_calls)
    assert.are.same({ "%7" }, enter_calls)
  end)

  it("opens a Snacks edit window seeded with the selected text", function()
    local snacks_calls = {}
    local send_to_tmux = require("send_to_tmux")

    package.loaded["snacks"] = {
      win = function(opts)
        table.insert(snacks_calls, opts)
        table.insert(temp_buffers, opts.buf)
        return {
          buf = opts.buf,
          close = function() end,
        }
      end,
    }

    vim.fn.mode = function()
      return "n"
    end
    vim.fn.getline = function()
      return "echo hi"
    end

    send_to_tmux.select_target("%7")
    send_to_tmux.send_to_tmux_edit()

    assert.are.equal(1, #snacks_calls)
    assert.are.same({ "echo hi" }, vim.api.nvim_buf_get_lines(snacks_calls[1].buf, 0, -1, false))
    assert.are.equal("acwrite", vim.bo[snacks_calls[1].buf].buftype)
  end)

  it("maps the default edit send key in normal and insert modes", function()
    local snacks_calls = {}
    local send_to_tmux = require("send_to_tmux")

    package.loaded["snacks"] = {
      win = function(opts)
        table.insert(snacks_calls, opts)
        table.insert(temp_buffers, opts.buf)
        return {
          buf = opts.buf,
          close = function() end,
        }
      end,
    }

    vim.fn.mode = function()
      return "n"
    end
    vim.fn.getline = function()
      return "echo hi"
    end

    send_to_tmux.select_target("%7")
    send_to_tmux.send_to_tmux_edit()

    local edit_buf = snacks_calls[1].buf
    local normal_map = find_buf_keymap(edit_buf, "n", "<C-s>")
    local insert_map = find_buf_keymap(edit_buf, "i", "<C-s>")

    assert.is_not_nil(normal_map)
    assert.is_not_nil(insert_map)
    assert.is_function(normal_map.callback)
    assert.is_function(insert_map.callback)
    assert.are.equal("Send edited text to tmux", normal_map.desc)
    assert.are.equal("Send edited text to tmux", insert_map.desc)
    assert.are.equal(1, normal_map.silent)
    assert.are.equal(1, insert_map.silent)
  end)

  it("sends edited text with the default edit send key and closes the window", function()
    local send_calls = {}
    local closed = false
    local send_to_tmux = require("send_to_tmux")

    package.loaded["send_to_tmux.module"].send_to_tmux = function(target, text, opts)
      table.insert(send_calls, {
        target = target,
        text = text,
        opts = opts,
      })
      return true
    end

    package.loaded["snacks"] = {
      win = function(opts)
        table.insert(temp_buffers, opts.buf)
        vim.api.nvim_set_current_buf(opts.buf)
        return {
          buf = opts.buf,
          close = function()
            closed = true
          end,
        }
      end,
    }

    vim.fn.mode = function()
      return "n"
    end
    vim.fn.getline = function()
      return "echo hi"
    end

    send_to_tmux.select_target("%7")
    send_to_tmux.send_to_tmux_edit()

    local edit_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(edit_buf, 0, -1, false, { "python", "print('hi')" })
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-s>", true, false, true), "mx", false)

    assert.are.same({
      {
        target = "%7",
        text = "python\nprint('hi')",
        opts = {
          bracketed_paste = true,
        },
      },
    }, send_calls)
    assert.is_true(closed)
    assert.is_false(vim.api.nvim_buf_is_valid(edit_buf))
  end)

  it("uses a custom edit send key instead of the default key", function()
    local snacks_calls = {}
    local send_to_tmux = require("send_to_tmux")

    send_to_tmux.setup({
      edit_send_key = "<C-g>",
    })

    package.loaded["snacks"] = {
      win = function(opts)
        table.insert(snacks_calls, opts)
        table.insert(temp_buffers, opts.buf)
        return {
          buf = opts.buf,
          close = function() end,
        }
      end,
    }

    vim.fn.mode = function()
      return "n"
    end
    vim.fn.getline = function()
      return "echo hi"
    end

    send_to_tmux.select_target("%7")
    send_to_tmux.send_to_tmux_edit()

    local edit_buf = snacks_calls[1].buf
    assert.is_not_nil(find_buf_keymap(edit_buf, "n", "<C-g>"))
    assert.is_not_nil(find_buf_keymap(edit_buf, "i", "<C-g>"))
    assert.is_nil(find_buf_keymap(edit_buf, "n", "<C-s>"))
    assert.is_nil(find_buf_keymap(edit_buf, "i", "<C-s>"))
  end)

  it("sends edited text on save and closes the window", function()
    local send_calls = {}
    local closed = false
    local send_to_tmux = require("send_to_tmux")

    package.loaded["send_to_tmux.module"].send_to_tmux = function(target, text, opts)
      table.insert(send_calls, {
        target = target,
        text = text,
        opts = opts,
      })
      return true
    end

    package.loaded["snacks"] = {
      win = function(opts)
        table.insert(temp_buffers, opts.buf)
        vim.api.nvim_set_current_buf(opts.buf)
        return {
          buf = opts.buf,
          close = function()
            closed = true
          end,
        }
      end,
    }

    vim.fn.mode = function()
      return "n"
    end
    vim.fn.getline = function()
      return "echo hi"
    end

    send_to_tmux.select_target("%7")
    send_to_tmux.send_to_tmux_edit()

    local edit_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(edit_buf, 0, -1, false, { "python", "print('hi')" })
    vim.cmd("write")

    assert.are.same({
      {
        target = "%7",
        text = "python\nprint('hi')",
        opts = {
          bracketed_paste = true,
        },
      },
    }, send_calls)
    vim.wait(100, function()
      return closed
    end)
    assert.is_true(closed)
  end)

  it("keeps the host window open when the edit window is saved with wq", function()
    local send_to_tmux = require("send_to_tmux")
    local host_win = vim.api.nvim_get_current_win()
    local edit_win

    vim.cmd("vsplit")
    local safety_win = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(host_win)

    package.loaded["snacks"] = {
      win = function(opts)
        table.insert(temp_buffers, opts.buf)
        edit_win = vim.api.nvim_open_win(opts.buf, true, {
          relative = "editor",
          row = 1,
          col = 1,
          width = 40,
          height = 8,
          style = "minimal",
        })
        return {
          buf = opts.buf,
          close = function()
            if vim.api.nvim_win_is_valid(edit_win) then
              vim.api.nvim_win_close(edit_win, true)
            end
          end,
        }
      end,
    }

    vim.fn.mode = function()
      return "n"
    end
    vim.fn.getline = function()
      return "echo hi"
    end

    send_to_tmux.select_target("%7")
    send_to_tmux.send_to_tmux_edit()

    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "echo changed" })
    vim.cmd("wq")
    vim.wait(100)

    local host_survived = vim.api.nvim_win_is_valid(host_win)
    local edit_closed = not vim.api.nvim_win_is_valid(edit_win)

    if host_survived then
      vim.api.nvim_set_current_win(host_win)
      vim.api.nvim_win_close(safety_win, true)
    else
      vim.api.nvim_set_current_win(safety_win)
      vim.cmd("vsplit")
      vim.api.nvim_win_close(safety_win, true)
    end

    assert.is_true(edit_closed)
    assert.is_true(host_survived)
  end)

  it("disables edit send keymaps while keeping write-to-send", function()
    local send_calls = {}
    local closed = false
    local send_to_tmux = require("send_to_tmux")

    send_to_tmux.setup({
      edit_send_key = false,
    })

    package.loaded["send_to_tmux.module"].send_to_tmux = function(target, text, opts)
      table.insert(send_calls, {
        target = target,
        text = text,
        opts = opts,
      })
      return true
    end

    package.loaded["snacks"] = {
      win = function(opts)
        table.insert(temp_buffers, opts.buf)
        vim.api.nvim_set_current_buf(opts.buf)
        return {
          buf = opts.buf,
          close = function()
            closed = true
          end,
        }
      end,
    }

    vim.fn.mode = function()
      return "n"
    end
    vim.fn.getline = function()
      return "echo hi"
    end

    send_to_tmux.select_target("%7")
    send_to_tmux.send_to_tmux_edit()

    local edit_buf = vim.api.nvim_get_current_buf()
    assert.is_nil(find_buf_keymap(edit_buf, "n", "<C-s>"))
    assert.is_nil(find_buf_keymap(edit_buf, "i", "<C-s>"))

    vim.api.nvim_buf_set_lines(edit_buf, 0, -1, false, { "echo changed" })
    vim.cmd("write")

    assert.are.same({
      {
        target = "%7",
        text = "echo changed",
        opts = {
          bracketed_paste = true,
        },
      },
    }, send_calls)
    vim.wait(100, function()
      return closed
    end)
    assert.is_true(closed)
  end)

  it("focuses the target pane after successful sends when auto-focus is enabled", function()
    local focus_calls = {}
    local send_to_tmux = require("send_to_tmux")

    package.loaded["send_to_tmux.module"].send_to_tmux = function()
      return true
    end
    package.loaded["send_to_tmux.module"].focus_target = function(target)
      table.insert(focus_calls, target)
      return true
    end

    vim.fn.mode = function()
      return "n"
    end
    vim.fn.getline = function()
      return "echo hi"
    end

    send_to_tmux.select_target("%7")
    send_to_tmux.set_auto_focus("on")
    send_to_tmux.send_to_tmux()

    assert.are.same({ "%7" }, focus_calls)
  end)

  it("toggles auto-enter and auto-focus settings", function()
    local notifications = {}
    local send_to_tmux = require("send_to_tmux")

    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end

    send_to_tmux.set_auto_enter("on")
    send_to_tmux.set_auto_focus("toggle")

    assert.are.same({
      { msg = "Auto enter on send enabled", level = vim.log.levels.INFO },
      { msg = "Auto focus on send enabled", level = vim.log.levels.INFO },
    }, notifications)
  end)

  it("keeps the edit window open when sending edited text fails", function()
    local send_calls = {}
    local closed = false
    local notifications = {}
    local send_to_tmux = require("send_to_tmux")

    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end

    package.loaded["send_to_tmux.module"].send_to_tmux = function(target, text, opts)
      table.insert(send_calls, {
        target = target,
        text = text,
        opts = opts,
      })
      return false, "boom"
    end

    package.loaded["snacks"] = {
      win = function(opts)
        table.insert(temp_buffers, opts.buf)
        vim.api.nvim_set_current_buf(opts.buf)
        return {
          buf = opts.buf,
          close = function()
            closed = true
          end,
        }
      end,
    }

    vim.fn.mode = function()
      return "n"
    end
    vim.fn.getline = function()
      return "echo hi"
    end

    send_to_tmux.select_target("%7")
    send_to_tmux.send_to_tmux_edit()

    local edit_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(edit_buf, 0, -1, false, { "echo changed" })
    vim.cmd("write")

    assert.are.same({
      {
        target = "%7",
        text = "echo changed",
        opts = {
          bracketed_paste = true,
        },
      },
    }, send_calls)
    assert.is_false(closed)
    assert.is_true(vim.api.nvim_buf_is_valid(edit_buf))
    assert.are.same({
      { msg = "Tmux pane ID set to: %7", level = vim.log.levels.INFO },
      { msg = "Failed to send to tmux: boom", level = vim.log.levels.ERROR },
    }, notifications)
  end)

  it("notifies when snacks.nvim is unavailable for edit commands", function()
    local notifications = {}
    local send_to_tmux = require("send_to_tmux")

    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end

    vim.fn.mode = function()
      return "n"
    end
    vim.fn.getline = function()
      return "echo hi"
    end

    send_to_tmux.select_target("%7")
    send_to_tmux.send_to_tmux_edit()

    assert.are.same({
      { msg = "Tmux pane ID set to: %7", level = vim.log.levels.INFO },
      { msg = "snacks.nvim is required for SendToTmuxEdit", level = vim.log.levels.ERROR },
    }, notifications)
  end)

  it("opens an edit window seeded with the current file line reference", function()
    local snacks_calls = {}
    local range_buf = vim.api.nvim_create_buf(false, true)
    local send_to_tmux = require("send_to_tmux")

    table.insert(temp_buffers, range_buf)
    vim.api.nvim_buf_set_name(range_buf, vim.fn.getcwd() .. "/lua/send_to_tmux.lua")
    vim.api.nvim_buf_set_lines(range_buf, 0, -1, false, {
      "line 1",
      "line 2",
    })
    vim.api.nvim_set_current_buf(range_buf)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    package.loaded["snacks"] = {
      win = function(opts)
        table.insert(snacks_calls, opts)
        table.insert(temp_buffers, opts.buf)
        return {
          buf = opts.buf,
          close = function() end,
        }
      end,
    }

    send_to_tmux.select_target("%7")
    send_to_tmux.send_to_tmux_edit_ref_line()

    assert.are.equal(1, #snacks_calls)
    assert.are.same({ "lua/send_to_tmux.lua:2" }, vim.api.nvim_buf_get_lines(snacks_calls[1].buf, 0, -1, false))
  end)

  it("opens an edit window seeded with a current file line range", function()
    local snacks_calls = {}
    local range_buf = vim.api.nvim_create_buf(false, true)
    local send_to_tmux = require("send_to_tmux")

    table.insert(temp_buffers, range_buf)
    vim.api.nvim_buf_set_name(range_buf, vim.fn.getcwd() .. "/lua/send_to_tmux.lua")
    vim.api.nvim_buf_set_lines(range_buf, 0, -1, false, {
      "line 1",
      "line 2",
      "line 3",
      "line 4",
    })
    vim.api.nvim_set_current_buf(range_buf)

    package.loaded["snacks"] = {
      win = function(opts)
        table.insert(snacks_calls, opts)
        table.insert(temp_buffers, opts.buf)
        return {
          buf = opts.buf,
          close = function() end,
        }
      end,
    }

    send_to_tmux.select_target("%7")
    send_to_tmux.send_to_tmux_edit_ref_line({
      range = 2,
      line1 = 2,
      line2 = 4,
    })

    assert.are.equal(1, #snacks_calls)
    assert.are.same({ "lua/send_to_tmux.lua:2-4" }, vim.api.nvim_buf_get_lines(snacks_calls[1].buf, 0, -1, false))
  end)
end)
