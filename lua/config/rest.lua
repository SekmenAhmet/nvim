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
--  3. UTILS & ROBUST OPENAPI ENGINE
-- ============================================================================

local U = {}
function U.uuid() return string.format("%x", vim.uv.hrtime()) end
function U.debounce(ms, f)
  local t = vim.uv.new_timer()
  return function(...) local a={...}; t:stop(); t:start(ms,0,vim.schedule_wrap(function() f(unpack(a)) end)) end
end

local YAML = {}

-- Helper: Count indentation spaces
local function indent_len(line) return #(line:match("^(%s*)")) end

-- Helper: Check if line is a path definition (starts with / or quote+/)
local function is_path_key(line)
  local content = vim.trim(line)
  return content:match("^['\"]?/") and content:match(":$")
end

-- Helper: Check if line is a method definition
local function is_method_key(line)
  local content = vim.trim(line)
  local m = content:match("^(%w+):")
  return m and vim.tbl_contains(Config.methods, m:upper())
end

function YAML.parse(content)
  local root_tree = {}
  local lines = vim.split(content, "\n")
  
  -- State preservation
  State.yaml_header = {}
  State.yaml_footer = {}
  State.indent_style = "  "
  
  local mode = "HEADER"
  local paths_indent = -1
  local current_full_path = nil
  local base_url = "http://localhost"

  -- Helper to find/create folder path
  local function get_target_list(tree, path_str)
    -- Remove leading slash
    local clean_path = path_str:gsub("^/", "")
    if clean_path == "" then return tree, "/" end -- Root path case
    
    local parts = vim.split(clean_path, "/")
    -- The last part is the request name itself, we only want folders for the previous parts
    -- BUT: if path is /users, parts={"users"}. We want 'users' to be the request in root.
    -- If path is /auth/login, parts={"auth", "login"}. 'auth' is folder, 'login' is request.
    
    local current_list = tree
    
    -- Iterate up to second-to-last part to create folders
    for i = 1, #parts - 1 do
      local folder_name = parts[i]
      local found = nil
      for _, node in ipairs(current_list) do
        if node.type == "folder" and node.name == folder_name then
          found = node
          break
        end
      end
      
      if not found then
        found = {
          id = U.uuid(),
          name = folder_name,
          type = "folder",
          expanded = true,
          children = {},
          variables = {}
        }
        table.insert(current_list, found)
      end
      current_list = found.children
    end
    
    return current_list, parts[#parts] -- return the list and the final name
  end

  -- First pass: Header scan
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
            
            -- Case 1: $ref
            if sub_trim:match("^%$ref:") then
               -- Handle Ref similar to request
               local target_list, final_name = get_target_list(root_tree, current_full_path)
               table.insert(target_list, {
                 id = U.uuid(),
                 name = final_name .. " [REF]",
                 type = "request",
                 meta = { "GET " .. base_url .. current_full_path, "# Ref: " .. sub_trim:match("^%$ref:%s*(.*)") },
                 body = { "{}" },
                 variables = {}
               })
            end

            -- Case 2: Method
            if is_method_key(sub) then
               local method = sub_trim:match("^(%w+)"):upper()
               
               -- Reconstruct Tree Position
               local target_list, final_name = get_target_list(root_tree, current_full_path)
               
               local req = {
                 id = U.uuid(),
                 name = final_name, -- Use the last part of path as name (e.g. 'Login')
                 type = "request",
                 meta = { method .. " " .. base_url .. current_full_path, "Content-Type: application/json" },
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
                       capturing_body = false
                       i = i - 1
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
  -- Reconstruct: Header + Generated Paths + Footer
  local lines = {}
  
  -- 1. Header
  if State.yaml_header and #State.yaml_header > 0 then
    for _, l in ipairs(State.yaml_header) do table.insert(lines, l) end
  else
    -- Fallback default header
    table.insert(lines, "openapi: 3.0.0")
    table.insert(lines, "info:")
    table.insert(lines, "  title: Generated API")
    table.insert(lines, "  version: 1.0.0")
    table.insert(lines, "paths:")
  end

  -- 2. Paths (Grouped)
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
      -- Special case: Ref
      if req.meta[2] and req.meta[2]:match("^# Ref:") then
         local ref = req.meta[2]:match("^# Ref:%s*(.*)")
         table.insert(lines, "    $ref: " .. ref)
      else
        local method = (req.meta[1] or "GET"):match("^(%a+)"):lower()
        table.insert(lines, "    " .. method .. ":")
        table.insert(lines, "      summary: " .. (req.name or "Request"))
        
        -- Serialize Body (Simplified for OpenAPI valid output)
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
  end

  -- 3. Footer
  if State.yaml_footer then
    for _, l in ipairs(State.yaml_footer) do table.insert(lines, l) end
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
  
  -- Find existing file
  local potentials = { "openapi.yaml", "openapi.yml", "swagger.yaml", "swagger.yml" }
  for _, p in ipairs(potentials) do
    if fn.filereadable(cwd .. "/" .. p) == 1 then
      State.file_path = cwd .. "/" .. p
      break
    end
  end

  local f = io.open(State.file_path, "r")
  if f then
    local content = f:read("*a")
    f:close()
    if content then
      State.tree = YAML.parse(content)
    else
      State.tree = {}
    end
  else
    -- New file init
    State.tree = {}
    State.yaml_header = { "openapi: 3.0.0", "info:", "  title: API", "  version: 1.0.0", "paths:" }
    State.yaml_footer = {}
  end
  
  DB.flat()
  
  -- Bidirectional Sync: Watch for external changes
  api.nvim_create_autocmd("BufWritePost", {
    group = AU_GROUP,
    pattern = State.file_path,
    callback = function()
      -- Eviter de recharger si c'est nous qui venons de sauvegarder (boucle)
      -- On peut utiliser un timestamp ou juste recharger, c'est rapide.
      -- Ici on recharge simplement pour être sûr.
      local current_req_id = State.req_id
      
      -- Re-read file
      local rf = io.open(State.file_path, "r")
      if rf then
        local c = rf:read("*a")
        rf:close()
        if c then
           State.tree = YAML.parse(c)
           DB.flat()
           UI.draw_side()
           -- Si la requête active existe toujours, on la recharge pour mettre à jour vars/body
           if current_req_id then
             local node = DB.find(current_req_id)
             if node then 
               App.load(node) 
             else
               -- Si elle a disparu, on charge la première dispo
               -- App.load(nil) -- ou garder l'écran actuel
             end
           end
        end
      end
    end
  })
end

function DB.save(silent) 
  if not State.tree then return end
  local content = YAML.dump(State.tree)
  local f = io.open(State.file_path, "w+")
  if f then 
    f:write(content)
    f:close()
    if not silent then
      vim.notify("Spec saved: " .. fn.fnamemodify(State.file_path, ":t"), vim.log.levels.INFO) 
    end
  else
    vim.notify("Error writing file", vim.log.levels.ERROR)
  end 
end

function DB.flat()
  State.flat = {}
  local function rec(list, depth)
    for _, n in ipairs(list) do 
      table.insert(State.flat, { n = n, d = depth }) 
      if n.type == "folder" and n.expanded and n.children then
        rec(n.children, depth + 1)
      end
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
  local is_folder = name:sub(-1) == "/"
  local clean_name = is_folder and name:sub(1, -2) or name
  
  local n = { 
    id = U.uuid(), 
    name = clean_name, 
    type = is_folder and "folder" or "request", 
    expanded = true
  }
  
  if is_folder then
    n.children = {}
  else
    n.meta = {"GET http://localhost/"..clean_name:gsub(" ","-"), "Content-Type: application/json"}
    n.body = {"{}"}
  end

  table.insert(list, n)
  DB.flat()
  return n
end

function DB.del(id)
  local function rec_del(list)
    for i, n in ipairs(list) do 
      if n.id == id then 
        table.remove(list, i)
        return true 
      end 
      if n.children then
        if rec_del(n.children) then return true end
      end
    end
  end
  
  if rec_del(State.tree) then
    DB.flat()
    return true
  end
end

function DB.vars(id)
  local v = {}
  -- 1. Global vars from YAML (if any)
  if State.yaml_header then
    for _, l in ipairs(State.yaml_header) do
      local k, val = l:match("^%s*([%w_-]+):%s*(.*)")
      if k and not vim.tbl_contains({"openapi", "info", "paths"}, k) then v[k] = val end
    end
  end
  -- 2. Request local vars
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
--  5. UI LAYER (View)
-- ============================================================================

local UI = {}
function UI.buf(k, ft, init_fn)
  if State.bufs[k] and api.nvim_buf_is_valid(State.bufs[k]) then return State.bufs[k] end
  local b = api.nvim_create_buf(false, true)
  vim.bo[b].filetype = ft
  api.nvim_buf_set_name(b, "REST_" .. k:upper())
  
  if k=="side" or k=="meta" or k=="body" or k=="vars" then 
    vim.bo[b].buftype = "acwrite" 
  else 
    vim.bo[b].buftype = "nofile" 
  end
  
  if k=="meta" or k=="body" then 
    api.nvim_buf_call(b, function() 
      vim.cmd("syn match RestVar /{{.\\{-}}}/")
      vim.cmd("hi def link RestVar "..Config.hl.var) 
    end) 
  end
  if init_fn then init_fn(b) end
  State.bufs[k] = b
  return b
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
App.autosave = U.debounce(1000, function() App.sync(); DB.save(true) end)

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
  App.sync()
  
  -- Properly kill previous job if it exists
  if State.job and not State.job:is_closing() then
    pcall(function() State.job:kill(15) end)
    State.job:close()
    State.job = nil
  end

  local n = DB.find(State.req_id)
  if not n then return end
  
  local meta = n.meta or {}
  local first_line = meta[1] or ""
  
  -- Robust URL/Method capture (supports spaces and query params)
  local m, u = first_line:match("^(%a+)%s+(.*)")
  if not m then 
    m = "GET"
    u = first_line:gsub("^%s*", "")
  end
  u = vim.trim(u)
  if u == "" then u = "http://localhost" end

  local A = { "-s", "-i", "-X", m, u }
  
  -- Headers
  for i=2,#meta do
    local h = vim.trim(meta[i])
    if h ~= "" and h:match(":") then
      table.insert(A, "-H")
      table.insert(A, h)
    end
  end

  -- Body
  local B = table.concat(n.body or {}, "\n")
  if m ~= "GET" and #B > 0 then
    table.insert(A, "-d")
    table.insert(A, B)
  end

  local br = UI.buf("resp", "json")
  vim.bo[br].modifiable = true
  api.nvim_buf_set_lines(br, 0, -1, false, { "🚀 " .. m .. " " .. u .. " ..." })
  vim.bo[br].modifiable = false

  local out, dat = vim.uv.new_pipe(false), ""
  State.job = vim.uv.spawn("curl", { args = A, stdio = { nil, out, nil } }, function(code, signal)
    if out then out:read_stop(); out:close() end
    State.job = nil
    
    vim.schedule(function()
      if not api.nvim_buf_is_valid(br) then return end
      vim.bo[br].modifiable = true
      
      if code ~= 0 then
        api.nvim_buf_set_lines(br, 0, -1, false, { "❌ Error (Exit Code: " .. code .. ")", "Signal: " .. (signal or 0) })
      elseif dat == "" then
        api.nvim_buf_set_lines(br, 0, -1, false, { "⚠️ Empty response from server" })
      else
        -- Separate headers and body safely (handle 100 Continue etc.)
        local p = vim.split(dat, "\r?\n\r?\n")
        local body_start = 2
        while p[body_start] and p[body_start-1]:match("^HTTP/%d%.%d 100") do
          body_start = body_start + 1
        end
        
        local cnt = table.concat({ unpack(p, body_start) }, "\n\n")
        
        -- Safe JQ formatting
        if fn.executable("jq") == 1 and cnt:match("%S") and cnt:match("^%s*[{%[]") then
          local j = fn.system("jq .", cnt)
          if vim.v.shell_error == 0 then cnt = j end
        end
        
        api.nvim_buf_set_lines(br, 0, -1, false, vim.split(cnt:gsub("\r", ""), "\n"))
      end
      vim.bo[br].modifiable = false
    end)
  end)
  
  if State.job then
    out:read_start(function(err, d)
      if err then return end
      if d then dat = dat .. d end
    end)
  end
end

function App.map_all(b)
  local o = { buffer=b, silent=true, nowait=true }
  vim.keymap.set("n", "<Esc>", UI.close, o); vim.keymap.set({"n","i"}, "<C-p>", UI.close, o); vim.keymap.set("n", "q", UI.close, o)
  vim.keymap.set({"n","i"}, "<C-b>", function() State.side_open = not State.side_open; UI.layout(); if State.side_open and State.wins.side then api.nvim_set_current_win(State.wins.side) end end, o)
  api.nvim_create_autocmd("BufWriteCmd", { buffer = b, group = AU_GROUP, callback = function() App.sync(); DB.save(); vim.bo[b].modified=false end })
  if vim.bo[b].buftype == "acwrite" then
    api.nvim_create_autocmd({"TextChanged", "TextChangedI"}, { buffer = b, group = AU_GROUP, callback = App.autosave })
  end
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
      local curr_line = api.nvim_win_get_cursor(0)[1]
      if curr_line ~= 1 then
        -- Comportement normal si on n'est pas sur la ligne 1 (méthode/url)
        local key = d > 0 and "<Down>" or "<Up>"
        api.nvim_feedkeys(api.nvim_replace_termcodes(key, true, false, true), "n", false)
        return
      end

      local l = api.nvim_buf_get_lines(b, 0, 1, false)[1] or ""
      local m = l:match("^(%a+)")
      local u = l:sub(#(m or "") + 1) -- Capture tout ce qui suit la méthode exactement

      if not m or not vim.tbl_contains(Config.methods, m:upper()) then
        m = "GET"
        u = " " .. l:gsub("^%s*", "")
      end

      local idx = 1
      for i, v in ipairs(Config.methods) do
        if v == m:upper() then idx = i break end
      end

      idx = (idx + d - 1) % #Config.methods + 1
      api.nvim_buf_set_lines(b, 0, 1, false, { Config.methods[idx] .. u })
      App.refresh()
    end
    vim.keymap.set({ "n", "i" }, "<Up>", function() cyc(-1) end, { buffer = b })
    vim.keymap.set({ "n", "i" }, "<Down>", function() cyc(1) end, { buffer = b })
  end)
  UI.buf("body", "json", function(b) App.map_all(b) end)
  UI.buf("resp", "json", function(b) App.map_all(b); api.nvim_create_autocmd("BufEnter", { buffer=b, callback=function() vim.cmd("stopinsert") end, group=AU_GROUP }) end)
  UI.layout(); UI.draw_side()
  local function f(l) for _,n in ipairs(l) do if n.type=="request" then return n end if n.children then local r=f(n.children) if r then return r end end end end
  App.load(DB.find(State.req_id) or f(State.tree)); if State.wins.meta then api.nvim_set_current_win(State.wins.meta) end
end

M.open = M.toggle
return M
