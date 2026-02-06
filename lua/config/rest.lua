-- Native REST Client (Gold Master OpenAPI Edition)
-- Architecture: MVC + Event Driven | Features: acwrite support, YAML Sync, Vars, completion

local M = {}
local api = vim.api
local fn = vim.fn

-- ============================================================================
--  1. CONFIG & CONSTANTS
-- ============================================================================

local Config = {
  default_file = "openapi.yaml",
  ui = { side_pct = 0.22, meta_pct = 0.30 },
  hl = { dir = "Directory", file = "Normal", method = "Function", border = "FloatBorder", var = "Special" },
  methods = { "GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS" }
}

local AU_GROUP = api.nvim_create_augroup("RESTClient", { clear = true })

-- ============================================================================
--  2. STATE STORE
-- ============================================================================

local State = {
  active = false,
  side_open = false,
  req_id = nil,
  tree = {},
  flat = {},
  bufs = {}, 
  wins = {},
  job = nil,
  file_path = nil
}

-- ============================================================================
--  3. UTILS & OPENAPI ENGINE
-- ============================================================================

local U = {}
function U.uuid() return string.format("%x", vim.uv.hrtime()) end
function U.debounce(ms, f)
  local t = vim.uv.new_timer()
  return function(...) local a={...}; t:stop(); t:start(ms,0,vim.schedule_wrap(function() f(unpack(a)) end)) end
end

-- Robust OpenAPI 3.0 Parser/Dumper (Native Lua)
local YAML = {}

-- Parse simplified OpenAPI structure
function YAML.parse(content)
  local tree = {}
  local lines = vim.split(content, "\n")
  local current_path = nil
  local current_method = nil
  local base_url = "http://localhost"
  
  -- 1. Scan for Server URL
  for _, line in ipairs(lines) do
    local url = line:match("^%s*-%s*url:%s*(.*)")
    if url then base_url = vim.trim(url); break end
  end

  local i = 1
  while i <= #lines do
    local line = lines[i]
    -- Detect Path (Indent 2 spaces: '/users':)
    local path_key = line:match("^  ['\"]?(/[%w_/%-%.]+)['\"]?:")
    
    if path_key then
      current_path = path_key
      -- Scan methods under this path
      i = i + 1
      while i <= #lines do
        local sub = lines[i]
        if not sub:match("^    ") then i = i - 1; break end -- End of path block
        
        -- Detect Method (Indent 4 spaces: get:)
        local method_key = sub:match("^    (%w+):")
        if method_key and vim.tbl_contains(Config.methods, method_key:upper()) then
          method_key = method_key:upper()
          local req = {
            id = U.uuid(),
            name = method_key .. " " .. current_path, -- Default name
            type = "request",
            meta = { method_key .. " " .. base_url .. current_path, "Content-Type: application/json" },
            body = { "{}" },
            variables = {}
          }
          
          -- Scan request details (Indent 6+ spaces)
          i = i + 1
          local body_lines = {}
          local in_body = false
          
          while i <= #lines do
            local det = lines[i]
            if not det:match("^      ") then i = i - 1; break end -- End of method block
            
            local summary = det:match("^      summary:%s*(.*)")
            if summary then req.name = vim.trim(summary) end
            
            -- Simple Body Extraction (from 'example:' or raw indentation)
            -- This is a simplified parser for the 'example' field in OpenAPI
            if det:match("^          example:") then
               in_body = true
               local first_line = det:match("^          example:%s*(.*)")
               if first_line and first_line ~= "" and first_line ~= "|" then
                 table.insert(body_lines, first_line)
               end
            elseif in_body and det:match("^            ") then
               table.insert(body_lines, det:sub(13)) -- Remove indentation
            elseif in_body and not det:match("^            ") then
               in_body = false
            end
            
            i = i + 1
          end
          
          if #body_lines > 0 then req.body = body_lines end
          table.insert(tree, req)
        else
          i = i + 1
        end
      end
    else
      i = i + 1
    end
  end
  return tree
end

