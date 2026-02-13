local runner = require("tests.runner")

runner.run("Full IDE Module Validation", {
  ["Utils: Process Engine"] = function(done)
    local process = require("utils.process")
    process.exec("echo", { args = { "test" } }, function(code, stdout)
      done(code == 0 and stdout:match("test"), "Process engine failed")
    end)
  end,

  ["Utils: UI Kit (Float)"] = function(done)
    local ui = require("utils.ui")
    local buf, win = ui.create_float({ width = 10, height = 5 })
    local valid = vim.api.nvim_win_is_valid(win)
    local modifiable = vim.bo[buf].modifiable
    if valid then vim.api.nvim_win_close(win, true) end
    done(valid and modifiable, "UI Float failed or not modifiable")
  end,

  ["Module: Cmdline"] = function(done)
    local cmd = require("config.cmdline")
    local ok = pcall(cmd.open)
    if ok then
      local buf = vim.api.nvim_get_current_buf()
      local mod = vim.bo[buf].modifiable
      cmd.close()
      done(mod, "Cmdline buffer not modifiable")
    else
      done(false, "Cmdline open failed")
    end
  end,

  ["Module: Project Manager"] = function(done)
    local ok, project = pcall(require, "modules.project.controller")
    done(ok and type(project.toggle) == "function", "Project module load failed")
  end,

  ["Module: AI"] = function(done)
    local ok, ai = pcall(require, "utils.ai")
    done(ok and type(ai.generate) == "function", "AI module load failed")
  end,

  ["Module: LSP Extensions"] = function(done)
    local ok1 = pcall(require, "modules.lsp.actions")
    local ok2 = pcall(require, "modules.lsp.symbols")
    done(ok1 and ok2, "LSP extensions load failed")
  end,

  ["Module: Picker Engine"] = function(done)
    local picker = require("utils.picker")
    local p = picker.new({ title = "Test" })
    local ok = pcall(p.start, p)
    if ok then p:close() end
    done(ok, "Picker start failed")
  end,

  ["Module: Live Grep"] = function(done)
    local grep = require("config.grep")
    local ok = pcall(grep.open)
    -- We can't easily test the async results here, but we check if it opens
    done(ok, "Live Grep open failed")
  end
})
