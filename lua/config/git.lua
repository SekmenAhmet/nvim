-- Native Git Dashboard
-- Clean, fast, and feature-rich.

local M = {}
local api = vim.api
local ui = require("config.ui") -- Icons

-- =============================================================================
-- 1. CONFIGURATION & CONSTANTS
-- =============================================================================

local CONFIG = {
  mappings = {
    close       = { "q", "<Esc>" },
    switch_pane = { "<Tab>", "<S-Tab>" },
    nav_left    = "<C-h>",
    nav_down    = "<C-j>",
    nav_up      = "<C-k>",
    nav_right   = "<C-l>",
    action      = { "<Space>", "<CR>" },
    stage_all   = "S",
    unstage_all = "U",
    commit      = "c",
    push        = "P",
    pull        = "p",
    refresh     = "r",
    help        = "?",
  },
  layout = {
    sidebar_width = 0.35, -- Percentage
    heights = {
      files = 0.4,    -- Percentage of vertical space for files
      branches = 0.25, -- Percentage for branches
      -- Log takes the rest
    }
  }
}

-- =============================================================================
-- 2. STATE MANAGEMENT
-- =============================================================================

local state = {
  -- Window & Buffer Handles
  bufs = { files = -1, branches = -1, log = -1, preview = -1, help = -1 },
  wins = { files = -1, branches = -1, log = -1, preview = -1, help = -1 },
  
  -- Data Models
  files = {},     -- List of { path, status, staged, type, icon, hl }
  branches = {},  -- List of { name, is_head, remote }
  commits = {},   -- List of { raw_line, hash, subject }
  repo_root = nil,
  
  -- UI State
  active_pane = "files",
  is_loading = false,
  augroup = nil,
}

-- =============================================================================
-- 3. UTILS & SYSTEM
-- =============================================================================

-- Async Git Wrapper using vim.system (Native, Fast)
local function git(args, on_success, on_error)
  local cmd = { "git", unpack(args) }
  
  -- Add standard arguments to avoid pagers or colors messing up parsing
  -- (Though some commands need specific flags like --color=never)
  
  vim.system(cmd, { text = true, cwd = state.repo_root or vim.fn.getcwd() }, function(obj)
    if obj.code == 0 then
      if on_success then 
        -- Schedule callback on main thread to allow UI updates
        vim.schedule(function() on_success(obj.stdout) end)
      end
    else
      if on_error then
        vim.schedule(function() on_error(obj.stderr) end)
      else
        vim.schedule(function() 
          vim.notify("Git Error: " .. (obj.stderr or ""), vim.log.levels.ERROR) 
        end)
      end
    end
  end)
end

-- Helper to set buffer content safely
local function set_buf(buf, lines, highlights)
  if not api.nvim_buf_is_valid(buf) then return end
  
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  
  api.nvim_buf_clear_namespace(buf, -1, 0, -1)
  if highlights then
    for _, hl in ipairs(highlights) do
      api.nvim_buf_add_highlight(buf, -1, hl.group, hl.line, hl.col_start, hl.col_end)
    end
  end
end

-- =============================================================================
-- 4. DATA PARSING
-- =============================================================================

local function parse_status(raw)
  state.files = {}
  local lines = vim.split(raw, "\n", { trimempty = true })
  
  for _, line in ipairs(lines) do
    local status_code = line:sub(1, 2)
    local path = line:sub(4)
    
    -- Handle renames "R  old -> new"
    if status_code:match("R") then 
      local arrow = path:find(" -> ")
      if arrow then path = path:sub(arrow + 4) end
    end
    
    -- Determine Type & Staged status
    local type = "modified"
    local s1, s2 = status_code:sub(1,1), status_code:sub(2,2)
    
    if s1 == "?" then type = "untracked"
    elseif s1 == "A" or s2 == "A" then type = "added"
    elseif s1 == "D" or s2 == "D" then type = "deleted" 
    end
    
    local is_staged = (s1 ~= " " and s1 ~= "?")
    local icon_data = ui.get_icon_data(path)
    
    table.insert(state.files, {
      path = path,
      status = status_code,
      staged = is_staged,
      type = type,
      icon = icon_data.icon,
      hl = icon_data.hl
    })
  end
