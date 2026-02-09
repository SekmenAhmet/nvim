-- Native REST Client (Gold Master OpenAPI Edition)
-- Architecture: MVC + Event Driven | Features: Tabbed UI, Env Vars, Syntax Highlighting, Strict Mode

local M = {}
local api = vim.api
local fn = vim.fn

-- ============================================================================
--  1. CONFIG & CONSTANTS
-- ============================================================================

local Config = {
  default_file = "openapi.yaml",
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
  methods = { 
    GET = "󰖟 GET", POST = "󰐪 POST", PUT = "󰏫 PUT", 
    PATCH = "󰏫 PATCH", DELETE = "󰩹 DEL", HEAD = "󰛵 HEAD", OPTIONS = "󰒓 OPT" 
  },
  tabs = { 
    { name = "Body", icon = "󰅜 " }, 
    { name = "Headers", icon = "󰈙 " }
  }
}

local AU_GROUP = api.nvim_create_augroup("RESTClient", { clear = true })

-- ============================================================================
--  2. STATE STORE
-- ============================================================================

local State = {
  active = false,
  side_open = false,
  req_id = nil,
  active_tab = 1, 
  tree = {},
  flat = {},
  bufs = {}, 
  wins = {},
  job = nil,
  file_path = nil,
  env = {},
  response_meta = { status = "", time = "" }
}

-- ============================================================================
--  3. UTILS
-- ============================================================================

local U = {}
function U.uuid() return string.format("%x", vim.uv.hrtime()) end
function U.debounce(ms, f)
  local t = vim.uv.new_timer()
  return function(...) local a={...}; t:stop(); t:start(ms,0,vim.schedule_wrap(function() f(unpack(a)) end)) end
end

function U.load_env()
  local env = {}
  local f = io.open(vim.uv.cwd() .. "/.env", "r")
  if f then
    for line in f:lines() do
      local k, v = line:match("^%s*([%w_]+)%s*=%s*(.*)")
      if k and v then 
        v = v:gsub("^['\"]", ""):gsub("['\"]$", "")
        env[k] = v 
      end
    end
    f:close()
  end
  return env
end

-- ============================================================================
--  4. OPENAPI YAML ENGINE
-- ============================================================================

local YAML = {}

local function indent_len(line) return #(line:match("^(%s*)")) end
local function is_path_key(line)
  local content = vim.trim(line)
  return content:match("^['\"]?/") and content:match(":$")
end
local function is_method_key(line)
  local content = vim.trim(line)
  local m = content:match("^(%w+):")
  return m and vim.tbl_contains(Config.methods, m:upper())
end

