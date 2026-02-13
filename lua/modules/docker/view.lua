local api = vim.api
local State = require("core.state")
local ui_utils = require("utils.ui")
local icons = require("utils.icons").ui
local ViewFactory = require("utils.view_factory")

local M = {}

local Config = {
  side_pct = 0.25,
  meta_pct = 0.15,
  hl = { 
    running = "DiagnosticOk", 
    exited = "DiagnosticError", 
    building = "DiagnosticWarn", 
    border = "FloatBorder", 
    label = "Comment" 
  },
  icons = { 
    running = icons.ok, 
    exited = icons.error, 
    building = icons.spinner 
  }
}

M.wins = {}
M.components = {
  side = ViewFactory.create_component("DOCKER_SIDE", { filetype = "docker_tree" }),
  meta = ViewFactory.create_component("DOCKER_META", { filetype = "docker_info" }),
  logs = ViewFactory.create_component("DOCKER_LOGS", { filetype = "docker_logs" }),
  term = ViewFactory.create_component("DOCKER_TERM", { filetype = "docker_term" })
}

function M.layout()
  local is_active = State.get("docker.is_active")
  if not is_active then return end

  local W, H = vim.o.columns, math.max(10, vim.o.lines - 2)
  local sw = math.floor(W * Config.side_pct)
  local mw = W - sw
  local mh = math.floor(H * Config.meta_pct)

  local entity_type = State.get("docker.entity_type") or "containers"
  local side_title = entity_type:gsub("^%l", string.upper)
  local active_tab = State.get("docker.active_tab") or 1
  
  local t1 = (active_tab == 1 and "󰄬" or "󰈙") .. " Logs"
  local t2 = (active_tab == 2 and "󰄬" or "󰆍") .. " Terminal"

  M.wins = ui_utils.layout_manager({
    side = { 
      width = sw, height = H, row = 0, col = 0, 
      title = side_title, filetype = "docker_tree", cursorline = true,
      buf = M.components.side.buf
    },
    meta = { 
      width = mw, height = mh, row = 0, col = sw, 
      title = "Details", filetype = "docker_info",
      buf = M.components.meta.buf
    },
    main = { 
      width = mw, height = H - mh, row = mh, col = sw, 
      title = string.format("%s  │  %s", t1, t2),
      filetype = active_tab == 1 and "docker_logs" or "docker_term",
      buf = active_tab == 1 and M.components.logs.buf or M.components.term.buf
    }
  }, M.wins)
  
  -- Sync window handles back to components
  for k, res in pairs(M.wins) do
    if M.components[k] then M.components[k].win = res.win end
  end
  
  ui_utils.set_ui_mode(M.components.side.buf, { win = M.wins.side.win })
end

function M.draw_side()
  local entity_type = State.get("docker.entity_type") or "containers"
  local entities = State.get("docker.entities." .. entity_type) or {}
  local selected_id = State.get("docker.selected_id")
  
  local lines, hl = {}, {}
  
  for i, entity in ipairs(entities) do
    local text = ""
    local color = "Normal"
    local icon = "  "
    
    if entity_type == "containers" then
      local is_running = entity.state:lower():match("up") or entity.state:lower():match("running")
      icon = is_running and Config.icons.running or Config.icons.exited
      color = is_running and Config.hl.running or Config.hl.exited
      text = " " .. entity.name
    elseif entity_type == "images" then
      icon = "󰋚 "
      color = "Function"
      text = " " .. entity.repo .. ":" .. entity.tag
    elseif entity_type == "volumes" then
      icon = "󱁐 "
      color = "Directory"
      text = " " .. entity.name
    end
    
    local prefix = (selected_id == (entity.id or entity.name)) and "→ " or "  "
    table.insert(lines, prefix .. icon .. text)
    table.insert(hl, { group = color, line = i-1, col_start = #prefix, col_end = #prefix + #icon })
  end
  
  ViewFactory.render(M.components.side, lines, hl)
end

function M.draw_meta(stats)
  local entity_type = State.get("docker.entity_type") or "containers"
  local entities = State.get("docker.entities." .. entity_type) or {}
  local selected_id = State.get("docker.selected_id")
  
  local entity = nil
  for _, e in ipairs(entities) do
    if (e.id or e.name) == selected_id then
      entity = e
      break
    end
  end
  
  local lines, hl = {}, {}
  if entity then
    if entity_type == "containers" then
      lines = { 
        "  ID:      " .. entity.id:sub(1,12), 
        "  Service: " .. (entity.service or "N/A"), 
        "  Image:   " .. entity.image, 
        "  Status:  " .. entity.status,
      }
      if stats then
        table.insert(lines, "  CPU/MEM: " .. stats.cpu .. " / " .. stats.mem)
        table.insert(lines, "  NET IO:  " .. stats.net)
      end
    elseif entity_type == "images" then
      lines = { 
        "  ID:      " .. entity.id:sub(1,12), 
        "  Repo:    " .. entity.repo, 
        "  Tag:     " .. entity.tag, 
        "  Size:    " .. entity.size, 
        "  Created: " .. entity.created 
      }
    elseif entity_type == "volumes" then
      lines = { "  Name:    " .. entity.name, "  Driver:  " .. entity.driver, "  Scope:   " .. entity.scope }
    end
  else
    lines = { "  Select an item to see details..." }
  end
  
  for i=0, #lines-1 do
    table.insert(hl, { group = Config.hl.label, line = i, col_start = 0, col_end = 10 })
  end
  
  ViewFactory.render(M.components.meta, lines, hl)
end

function M.close()
  for _, res in pairs(M.wins) do
    if res.win and api.nvim_win_is_valid(res.win) then 
      api.nvim_win_close(res.win, true) 
    end
  end
  M.wins = {}
end

-- Subscribe to state changes to reactively update the UI
State.subscribe("docker.entities.containers", function() M.draw_side() end)
State.subscribe("docker.entities.images", function() M.draw_side() end)
State.subscribe("docker.entities.volumes", function() M.draw_side() end)
State.subscribe("docker.selected_id", function() M.draw_side(); M.draw_meta() end)
State.subscribe("docker.active_tab", function() M.layout() end)
State.subscribe("docker.entity_type", function() M.layout(); M.draw_side() end)

return M
