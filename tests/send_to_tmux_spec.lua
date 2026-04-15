describe("send_to_tmux.module", function()
  local original_popen
  local original_execute

  before_each(function()
    original_popen = io.popen
    original_execute = os.execute
    package.loaded["send_to_tmux.module"] = nil
  end)

  after_each(function()
    io.popen = original_popen
    os.execute = original_execute
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

  it("presses Enter when send_enter is enabled", function()
    local executed = {}

    io.popen = function(cmd)
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
    local success, err = tmux.send_to_tmux("%7", "echo hi", {
      bracketed_paste = true,
      send_enter = true,
    })

    assert.is_true(success)
    assert.is_nil(err)
    assert.are.same({
      "tmux send-keys -t '%7' Enter",
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

  before_each(function()
    original_notify = vim.notify
    original_input = vim.ui.input
    original_mode = vim.fn.mode
    original_getline = vim.fn.getline
    package.loaded["send_to_tmux"] = nil
    package.loaded["send_to_tmux.module"] = {
      is_tmux_installed = function()
        return true
      end,
      target_exists = function(target)
        return target == "%7"
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
          send_enter = false,
        },
      },
    }, send_calls)
  end)

  it("sends with Enter for SendToTmuxExec", function()
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
    send_to_tmux.send_to_tmux_exec()

    assert.are.same({
      {
        target = "%7",
        text = "echo hi",
        opts = {
          bracketed_paste = true,
          send_enter = true,
        },
      },
    }, send_calls)
  end)
end)
