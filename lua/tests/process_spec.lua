local runner = require("tests.runner")
local process = require("utils.process")

runner.run("Utils: Process", {
  ["Exec: simple command (ls)"] = function(done)
    process.exec("ls", { args = { "-la" } }, function(code, stdout, stderr)
      local ok = (code == 0 and #stdout > 0)
      done(ok, ok and nil or "Code: " .. code .. " Stdout len: " .. #stdout)
    end)
  end,

  ["Exec: stdin (cat)"] = function(done)
    local input = "hello neovim"
    process.exec("cat", { stdin = input }, function(code, stdout, stderr)
      local ok = (code == 0 and stdout == input)
      done(ok, ok and nil or "Expected '" .. input .. "', got '" .. stdout .. "'")
    end)
  end,

  ["Exec: error command"] = function(done)
    process.exec("ls", { args = { "/non_existent_path" } }, function(code, stdout, stderr)
      local ok = (code ~= 0 and #stderr > 0)
      done(ok, ok and nil or "Should have failed with stderr")
    end)
  end
})