function YAML.dump(tree)
  local lines = {
    "openapi: 3.0.0",
    "info:",
    "  title: API Collection",
    "  version: 1.0.0",
    "servers:",
    "  - url: http://localhost",
    "paths:"
  }

  -- Group by Path to respect OpenAPI structure
  local by_path = {}
  for _, node in ipairs(tree) do
    if node.type == "request" then
      local method, url = (node.meta[1] or ""):match("^(%a+)%s+(http%S+)")
      if not method then method = "GET"; url = node.meta[1] or "" end
      
      -- Extract path from full URL (remove http://host)
      local path = url:match("^https?://[^/]+(/.*)") or url
      if not path:match("^/") then path = "/" .. path end
      
      if not by_path[path] then by_path[path] = {} end
      table.insert(by_path[path], node)
    end
  end

  -- Sort paths
  local paths_sorted = vim.tbl_keys(by_path)
  table.sort(paths_sorted)

  for _, path in ipairs(paths_sorted) do
    table.insert(lines, "  '" .. path .. "':")
    for _, req in ipairs(by_path[path]) do
      local method = (req.meta[1] or "GET"):match("^(%a+)"):lower()
      table.insert(lines, "    " .. method .. ":")
      table.insert(lines, "      summary: " .. (req.name or "New Request"))
      
      -- Body handling (Standard OpenAPI 'requestBody')
      if req.body and #req.body > 0 and table.concat(req.body):match("%S") then
        table.insert(lines, "      requestBody:")
        table.insert(lines, "        content:")
        table.insert(lines, "          application/json:")
        table.insert(lines, "            example: |")
        for _, l in ipairs(req.body) do
          table.insert(lines, "              " .. l)
        end
      end
      
      table.insert(lines, "      responses:")
      table.insert(lines, "        '200':")
      table.insert(lines, "          description: OK")
    end
  end
  
  return table.concat(lines, "\n")
end

-- ============================================================================
--  4. DATA LAYER (DB)
-- ============================================================================

local DB = {}

function DB.init()
  local cwd = vim.uv.cwd()
  State.file_path = cwd .. "/" .. Config.default_file
  
  -- Auto-detect .yml or .yaml
  if fn.filereadable(cwd .. "/openapi.yml") == 1 then 
    State.file_path = cwd .. "/openapi.yml"
  end

  local f = io.open(State.file_path, "r")
  if f then
    local content = f:read("*a")
    f:close()
    if content and content ~= "" then
      State.tree = YAML.parse(content)
    else
      State.tree = {}
    end
  else
    State.tree = {}
  end
  
  DB.flat()
end

function DB.save() 
  if not State.tree then return end
  local content = YAML.dump(State.tree)
  
  local f = io.open(State.file_path, "w+")
  if f then 
    f:write(content)
    f:close()
    vim.notify("Spec saved: " .. fn.fnamemodify(State.file_path, ":t"), vim.log.levels.INFO) 
  else
    vim.notify("Error writing to file", vim.log.levels.ERROR)
  end 
end

function DB.flat()
  State.flat = {}
  -- Flatten logic simpler: Just list requests, folders could be added later if UI supports nesting
  -- Current YAML parser flattens everything to list of requests
  for _, n in ipairs(State.tree) do 
    table.insert(State.flat, { n = n, d = 0 }) 
  end
end

function DB.find(id)
  for _, n in ipairs(State.tree) do if n.id == id then return n end end
  return nil
end

function DB.vars(id)
  -- Simplified variables: Global + Local (merged)
  -- For now, just return empty or what's in the node
  local n = DB.find(id)
  return n and n.variables or {}
end

function DB.add(list, name)
  local n = { 
    id = U.uuid(), 
    name = name, 
    type = "request", 
    meta = {"GET http://localhost/"..name:gsub(" ","-"), "Content-Type: application/json"}, 
    body = {"{}"}, 
    variables = {} 
  }
  table.insert(State.tree, n) -- Always add to root in flat mode
  DB.flat()
  return n
end

function DB.del(id)
  for i, n in ipairs(State.tree) do 
    if n.id == id then 
      table.remove(State.tree, i)
      DB.flat()
      return true 
    end 
  end
end

-- ============================================================================
--  5. UI LAYER (View)
-- ============================================================================

local UI = {}
function UI.buf(k, ft, init_fn)
  if State.bufs[k] and api.nvim_buf_is_valid(State.bufs[k]) then return State.bufs[k] end
  local b = api.nvim_create_buf(false, true); api.nvim_buf_set_option(b, "filetype", ft)
  api.nvim_buf_set_name(b, "REST_" .. k:upper())
  if k=="side" or k=="meta" or k=="body" or k=="vars" then api.nvim_buf_set_option(b, "buftype", "acwrite") else api.nvim_buf_set_option(b, "buftype", "nofile") end
  if k=="meta" or k=="body" then api.nvim_buf_call(b, function() vim.cmd("syn match RestVar /{{.\\{-}}}/"); vim.cmd("hi def link RestVar "..Config.hl.var) end) end
  if init_fn then init_fn(b) end; State.bufs[k] = b; return b
end

function UI.draw_side()
  local b = State.bufs.side; if not b or not api.nvim_buf_is_valid(b) then return end
  local l, h = {}, {}
  for i,it in ipairs(State.flat) do
    local pre = "  "..string.rep("  ", it.d)
    local m = (it.n.meta and it.n.meta[1] or "GET"):match("^(%a+)") or "GET"
    local icon = it.n.type=="folder" and (it.n.expanded and " " or " ") or ("["..m.."] ")
    table.insert(l, "  " .. pre .. icon .. it.n.name)
    local g = it.n.type=="folder" and Config.hl.dir or Config.hl.file
    table.insert(h, {r=i-1, s=0, e=-1, g=g}); if it.n.type=="request" then table.insert(h, {r=i-1, s=#("  "..pre), e=#("  "..pre)+#icon, g=Config.hl.method}) end
  end
  vim.bo[b].modifiable=true; api.nvim_buf_set_lines(b, 0, -1, false, l); vim.bo[b].modifiable=false
  api.nvim_buf_clear_namespace(b, -1, 0, -1); for _,v in ipairs(h) do api.nvim_buf_add_highlight(b, -1, v.g, v.r, v.s, v.e) end
end

function UI.layout()
  if not State.active then return end
  local W, H = vim.o.columns, math.max(10, vim.o.lines-2)
  local sw = State.side_open and math.floor(W*Config.ui.side_pct) or 0
  local mw, ew = W-sw, math.floor((W-sw)/2); local rw = mw-ew; local mh = math.floor(H*Config.ui.meta_pct)
  local function win(k, b, r, c, w, h, t)
    if w<=1 then if State.wins[k] and api.nvim_win_is_valid(State.wins[k]) then api.nvim_win_close(State.wins[k], true) end State.wins[k]=nil return end
    local cfg = { relative="editor", row=r, col=c, width=w-2, height=h-2, style="minimal", border="rounded", title=" "..t.." ", title_pos="center" }
    if State.wins[k] and api.nvim_win_is_valid(State.wins[k]) then api.nvim_win_set_config(State.wins[k], cfg)
    else State.wins[k] = api.nvim_open_win(b, false, cfg); vim.wo[State.wins[k]].winhl = "NormalFloat:NormalFloat,FloatBorder:"..Config.hl.border end
  end
  win("side", UI.buf("side", "rest_tree"), 0, 0, sw, H, "Collection")
  win("meta", UI.buf("meta", "conf"), 0, sw, ew, mh, "Request")
  win("body", UI.buf("body", "json"), mh, sw, ew, H - mh, "Body")
  win("resp", UI.buf("resp", "json"), 0, sw + ew, rw, H, "Response")
  if State.wins.side then vim.wo[State.wins.side].cursorline=true end
  if State.wins.resp then vim.wo[State.wins.resp].wrap=true end
end

function UI.close()
  local App = require("config.rest").App; App.sync()
  for k,w in pairs(State.wins) do if w and api.nvim_win_is_valid(w) then api.nvim_win_close(w, true) end State.wins[k]=nil end
  State.active=false
end

-- ============================================================================
--  6. APP LOGIC
-- ============================================================================

local App = {}
M.App = App
App.refresh = U.debounce(200, function() if State.req_id and api.nvim_buf_is_valid(State.bufs.meta or -1) then local n = DB.find(State.req_id); if n then n.meta = api.nvim_buf_get_lines(State.bufs.meta, 0, -1, false); UI.draw_side() end end end)

function App.sync()
  if not State.req_id then return end
  local n = DB.find(State.req_id); if not n then return end
  if State.bufs.meta and api.nvim_buf_is_valid(State.bufs.meta) then n.meta = api.nvim_buf_get_lines(State.bufs.meta, 0, -1, false) end
  if State.bufs.body and api.nvim_buf_is_valid(State.bufs.body) then n.body = api.nvim_buf_get_lines(State.bufs.body, 0, -1, false) end
end

function App.load(node)
  App.sync(); local m, b = {"GET http://"}, {"{}"}
  if node and node.type=="request" then State.req_id=node.id; m=node.meta or m; b=node.body or b else State.req_id=nil end
  api.nvim_buf_set_lines(UI.buf("meta", "conf"), 0, -1, false, m)
  api.nvim_buf_set_lines(UI.buf("body", "json"), 0, -1, false, b)
  local r = UI.buf("resp", "json"); vim.bo[r].modifiable=true; api.nvim_buf_set_lines(r, 0, -1, false, {}); vim.bo[r].modifiable=false
end

function App.run()
  if fn.executable("curl") == 0 then vim.notify("Curl required", vim.log.levels.ERROR); return end
  App.sync(); if State.job and not State.job:is_closing() then State.job:close() end
  local n = DB.find(State.req_id); if not n then return end
  local v = DB.vars(n.id); local function S(s) return (s:gsub("{{(.-)}}", function(k) return v[k] or "{{"..k.."}}" end)) end
  local meta = {}; for _,l in ipairs(n.meta or {}) do table.insert(meta, S(l)) end
  local m, u = (meta[1] or ""):match("^(%a+)%s+(http%S+)"); if not m then u=(meta[1] or ""):match("(http%S+)"); m="GET" end
  if not u then return end
  local A = { "-s", "-i", "-X", m, u }; for i=2,#meta do if meta[i]:match(":") then table.insert(A, "-H"); table.insert(A, meta[i]) end end
  local B = S(table.concat(n.body or {}, "\n")); if m~="GET" and #B>0 then table.insert(A, "-d"); table.insert(A, B) end
  local br = UI.buf("resp", "json"); vim.bo[br].modifiable=true; api.nvim_buf_set_lines(br, 0, -1, false, {"Fetching..."}); vim.bo[br].modifiable=false
  local out, dat = vim.uv.new_pipe(false), ""
  State.job = vim.uv.spawn("curl", { args=A, stdio={nil,out,nil} }, function(c)
    out:read_stop(); out:close(); State.job=nil
    vim.schedule(function()
      if not api.nvim_buf_is_valid(br) then return end; vim.bo[br].modifiable=true
      if c~=0 then api.nvim_buf_set_lines(br, 0, -1, false, {"Error: "..c})
      else
        local p = vim.split(dat, "\r?\n\r?\n"); local cnt = table.concat({ unpack(p, 2) }, "\n\n")
        if fn.executable("jq")==1 and cnt:match("^%s*[{%[]") then local j=fn.system("jq .", cnt); if vim.v.shell_error==0 then cnt=j end end
        api.nvim_buf_set_lines(br, 0, -1, false, vim.split(cnt:gsub("\r",""), "\n"))
      end
      vim.bo[br].modifiable=false
    end)
  end)
  out:read_start(function(_,d) if d then dat=dat..d end end)
end

function App.edit_vars(node)
  App.sync(); local b = UI.buf("vars", "lua", function(buf) App.map_all(buf) end); api.nvim_buf_set_lines(b, 0, -1, false, {})
  local l={}; for k,v in pairs(node.variables or {}) do table.insert(l, k..' = "'..v..'"') end; api.nvim_buf_set_lines(b, 0, -1, false, l)
  local W,H = math.floor(vim.o.columns*0.4), math.floor(vim.o.lines*0.4)
  local w = api.nvim_open_win(b, true, { relative="editor", row=math.floor((vim.o.lines-H)/2), col=math.floor((vim.o.columns-W)/2), width=W, height=H, style="minimal", border="rounded", title=" Vars: "..node.name.." " })
  vim.wo[w].winhl = "NormalFloat:NormalFloat,FloatBorder:"..Config.hl.border; State.wins.vars = w
  local function sync_v()
    local nv = {}; for _,ln in ipairs(api.nvim_buf_get_lines(b, 0, -1, false)) do local k,v=ln:match('^%s*([%w_.-]+)%s*=%s*(.-)%s*$'); if k then v=v:gsub('^["\']',''):gsub('["\']$',''); nv[vim.trim(k)]=vim.trim(v) end end
    node.variables=nv; vim.bo[b].modified = false
  end
  local function cl() sync_v(); if api.nvim_win_is_valid(w) then api.nvim_win_close(w, true) end State.wins.vars=nil end
  vim.keymap.set("n", "<Esc>", cl, {buffer=b, silent=true}); vim.keymap.set("n", "q", cl, {buffer=b, silent=true})
  api.nvim_create_autocmd("BufWriteCmd", { buffer=b, group=AU_GROUP, callback=function() sync_v(); DB.save() end })
end

function App.map_all(b)
  local o = { buffer=b, silent=true, nowait=true }
  vim.keymap.set("n", "<Esc>", UI.close, o); vim.keymap.set({"n","i"}, "<C-p>", UI.close, o); vim.keymap.set("n", "q", UI.close, o)
  vim.keymap.set({"n","i"}, "<C-b>", function() State.side_open = not State.side_open; UI.layout(); if State.side_open and State.wins.side then api.nvim_set_current_win(State.wins.side) end end, o)
  api.nvim_create_autocmd("BufWriteCmd", { buffer = b, group = AU_GROUP, callback = function() App.sync(); DB.save(); vim.bo[b].modified=false end })
  vim.keymap.set({"n","i"}, "<C-s>", "<cmd>w<cr>", o)
  vim.keymap.set({"n","i"}, "<C-CR>", App.run, o); vim.keymap.set({"n","i"}, "<C-Enter>", App.run, o)
  vim.keymap.set({"n","i"}, "<C-h>", function() 
    if State.wins.side and api.nvim_win_is_valid(State.wins.side) then api.nvim_set_current_win(State.wins.side)
    elseif api.nvim_get_current_win() == State.wins.resp then api.nvim_set_current_win(State.wins.meta) end
  end, o)
  vim.keymap.set({"n","i"}, "<C-l>", function() 
    local cur = api.nvim_get_current_win()
    if cur == State.wins.side then
      if State.wins.meta and api.nvim_win_is_valid(State.wins.meta) then api.nvim_set_current_win(State.wins.meta) end
    elseif cur == State.wins.meta or cur == State.wins.body then
      if State.wins.resp and api.nvim_win_is_valid(State.wins.resp) then api.nvim_set_current_win(State.wins.resp) end
    end
  end, o)
  vim.keymap.set({"n","i"}, "<C-j>", function() if State.wins.body and api.nvim_win_is_valid(State.wins.body) then api.nvim_set_current_win(State.wins.body) end end, o)
  vim.keymap.set({"n","i"}, "<C-k>", function() if State.wins.meta and api.nvim_win_is_valid(State.wins.meta) then api.nvim_set_current_win(State.wins.meta) end end, o)
end

function M.comp(f, b)
  if f == 1 then local l=api.nvim_get_current_line(); local c=api.nvim_win_get_cursor(0)[2]; local s=l:sub(1,c):find("{{[^}]*$"); return s and s-1 or -1 end
  local v, r = DB.vars(State.req_id or ""), {}; for k,val in pairs(v) do if k:find("^"..b) then table.insert(r, {word=k.."}}", abbr=k, menu=" ["..val.."]"}) end end return r
end

function M.toggle()
  if State.active then local v=false; for _,w in pairs(State.wins) do if w and api.nvim_win_is_valid(w) then v = true end end; if v then UI.close(); return end end
  State.active = true; State.side_open = false; DB.init()
  UI.buf("side", "rest_tree", function(b)
    App.map_all(b); local o={buffer=b, silent=true, nowait=true}
    vim.keymap.set("n", "a", function() local idx = api.nvim_win_get_cursor(0)[1]; local it = State.flat[idx]; local list = (it and it.n.type=="folder") and it.n.children or State.tree; vim.ui.input({prompt="Create:"}, function(x) if x and x~="" then local n=DB.add(list, x); UI.draw_side(); if n.type=="request" then App.load(n); if State.wins.meta then api.nvim_set_current_win(State.wins.meta) end end end end) end, o)
    vim.keymap.set("n", "v", function() local idx = api.nvim_win_get_cursor(0)[1]; local it = State.flat[idx]; if it and it.n.type=="folder" then App.edit_vars(it.n) end end, o)
    vim.keymap.set("n", "d", function() local idx = api.nvim_win_get_cursor(0)[1]; local it = State.flat[idx]; if it and fn.confirm("Del?", "&Y\n&N")==1 then DB.del(it.n.id); UI.draw_side(); if State.req_id==it.n.id then App.load(nil) end end end, o)
    vim.keymap.set("n", "<CR>", function() local idx = api.nvim_win_get_cursor(0)[1]; local it = State.flat[idx]; if not it then return end if it.n.type=="folder" then it.n.expanded=not it.n.expanded; DB.flat(); UI.draw_side() else App.load(it.n); if State.wins.meta then api.nvim_set_current_win(State.wins.meta) end end end, {buffer=b, silent=true})
    for _,k in ipairs({"i","o","I","O"}) do vim.keymap.set("n", k, "<Nop>", o) end
    api.nvim_create_autocmd("BufEnter", { buffer=b, callback=function() vim.cmd("stopinsert") end, group=AU_GROUP })
  end)
  local bm = UI.buf("meta", "conf", function(b)
    App.map_all(b); api.nvim_create_autocmd({"TextChanged","TextChangedI"}, { buffer=b, callback=App.refresh, group=AU_GROUP })
    vim.bo[b].completefunc = "v:lua.require'config.rest'.comp"
    vim.keymap.set("i", "{", function() if api.nvim_get_current_line():sub(api.nvim_win_get_cursor(0)[2], api.nvim_win_get_cursor(0)[2])=="{" then vim.schedule(function() api.nvim_feedkeys(api.nvim_replace_termcodes("<C-x><C-u>", true, false, true), "n", true) end) end return "{" end, {buffer=b, expr=true})
    local function cyc(d)
      local l=api.nvim_buf_get_lines(b, 0, 1, false)[1] or ""; local m,u=l:match("^(%a+)%s+(.*)"); if not m then m="GET"; u=l:gsub("^%s*","") end
      local idx=1; for i,v in ipairs(Config.methods) do if v==m:upper() then idx=i break end end; idx=(idx+d-1)%#Config.methods+1; api.nvim_buf_set_lines(b, 0, 1, false, {Config.methods[idx].." "..u}); App.refresh()
    end
    vim.keymap.set({"n","i"}, "<Up>", function() cyc(-1) end, {buffer=b}); vim.keymap.set({"n","i"}, "<Down>", function() cyc(1) end, {buffer=b})
  end)
  UI.buf("body", "json", function(b) App.map_all(b) end)
  UI.buf("resp", "json", function(b) App.map_all(b); api.nvim_create_autocmd("BufEnter", { buffer=b, callback=function() vim.cmd("stopinsert") end, group=AU_GROUP }) end)
  UI.layout(); UI.draw_side()
  local function f(l) for _,n in ipairs(l) do if n.type=="request" then return n end if n.children then local r=f(n.children) if r then return r end end end end
  App.load(DB.find(State.req_id) or f(State.tree)); if State.wins.meta then api.nvim_set_current_win(State.wins.meta) end
end

M.open = M.toggle
return M
