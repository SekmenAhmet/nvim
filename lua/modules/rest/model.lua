local state = require("core.state")
local io_utils = require("utils.io")

local M = {}

M.Config = {
  default_file = "openapi.yaml",
  methods = {
    GET = "󰖟 GET", POST = "󰐪 POST", PUT = "󰏫 PUT",
    PATCH = "󰏫 PATCH", DELETE = "󰩹 DEL", HEAD = "󰛵 HEAD", OPTIONS = "󰒓 OPT"
  }
}

-- internal local state for data that doesn't need to be in global state
local internal = {
  tree = {},
  flat = {},
  yaml_header = {},
  yaml_footer = {},
  env = {},
  file_path = nil,
}

local function uuid() return string.format("%x", vim.uv.hrtime()) end

local function indent_len(line) return #(line:match("^(%s*)")) end

local function is_path_key(line)
  local content = vim.trim(line)
  return (content:match("^/") or content:match("^['\"]/")) and content:match(":$")
end

local function is_method_key(line)
  local content = vim.trim(line)
  local m = content:match("^(%w+):")
  return m and vim.tbl_contains(vim.tbl_keys(M.Config.methods), m:upper())
end

function M.parse_yaml(content)
  local root_tree = {}
  local lines = vim.split(content, "\n")

  internal.yaml_header = {}
  internal.yaml_footer = {}

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
        found = { id = uuid(), name = folder_name, type = "folder", expanded = true, children = {}, variables = {} }
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
        table.insert(internal.yaml_header, line)
      else
        table.insert(internal.yaml_header, line)
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
                 id = uuid(),
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
      table.insert(internal.yaml_footer, line)
      i = i + 1
    end
  end
  internal.tree = root_tree
  return root_tree
end

function M.dump_yaml()
  local lines = {}
  if internal.yaml_header and #internal.yaml_header > 0 then
    for _, l in ipairs(internal.yaml_header) do table.insert(lines, l) end
  else
    table.insert(lines, "openapi: 3.0.0")
    table.insert(lines, "info:")
    table.insert(lines, "  title: Generated API")
    table.insert(lines, "  version: 1.0.0")
    table.insert(lines, "paths:")
  end

  local by_path = {}
  local function collect_reqs(list)
    for _, node in ipairs(list) do
      if node.type == "request" then
        local method, url = (node.meta[1] or ""):match("^(%a+)%s+(http%S+)")
        if not method then method = "GET"; url = node.meta[1] or "" end
        local path = url:match("^https?://[^/]+(/.*)") or url
        if not path:match("^/") then path = "/" .. path end
        if not by_path[path] then by_path[path] = {} end
        table.insert(by_path[path], node)
      elseif node.children then
        collect_reqs(node.children)
      end
    end
  end
  collect_reqs(internal.tree)

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

  if internal.yaml_footer then for _, l in ipairs(internal.yaml_footer) do table.insert(lines, l) end end
  return table.concat(lines, "\n")
end

function M.load_env(name, cb)
  name = name or state.get("rest.env_name") or "local"
  local file = name == "local" and ".env" or ("." .. name .. ".env")
  io_utils.read_file(vim.uv.cwd() .. "/" .. file, function(content)
    local env = {}
    if content then
      for line in content:gmatch("[^\n]+") do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*(.*)")
        if k and v then
          v = v:gsub("^['\"]", ""):gsub("['\"]$", "")
          env[k] = v
        end
      end
    end
    internal.env = env
    state.set("rest.env_name", name)
    if cb then cb(env) end
  end)
end

function M.init(cb)
  local cwd = vim.uv.cwd()
  internal.file_path = cwd .. "/" .. M.Config.default_file

  M.load_env(nil, function()
    local potentials = { "openapi.yaml", "openapi.yml", "swagger.yaml", "swagger.yml" }
    local function check_potentials(idx)
      if idx > #potentials then
        io_utils.read_file(internal.file_path, function(content)
          if content then M.parse_yaml(content) else internal.tree = {} end
          M.flatten()
          if cb then cb() end
        end)
        return
      end

      local p = cwd .. "/" .. potentials[idx]
      vim.uv.fs_stat(p, function(err, stat)
        if not err and stat then
          internal.file_path = p
          io_utils.read_file(internal.file_path, function(content)
            if content then M.parse_yaml(content) else internal.tree = {} end
            M.flatten()
            if cb then cb() end
          end)
        else
          check_potentials(idx + 1)
        end
      end)
    end

    check_potentials(1)
  end)
