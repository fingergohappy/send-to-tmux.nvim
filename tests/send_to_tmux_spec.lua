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

  it("lists tmux panes with window index metadata", function()
    local commands = {}

    io.popen = function(cmd)
      table.insert(commands, cmd)
      if cmd == "tmux list-panes -a -F '#{window_index}\t#{pane_id}\t#{pane_current_command}\t#{pane_current_path}' 2>/dev/null" then
        return {
          read = function()
            return "2\t%7\tnvim\t/tmp/project\n5\t%8\tpython\t/tmp/other\n"
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
        window_index = "2",
        pane_id = "%7",
        process_name = "nvim",
        path = "/tmp/project",
      },
      {
        window_index = "5",
        pane_id = "%8",
        process_name = "python",
        path = "/tmp/other",
      },
    }, targets)
    assert.are.same({
      "tmux list-panes -a -F '#{window_index}\t#{pane_id}\t#{pane_current_command}\t#{pane_current_path}' 2>/dev/null",
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
        return target == "%7" or target == "%8"
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

  it("opens a Snacks picker to choose a tmux pane when no target is provided", function()
    local picker_calls = {}
    local notifications = {}
    local send_to_tmux = require("send_to_tmux")

    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end

    package.loaded["send_to_tmux.module"].list_targets = function()
      return {
        {
          window_index = "2",
          pane_id = "%7",
          process_name = "nvim",
          path = "/tmp/project",
        },
        {
          window_index = "5",
          pane_id = "%8",
          process_name = "python",
          path = "/tmp/other",
        },
      }
    end
    package.loaded["send_to_tmux.module"].current_pane_id = function()
      return "%7"
    end
    package.loaded["send_to_tmux.module"].preview_target = function(target)
      return "\27[31mheader %8\27[0m\nbody %8\n"
    end

    package.loaded["snacks"] = {
      picker = {
        pick = function(_, opts)
          table.insert(picker_calls, opts)
          opts.confirm({
            close = function() end,
          }, opts.items[1])
        end,
      },
    }

    send_to_tmux.select_target()

    assert.are.equal(1, #picker_calls)
    assert.is_function(picker_calls[1].preview)
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
    assert.are.same({
      {
        window_index = "5",
        pane_id = "%8",
        process_name = "python",
        path = "/tmp/other",
        text = "5  %8  python",
        pos = { 2, 0 },
        preview_text = "\27[31mheader %8\27[0m\nbody %8",
        preview_ansi_text = "\27[31mheader %8\27[0m\nbody %8",
      },
    }, picker_calls[1].items)
    assert.are.equal("%8", send_to_tmux.get_target())
    assert.are.same({
      { msg = "Tmux pane ID set to: %8", level = vim.log.levels.INFO },
    }, notifications)
  end)

  it("highlights the hovered pane and clears highlight when the picker closes", function()
    local highlighted = {}
    local cleared = {}
    local picker_calls = {}
    local send_to_tmux = require("send_to_tmux")

    package.loaded["send_to_tmux.module"].list_targets = function()
      return {
        {
          window_index = "2",
          pane_id = "%7",
          process_name = "nvim",
          path = "/tmp/project",
        },
        {
          window_index = "5",
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
          opts.on_change(nil, opts.items[2])
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
