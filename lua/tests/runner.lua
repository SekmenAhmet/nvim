local M = {}

--- Simple test runner that handles async tests
--- @param name string Name of the test suite
--- @param tests table<string, function> Table of test functions
function M.run(name, tests)
  print("\n--- Running Suite: " .. name .. " ---")
  local passed = 0
  local failed = 0
  local total = 0
  
  local results = {}
  
  for t_name, t_fn in pairs(tests) do
    total = total + 1
    local ok, err = pcall(t_fn, function(success, msg)
      table.insert(results, { name = t_name, ok = success, err = msg })
    end)
    
    if not ok then
      table.insert(results, { name = t_name, ok = false, err = err })
    end
  end

  -- Wait for async results (max 2s)
  vim.wait(2000, function() return #results >= total end, 10)

  for _, res in ipairs(results) do
    if res.ok then
      print("  ✓ " .. res.name)
      passed = passed + 1
    else
      print("  ❌ " .. res.name .. ": " .. tostring(res.err))
      failed = failed + 1
    end
  end

  print(string.format("\nResults: %d Passed, %d Failed", passed, failed))
  
  if failed > 0 then
    os.exit(1)
  else
    os.exit(0)
  end
end

return M
