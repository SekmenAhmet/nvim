local state = require("core.state")
local model = require("modules.rest.model")
local view = require("modules.rest.view")
local api = vim.api
local fn = vim.fn

local M = {}

local AU_GROUP = api.nvim_create_augroup("RESTController", { clear = true })

local function debounce(ms, f)
  local t = vim.uv.new_timer()
  return function(...) 
    local a = {...}
    t:stop()
    t:start(ms, 0, vim.schedule_wrap(function() f(unpack(a)) end)) 
  end
end

function M.sync()
  local req_id = state.get("rest.req_id")
  if not req_id then return end
  local n = model.find_node(req_id)
  if not n then return end
  
  if view.components.meta and api.nvim_buf_is_valid(view.components.meta.buf) then
    n.meta = api.nvim_buf_get_lines(view.components.meta.buf, 0, -1, false)
  end
  if view.components.body and api.nvim_buf_is_valid(view.components.body.buf) then
    n.body = api.nvim_buf_get_lines(view.components.body.buf, 0, -1, false)
  end
  if view.components.headers and api.nvim_buf_is_valid(view.components.headers.buf) then
    n.headers = api.nvim_buf_get_lines(view.components.headers.buf, 0, -1, false)
  end
end

M.autosave = debounce(1000, function() 
  M.sync()
  if #model.get_tree() > 0 then model.save(true) end
end)

function M.run()
  if fn.executable("curl") == 0 then vim.notify("Curl required", vim.log.levels.ERROR); return end
  M.sync()
  
  local req_id = state.get("rest.req_id")
  local args = model.get_curl_args(req_id)
  if not args then return end
  
  state.set("rest.is_pending", true)
  state.set("rest.response_meta", { status = "Pending...", time = "0ms" })
  vim.cmd("redrawstatus")

  local br = view.components.resp.buf
  vim.bo[br].modifiable = true
  api.nvim_buf_set_lines(br, 0, -1, false, { "" })
  vim.bo[br].modifiable = false

  local start_time = vim.uv.hrtime()
  local process = require("utils.process")
  
  process.exec("curl", { args = args }, function(code, stdout_content, stderr_content)
    local end_time = vim.uv.hrtime()
    local duration = (end_time - start_time) / 1000000
    local duration_str = string.format("%.0fms", duration)
    
    state.set("rest.is_pending", false)
    if not api.nvim_buf_is_valid(br) then return end
    
    local parts = vim.split(stdout_content, "\r\n\r\n")
    local header_part = parts[1] or ""
    local body_idx = 2
    while parts[body_idx] and parts[body_idx-1]:match("^HTTP/%d%.%d 100") do 
      header_part = parts[body_idx]
      body_idx = body_idx + 1 
    end
    
    local body_cnt = table.concat({ unpack(parts, body_idx) }, "\n\n")
    local status_code = header_part:match("^(HTTP/%d%.%d %d+ [^\n]*)") or header_part:match("^(HTTP/%d%.%d %d+)") or "Unknown"
    
    state.set("rest.response_meta", { status = status_code, time = duration_str })
    state.set("rest.last_status", status_code)
    M.response_headers = vim.split(header_part, "\n")
    vim.cmd("redrawstatus")
    
    local function display(content)
      if not api.nvim_buf_is_valid(br) then return end
      vim.bo[br].modifiable = true
      api.nvim_buf_set_lines(br, 0, -1, false, vim.split(content:gsub("\r", ""), "\n"))
      vim.bo[br].modifiable = false
    end

    if fn.executable("jq") == 1 and body_cnt:match("%S") and body_cnt:match("^%s*[{%[]") then
      vim.system({ "jq", "." }, { stdin = body_cnt }, function(obj)
        vim.schedule(function()
          if obj.code == 0 then display(obj.stdout) else display(body_cnt) end
        end)
      end)
    else
      display(body_cnt)
    end
  end)
end

function M.switch_tab(dir)
  local current = state.get("rest.active_tab") or 1
  local next_idx = current + dir
  if next_idx < 1 then next_idx = 2 end
  if next_idx > 2 then next_idx = 1 end
  state.set("rest.active_tab", next_idx)
  view.layout()
end

