local picker = require("utils.picker")
local ui = require("utils.ui")
local icons = require("utils.icons")

local M = {}

function M.open()
  local p = picker.new({
    title = "Live Grep",
    width_pct = 0.8,
    height_pct = 0.8,
    preview_pct = 0.55,
    debounce = 150,
    on_change = function(query, self)
      if query == "" then
        self:clear_items()
        return
      end
      
      self:clear_items()
      self:spawn("rg", { 
        "--no-config", "--column", "--line-number", "--no-heading", "--color=never", 
        "--smart-case", "--", query, vim.uv.cwd()
      }, function(lines)
        self:add_items(lines)
      end)
    end,
    format_item = function(item)
      local parts = vim.split(item, ":")
      if #parts >= 3 then
        local file = parts[1]:gsub("^%./", "")
        local line = parts[2]
        local text = vim.trim(table.concat(parts, ":", 3))
        local icon_data = icons.get(file)
        return string.format("%s:%s %s", file, line, text), icon_data.icon, icon_data.hl
      end
      return item
    end,
    preview_item = function(item, buf, win)
      local parts = vim.split(item, ":")
      if parts[1] then
        ui.async_preview(parts[1], buf, win, { lnum = tonumber(parts[2]) })
      end
    end,
    on_select = function(item)
      local parts = vim.split(item, ":")
      if parts[1] then
        ui.open_in_normal_win(parts[1], parts[2])
      end
    end
  })
  
  p:start()
end

return M