function YAML.parse(content)
  local root_tree = {}
  local lines = vim.split(content, "\n")
  
  State.yaml_header = {}
  State.yaml_footer = {}
  
  local mode = "HEADER"
  local paths_indent = -1
  local current_full_path = nil
  local base_url = "http://localhost"

  local function get_target_list(tree, path_str)
    local clean_path = path_str:gsub("^/", "")
    if clean_path == "" then return tree, "/" end
    local parts = vim.split(clean_path, "/")
    local current_list = tree
    for i = 1, #parts - 1 do
      local folder_name = parts[i]
      local found = nil
      for _, node in ipairs(current_list) do
        if node.type == "folder" and node.name == folder_name then found = node break end
      end
      if not found then
        found = { id = U.uuid(), name = folder_name, type = "folder", expanded = true, children = {}, variables = {} }
        table.insert(current_list, found)
      end
      current_list = found.children
    end
    return current_list, parts[#parts]
  end

  for _, line in ipairs(lines) do
    if mode == "HEADER" and line:match("^%s*paths:") then break end
    local url = line:match("^%s*-%s*url:%s*(.*)")
    if url and not url:match("{") then base_url = vim.trim(url):gsub("['\"]", "") end
  end

  local i = 1
  while i <= #lines do
    local line = lines[i]
    local trim = vim.trim(line)
    local indent = indent_len(line)

    if mode == "HEADER" then
      if line:match("^%s*paths:%s*$") then
        mode = "PATHS"
        paths_indent = indent
        table.insert(State.yaml_header, line)
      else
        table.insert(State.yaml_header, line)
      end
      i = i + 1
    elseif mode == "PATHS" then
      if trim ~= "" and indent <= paths_indent and not line:match("^%s*#") then
        mode = "FOOTER"
      elseif trim == "" or line:match("^%s*#") then
        i = i + 1
      else
        if is_path_key(line) then
          current_full_path = trim:gsub(":$", ""):gsub("^['\"]", ""):gsub("['\"]$", "")
          i = i + 1
          while i <= #lines do
            local sub = lines[i]
            local sub_indent = indent_len(sub)
            if sub_indent <= indent and vim.trim(sub) ~= "" then break end
            local sub_trim = vim.trim(sub)
            
            if is_method_key(sub) then
               local method = sub_trim:match("^(%w+)"):upper()
               local target_list, final_name = get_target_list(root_tree, current_full_path)
               local req = {
                 id = U.uuid(),
                 name = final_name,
                 type = "request",
                 meta = { method .. " " .. base_url .. current_full_path },
                 headers = { "Content-Type: application/json" },
                 body = { "{}" }
               }
               i = i + 1
               local body_lines = {}
               local capturing_body = false
               while i <= #lines do
                 local det = lines[i]
                 if indent_len(det) <= sub_indent and vim.trim(det) ~= "" then i = i - 1; break end
                 local det_trim = vim.trim(det)
                 if det_trim:match("^summary:") then
                   req.name = det_trim:match("^summary:%s*(.*)")
                   capturing_body = false
                 elseif det_trim:match("^example:") then
                    capturing_body = true
                    local inline = det_trim:match("^example:%s*(.*)")
                    if inline and inline ~= "|" and inline ~= "" then table.insert(body_lines, inline) end
                 elseif capturing_body then
                    if det:match(":") and not det:match("^%s*[%w_-]+:") then 
                       table.insert(body_lines, vim.trim(det))
                    elseif det:match(":") then 
                       capturing_body = false; i = i - 1
                    else
                       table.insert(body_lines, vim.trim(det))
                    end
                 end
                 i = i + 1
               end
               if #body_lines > 0 then req.body = body_lines end
               table.insert(target_list, req)
            else
               i = i + 1
            end
          end
        else
          i = i + 1
        end
      end
    elseif mode == "FOOTER" then
      table.insert(State.yaml_footer, line)
      i = i + 1
    end
  end
  return root_tree
end

function YAML.dump(tree)
  local lines = {}
  if State.yaml_header and #State.yaml_header > 0 then
    for _, l in ipairs(State.yaml_header) do table.insert(lines, l) end
  else
    table.insert(lines, "openapi: 3.0.0")
    table.insert(lines, "info:")
    table.insert(lines, "  title: Generated API")
    table.insert(lines, "  version: 1.0.0")
    table.insert(lines, "paths:")
  end

  local by_path = {}
  for _, node in ipairs(tree) do
    if node.type == "request" then
      local method, url = (node.meta[1] or ""):match("^(%a+)%s+(http%S+)")
      if not method then method = "GET"; url = node.meta[1] or "" end
      local path = url:match("^https?://[^/]+(/.*)") or url
      if not path:match("^/") then path = "/" .. path end
      if not by_path[path] then by_path[path] = {} end
      table.insert(by_path[path], node)
    end
  end

  local sorted_paths = vim.tbl_keys(by_path)
  table.sort(sorted_paths)

  for _, path in ipairs(sorted_paths) do
    table.insert(lines, "  '" .. path .. "':")
    for _, req in ipairs(by_path[path]) do
       local method = (req.meta[1] or "GET"):match("^(%a+)"):lower()
       table.insert(lines, "    " .. method .. ":")
       table.insert(lines, "      summary: " .. (req.name or "Request"))
       if req.body and #req.body > 0 and table.concat(req.body):match("%S") then
          table.insert(lines, "      requestBody:")
          table.insert(lines, "        content:")
          table.insert(lines, "          application/json:")
          table.insert(lines, "            example: |")
          for _, l in ipairs(req.body) do table.insert(lines, "              " .. l) end
       end
       table.insert(lines, "      responses:")
       table.insert(lines, "        '200':")
       table.insert(lines, "          description: OK")
    end
  end

  if State.yaml_footer then for _, l in ipairs(State.yaml_footer) do table.insert(lines, l) end end
  return table.concat(lines, "\n")
end

-- ============================================================================
--  5. DATA LAYER (DB)
-- ============================================================================

local DB = {}

function DB.init()
  local cwd = vim.uv.cwd()
  State.file_path = cwd .. "/" .. Config.default_file
  State.env = U.load_env() -- Load env vars
  
  local potentials = { "openapi.yaml", "openapi.yml", "swagger.yaml", "swagger.yml" }
  for _, p in ipairs(potentials) do
    if fn.filereadable(cwd .. "/" .. p) == 1 then State.file_path = cwd .. "/" .. p; break end
  end

  local f = io.open(State.file_path, "r")
  if f then
    local content = f:read("*a"); f:close()
    if content then State.tree = YAML.parse(content) else State.tree = {} end
  else
    State.tree = {}
    State.yaml_header = { "openapi: 3.0.0", "info:", "  title: API", "  version: 1.0.0", "paths:" }
    State.yaml_footer = {}
  end
  DB.flat()
  
  api.nvim_create_autocmd("BufWritePost", {
    group = AU_GROUP, pattern = State.file_path,
    callback = function()
      local rf = io.open(State.file_path, "r")
      if rf then
        local c = rf:read("*a"); rf:close()
        if c then
           State.tree = YAML.parse(c)
           DB.flat()
           local UI = require("config.rest").UI -- Late bind
           if UI then UI.draw_side() end
        end
      end
    end
  })
end

function DB.save(silent) 
  if not State.tree then return end
  local content = YAML.dump(State.tree)
  local f = io.open(State.file_path, "w+")
  if f then f:write(content); f:close() end 
end

function DB.flat()
  State.flat = {}
  local function rec(list, depth)
    for _, n in ipairs(list) do 
      table.insert(State.flat, { n = n, d = depth }) 
      if n.type == "folder" and n.expanded and n.children then rec(n.children, depth + 1) end
    end
  end
  rec(State.tree, 0)
end

function DB.find(id, list)
  list = list or State.tree
  for _, n in ipairs(list) do 
    if n.id == id then return n end 
    if n.children then
      local found = DB.find(id, n.children)
      if found then return found end
    end
  end
  return nil
end

function DB.add(list, name)
  if not vim.uv.fs_stat(State.file_path) then DB.save(true) end
  local is_folder = name:sub(-1) == "/"
  local clean_name = is_folder and name:sub(1, -2) or name
  local n = {
    id = U.uuid(), name = clean_name, type = is_folder and "folder" or "request", expanded = true
  }
  if is_folder then n.children = {}
  else
    n.meta = {"GET http://localhost/"..clean_name:gsub(" ","-")}
    n.headers = {"Content-Type: application/json"}
    n.body = {"{}"}
  end
  table.insert(list, n)
  DB.flat()
  return n
end

function DB.del(id)
  local function rec_del(list)
    for i, n in ipairs(list) do 
      if n.id == id then table.remove(list, i); return true end 
      if n.children then if rec_del(n.children) then return true end end
    end
  end
  if rec_del(State.tree) then DB.flat(); return true end
end

function DB.vars(id)
  local v = {}
  for k, val in pairs(State.env) do v[k] = val end
  if State.yaml_header then
    for _, l in ipairs(State.yaml_header) do
      local k, val = l:match("^%s*([%w_-]+):%s*(.*)")
      if k and not vim.tbl_contains({"openapi", "info", "paths"}, k) then v[k] = val end
    end
  end
  local n = DB.find(id)
  if n and n.meta then
    for _, l in ipairs(n.meta) do
      local k, val = l:match("^#%s*([%w_-]+)%s*=%s*(.*)")
      if k then v[k] = val end
    end
  end
  return v
end

-- ============================================================================
--  6. APP LOGIC (Controller) - DEFINED BEFORE UI
-- ============================================================================

local App = {}

App.sync = function()
  if not State.req_id then return end
  local n = DB.find(State.req_id)
  if not n then return end
  
  -- Sync buffers back to node
  if State.bufs.meta and api.nvim_buf_is_valid(State.bufs.meta) then
    n.meta = api.nvim_buf_get_lines(State.bufs.meta, 0, -1, false)
  end
  if State.bufs.body and api.nvim_buf_is_valid(State.bufs.body) then
    n.body = api.nvim_buf_get_lines(State.bufs.body, 0, -1, false)
  end
  if State.bufs.headers and api.nvim_buf_is_valid(State.bufs.headers) then
    n.headers = api.nvim_buf_get_lines(State.bufs.headers, 0, -1, false)
  end
end

App.autosave = U.debounce(1000, function() 
  App.sync()
  if vim.uv.fs_stat(State.file_path) or #State.tree > 0 then DB.save(true) end
end)

App.run = function()
  if fn.executable("curl") == 0 then vim.notify("Curl required", vim.log.levels.ERROR); return end
  App.sync()
  
  if State.job and not State.job:is_closing() then
    pcall(function() State.job:kill(15) end); State.job:close(); State.job = nil
  end

  local n = DB.find(State.req_id)
  if not n then return end
  
  -- Reset status
  State.response_meta = { status = "Pending...", time = "0ms" }
  vim.cmd("redrawstatus")

  local meta = n.meta or {}
  local first_line = meta[1] or ""
  
  -- Vars
  local vars = DB.vars(n.id)
  local function replace_vars(s)
    return s:gsub("{{([%w_-]+)}}", function(k) return vars[k] or "{{"..k.."}}" end)
  end
  first_line = replace_vars(first_line)
  
  local m, u = first_line:match("^(%a+)%s+(.*)")
  if not m then m = "GET"; u = first_line:gsub("^%s*", "") end
  u = vim.trim(u)
  if u == "" then u = "http://localhost" end

  local A = { "-s", "-i", "-X", m, u }
  
  -- Headers
  if n.headers then
    for _, h in ipairs(n.headers) do
      local rh = replace_vars(vim.trim(h))
      if rh ~= "" and rh:match(":") then table.insert(A, "-H"); table.insert(A, rh) end
    end
  end

  -- Body
  local B = table.concat(n.body or {}, "\n")
  B = replace_vars(B)
  if m ~= "GET" and #B > 0 then table.insert(A, "-d"); table.insert(A, B) end

  local br = State.bufs.resp
  vim.bo[br].modifiable = true
  api.nvim_buf_set_lines(br, 0, -1, false, { "" })
  vim.bo[br].modifiable = false

  local start_time = vim.uv.hrtime()
  local out, dat = vim.uv.new_pipe(false), ""
  State.job = vim.uv.spawn("curl", { args = A, stdio = { nil, out, nil } }, function(code, signal)
    if out then out:read_stop(); out:close() end
    State.job = nil
    
    local end_time = vim.uv.hrtime()
    local duration = (end_time - start_time) / 1000000 -- ns to ms
    local duration_str = string.format("%.0fms", duration)
    
    vim.schedule(function()
      if not api.nvim_buf_is_valid(br) then return end
      
      -- Parse Status
      local status_code = "Unknown"
      if dat ~= "" then
        local head = dat:match("^(HTTP/%d%.%d %d+ [^\r\n]*)") or dat:match("^(HTTP/%d%.%d %d+)")
        if head then status_code = head end
      end
      
      State.response_meta = { status = status_code, time = duration_str }
      vim.cmd("redrawstatus") -- Force winbar update
      
      vim.bo[br].modifiable = true
      
      if code ~= 0 then
        api.nvim_buf_set_lines(br, 0, -1, false, { "❌ Error (" .. code .. ")" })
        State.response_meta.status = "Error " .. code
      elseif dat == "" then
        api.nvim_buf_set_lines(br, 0, -1, false, { "⚠️ Empty response" })
      else
        local p = vim.split(dat, "\r?\n\r?\n")
        local body_start = 2
        while p[body_start] and p[body_start-1]:match("^HTTP/%d%.%d 100") do body_start = body_start + 1 end
        local cnt = table.concat({ unpack(p, body_start) }, "\n\n")
        if fn.executable("jq") == 1 and cnt:match("%S") and cnt:match("^%s*[{%[]") then
          local j = fn.system("jq .", cnt)
          if vim.v.shell_error == 0 then cnt = j end
        end
        api.nvim_buf_set_lines(br, 0, -1, false, vim.split(cnt:gsub("\r", ""), "\n"))
      end
      vim.bo[br].modifiable = false
    end)
  end)
  
  if State.job then out:read_start(function(err, d) if d then dat = dat .. d end end) end
end

-- ============================================================================
--  7. UI LAYER (View)
-- ============================================================================

local UI = {}
M.UI = UI -- Export for external callbacks

function UI.buf(k, ft, init_fn)
  if State.bufs[k] and api.nvim_buf_is_valid(State.bufs[k]) then return State.bufs[k] end
  
  local name = "REST_" .. k:upper()
  local existing = fn.bufnr(name)
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
    vim.cmd("syn match RestVar /{{.\\{-}}}/")
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
  
  if init_fn then init_fn(b) end
  State.bufs[k] = b
  return b
end

function UI.draw_side()
  local b = State.bufs.side
  if not b or not api.nvim_buf_is_valid(b) then return end
  local l, h = {}, {}
  for i, it in ipairs(State.flat) do
    local pre = " " .. string.rep("│ ", it.d)
    local m_str = (it.n.meta and it.n.meta[1] or "GET"):match("^(%a+)") or "GET"
    local m_icon = Config.methods[m_str:upper()] or m_str
    local icon = it.n.type == "folder" and (it.n.expanded and "󰉋 " or "󰉓 ") or (m_icon .. " ")
    
    local is_active = State.req_id == it.n.id
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
      local offset = #l[#l] - #it.n.name - #icon + 1
      local current_line_len = #l[#l]
      local name_len = #it.n.name
      local icon_len = #icon
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
  local s = State.response_meta.status
  local t = State.response_meta.time
  if s == "" or s == "Pending..." then return "" end
  
  local status_hl = "DiagnosticInfo"
  if s:match("^HTTP/%d%.%d 2") or s == "200" then status_hl = "DiagnosticOk"
  elseif s:match("^HTTP/%d%.%d 4") or s == "400" then status_hl = "DiagnosticWarn"
  elseif s:match("^HTTP/%d%.%d 5") or s == "500" then status_hl = "DiagnosticError"
  end
  
  return "%#Function#  " .. t .. " %#Normal# │ %#" .. status_hl .. "#" .. s
end

function UI.layout()
  if not State.active then return end
  local W = vim.o.columns
  local H = math.max(10, vim.o.lines - 2)
  local sw = State.side_open and math.floor(W * Config.ui.side_pct) or 0
  local mw = W - sw
  local ew = math.floor(mw / 2.1)
  local rw = mw - ew
  local mh = math.floor(H * Config.ui.meta_pct)

  local function win(k, b, r, c, w, h, title)
    if w <= 1 then
      if State.wins[k] and api.nvim_win_is_valid(State.wins[k]) then api.nvim_win_close(State.wins[k], true) end
      State.wins[k] = nil
      return
    end
    local cfg = {
      relative = "editor", row = r, col = c, width = w - 2, height = h - 2,
      style = "minimal", border = "rounded", title = " " .. title .. " ", title_pos = "left",
    }
    if State.wins[k] and api.nvim_win_is_valid(State.wins[k]) then
      api.nvim_win_set_config(State.wins[k], cfg)
      api.nvim_win_set_buf(State.wins[k], b)
    else
      State.wins[k] = api.nvim_open_win(b, false, cfg)
      vim.wo[State.wins[k]].winhl = "Normal:Normal,FloatBorder:" .. Config.hl.border .. ",WinBar:Normal,WinBarNC:Normal"
    end
    return State.wins[k]
  end

  win("side", UI.buf("side", "rest_tree"), 0, 0, sw, H, "Collection")
  win("meta", UI.buf("meta", "conf"), 0, sw, ew, mh, "Request")
  
  -- Integrated Tab Bar in Border
  local active_buf_key = Config.tabs[State.active_tab].name:lower()
  local input_buf = UI.buf(active_buf_key, active_buf_key == "body" and "json" or "conf")
  
  local body_icon = (State.active_tab == 1) and "󰄬 Body" or "󰅜 Body"
  local headers_icon = (State.active_tab == 2) and "󰄬 Headers" or "󰈙 Headers"
  local input_title = string.format(" %s  │  %s ", body_icon, headers_icon)
  
  win("input", input_buf, mh, sw, ew, H - mh, input_title)

  local resp_win = win("resp", UI.buf("resp", "json"), 0, sw + ew, rw, H, "Response")
  if resp_win then vim.wo[resp_win].winbar = "%!v:lua.require'config.rest'.get_resp_winbar()" end

  if State.wins.side then vim.wo[State.wins.side].cursorline = true end
  if State.wins.resp then vim.wo[State.wins.resp].wrap = true end
end

function UI.close()
  App.sync()
  for k, w in pairs(State.wins) do
    if w and api.nvim_win_is_valid(w) then api.nvim_win_close(w, true) end
    State.wins[k] = nil
  end
  State.active = false
end

-- ============================================================================
--  8. PUBLIC INTERACTION & MAPPINGS
-- ============================================================================

App.switch_tab = function(dir)
  local new_idx = State.active_tab + dir
  if new_idx < 1 then new_idx = #Config.tabs end
  if new_idx > #Config.tabs then new_idx = 1 end
  State.active_tab = new_idx
  UI.layout() 
end

App.map_all = function(b)
  local o = { buffer = b, silent = true, nowait = true }
  vim.keymap.set("n", "<Esc>", UI.close, o)
  vim.keymap.set("n", "q", UI.close, o)
  
  -- Tabs
  vim.keymap.set({"n", "i"}, "<Tab>", function() App.switch_tab(1) end, o)
  vim.keymap.set({"n", "i"}, "<S-Tab>", function() App.switch_tab(-1) end, o)
  vim.keymap.set({"n", "i"}, ")", function() App.switch_tab(1) end, o)
  vim.keymap.set({"n", "i"}, "(", function() App.switch_tab(-1) end, o)

  -- Run
  vim.keymap.set({ "n", "i" }, "<C-s>", "<cmd>w<cr>", o)
  vim.keymap.set({ "n", "i" }, "<C-CR>", App.run, o)

  -- Sidebar Toggle
  vim.keymap.set({ "n", "i" }, "<C-b>", function()
    -- Sync state with reality (if user closed it manually)
    if State.wins.side and not api.nvim_win_is_valid(State.wins.side) then
      State.side_open = false
      State.wins.side = nil
    end

    State.side_open = not State.side_open
    UI.layout()
    
    if State.side_open and State.wins.side and api.nvim_win_is_valid(State.wins.side) then
      api.nvim_set_current_win(State.wins.side)
    end
  end, o)

  -- Nav
  vim.keymap.set({ "n", "i" }, "<C-h>", function() 
    if State.wins.side and api.nvim_win_is_valid(State.wins.side) then
      api.nvim_set_current_win(State.wins.side)
    end
  end, o)
  vim.keymap.set({ "n", "i" }, "<C-l>", function() 
    local cur = api.nvim_get_current_win()
    if cur == State.wins.side then api.nvim_set_current_win(State.wins.meta)
    elseif cur == State.wins.meta or cur == State.wins.input then api.nvim_set_current_win(State.wins.resp)
    end
  end, o)
  vim.keymap.set({ "n", "i" }, "<C-k>", function() api.nvim_set_current_win(State.wins.meta) end, o)
  vim.keymap.set({ "n", "i" }, "<C-j>", function() api.nvim_set_current_win(State.wins.input) end, o)

  api.nvim_create_autocmd("BufWriteCmd", {
    buffer = b, group = AU_GROUP, callback = function() App.sync(); DB.save(); vim.bo[b].modified = false end,
  })
  if vim.bo[b].buftype == "acwrite" then
    api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      buffer = b, group = AU_GROUP, callback = App.autosave,
    })
  end
