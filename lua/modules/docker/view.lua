local api = vim.api
local State = require("core.state")
local ui_utils = require("utils.ui")
local icons = require("utils.icons").ui

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
M.bufs = {}

function M.get_buf(name, ft)
  local n = "DOCKER_" .. name:upper()
  local b = vim.fn.bufnr(n)
  if b == -1 or not api.nvim_buf_is_valid(b) then
    b = api.nvim_create_buf(false, true)
    pcall(api.nvim_buf_set_name, b, n)
  end
  M.bufs[name] = b
  vim.bo[b].filetype = ft or "text"
  return b
end

function M.layout()
  local is_active = State.get("docker.is_active")
  if not is_active then return end

  local W, H = vim.o.columns, math.max(10, vim.o.lines - 2)
  local sw = math.floor(W * Config.side_pct)
  local mw = W - sw
  local mh = math.floor(H * Config.meta_pct)

  local function setup_win(k, b, r, c, w, h, title)
    local cfg = { 
      relative = "editor", row = r, col = c, width = w-2, height = h-2, 
      style = "minimal", border = "rounded", 
      title = " " .. title .. " ", title_pos = "left" 
    }
    if M.wins[k] and api.nvim_win_is_valid(M.wins[k]) then 
      api.nvim_win_set_config(M.wins[k], cfg)
      api.nvim_win_set_buf(M.wins[k], b)
    else 
      M.wins[k] = api.nvim_open_win(b, false, cfg)
    end
    vim.wo[M.wins[k]].winhl = "Normal:Normal,FloatBorder:" .. Config.hl.border
  end

  local entity_type = State.get("docker.entity_type") or "containers"
  local side_title = entity_type:gsub("^%l", string.upper)
  local side_buf = M.get_buf("side", "docker_tree")
  setup_win("side", side_buf, 0, 0, sw, H, side_title)

  local meta_buf = M.get_buf("meta", "docker_info")
  setup_win("meta", meta_buf, 0, sw, mw, mh, "Details")
  
  local active_tab = State.get("docker.active_tab") or 1
  local t1 = (active_tab == 1 and "󰄬" or "󰈙") .. " Logs"
  local t2 = (active_tab == 2 and "󰄬" or "󰆍") .. " Terminal"
  local main_buf = (active_tab == 1 and M.get_buf("logs") or M.get_buf("term"))
  setup_win("main", main_buf, mh, sw, mw, H - mh, string.format("%s  │  %s", t1, t2))
end

function M.draw_side()
  local b = M.bufs.side
  if not b or not api.nvim_buf_is_valid(b) then return end
  
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
    table.insert(hl, { g = color, l = i-1, s = #prefix, e = #prefix + #icon })
  end
  
  vim.bo[b].modifiable = true
  api.nvim_buf_set_lines(b, 0, -1, false, lines)
  vim.bo[b].modifiable = false
  api.nvim_buf_clear_namespace(b, -1, 0, -1)
  for _, h in ipairs(hl) do
    api.nvim_buf_add_highlight(b, -1, h.g, h.l, h.s, h.e)
  end
end

function M.draw_meta(stats)
  local b = M.bufs.meta
  if not b or not api.nvim_buf_is_valid(b) then return end
  
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
  
  local lines = {}
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
  
  vim.bo[b].modifiable = true
  api.nvim_buf_set_lines(b, 0, -1, false, lines)
  vim.bo[b].modifiable = false
  api.nvim_buf_clear_namespace(b, -1, 0, -1)
  for i=0, #lines-1 do
    api.nvim_buf_add_highlight(b, -1, Config.hl.label, i, 0, 10)
  end
end

function M.close()
  for _, w in pairs(M.wins) do
    if api.nvim_win_is_valid(w) then api.nvim_win_close(w, true) end
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
