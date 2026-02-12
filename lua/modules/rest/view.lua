local state = require("core.state")
local ui_utils = require("utils.ui")
local model = require("modules.rest.model")

local M = {}
local api = vim.api

M.bufs = {}
M.wins = {}

local Config = {
  ui = { side_pct = 0.22, meta_pct = 0.12 },
  hl = {
    dir = "Directory",
    file = "Normal",
    method = "Function",
    border = "FloatBorder",
    var = "Special",
    tab_sel = "PmenuSel",
    tab_norm = "Pmenu",
    active_icon = "DiagnosticInfo"
  },
  tabs = {
    { name = "Body", icon = "󰅜 " },
    { name = "Headers", icon = "󰈙 " }
  }
}

function M.get_buf(k, ft)
  if M.bufs[k] and api.nvim_buf_is_valid(M.bufs[k]) then return M.bufs[k] end
  
  local name = "REST_" .. k:upper()
  local existing = vim.fn.bufnr(name)
  local b
  
  if existing ~= -1 and api.nvim_buf_is_valid(existing) then
    b = existing
  else
    b = api.nvim_create_buf(false, true)
    pcall(api.nvim_buf_set_name, b, name)
  end
  
  vim.bo[b].filetype = ft
  if k == "resp" then vim.bo[b].buftype = "nofile" else vim.bo[b].buftype = "acwrite" end
  
  api.nvim_buf_call(b, function() 
    vim.cmd([[syn match RestVar /{{.\{-}}}/]])
    vim.cmd("hi def link RestVar "..Config.hl.var) 
    
    if k == "meta" then
      vim.cmd([[syn match RestMethod /^\(GET\|POST\|PUT\|PATCH\|DELETE\|HEAD\|OPTIONS\)/]])
      vim.cmd([[syn match RestUrl /https\?:\/\/[^ ]\+/]])
      vim.cmd([[hi def link RestMethod Function]])
      vim.cmd([[hi def link RestUrl Underlined]])
    elseif k == "headers" then
       vim.cmd([[syn match RestHeaderKey /^[^:]\+:/]])
       vim.cmd([[hi def link RestHeaderKey Type]])
    end
  end)
  
  M.bufs[k] = b
  return b
end

function M.draw_side()
  local b = M.bufs.side
  if not b or not api.nvim_buf_is_valid(b) then return end
  local flat = model.get_flat()
  local l, h = {}, {}
  local req_id = state.get("rest.req_id")

  for i, it in ipairs(flat) do
    local pre = " " .. string.rep("│ ", it.d)
    local m_str = (it.n.meta and it.n.meta[1] or "GET"):match("^(%a+)") or "GET"
    local m_icon = model.Config.methods[m_str:upper()] or m_str
    local icon = it.n.type == "folder" and (it.n.expanded and "󰉋 " or "󰉓 ") or (m_icon .. " ")
    
    local is_active = req_id == it.n.id
    local prefix = is_active and "󰁕 " or "  "
    
    table.insert(l, prefix .. pre .. icon .. it.n.name)
    
    local g = it.n.type == "folder" and Config.hl.dir or Config.hl.file
    table.insert(h, { r = i - 1, s = 0, e = -1, g = g })
    
    if is_active then
      table.insert(h, { r = i - 1, s = 0, e = 3, g = Config.hl.active_icon })
    end
    
    -- Highlight tree guides
    for k = 1, it.d do
       local guide_start = 3 + 1 + (k-1)*4 
       table.insert(h, { r = i - 1, s = guide_start, e = guide_start + 3, g = Config.hl.tab_norm })
    end

    if it.n.type == "request" then
      local icon_len = #icon
      local current_line_len = #l[#l]
      local name_len = #it.n.name
      local method_start = current_line_len - name_len - icon_len
      table.insert(h, { r = i - 1, s = method_start, e = method_start + icon_len, g = Config.hl.method })
    end
  end
  vim.bo[b].modifiable = true
  api.nvim_buf_set_lines(b, 0, -1, false, l)
  vim.bo[b].modifiable = false
  api.nvim_buf_clear_namespace(b, -1, 0, -1)
  for _, v in ipairs(h) do api.nvim_buf_add_highlight(b, -1, v.g, v.r, v.s, v.e) end