end

local function parse_branches(raw)
  state.branches = {}
  local lines = vim.split(raw, "\n", { trimempty = true })
  for _, line in ipairs(lines) do
    -- Format: %(HEAD)|%(refname:short)|%(upstream:short)
    local parts = vim.split(line, "|")
    local is_head = (parts[1] == "*")
    local name = parts[2]
    local remote = parts[3] or ""
    
    table.insert(state.branches, { 
      is_head = is_head, 
      name = name,
      remote = remote
    })
  end
end

local function parse_log(raw)
  state.commits = {}
  local lines = vim.split(raw, "\n", { trimempty = true })
  
  for _, line in ipairs(lines) do
    local commit = { raw_line = line, hash = nil, graph = "", msg = "" }
    
    -- Try to find our custom markers
    local s_hash, e_hash = line:find("_H_.-_M_")
    
    if s_hash and e_hash then
      -- It's a commit line
      commit.hash = line:sub(s_hash + 3, e_hash - 3)
      commit.graph = line:sub(1, s_hash - 1)
      commit.msg = line:sub(e_hash + 3)
      commit.raw_line = commit.graph .. commit.msg -- Only graph and message
    else
      -- It's a pure graph line (routing)
      commit.graph = line
      commit.raw_line = line
    end
    
    table.insert(state.commits, commit)
  end
end

-- =============================================================================
-- 5. RENDERING
-- =============================================================================

