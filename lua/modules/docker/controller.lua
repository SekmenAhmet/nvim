local api = vim.api
local State = require("core.state")
local Model = require("modules.docker.model")
local View = require("modules.docker.view")
local uv = vim.uv

local M = {}
local refresh_timer = nil

function M.refresh()
  local entity_type = State.get("docker.entity_type") or "containers"
  if entity_type == "containers" then
    Model.list_containers(function()
      local selected_id = State.get("docker.selected_id")
      if selected_id then
        Model.get_stats(selected_id, function(stats)
          View.draw_meta(stats)
        end)
      end
    end)
  elseif entity_type == "images" then
    Model.list_images()
  elseif entity_type == "volumes" then
    Model.list_volumes()
  end
end

function M.toggle()
  local is_active = not State.get("docker.is_active")
  State.set("docker.is_active", is_active)
  
  if is_active then
    View.layout()
    M.setup_autocmds()
    M.setup_keymaps()
    M.start_refresh_timer()
    M.refresh()
  else
    M.stop_refresh_timer()
    View.close()
  end
end

function M.start_refresh_timer()
  if refresh_timer then return end
  refresh_timer = uv.new_timer()
  refresh_timer:start(0, 3000, vim.schedule_wrap(function()
    if State.get("docker.is_active") then
      M.refresh()
    else
      M.stop_refresh_timer()
    end
  end))
end

function M.stop_refresh_timer()
  if refresh_timer then
    refresh_timer:stop()
    refresh_timer:close()
    refresh_timer = nil
  end
end

function M.setup_autocmds()
  local side_comp = View.components.side
  if not side_comp or not api.nvim_buf_is_valid(side_comp.buf) then return end
  
  local augroup = api.nvim_create_augroup("DockerController", { clear = true })
  
  api.nvim_create_autocmd("CursorMoved", {
    buffer = side_comp.buf,
    group = augroup,
    callback = function()
      local idx = api.nvim_win_get_cursor(0)[1]
      local entity_type = State.get("docker.entity_type") or "containers"
      local entities = State.get("docker.entities." .. entity_type) or {}
      local entity = entities[idx]
      if entity then
        local id = entity.id or entity.name
        if id ~= State.get("docker.selected_id") then
          State.set("docker.selected_id", id)
        end
      end
    end
  })

  -- Handle WinClosed to cleanup state and timer if a main window is closed manually
  local side_win = side_comp.win
  if side_win and api.nvim_win_is_valid(side_win) then
    api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(side_win),
      group = augroup,
      callback = function()
        if State.get("docker.is_active") then
          State.set("docker.is_active", false)
          M.stop_refresh_timer()
          View.close()
        end
      end
    })
  end
end

function M.setup_keymaps()
  for _, component in pairs(View.components) do
    local buf = component.buf
    if api.nvim_buf_is_valid(buf) then
      local opts = { buffer = buf, silent = true }
      vim.keymap.set({"n", "i", "v", "t"}, "<C-d>", M.toggle, opts)
      vim.keymap.set({"n", "i", "v", "t"}, "<Esc>", M.toggle, opts)
      vim.keymap.set("n", "q", M.toggle, opts)
      vim.keymap.set("n", "<Tab>", function()
        local current = State.get("docker.active_tab") or 1
        State.set("docker.active_tab", current == 1 and 2 or 1)
      end, opts)
      
      -- Entity selection
      vim.keymap.set("n", "C", function() State.set("docker.entity_type", "containers") end, opts)
      vim.keymap.set("n", "I", function() State.set("docker.entity_type", "images") end, opts)
      vim.keymap.set("n", "V", function() State.set("docker.entity_type", "volumes") end, opts)
      
      -- Navigation
      vim.keymap.set("n", "<C-h>", function() 
        if View.components.side.win and api.nvim_win_is_valid(View.components.side.win) then 
          api.nvim_set_current_win(View.components.side.win) 
        end 
      end, opts)
      vim.keymap.set("n", "<C-l>", function() 
        local main_win = View.wins.main and View.wins.main.win
        if main_win and api.nvim_win_is_valid(main_win) then 
          api.nvim_set_current_win(main_win) 
        end 
      end, opts)
    end
  end
end

return M
