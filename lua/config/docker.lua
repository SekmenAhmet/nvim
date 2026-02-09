-- Native Docker Client (V10 - Anti-Freeze Edition)
local M = {}
local api = vim.api
local fn = vim.fn

local Config = {
  ui = { side_pct = 0.25, meta_pct = 0.15 },
  hl = { running = "DiagnosticOk", exited = "DiagnosticError", building = "DiagnosticWarn", border = "FloatBorder", label = "Comment" },
  icons = { running = "🟢", exited = "🔴", building = "🟠" }
}

local State = {
  active = false, active_tab = 1, containers = {}, selected_id = nil, building = {},
  wins = {}, bufs = {}, last_exec_id = nil, refresh_timer = nil, compose_file = nil
}

-- ============================================================================
--  DOCKER ENGINE
-- ============================================================================

local Docker = {}

function Docker.detect_compose()
  for _, f in ipairs({"docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml"}) do
    if fn.filereadable(fn.getcwd() .. "/" .. f) == 1 then State.compose_file = f; return end
  end
  State.compose_file = nil
end

function Docker.list(cb)
  local fmt = "{{.ID}}|{{.Names}}|{{.Image}}|{{.State}}|{{.Status}}|{{.Ports}}|{{.Labels}}"
  fn.jobstart({"docker", "ps", "-a", "--format", fmt}, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      local list = {}
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            local p = vim.split(line, "|")
            if #p >= 7 then
              local labels = {}
              for item in p[7]:gmatch("[^,]+") do
                local k, v = item:match("([^=]+)=(.*)")
                if k and v then labels[k] = v end
              end
              table.insert(list, { 
                id = p[1], name = p[2], image = p[3], state = p[4], 
                status = p[5], ports = p[6] or "", 
                service = labels["com.docker.compose.service"],
                workdir = labels["com.docker.compose.project.working_dir"]
              }) 
            end
          end
        end
      end
      State.containers = list
      if cb then cb() end
    end
  })
end

function Docker.logs(id)
  local buf = M.UI.get_buf("logs")
  if State.job_logs then fn.jobstop(State.job_logs) end
  if not api.nvim_buf_is_valid(buf) then return end
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, { " 󱎫 Streaming logs..." })
  vim.bo[buf].modifiable = false
  State.job_logs = fn.jobstart({"docker", "logs", "-f", "--tail", "50", id}, {
    on_stdout = function(_, data)
      if not api.nvim_buf_is_valid(buf) then return end
      vim.bo[buf].modifiable = true
      local clean = {}
      if data then for _, l in ipairs(data) do if l ~= "" then table.insert(clean, l) end end end
      if #clean > 0 then
        api.nvim_buf_set_lines(buf, -1, -1, false, clean)
        if State.active_tab == 1 and State.wins.main and api.nvim_win_is_valid(State.wins.main) then
          local count = api.nvim_buf_line_count(buf)
          -- Auto scroll only if we are "close" to bottom
          local curr = api.nvim_win_get_cursor(State.wins.main)[1]
          if count - curr < 50 then
             pcall(api.nvim_win_set_cursor, State.wins.main, {count, 0})
          end
        end
      end
      vim.bo[buf].modifiable = false
    end
  })
end

function Docker.exec(id)
  local buf = M.UI.get_buf("term")
  if not api.nvim_buf_is_valid(buf) then return end
  
  -- Force Tab 2
  State.active_tab = 2
  M.UI.layout()
  
  -- Spawn if new container
  if State.last_exec_id ~= id or vim.bo[buf].buftype ~= "terminal" then
    State.last_exec_id = id
    api.nvim_buf_call(buf, function()
      vim.bo[buf].modifiable = true
      vim.cmd("enew") 
      fn.termopen("docker exec -it " .. id .. " /bin/sh -c '[ -x /bin/bash ] && exec /bin/bash || exec /bin/sh'")
      pcall(api.nvim_buf_set_name, 0, "DOCKER_TERM")
      State.bufs["term"] = api.nvim_get_current_buf() -- Ref update
      M.UI.add_term_maps(State.bufs["term"])
    end)
  end
  
  -- Focus & Insert
  if State.wins.main and api.nvim_win_is_valid(State.wins.main) then
    api.nvim_set_current_win(State.wins.main)
    vim.cmd("startinsert")
  end
end