end

function M.get_resp_winbar()
  local meta = state.get("rest.response_meta")
  local s = meta.status or ""
  local t = meta.time or ""
  local env = (state.get("rest.env_name") or "local"):upper()
  
  local env_hl = "DiagnosticInfo"
  if env == "PROD" then env_hl = "DiagnosticError"
  elseif env == "DEV" then env_hl = "DiagnosticWarn"
  end

  local status_hl = "DiagnosticInfo"
  if s:match("2%d%d") or s == "200" then status_hl = "DiagnosticOk"
  elseif s:match("4%d%d") or s == "400" then status_hl = "DiagnosticWarn"
  elseif s:match("5%d%d") or s == "500" then status_hl = "DiagnosticError"
  end
  
  return string.format("%%#%s# 󰖟 %s %%#Normal# │ %%#Function#  %s %%#Normal# │ %%#%s# %s", env_hl, env, t, status_hl, s)
end

function M.layout()
  if not state.get("rest.is_active") then return end
  local W = vim.o.columns
  local H = math.max(10, vim.o.lines - 2)
  local side_open = state.get("rest.side_open")
  local sw = side_open and math.floor(W * Config.ui.side_pct) or 0
  local mw = W - sw
  local ew = math.floor(mw / 2.1)
  local rw = mw - ew
  local mh = math.floor(H * Config.ui.meta_pct)

  local function win(k, b, r, c, w, h, title)
    if w <= 1 then
      if M.wins[k] and api.nvim_win_is_valid(M.wins[k]) then api.nvim_win_close(M.wins[k], true) end
      M.wins[k] = nil
      return
    end
    
    local cfg = {
      width = w - 2, height = h - 2, row = r, col = c,
      title = " " .. title .. " ", title_pos = "left",
      enter = false, buf = b
    }
    
    if M.wins[k] and api.nvim_win_is_valid(M.wins[k]) then
      api.nvim_win_set_config(M.wins[k], {
        relative = "editor", row = cfg.row, col = cfg.col, width = cfg.width, height = cfg.height,
        title = cfg.title, title_pos = cfg.title_pos
      })
      api.nvim_win_set_buf(M.wins[k], b)
    else
      local _, w_id = ui_utils.create_float(cfg)
      M.wins[k] = w_id
      vim.wo[M.wins[k]].winhl = "Normal:Normal,FloatBorder:" .. Config.hl.border .. ",WinBar:Normal,WinBarNC:Normal"
    end
    return M.wins[k]
  end

  win("side", M.get_buf("side", "rest_tree"), 0, 0, sw, H, "Collection")
  win("meta", M.get_buf("meta", "conf"), 0, sw, ew, mh, "Request")
  
  local active_tab = state.get("rest.active_tab") or 1
  local active_buf_key = Config.tabs[active_tab].name:lower()
  local input_buf = M.get_buf(active_buf_key, active_buf_key == "body" and "json" or "conf")
  
  local body_icon = (active_tab == 1) and "󰄬 Body" or "󰅜 Body"
  local headers_icon = (active_tab == 2) and "󰄬 Headers" or "󰈙 Headers"
  local input_title = string.format(" %s  │  %s ", body_icon, headers_icon)
  
  win("input", input_buf, mh, sw, ew, H - mh, input_title)

  local resp_win = win("resp", M.get_buf("resp", "json"), 0, sw + ew, rw, H, "Response")
  if resp_win then 
    vim.wo[resp_win].winbar = "%!v:lua.require'modules.rest.view'.get_resp_winbar()"
    vim.wo[resp_win].wrap = true
  end

  if M.wins.side then vim.wo[M.wins.side].cursorline = true end
end

function M.close()
  for k, w in pairs(M.wins) do
    if w and api.nvim_win_is_valid(w) then api.nvim_win_close(w, true) end
    M.wins[k] = nil
  end
end

return M