function M.load_node(node)
  M.sync()
  local m, b, h = { "GET http://" }, { "{}" }, { "Content-Type: application/json" }
  if node and node.type == "request" then
    state.set("rest.req_id", node.id)
    m = node.meta or m
    b = node.body or b
    h = node.headers or h
  else
    state.set("rest.req_id", nil)
  end
  api.nvim_buf_set_lines(view.components.meta.buf, 0, -1, false, m)
  api.nvim_buf_set_lines(view.components.body.buf, 0, -1, false, b)
  api.nvim_buf_set_lines(view.components.headers.buf, 0, -1, false, h)
  
  local r = view.components.resp.buf
  vim.bo[r].modifiable = true
  api.nvim_buf_set_lines(r, 0, -1, false, {})
  vim.bo[r].modifiable = false
  
  view.draw_side()
end

function M.copy_as_curl()
  M.sync()
  local req_id = state.get("rest.req_id")
  local args = model.get_curl_args(req_id)
  if not args then return end
  
  local cmd = "curl"
  for _, arg in ipairs(args) do
    if arg:match("[ %c']") then
      cmd = cmd .. " " .. vim.fn.shellescape(arg)
    else
      cmd = cmd .. " " .. arg
    end
  end
  
  vim.fn.setreg("+", cmd)
  vim.notify("📋 Curl command copied to clipboard!", vim.log.levels.INFO)
end

function M.switch_env()
  local envs = { "local", "dev", "prod", "staging" }
  local current = state.get("rest.env_name") or "local"
  local current_idx = 1
  for i, e in ipairs(envs) do if e == current then current_idx = i break end end
  
  local next_idx = current_idx + 1
  if next_idx > #envs then next_idx = 1 end
  
  model.load_env(envs[next_idx], function()
    vim.notify("🚀 Switched to environment: " .. envs[next_idx], vim.log.levels.INFO)
    vim.cmd("redrawstatus")
  end)
end

function M.map_buffer(b)
  local o = { buffer = b, silent = true, nowait = true }
  vim.keymap.set({"n", "i", "v", "t"}, "<C-p>", M.close, o)
  vim.keymap.set({"n", "i", "v", "t"}, "<Esc>", M.close, o)
  vim.keymap.set("n", "q", M.close, o)
  
  vim.keymap.set({"n", "i"}, "<Tab>", function() M.switch_tab(1) end, o)
  vim.keymap.set({"n", "i"}, "<S-Tab>", function() M.switch_tab(-1) end, o)

  vim.keymap.set({ "n", "i" }, "<C-s>", "<cmd>w<cr>", o)
  vim.keymap.set({ "n", "i" }, "<C-CR>", M.run, o)
  vim.keymap.set({ "n" }, "E", M.switch_env, o)
  vim.keymap.set({ "n" }, "C", M.copy_as_curl, o)

  -- Response Toggle (Body/Headers)
  vim.keymap.set({ "n" }, "H", function()
    local br = view.components.resp.buf
    if not br or not api.nvim_buf_is_valid(br) then return end
    vim.bo[br].modifiable = true
    if M.showing_headers then
       if M.last_body then
          api.nvim_buf_set_lines(br, 0, -1, false, vim.split(M.last_body, "\n"))
          M.showing_headers = false
       end
    else
       M.last_body = table.concat(api.nvim_buf_get_lines(br, 0, -1, false), "\n")
       api.nvim_buf_set_lines(br, 0, -1, false, M.response_headers)
       M.showing_headers = true
    end
    vim.bo[br].modifiable = false
  end, o)
    
  -- Sidebar Toggle
  vim.keymap.set({ "n", "i" }, "<C-b>", function()
    local side_comp = view.components.side
    if side_comp.win and not api.nvim_win_is_valid(side_comp.win) then
      state.set("rest.side_open", false)
      side_comp.win = -1
    end

    local current = state.get("rest.side_open")
    state.set("rest.side_open", not current)
    view.layout()
    
    if not current and side_comp.win and api.nvim_win_is_valid(side_comp.win) then
      api.nvim_set_current_win(side_comp.win)
    end
  end, o)

  -- Nav
  vim.keymap.set({ "n", "i" }, "<C-h>", function() 
    if view.components.side.win and api.nvim_win_is_valid(view.components.side.win) then
      api.nvim_set_current_win(view.components.side.win)
    end
  end, o)
  
  vim.keymap.set({ "n", "i" }, "<C-l>", function() 
    local cur = api.nvim_get_current_win()
    if view.components.side.win and cur == view.components.side.win then 
      if view.wins.meta and api.nvim_win_is_valid(view.wins.meta.win) then api.nvim_set_current_win(view.wins.meta.win) end
    elseif view.wins.meta and (cur == view.wins.meta.win or (view.wins.input and cur == view.wins.input.win)) then 
      if view.wins.resp and api.nvim_win_is_valid(view.wins.resp.win) then api.nvim_set_current_win(view.wins.resp.win) end
    end
  end, o)

  vim.keymap.set({ "n", "i" }, "<C-k>", function() if view.wins.meta and api.nvim_win_is_valid(view.wins.meta.win) then api.nvim_set_current_win(view.wins.meta.win) end end, o)
  vim.keymap.set({ "n", "i" }, "<C-j>", function() if view.wins.input and api.nvim_win_is_valid(view.wins.input.win) then api.nvim_set_current_win(view.wins.input.win) end end, o)

  api.nvim_create_autocmd("BufWriteCmd", {
    buffer = b, group = AU_GROUP, callback = function() M.sync(); model.save(); vim.bo[b].modified = false end,
  })
  
  if vim.bo[b].buftype == "acwrite" then
    api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      buffer = b, group = AU_GROUP, callback = M.autosave,
    })
  end

  -- Header-specific mappings
  if b == view.components.headers.buf then
    vim.keymap.set("i", "<Tab>", function()
      local line = api.nvim_get_current_line()
      local _, col = unpack(api.nvim_win_get_cursor(0))
      local colon = line:find(":")
      if colon and col < colon then
        api.nvim_win_set_cursor(0, {api.nvim_win_get_cursor(0)[1], colon + 1})
      else
        if not colon then api.nvim_feedkeys(": ", "n", true) end
      end
    end, o)
    vim.keymap.set("i", ":", ": ", o)
  end