end

App.load = function(node)
  App.sync()
  local m, b, h = { "GET http://" }, { "{}" }, { "Content-Type: application/json" }
  if node and node.type == "request" then
    State.req_id = node.id
    m = node.meta or m
    b = node.body or b
    h = node.headers or h
  else
    State.req_id = nil
  end
  api.nvim_buf_set_lines(UI.buf("meta", "conf"), 0, -1, false, m)
  api.nvim_buf_set_lines(UI.buf("body", "json"), 0, -1, false, b)
  api.nvim_buf_set_lines(UI.buf("headers", "conf"), 0, -1, false, h)
  local r = UI.buf("resp", "json")
  vim.bo[r].modifiable = true
  api.nvim_buf_set_lines(r, 0, -1, false, {})
  vim.bo[r].modifiable = false
end

M.toggle = function()
  if State.active then UI.close(); return end
  State.active = true
  State.side_open = false -- Closed by default
  DB.init()

  UI.buf("side", "rest_tree", function(b)
    App.map_all(b)
    local opts = { buffer = b, silent = true }
    -- Strict Mode Side
    local banned = { "i", "a", "o", "c", "d", "x", "p", "r" } 
    for _,k in ipairs(banned) do vim.keymap.set("n", k, "<Nop>", opts) end
    
    vim.keymap.set("n", "a", function()
       local name = vim.fn.input("Create: ")
       if name ~= "" then DB.add(State.tree, name); UI.draw_side() end
    end, opts)
    vim.keymap.set("n", "d", function()
      local idx = api.nvim_win_get_cursor(0)[1]
      local it = State.flat[idx]
      if it and fn.confirm("Del?", "&Y\n&N") == 1 then
        DB.del(it.n.id); UI.draw_side()
        if State.req_id == it.n.id then App.load(nil) end
      end
    end, opts)
    vim.keymap.set("n", "<CR>", function()
      local idx = api.nvim_win_get_cursor(0)[1]
      local it = State.flat[idx]
      if it then 
        if it.n.type == "folder" then it.n.expanded = not it.n.expanded; DB.flat(); UI.draw_side()
        else App.load(it.n); if State.wins.meta then api.nvim_set_current_win(State.wins.meta) end end
      end
    end, opts)
  end)

  UI.buf("meta", "conf", function(b) App.map_all(b) end)
  UI.buf("body", "json", function(b) App.map_all(b) end)
  
  -- Headers with Smart Navigation
  UI.buf("headers", "conf", function(b) 
    App.map_all(b)
    local opts = { buffer = b, silent = true }
    
    -- Jump between Key and Value
    vim.keymap.set("i", "<Tab>", function()
      local line = api.nvim_get_current_line()
      local _, col = unpack(api.nvim_win_get_cursor(0))
      local colon = line:find(":")
      if colon and col < colon then
        api.nvim_win_set_cursor(0, {api.nvim_win_get_cursor(0)[1], colon + 1})
      else
        -- If no colon or after colon, just insert tab or move? 
        -- Let's just go to end or next line
        if not colon then api.nvim_feedkeys(": ", "n", true) end
      end
    end, opts)
    
    -- Auto-pair formatting
    vim.keymap.set("i", ":", ": ", opts)
  end)

  -- Strict Mode Resp
  UI.buf("resp", "json", function(b)
    App.map_all(b)
    local opts = { buffer = b, silent = true }
    local banned = { "i", "a", "o", "c", "d", "x", "p" } 
    for _,k in ipairs(banned) do vim.keymap.set({"n","v"}, k, "<Nop>", opts) end
  end)

  UI.layout()
  UI.draw_side()
  
  local req = State.tree[1]
  if req and req.type == "folder" and req.children then req = req.children[1] end
  if req then App.load(req) end

  -- FOCUS the meta window after layout
  if State.wins.meta and api.nvim_win_is_valid(State.wins.meta) then
    api.nvim_set_current_win(State.wins.meta)
  end
end

M.open = M.toggle
M.App = App 
return M