function Docker.build(id)
  local c = nil
  for _, item in ipairs(State.containers) do if item.id == id then c = item break end end
  if not c then return end
  
  State.building[id] = true
  M.UI.draw_side()
  
  local cmd = {}
  local opts = {}
  
  if c.workdir and c.service then
     cmd = {"docker", "compose", "build", c.service}
     opts.cwd = c.workdir
     vim.notify("󱐌 Magic Build: " .. c.service, vim.log.levels.INFO)
  elseif State.compose_file and c.service then
     cmd = {"docker", "compose", "build", c.service}
     vim.notify("󱐌 Local Build: " .. c.service, vim.log.levels.INFO)
  elseif fn.filereadable("Dockerfile") == 1 then
     cmd = {"docker", "build", "-t", c.image, "."}
     vim.notify("󱐌 Dockerfile Build: " .. c.image, vim.log.levels.INFO)
  else
     vim.notify("󰅚 No build config found.", vim.log.levels.ERROR)
     State.building[id] = nil
     M.UI.draw_side()
     return
  end
  
  opts.on_exit = function(_, code)
    State.building[id] = nil
    vim.schedule(function() 
      M.UI.draw_side()
      if code == 0 then vim.notify("󰄬 Build success", vim.log.levels.INFO) else vim.notify("󰅚 Build failed", vim.log.levels.ERROR) end
    end)
  end
  fn.jobstart(cmd, opts)
end

function Docker.action(a, id)
  fn.jobstart({"docker", a, id}, { on_exit = function() Docker.list(function() M.UI.draw_side(); M.UI.draw_meta() end) end })
end

-- ============================================================================
--  UI LAYER
-- ============================================================================

local UI = {}
M.UI = UI

function UI.add_term_maps(buf)
  -- Robust mappings to escape Terminal Mode properly
  local opts = { buffer = buf, silent = true }
  
  -- <C-h> escapes terminal mode AND moves window
  vim.keymap.set("t", "<C-h>", function()
    vim.cmd("stopinsert")
    if State.wins.side and api.nvim_win_is_valid(State.wins.side) then
      api.nvim_set_current_win(State.wins.side)
    end
  end, opts)
  
  -- Tab switching from terminal
  vim.keymap.set("t", "<Tab>", function()
    vim.cmd("stopinsert")
    State.active_tab = 1
    M.UI.layout()
  end, opts)
end

function UI.get_buf(name, ft)
  local n = "DOCKER_" .. name:upper()
  local b = fn.bufnr(n)
  if b == -1 or not api.nvim_buf_is_valid(b) then
    b = api.nvim_create_buf(false, true)
    pcall(api.nvim_buf_set_name, b, n)
  end
  State.bufs[name] = b
  
  if name == "term" then 
    UI.add_term_maps(b)
    return b 
  end
  
  vim.bo[b].filetype = ft or "text"
  vim.bo[b].buftype = "nofile"
  return b
end

function UI.layout()
  if not State.active then return end
  local W, H = vim.o.columns, math.max(10, vim.o.lines - 2)
  local sw, mw, mh = math.floor(W * Config.ui.side_pct), W - math.floor(W * Config.ui.side_pct), math.floor(H * Config.ui.meta_pct)

  local function win(k, b, r, c, w, h, title)
    local cfg = { relative = "editor", row = r, col = c, width = w-2, height = h-2, style = "minimal", border = "rounded", title = " " .. title .. " ", title_pos = "left" }
    if State.wins[k] and api.nvim_win_is_valid(State.wins[k]) then api.nvim_win_set_config(State.wins[k], cfg); api.nvim_win_set_buf(State.wins[k], b)
    else State.wins[k] = api.nvim_open_win(b, false, cfg); vim.wo[State.wins[k]].winhl = "Normal:Normal,FloatBorder:" .. Config.hl.border end
  end

  win("side", UI.get_buf("side", "docker_tree"), 0, 0, sw, H, "Containers")
  win("meta", UI.get_buf("meta", "docker_info"), 0, sw, mw, mh, "Details")
  
  local t1 = (State.active_tab == 1 and "󰄬" or "󰈙") .. " Logs"
  local t2 = (State.active_tab == 2 and "󰄬" or "󰆍") .. " Terminal"
  local main_buf = (State.active_tab == 1 and UI.get_buf("logs") or UI.get_buf("term"))
  win("main", main_buf, mh, sw, mw, H - mh, string.format("%s  │  %s", t1, t2))
  
  -- MAPPINGS
  for _, b in pairs(State.bufs) do
    if b ~= State.bufs.term then
      local opts = { buffer = b, silent = true }
      vim.keymap.set("n", "<C-h>", function() api.nvim_set_current_win(State.wins.side) end, opts)
      vim.keymap.set("n", "<C-l>", function() if State.wins.main then api.nvim_set_current_win(State.wins.main) end end, opts)
      vim.keymap.set("n", "<C-k>", function() if State.wins.meta then api.nvim_set_current_win(State.wins.meta) end end, opts)
      vim.keymap.set("n", "<C-j>", function() if State.wins.main then api.nvim_set_current_win(State.wins.main) end end, opts)
      vim.keymap.set("n", "<Tab>", M.switch_tab, opts)
      vim.keymap.set("n", "q", M.close, opts)
      for _, k in ipairs({"i", "a", "o", "r", "x", "d", "p"}) do vim.keymap.set("n", k, "<Nop>", opts) end
    end
  end
  
  -- Force Normal mode when entering Sidebar (Safety Net)
  api.nvim_create_autocmd("BufEnter", {
    buffer = State.bufs.side,
    callback = function() vim.cmd("stopinsert") end
  })
  
  vim.wo[State.wins.side].cursorline = true
