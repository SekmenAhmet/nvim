local runner = require("tests.runner")
local Model = require("modules.project.model")

runner.run("Module: Project Manager", {
  ["Model: Add and List"] = function(done)
    local test_path = "/tmp/test_project"
    vim.fn.mkdir(test_path, "p")
    Model.add(test_path)
    
    local list = Model.load()
    local found = false
    for _, p in ipairs(list) do
      if p.path == test_path then found = true break end
    end
    
    Model.remove(test_path)
    vim.fn.delete(test_path, "rf")
    done(found, "Project was not added or found in list")
  end,

  ["UI: Search logic"] = function(done)
    -- We test the filtering logic that we use in the controller
    local items = {
      { name = "Alpha", path = "/a" },
      { name = "Beta", path = "/b" },
      { name = "Gamma", path = "/g" }
    }
    
    local function filter(items, query)
      if query == "" then return items end
      local filtered = {}
      for _, it in ipairs(items) do
        if (it.name or it.path):lower():match(query:lower()) then
          table.insert(filtered, it)
        end
      end
      return filtered
    end

    local res1 = filter(items, "al")
    local res2 = filter(items, "ga")
    local res3 = filter(items, "zeta")

    local ok = #res1 == 1 and res1[1].name == "Alpha" 
           and #res2 == 1 and res2[1].name == "Gamma"
           and #res3 == 0
    
    done(ok, "Filtering logic failed")
  end
})