end

function M.toggle()
  if state.get("rest.is_active") then M.close(); return end
  
  state.set("rest.is_active", true)
  state.set("rest.side_open", false)
  
  model.init(function()
    if not state.get("rest.is_active") then return end

    local side_buf = view.components.side.buf
    M.map_buffer(side_buf)
    
    local side_opts = { buffer = side_buf, silent = true }
    vim.keymap.set("n", "a", function()
       local name = vim.fn.input("Create: ")
       if name ~= "" then model.add_node(model.get_tree(), name); view.draw_side() end
    end, side_opts)
    
    vim.keymap.set("n", "d", function()
      local idx = api.nvim_win_get_cursor(0)[1]
      local flat = model.get_flat()
      local it = flat[idx]
      if it and fn.confirm("Del?", "&Y\n&N") == 1 then
        model.delete_node(it.n.id); view.draw_side()
        if state.get("rest.req_id") == it.n.id then M.load_node(nil) end
      end
    end, side_opts)
    
    vim.keymap.set("n", "<CR>", function()
      local idx = api.nvim_win_get_cursor(0)[1]
      local flat = model.get_flat()
      local it = flat[idx]
      if it then 
        if it.n.type == "folder" then 
          it.n.expanded = not it.n.expanded
          model.flatten()
          view.draw_side()
        else 
          M.load_node(it.n)
          if view.wins.meta and api.nvim_win_is_valid(view.wins.meta.win) then 
            api.nvim_set_current_win(view.wins.meta.win) 
          end 
        end
      end
    end, side_opts)

    M.map_buffer(view.components.meta.buf)
    M.map_buffer(view.components.body.buf)
    M.map_buffer(view.components.headers.buf)
    M.map_buffer(view.components.resp.buf)

    view.layout()
    view.draw_side()
    
    local tree = model.get_tree()
    local req = tree[1]
    if req and req.type == "folder" and req.children then req = req.children[1] end
    if req then M.load_node(req) end

    if view.wins.meta and api.nvim_win_is_valid(view.wins.meta.win) then
      api.nvim_set_current_win(view.wins.meta.win)
    end
  end)
end

function M.close()
  M.sync()
  view.close()
  state.set("rest.is_active", false)
end

return M