end

function M.save(silent)
  if not internal.tree then return end
  local content = M.dump_yaml()
  io_utils.write_file(internal.file_path, content, function(err)
    if err and not silent then
      vim.notify("Failed to save REST DB: " .. tostring(err), vim.log.levels.ERROR)
    end
  end)
end

function M.flatten()
  internal.flat = {}
  local function rec(list, depth)
    for _, n in ipairs(list) do
      table.insert(internal.flat, { n = n, d = depth })
      if n.type == "folder" and n.expanded and n.children then rec(n.children, depth + 1) end
    end
  end
  rec(internal.tree, 0)
  return internal.flat
end

function M.find_node(id, list)
  list = list or internal.tree
  for _, n in ipairs(list) do
    if n.id == id then return n end
    if n.children then
      local found = M.find_node(id, n.children)
      if found then return found end
    end
  end
  return nil
end

function M.add_node(list, name)
  if not vim.uv.fs_stat(internal.file_path) then M.save(true) end
  local is_folder = name:sub(-1) == "/"
  local clean_name = is_folder and name:sub(1, -2) or name
  local n = {
    id = uuid(), name = clean_name, type = is_folder and "folder" or "request", expanded = true
  }
  if is_folder then n.children = {}
  else
    n.meta = {"GET http://localhost/"..clean_name:gsub(" ","-")}
    n.headers = {"Content-Type: application/json"}
    n.body = {"{}"}
  end
  table.insert(list, n)
  M.flatten()
  return n
end

function M.delete_node(id)
  local function rec_del(list)
    for i, n in ipairs(list) do
      if n.id == id then table.remove(list, i); return true end
      if n.children then if rec_del(n.children) then return true end end
    end
  end
  if rec_del(internal.tree) then M.flatten(); return true end
end

function M.get_vars(id)
  local v = {}
  for k, val in pairs(internal.env) do v[k] = val end
  if internal.yaml_header then
    for _, l in ipairs(internal.yaml_header) do
      local k, val = l:match("^%s*([%w_-]+):%s*(.*)")
      if k and not vim.tbl_contains({"openapi", "info", "paths"}, k) then v[k] = val end
    end
  end
  local n = M.find_node(id)
  if n and n.meta then
    for _, l in ipairs(n.meta) do
      local k, val = l:match("^#%s*([%w_-]+)%s*=%s*(.*)")
      if k then v[k] = val end
    end
  end
  return v
end

function M.get_curl_args(req_id)
  local n = M.find_node(req_id)
  if not n then return nil end

  local meta = n.meta or {}
  local first_line = meta[1] or ""

  -- Vars
  local vars = M.get_vars(n.id)
  local function replace_vars(s)
    return s:gsub("{{([%w_-]+)}}", function(k) return vars[k] or "{{"..k.."}}" end)
  end
  first_line = replace_vars(first_line)

  local m, u = first_line:match("^(%a+)%s+(.*)")
  if not m then m = "GET"; u = first_line:gsub("^%s*", "") end
  u = vim.trim(u)
  if u == "" then u = "http://localhost" end

  local args = { "-s", "-i", "-X", m, u }

  -- Headers
  if n.headers then
    for _, h in ipairs(n.headers) do
      local rh = replace_vars(vim.trim(h))
      if rh ~= "" and rh:match(":") then table.insert(args, "-H"); table.insert(args, rh) end
    end
  end

  -- Body
  local B = table.concat(n.body or {}, "\n")
  B = replace_vars(B)
  if m ~= "GET" and #B > 0 then table.insert(args, "-d"); table.insert(args, B) end

  return args
end

function M.get_tree() return internal.tree end
function M.get_flat() return internal.flat end
function M.get_file_path() return internal.file_path end

return M