end

function UI.draw_side()
  local b = State.bufs.side
  if not b or not api.nvim_buf_is_valid(b) then return end
  local lines, hl = {}, {}
  for i, c in ipairs(State.containers) do
    local building = State.building[c.id]
    local icon = building and Config.icons.building or (c.state:match("^Up") and Config.icons.running or Config.icons.exited)
    local color = building and Config.hl.building or (c.state:match("^Up") and Config.hl.running or Config.hl.exited)
    table.insert(lines, "  " .. icon .. " " .. c.name .. (building and " (building...)" or ""))
    table.insert(hl, { g = color, l = i-1, s = 2, e = 5 })
  end
  vim.bo[b].modifiable = true
  api.nvim_buf_set_lines(b, 0, -1, false, lines)
  vim.bo[b].modifiable = false
  api.nvim_buf_clear_namespace(b, -1, 0, -1)
  for _, h in ipairs(hl) do api.nvim_buf_add_highlight(b, -1, h.g, h.l, h.s, h.e) end
end

function UI.draw_meta()
  local b = UI.get_buf("meta")
  local c = nil
  for _, item in ipairs(State.containers) do if item.id == State.selected_id then c = item break end end
  local lines = c and { "  ID:      " .. c.id:sub(1,12), "  Service: " .. (c.service or "N/A"), "  Image:   " .. c.image, "  Status:  " .. c.status, "  Workdir: " .. (c.workdir or "N/A") } or { "  Select a container..." }
  vim.bo[b].modifiable = true
  api.nvim_buf_set_lines(b, 0, -1, false, lines)
  vim.bo[b].modifiable = false
  api.nvim_buf_clear_namespace(b, -1, 0, -1)
  for i=0, #lines-1 do api.nvim_buf_add_highlight(b, -1, Config.hl.label, i, 0, 10) end
end

function M.switch_tab()
  State.active_tab = (State.active_tab == 1) and 2 or 1
  if State.active_tab == 2 and State.selected_id then Docker.exec(State.selected_id) else UI.layout() end
end

function M.close()
  State.active = false
  if State.refresh_timer then State.refresh_timer:stop() end
  if State.job_logs then fn.jobstop(State.job_logs) end
  for _, w in pairs(State.wins) do if api.nvim_win_is_valid(w) then api.nvim_win_close(w, true) end end
  State.wins = {}
end

function M.toggle()
  if State.active then M.close(); return end
  State.active = true
  Docker.detect_compose()
  UI.layout()
  State.refresh_timer = vim.uv.new_timer()
  State.refresh_timer:start(0, 3000, vim.schedule_wrap(function() if State.active then Docker.list(function() UI.draw_side() end) end end))
  api.nvim_create_autocmd("CursorMoved", { buffer = State.bufs.side, callback = function()
    local idx = api.nvim_win_get_cursor(0)[1]
    local c = State.containers[idx]
    if c and c.id ~= State.selected_id then State.selected_id = c.id; UI.draw_meta(); if State.active_tab == 1 then Docker.logs(c.id) end end
  end })
  local sb = State.bufs.side
  vim.keymap.set("n", "<CR>", function()
    local c = State.containers[api.nvim_win_get_cursor(0)[1]]
    if c then if not c.state:match("^Up") then Docker.action("start", c.id) else Docker.logs(c.id) end end
  end, { buffer = sb, silent = true })
  vim.keymap.set("n", "s", function() if State.selected_id then Docker.action("start", State.selected_id) end end, { buffer = sb })
  vim.keymap.set("n", "x", function() if State.selected_id then Docker.action("stop", State.selected_id) end end, { buffer = sb })
  vim.keymap.set("n", "b", function() if State.selected_id then Docker.build(State.selected_id) end end, { buffer = sb })
  vim.keymap.set("n", "e", function() if State.selected_id then Docker.exec(State.selected_id) end end, { buffer = sb })
  api.nvim_set_current_win(State.wins.side)
end

return M