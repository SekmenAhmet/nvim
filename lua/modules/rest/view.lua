local state = require("core.state")
local ui_utils = require("utils.ui")
local model = require("modules.rest.model")
local ViewFactory = require("utils.view_factory")

local M = {}
local api = vim.api

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

M.wins = {}
M.components = {
  side    = ViewFactory.create_component("REST_SIDE",    { filetype = "rest_tree" }),
  meta    = ViewFactory.create_component("REST_META",    { filetype = "conf", buftype = "acwrite" }),
  body    = ViewFactory.create_component("REST_BODY",    { filetype = "json", buftype = "acwrite" }),
  headers = ViewFactory.create_component("REST_HEADERS", { filetype = "conf", buftype = "acwrite" }),
  resp    = ViewFactory.create_component("REST_RESP",    { filetype = "json" })
}

-- Initial syntax for specific components
for k, comp in pairs(M.components) do
  api.nvim_buf_call(comp.buf, function()
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
end

function M.draw_side()
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
    table.insert(h, { line = i - 1, col_start = 0, col_end = -1, group = g })
    
    if is_active then
      table.insert(h, { line = i - 1, col_start = 0, col_end = 3, group = Config.hl.active_icon })
    end
    
    -- Highlight tree guides
    for k = 1, it.d do
       local guide_start = 3 + 1 + (k-1)*4 
       table.insert(h, { line = i - 1, col_start = guide_start, col_end = guide_start + 3, group = Config.hl.tab_norm })
    end

    if it.n.type == "request" then
      local icon_len = #icon
      local current_line_len = #l[#l]
      local name_len = #it.n.name
      local method_start = current_line_len - name_len - icon_len
      table.insert(h, { line = i - 1, col_start = method_start, col_end = method_start + icon_len, group = Config.hl.method })
    end
  end
  
  ViewFactory.render(M.components.side, l, h)
end

function M.get_resp_winbar()
  local meta = state.get("rest.response_meta") or {}
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

  local active_tab = state.get("rest.active_tab") or 1
  local active_buf_key = Config.tabs[active_tab].name:lower()
  local input_component = M.components[active_buf_key]
  
  local body_icon = (active_tab == 1) and "󰄬 Body" or "󰅜 Body"
  local headers_icon = (active_tab == 2) and "󰄬 Headers" or "󰈙 Headers"
  local input_title = string.format("%s  │  %s", body_icon, headers_icon)

  local layout_config = {
    side = { 
      width = sw, height = H, row = 0, col = 0, 
      title = "Collection", filetype = "rest_tree", cursorline = true,
      buf = M.components.side.buf
    },
    meta = { 
      width = ew, height = mh, row = 0, col = sw, 
      title = "Request", filetype = "conf",
      buf = M.components.meta.buf
    },
    input = { 
      width = ew, height = H - mh, row = mh, col = sw, 
      title = input_title, filetype = active_buf_key == "body" and "json" or "conf",
      buf = input_component.buf
    },
    resp = { 
      width = rw, height = H, row = 0, col = sw + ew, 
      title = "Response", filetype = "json",
      buf = M.components.resp.buf
    }
  }

  local active_layout = {}
  for k, v in pairs(layout_config) do if v.width > 1 then active_layout[k] = v end end
  
  for k, res in pairs(M.wins) do
    if not active_layout[k] and res.win and api.nvim_win_is_valid(res.win) then
      api.nvim_win_close(res.win, true)
      M.wins[k] = nil
    end
  end

  M.wins = ui_utils.layout_manager(active_layout, M.wins)
  
  -- Sync window handles and apply rules
  for k, res in pairs(M.wins) do
    local comp = (k == "input") and input_component or M.components[k]
    if comp then 
      comp.win = res.win 
      if k == "side" then ViewFactory.apply_ui_rules(comp, { mode = "strict" }) end
    end
  end
  
  if M.wins.resp and api.nvim_win_is_valid(M.wins.resp.win) then
    vim.wo[M.wins.resp.win].winbar = "%!v:lua.require'modules.rest.view'.get_resp_winbar()"
    vim.wo[M.wins.resp.win].wrap = true
  end
end

function M.close()
  for k, res in pairs(M.wins) do
    if res.win and api.nvim_win_is_valid(res.win) then api.nvim_win_close(res.win, true) end
  end
  M.wins = {}
end

return M