local function render_files()
  local lines = {}
  local hls = {}
  
  if #state.files == 0 then
    table.insert(lines, "  (No changes - Clean)")
    table.insert(hls, { group = "Comment", line = 0, col_start = 0, col_end = -1 })
  else
    for i, file in ipairs(state.files) do
      local checkbox = file.staged and "[x]" or "[ ]"
      local row = i - 1
      
      -- Line Format: [x] XY Icon Filename
      table.insert(lines, string.format(" %s %s %s %s", checkbox, file.status, file.icon, file.path))
      
      -- Checkbox color
      table.insert(hls, { group = (file.staged and "String" or "Comment"), line = row, col_start = 1, col_end = 4 })
      -- Status code color
      table.insert(hls, { group = (file.type == "untracked" and "ErrorMsg" or "WarningMsg"), line = row, col_start = 5, col_end = 7 })
      -- Icon color
      table.insert(hls, { group = file.hl, line = row, col_start = 8, col_end = 8 + #file.icon })
    end
  end
  
  set_buf(state.bufs.files, lines, hls)
end

local function render_branches()
  local lines = {}
  local hls = {}
  
  for i, b in ipairs(state.branches) do
    local row = i - 1
    local prefix = b.is_head and " * " or "   "
    local text = prefix .. b.name
    if b.remote ~= "" then text = text .. " -> " .. b.remote end
    
    table.insert(lines, text)
    
    if b.is_head then
      table.insert(hls, { group = "String", line = row, col_start = 0, col_end = -1 })
    end
  end
  set_buf(state.bufs.branches, lines, hls)
end

local function render_log()
  local lines = {}
  local hls = {}
  
  for i, c in ipairs(state.commits) do
    local row = i - 1
    table.insert(lines, c.raw_line)
    
    -- 1. Highlight Graph Characters
    local graph_len = #c.graph
    if graph_len > 0 then
      table.insert(hls, { group = "Special", line = row, col_start = 0, col_end = graph_len })
      
      local s_star, e_star = c.graph:find("%*")
      if s_star then
         table.insert(hls, { group = "Error", line = row, col_start = s_star - 1, col_end = e_star })
      end
    end
    
    -- 2. Highlight Decorations/Refs (HEAD -> ...) - Adjusted for removed hash
    if c.hash then
      local s_ref, e_ref = c.msg:find("%(.-%)")
      if s_ref then
        local ref_start = graph_len + s_ref - 1
        local ref_end = graph_len + e_ref
        table.insert(hls, { group = "String", line = row, col_start = ref_start, col_end = ref_end })
      end
    end
  end
  set_buf(state.bufs.log, lines, hls)
end

-- =============================================================================
-- 6. PREVIEW LOGIC
-- =============================================================================

local function update_preview()
  if not api.nvim_win_is_valid(state.wins.preview) then return end
  local buf = state.bufs.preview
  local pane = state.active_pane
  local cursor = api.nvim_win_get_cursor(state.wins[pane])[1]
  
  -- Clear
  vim.bo[buf].filetype = ""
  
  if pane == "files" then
    local file = state.files[cursor]
    if not file then return set_buf(buf, {""}) end
    
    if file.type == "untracked" then
      -- Show file content
      if vim.fn.filereadable(file.path) == 1 then
        local content = vim.fn.readfile(file.path)
        set_buf(buf, content)
        vim.bo[buf].filetype = vim.filetype.match({ filename = file.path }) or ""
      else
         set_buf(buf, { " [Directory or Binary] " })
      end
    else
      -- Show diff
      local args = { "diff", "--color=never" }
      if file.staged then table.insert(args, "--cached") end
      table.insert(args, file.path)
      
      git(args, function(out)
        set_buf(buf, vim.split(out, "\n"))
        vim.bo[buf].filetype = "diff"
      end)
    end
    
  elseif pane == "log" then
    local commit = state.commits[cursor]
    if not commit then return set_buf(buf, {""}) end
    
    git({ "show", "--color=never", commit.hash }, function(out)
      set_buf(buf, vim.split(out, "\n"))
      vim.bo[buf].filetype = "diff"
    end)
    
  elseif pane == "branches" then
    local branch = state.branches[cursor]
    if not branch then return set_buf(buf, {""}) end
    
    git({ "log", "--oneline", "-n", "20", branch.name }, function(out)
      set_buf(buf, vim.split(out, "\n"))
      vim.bo[buf].filetype = "git"
    end)
  end
end

-- =============================================================================
-- 7. ACTIONS
-- =============================================================================

local function refresh()
  -- Parallel Fetching
  
  -- 1. Status
  git({ "status", "--porcelain" }, function(out)
    parse_status(out)
    render_files()
    -- Update preview if on files pane
    if state.active_pane == "files" then update_preview() end
  end)
  
  -- 2. Branches
  git({ "branch", "--format=%(HEAD)|%(refname:short)|%(upstream:short)" }, function(out)
    parse_branches(out)
    render_branches()
  end)
  
  -- 3. Log (Full Graph)
  git({ "log", "--graph", "--all", "--color=never", "--pretty=format:_H_%H_M_ %d %s", "-n", "200" }, function(out)
    parse_log(out)
    render_log()
  end)
end

local function action_stage()
  local idx = api.nvim_win_get_cursor(state.wins.files)[1]
  local file = state.files[idx]
  if not file then return end
  
  local cmd = file.staged and "reset" or "add"
  git({ cmd, file.path }, function() refresh() end)
end

local function action_stage_all()
  git({ "add", "." }, function() refresh() end)
end

local function action_unstage_all()
  git({ "reset" }, function() refresh() end)
end

local function action_checkout()
  local idx = api.nvim_win_get_cursor(state.wins.branches)[1]
  local branch = state.branches[idx]
  if not branch then return end
  
  vim.notify("Checking out " .. branch.name .. "...", vim.log.levels.INFO)
  git({ "checkout", branch.name }, function() 
    vim.notify("Switched to " .. branch.name, vim.log.levels.INFO)
    refresh() 
  end)
end

local function action_push()
  vim.notify("Git Push...", vim.log.levels.INFO)
  git({ "push" }, 
    function() vim.notify("Push Successful!", vim.log.levels.INFO); refresh() end,
    function(err) vim.notify("Push Failed:\n" .. err, vim.log.levels.ERROR) end
  )
end

local function action_pull()
  vim.notify("Git Pull...", vim.log.levels.INFO)
  git({ "pull" }, 
    function() vim.notify("Pull Successful!", vim.log.levels.INFO); refresh() end,
    function(err) vim.notify("Pull Failed:\n" .. err, vim.log.levels.ERROR) end
  )
end

local function action_commit()
  -- Simple Float Input
  local buf, win = ui.select({}, { prompt = "Commit Message" }) -- Reusing create_win helper from UI implicitly via structure, but better to implement custom here
  
  -- Using a custom simple window instead of ui.select for text input
  local width = 60
  local height = 10
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  
  local c_buf = api.nvim_create_buf(false, true)
  local c_win = api.nvim_open_win(c_buf, true, {
    relative = "editor", width = width, height = height, row = row, col = col,
    style = "minimal", border = "rounded", title = " Commit Message (Ctrl+Enter) ", title_pos = "left"
  })
  
  vim.bo[c_buf].filetype = "gitcommit"
  vim.cmd("startinsert")
  
  vim.keymap.set({"i", "n"}, "<C-CR>", function()
    local lines = api.nvim_buf_get_lines(c_buf, 0, -1, false)
    local msg = table.concat(lines, "\n")
    if msg:gsub("%s", "") == "" then return end
    
    api.nvim_win_close(c_win, true)
    git({ "commit", "-m", msg }, function() 
      vim.notify("Committed.", vim.log.levels.INFO)
      refresh() 
    end)
  end, { buffer = c_buf })
  
  vim.keymap.set("n", "<Esc>", function() api.nvim_win_close(c_win, true) end, { buffer = c_buf })
end

local function action_help()
  if api.nvim_win_is_valid(state.wins.help) then
    api.nvim_win_close(state.wins.help, true)
    return
  end
  
  local width = 50
  local height = 15
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  
  local buf = api.nvim_create_buf(false, true)
  state.wins.help = api.nvim_open_win(buf, true, {
    relative = "editor", width = width, height = height, row = row, col = col,
    style = "minimal", border = "rounded", title = " Help ", zindex = 100
  })
  
  local lines = {
    " Navigation:",
    "   Tab / S-Tab  Switch Panes",
    "   h/j/k/l      Navigate",
    "",
    " Actions:",
    "   Space / CR   Stage/Checkout",
    "   c            Commit",
    "   P            Push",
    "   p            Pull",
    "   S            Stage All",
    "   U            Unstage All",
    "   r            Refresh",
    "   ?            Toggle Help",
    "   q / Esc      Close",
  }
  
  set_buf(buf, lines, {{ group = "Title", line = 0, col_start = 0, col_end = -1 }})
  vim.keymap.set("n", "q", function() api.nvim_win_close(state.wins.help, true) end, { buffer = buf })
  vim.keymap.set("n", "<Esc>", function() api.nvim_win_close(state.wins.help, true) end, { buffer = buf })
end

-- =============================================================================
-- 8. UI INIT & EVENT LOOP
-- =============================================================================

local function switch_pane(target)
  if target then
    state.active_pane = target
  else
    -- Cycle: Files -> Branches -> Log -> Files
    if state.active_pane == "files" then state.active_pane = "branches"
    elseif state.active_pane == "branches" then state.active_pane = "log"
    else state.active_pane = "files" end
  end
  
  local win = state.wins[state.active_pane]
  if api.nvim_win_is_valid(win) then
    api.nvim_set_current_win(win)
    update_preview()
  end
end

local function setup_buffer_maps(buf, pane)
  local opts = { buffer = buf, silent = true }
  
  local function map(mode, lhs, rhs)
    if type(rhs) == "string" then rhs = function() return rhs end end -- Handle strings if needed, but mostly funcs
    vim.keymap.set(mode, lhs, rhs, opts)
  end
  
  -- Generic
  for _, k in ipairs(CONFIG.mappings.close) do map("n", k, M.toggle) end
  for _, k in ipairs(CONFIG.mappings.switch_pane) do map("n", k, function() switch_pane() end) end
  map("n", CONFIG.mappings.help, action_help)
  map("n", CONFIG.mappings.commit, action_commit)
  map("n", CONFIG.mappings.push, action_push)
  map("n", CONFIG.mappings.pull, action_pull)
  map("n", CONFIG.mappings.refresh, refresh)
  
  -- Navigation
  map("n", CONFIG.mappings.nav_right, function() api.nvim_set_current_win(state.wins.preview) end)
  map("n", CONFIG.mappings.nav_left, function() api.nvim_set_current_win(state.wins.files); state.active_pane = "files" end)
  
  -- Context Specific
  if pane == "files" then
    for _, k in ipairs(CONFIG.mappings.action) do map("n", k, action_stage) end
    map("n", CONFIG.mappings.stage_all, action_stage_all)
    map("n", CONFIG.mappings.unstage_all, action_unstage_all)
    map("n", CONFIG.mappings.nav_down, function() switch_pane("branches") end)
    
  elseif pane == "branches" then
    for _, k in ipairs(CONFIG.mappings.action) do map("n", k, action_checkout) end
    map("n", CONFIG.mappings.nav_up, function() switch_pane("files") end)
    map("n", CONFIG.mappings.nav_down, function() switch_pane("log") end)
    
  elseif pane == "log" then
    map("n", CONFIG.mappings.nav_up, function() switch_pane("branches") end)
  end
  
  -- Auto-update preview on move
  api.nvim_create_autocmd("CursorMoved", {
    buffer = buf,
    callback = function()
      state.active_pane = pane
      -- Simple debounce: wait 5ms
      vim.defer_fn(update_preview, 5)
    end
  })
end

function M.open()
  if state.wins.files and api.nvim_win_is_valid(state.wins.files) then return end
  
  -- Calculate Layout
  local total_w = vim.o.columns
  local total_h = vim.o.lines - 2 -- Reserve space for statusline/cmdline
  
  local sidebar_w = math.floor(total_w * CONFIG.layout.sidebar_width)
  local preview_w = total_w - sidebar_w - 4 -- Adjust for borders (2 for sidebar + 2 for preview)
  
  local h_files = math.floor(total_h * CONFIG.layout.heights.files)
  local h_branches = math.floor(total_h * CONFIG.layout.heights.branches)
  local h_log = total_h - h_files - h_branches - 6 -- Adjust for borders between vertical panes
  
  -- Create Buffers
  for name, _ in pairs(state.bufs) do
    if not api.nvim_buf_is_valid(state.bufs[name]) then
      state.bufs[name] = api.nvim_create_buf(false, true)
      vim.bo[state.bufs[name]].bufhidden = "wipe"
    end
  end
  
  -- Open Windows
  local function open_win(buf, r, c, w, h, title)
    return api.nvim_open_win(buf, true, {
      relative = "editor", row = r, col = c, width = w, height = h,
      style = "minimal", border = "rounded", title = " " .. title .. " "
    })
  end
  
  state.wins.files    = open_win(state.bufs.files,    0, 0, sidebar_w, h_files, "Changed Files")
  state.wins.branches = open_win(state.bufs.branches, h_files + 2, 0, sidebar_w, h_branches, "Branches")
  state.wins.log      = open_win(state.bufs.log,      h_files + h_branches + 4, 0, sidebar_w, h_log, "Git Log")
  state.wins.preview  = open_win(state.bufs.preview,  0, sidebar_w + 2, preview_w, total_h - 2, "Preview")
  
  -- Configure Windows
  for name, win in pairs(state.wins) do
    if name ~= "help" then
      vim.wo[win].cursorline = true
      vim.wo[win].winhl = "NormalFloat:Normal,CursorLine:Visual"
      if name ~= "preview" then setup_buffer_maps(state.bufs[name], name) end
    end
  end
  
  -- Focus Files initially
  api.nvim_set_current_win(state.wins.files)
  state.active_pane = "files"
  
  -- Autoclose mechanism
  state.augroup = api.nvim_create_augroup("GitDashboard", { clear = true })
  api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(state.wins.files),
    group = state.augroup,
    callback = function()
      for _, win in pairs(state.wins) do pcall(api.nvim_win_close, win, true) end
    end
  })
  
  refresh()
end

function M.toggle()
  if state.wins.files and api.nvim_win_is_valid(state.wins.files) then
    api.nvim_win_close(state.wins.files, true)
  else
    M.open()
  end
end

return M