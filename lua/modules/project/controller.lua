local Model = require("modules.project.model")
local State = require("core.state")
local picker = require("utils.picker")
local ui = require("utils.ui")
local api = vim.api

local M = {}

function M.toggle()
  local projects = Model.load()
  
  if #projects == 0 then
    vim.notify("No projects found. Add one with :ProjectAdd", vim.log.levels.INFO)
    return
  end

  local p = picker.new({
    title = "Projects",
    width_pct = 0.6,
    height_pct = 0.6,
    preview_pct = 0.6,
    on_start = function(self)
      self.state.items = projects
      self.state.filtered = projects
      self:render("")
    end,
    format_item = function(p_item)
      return p_item.name or p_item.path
    end,
    static_filter = function(items, query)
      if query == "" then return items end
      local filtered = {}
      for _, it in ipairs(items) do
        local name = (it.name or it.path):lower()
        if name:match(query:lower()) then
          table.insert(filtered, it)
        end
      end
      return filtered
    end,
    preview_item = function(p_item, buf, win)
      if not api.nvim_buf_is_valid(buf) then return end
      
      local lines = {
        "",
        "  Name: " .. (p_item.name or "N/A"),
        "  Path: " .. p_item.path,
        "  Last Opened: " .. os.date("%Y-%m-%d %H:%M:%S", p_item.last_opened),
        "",
        "  --- Contents ---",
      }
      
      local handle = vim.uv.fs_scandir(p_item.path)
      if handle then
        local count = 0
        while count < 10 do
          local name, type = vim.uv.fs_scandir_next(handle)
          if not name then break end
          table.insert(lines, "  " .. (type == "directory" and "󰉋 " or "󰈙 ") .. name)
          count = count + 1
        end
      end

      if api.nvim_buf_is_valid(buf) then
        vim.bo[buf].modifiable = true
        api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.bo[buf].modifiable = false
      end
    end,
    on_select = function(p_item)
      M.switch_to(p_item.path)
    end
  })

  p:start()
  
  -- Add specific keymap for deletion within picker
  vim.keymap.set("n", "d", function()
    local cursor = api.nvim_win_get_cursor(0)
    local idx = cursor[1] - 2 -- Header offset
    local items = p.state.filtered
    local item = items[idx]
    if item and vim.fn.confirm("Remove project " .. (item.name or item.path) .. "?", "&Yes\n&No") == 1 then
      Model.remove(item.path)
      p:close()
      vim.schedule(M.toggle) -- Reopen
    end
  end, { buffer = p.state.buf_list, silent = true })
end

function M.switch_to(path)
  local Session = require("utils.session")
  local current_path = vim.fn.getcwd()
  
  -- 1. Save current session before leaving (auto-cleans UI)
  Session.save(current_path)
  
  M.toggle() -- Close UI
  
  -- 2. Clear previous session/environment buffers
  Session.clear_env()
  
  -- 3. Change Directory
  vim.api.nvim_set_current_dir(path)
  
  -- 4. Try to load session
  local loaded = Session.load(path)
  
  if not loaded then
    vim.notify("🚀 Switched to " .. vim.fn.fnamemodify(path, ":t") .. " (New Workspace)", vim.log.levels.INFO)
    vim.schedule(function()
      require("config.finder").open()
    end)
  else
    vim.notify("🚀 Restored project: " .. vim.fn.fnamemodify(path, ":t"), vim.log.levels.INFO)
  end
end

function M.add_current()
  Model.add(vim.fn.getcwd())
  vim.notify("✨ Project added: " .. vim.fn.fnamemodify(vim.fn.getcwd(), ":t"), vim.log.levels.INFO)
end

return M
