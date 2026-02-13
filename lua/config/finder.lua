local picker = require("utils.picker")
local ui = require("utils.ui")
local icons = require("utils.icons")

local M = {}

function M.open()
  local p = picker.new({
    title = "Files",
    width_pct = 0.7,
    height_pct = 0.8,
    preview_pct = 0.6,
    on_start = function(self)
      local cmd = vim.fn.executable("rg") == 1 and "rg" or "find"
      local args = cmd == "rg" 
        and { "--files", "--hidden", "--glob", "!.git/*" }
        or { ".", "-type", "f" }
      
      self:spawn(cmd, args, function(lines)
        self:add_items(lines)
      end)
    end,
    format_item = function(item)
      local clean = item:gsub("^%./", "")
      local icon_data = icons.get(clean)
      return clean, icon_data.icon, icon_data.hl
    end,
    static_filter = function(items, query)
      if query == "" then return items end
      local filtered = {}
      for _, it in ipairs(items) do
        if it:lower():match(query:lower()) then
          table.insert(filtered, it)
        end
      end
      return filtered
    end,
    preview_item = function(item, buf, win)
      ui.async_preview(item, buf, win)
    end,
    on_select = function(item)
      ui.open_in_normal_win(item)
    end
  })
  
  p:start()
end

return M
