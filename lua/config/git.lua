-- Native Git Dashboard v2
-- With integrated commit editor and floating log window

local M = {}
local api = vim.api
local ui = require("config.ui")

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
    commit      = "<C-CR>", -- Commit depuis le panneau commit
    generate_msg = "<Leader>g", -- Generate commit message with AI
    push        = "P",
    pull        = "p",
    refresh     = "r",
    help        = "?",
    toggle_log  = "<C-b>", -- Buffer-local only
  },
  ai = {
    ollama_url = "http://localhost:11434",
    model = "qwen2.5-coder:7b", -- ou "llama3", "codellama", etc.
    max_diff_lines = 200, -- Limite pour ne pas surcharger le contexte
  },
  layout = {
    sidebar_width = 0.35,
    heights = {
      commit = 0.20,    -- Top: commit message editor
      files = 0.50,     -- Middle: changed files
      branches = 0.30,  -- Bottom: branches
    }
  }
}

-- =============================================================================
-- 2. STATE MANAGEMENT
-- =============================================================================

local state = {
  -- Window & Buffer Handles
  bufs = { files = -1, branches = -1, commit = -1, preview = -1, help = -1, log = -1 },
  wins = { files = -1, branches = -1, commit = -1, preview = -1, help = -1, log = -1 },
  
  -- Data Models
  files = {},
  branches = {},
  commits = {},
  repo_root = nil,
  
  -- UI State
  active_pane = "files",
  is_loading = false,
  augroup = nil,
  log_visible = false,
  ollama_ready = false,
}

-- =============================================================================
-- 3. OLLAMA SETUP
-- =============================================================================

local function setup_ollama()
  if state.ollama_ready then return end
  
  -- Forward declaration
  local check_model
  
  check_model = function()
    -- Check if model is installed
    vim.system({"ollama", "list"}, { text = true }, function(obj)
      vim.schedule(function()
        if obj.code ~= 0 then
          vim.notify("Ollama not found. Install from: https://ollama.ai", vim.log.levels.WARN)
          return
        end
        
        local has_model = obj.stdout and obj.stdout:match(CONFIG.ai.model:gsub(":", "%%:"))
        
        if not has_model then
          vim.notify("Pulling AI model: " .. CONFIG.ai.model .. " (this may take a few minutes)...", vim.log.levels.INFO)
          vim.system({"ollama", "pull", CONFIG.ai.model}, { text = true }, function(pull_obj)
            vim.schedule(function()
              if pull_obj.code == 0 then
                vim.notify("✓ AI model ready: " .. CONFIG.ai.model, vim.log.levels.INFO)
                state.ollama_ready = true
              else
                vim.notify("Failed to pull model: " .. (pull_obj.stderr or ""), vim.log.levels.ERROR)
              end
            end)
          end)
        else
          state.ollama_ready = true
        end
      end)
    end)
  end
  
  -- Check if Ollama is responding
  local check_cmd = string.format("curl -s -o /dev/null -w '%%{http_code}' %s/api/tags", CONFIG.ai.ollama_url)
  
  vim.system({"sh", "-c", check_cmd}, { text = true }, function(obj)
    vim.schedule(function()
      local is_running = obj.stdout and obj.stdout:match("200")
      
      if not is_running then
        -- Try to start Ollama in background
        vim.notify("Starting Ollama server...", vim.log.levels.INFO)
        vim.system({"sh", "-c", "nohup ollama serve > /dev/null 2>&1 &"}, {}, function()
          vim.schedule(function()
            -- Wait 2 seconds for server to start
            vim.defer_fn(function()
              check_model()
            end, 2000)
          end)
        end)
      else
        check_model()
      end
    end)
  end)
end

-- =============================================================================
-- 4. UTILS & SYSTEM
-- =============================================================================

local function git(args, on_success, on_error)
  local cmd = { "git", unpack(args) }
  vim.system(cmd, { text = true, cwd = state.repo_root or vim.fn.getcwd() }, function(obj)
    if obj.code == 0 then
      if on_success then 
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
    if status_code:match("R") then 
      local arrow = path:find(" -> ")
      if arrow then path = path:sub(arrow + 4) end
    end
    local type = "modified"
    local s1, s2 = status_code:sub(1,1), status_code:sub(2,2)
    if s1 == "?" then type = "untracked"
    elseif s1 == "A" or s2 == "A" then type = "added"
    elseif s1 == "D" or s2 == "D" then type = "deleted" 
    end
    local is_staged = (s1 ~= " " and s1 ~= "?")
    local icon_data = ui.get_icon_data(path)
    table.insert(state.files, {
      path = path, status = status_code, staged = is_staged,
      type = type, icon = icon_data.icon, hl = icon_data.hl
    })
  end
end

local function parse_branches(raw)
  state.branches = {}
  local lines = vim.split(raw, "\n", { trimempty = true })
  for _, line in ipairs(lines) do
    local parts = vim.split(line, "|")
    local is_head = (parts[1] == "*")
    table.insert(state.branches, { 
      is_head = is_head, name = parts[2], remote = parts[3] or ""
    })
  end
end

local function parse_log(raw)
  state.commits = {}
  local lines = vim.split(raw, "\n", { trimempty = true })
  for _, line in ipairs(lines) do
    table.insert(state.commits, { raw_line = line })
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
      table.insert(lines, string.format(" %s %s %s %s", checkbox, file.status, file.icon, file.path))
      -- Checkbox highlight
      table.insert(hls, { group = (file.staged and "GitStatusStaged" or "GitStatusUnstaged"), line = row, col_start = 1, col_end = 4 })
      -- Status code highlight
      local status_hl = "GitStatusModified"
      if file.type == "untracked" then status_hl = "GitStatusUntracked"
      elseif file.type == "added" then status_hl = "GitStatusAdded"
      elseif file.type == "deleted" then status_hl = "GitStatusDeleted"
      end
      table.insert(hls, { group = status_hl, line = row, col_start = 5, col_end = 7 })
      -- Icon highlight
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
    local prefix = b.is_head and "* " or "  "
    local text = prefix .. b.name
    if b.remote ~= "" then text = text .. " -> " .. b.remote end
    table.insert(lines, text)
    if b.is_head then
      -- Highlight current branch
      table.insert(hls, { group = "GitBranchCurrent", line = row, col_start = 0, col_end = -1 })
    else
      -- Highlight branch name
      table.insert(hls, { group = "GitBranchLocal", line = row, col_start = 2, col_end = 2 + #b.name })
      -- Highlight remote if exists
      if b.remote ~= "" then
        table.insert(hls, { group = "GitBranchRemote", line = row, col_start = 2 + #b.name + 4, col_end = -1 })
      end
    end
  end
  set_buf(state.bufs.branches, lines, hls)
end

local function render_log()
  if not state.bufs.log or not api.nvim_buf_is_valid(state.bufs.log) then return end
  local lines = {}
  local hls = {}
  for i, c in ipairs(state.commits) do
    local line = c.raw_line
    table.insert(lines, line)
    local row = i - 1
    local hash_start, hash_end = line:find("%x%x%x%x%x%x%x+")
    if hash_start then
      if hash_start > 1 then
        table.insert(hls, { group = "GitLogGraph", line = row, col_start = 0, col_end = hash_start - 1 })
      end
      table.insert(hls, { group = "GitLogHash", line = row, col_start = hash_start - 1, col_end = hash_end })
      local ref_start, ref_end = line:find("%b()", hash_end + 1)
      if ref_start then
        table.insert(hls, { group = "GitLogRef", line = row, col_start = ref_start - 1, col_end = ref_end })
        local head_start, head_end = line:find("HEAD", ref_start, true)
        if head_start then
          table.insert(hls, { group = "GitLogHead", line = row, col_start = head_start - 1, col_end = head_end })
        end
      end
    end
  end
  if #lines == 0 then
    table.insert(lines, "  (No commits)")
  end
  set_buf(state.bufs.log, lines, #hls > 0 and hls or nil)
end

-- =============================================================================
-- 6. PREVIEW LOGIC
-- =============================================================================

local function update_preview()
  if not api.nvim_win_is_valid(state.wins.preview) then return end
  local buf = state.bufs.preview
  local pane = state.active_pane
  local cursor = api.nvim_win_get_cursor(state.wins[pane])[1]
  vim.bo[buf].filetype = ""
  
  if pane == "files" then
    local file = state.files[cursor]
    if not file then return set_buf(buf, {""}) end
    
    if file.type == "deleted" then
      -- Show file content before deletion
      local args = { "show", "HEAD:" .. file.path }
      git(args, function(out)
        if out and out:match("%S") then
          set_buf(buf, vim.split(out, "\n"))
          vim.bo[buf].filetype = vim.filetype.match({ filename = file.path }) or ""
        else
          set_buf(buf, { " [Deleted file - no content available] " })
        end
      end, function()
        set_buf(buf, { " [Deleted file] " })
      end)
    elseif file.type == "untracked" then
      if vim.fn.filereadable(file.path) == 1 then
        local content = vim.fn.readfile(file.path)
        set_buf(buf, content)
        vim.bo[buf].filetype = vim.filetype.match({ filename = file.path }) or ""
      else
         set_buf(buf, { " [Directory or Binary] " })
      end
    else
      local args = { "diff", "--color=never" }
      if file.staged then table.insert(args, "--cached") end
      table.insert(args, file.path)
      git(args, function(out)
        set_buf(buf, vim.split(out, "\n"))
        vim.bo[buf].filetype = "diff"
      end)
    end
  elseif pane == "branches" then
    local branch = state.branches[cursor]
    if not branch then return set_buf(buf, {""}) end
    git({ "log", "--oneline", "-n", "20", branch.name }, function(out)
      set_buf(buf, vim.split(out, "\n"))
      vim.bo[buf].filetype = "git"
    end)
  elseif pane == "commit" then
    -- Show staged diff in preview when in commit pane
    git({ "diff", "--cached", "--color=never" }, function(out)
      if out and out:match("%S") then
        set_buf(buf, vim.split(out, "\n"))
        vim.bo[buf].filetype = "diff"
      else
        set_buf(buf, { "  (No staged changes)" })
      end
    end)
  end
end

-- =============================================================================
-- 7. ACTIONS
-- =============================================================================

local function refresh()
  git({ "status", "--porcelain" }, function(out)
    parse_status(out)
    render_files()
    if state.active_pane == "files" then update_preview() end
  end)
  git({ "branch", "--format=%(HEAD)|%(refname:short)|%(upstream:short)" }, function(out)
    parse_branches(out)
    render_branches()
  end)
  git({ "log", "--oneline", "--graph", "--all", "--color=never", "-n", "100" }, function(out)
    parse_log(out)
    if state.log_visible then
      render_log()
    end
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

local function action_commit()
  -- Get commit message from the commit buffer
  if not state.bufs.commit or not api.nvim_buf_is_valid(state.bufs.commit) then return end
  local lines = api.nvim_buf_get_lines(state.bufs.commit, 0, -1, false)
  local msg = table.concat(lines, "\n"):gsub("^%s*", ""):gsub("%s*$", "")
  
  if msg == "" then
    vim.notify("Empty commit message", vim.log.levels.WARN)
    return
  end
  
  -- Check if there are staged changes
  local has_staged = false
  for _, f in ipairs(state.files) do
    if f.staged then has_staged = true break end
  end
  
  if not has_staged then
    vim.notify("No staged changes to commit", vim.log.levels.WARN)
    return
  end
  
  git({ "commit", "-m", msg }, function() 
    vim.notify("Committed!", vim.log.levels.INFO)
    -- Clear commit message
    api.nvim_buf_set_lines(state.bufs.commit, 0, -1, false, { "" })
    refresh() 
  end)
end

local function action_generate_commit_msg()
  if not state.bufs.commit or not api.nvim_buf_is_valid(state.bufs.commit) then return end
  
  -- Check if there are staged changes
  local has_staged = false
  for _, f in ipairs(state.files) do
    if f.staged then has_staged = true break end
  end
  
  if not has_staged then
    vim.notify("No staged changes to generate message from", vim.log.levels.WARN)
    return
  end
  
  -- Trigger setup if not done yet
  if not state.ollama_ready then
    setup_ollama()
    vim.notify("⏳ Setting up Ollama... Try again in a few seconds", vim.log.levels.INFO)
    return
  end
  
  vim.notify("🤖 Generating commit message with AI...", vim.log.levels.INFO)
  
  -- Get staged diff
  git({ "diff", "--cached", "--no-color" }, function(diff_output)
    if not diff_output or diff_output:match("^%s*$") then
      vim.notify("No diff to analyze", vim.log.levels.WARN)
      return
    end
    
    -- Limit diff size
    local diff_lines = vim.split(diff_output, "\n")
    if #diff_lines > CONFIG.ai.max_diff_lines then
      diff_lines = { unpack(diff_lines, 1, CONFIG.ai.max_diff_lines) }
      table.insert(diff_lines, "\n... (diff truncated)")
    end
    local diff = table.concat(diff_lines, "\n")
    
    -- Prepare prompt
    local prompt = [[Analyze this git diff and generate a concise, conventional commit message (50 chars max for first line).
Follow format: type(scope): description

Types: feat, fix, docs, style, refactor, test, chore
Be specific and technical. Only output the commit message, nothing else.

Diff:
]] .. diff
    
    -- Create temp file for payload (safer than shell escaping)
    local tmpfile = os.tmpname()
    local f = io.open(tmpfile, "w")
    if not f then
      vim.notify("Failed to create temp file", vim.log.levels.ERROR)
      return
    end
    
    f:write(vim.fn.json_encode({
      model = CONFIG.ai.model,
      prompt = prompt,
      stream = false,
      options = { temperature = 0.3, num_predict = 100 }
    }))
    f:close()
    
    local cmd = string.format(
      "curl -s -X POST %s/api/generate -H 'Content-Type: application/json' -d @%s",
      CONFIG.ai.ollama_url,
      tmpfile
    )
    
    vim.system({"sh", "-c", cmd}, { text = true }, function(obj)
      os.remove(tmpfile)
      
      vim.schedule(function()
        if obj.code ~= 0 then
          local err = obj.stderr or "connection failed"
          if err:match("Connection refused") or err:match("Failed to connect") then
            vim.notify("Ollama not running. Start with: ollama serve", vim.log.levels.ERROR)
          else
            vim.notify("Ollama error: " .. err, vim.log.levels.ERROR)
          end
          return
        end
        
        if not obj.stdout or obj.stdout == "" then
          vim.notify("Empty response from Ollama", vim.log.levels.ERROR)
          return
        end
        
        local ok, response = pcall(vim.fn.json_decode, obj.stdout)
        if not ok then
          vim.notify("Failed to parse Ollama response: " .. obj.stdout:sub(1, 100), vim.log.levels.ERROR)
          return
        end
        
        if response.error then
          local err_msg = response.error
          if err_msg:match("model") and err_msg:match("not found") then
            vim.notify("Model not found. Run: ollama pull " .. CONFIG.ai.model, vim.log.levels.ERROR)
          else
            vim.notify("Ollama error: " .. err_msg, vim.log.levels.ERROR)
          end
          return
        end
        
        if not response.response or response.response == "" then
          vim.notify("No commit message generated", vim.log.levels.WARN)
          return
        end
        
        local commit_msg = response.response:gsub("^%s*", ""):gsub("%s*$", "")
        
        if api.nvim_buf_is_valid(state.bufs.commit) then
          api.nvim_buf_set_lines(state.bufs.commit, 0, -1, false, vim.split(commit_msg, "\n"))
          vim.notify("✨ Commit message generated!", vim.log.levels.INFO)
        end
      end)
    end)
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

local function action_help()
  if api.nvim_win_is_valid(state.wins.help) then
    api.nvim_win_close(state.wins.help, true)
    return
  end
  
  local width = 50
  local height = 20
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
    "   C-CR         Commit (from commit pane)",
    "   Leader g     Generate commit msg (AI)",
    "   P            Push",
    "   p            Pull",
    "   S            Stage All",
    "   U            Unstage All",
    "   r            Refresh",
    "   C-b          Toggle Log Window",
    "   ?            Toggle Help",
    "   q / Esc      Close",
  }
  
  set_buf(buf, lines, {{ group = "Title", line = 0, col_start = 0, col_end = -1 }})
  vim.keymap.set("n", "q", function() api.nvim_win_close(state.wins.help, true) end, { buffer = buf })
  vim.keymap.set("n", "<Esc>", function() api.nvim_win_close(state.wins.help, true) end, { buffer = buf })
end

-- =============================================================================
-- 8. LOG WINDOW (Toggle with Ctrl+B - BUFFER LOCAL)
-- =============================================================================

local function toggle_log_window()
  if state.wins.log and api.nvim_win_is_valid(state.wins.log) then
    api.nvim_win_close(state.wins.log, true)
    state.wins.log = -1
    state.log_visible = false
    return
  end
  
  -- Create log window as floating panel on the right
  local active_win = api.nvim_get_current_win()
  local width = 60
  local height = math.floor(vim.o.lines * 0.7)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = vim.o.columns - width - 5
  
  -- Create/get buffer
  if not state.bufs.log or not api.nvim_buf_is_valid(state.bufs.log) then
    state.bufs.log = api.nvim_create_buf(false, true)
    vim.bo[state.bufs.log].bufhidden = "hide"
    vim.bo[state.bufs.log].filetype = "git"
  end
  
  state.wins.log = api.nvim_open_win(state.bufs.log, false, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Git Log ",
    title_pos = "left",
    focusable = true,
  })
  if api.nvim_win_is_valid(active_win) then
    api.nvim_set_current_win(active_win)
  end
  
  vim.wo[state.wins.log].cursorline = true
  vim.wo[state.wins.log].winhl = "NormalFloat:Normal,CursorLine:Visual"
  
  -- Buffer-local keymaps for log window
  vim.keymap.set("n", "q", toggle_log_window, { buffer = state.bufs.log, silent = true })
  vim.keymap.set("n", "<Esc>", toggle_log_window, { buffer = state.bufs.log, silent = true })
  vim.keymap.set("n", "<C-b>", toggle_log_window, { buffer = state.bufs.log, silent = true })
  local log_opts = { buffer = state.bufs.log, silent = true }
  local function focus_pane(pane, update)
    local win = state.wins[pane]
    if win and api.nvim_win_is_valid(win) then
      if pane ~= "preview" then state.active_pane = pane end
      api.nvim_set_current_win(win)
      if update then update_preview() end
    end
  end
  local function cycle_pane(reverse)
    if reverse then
      if state.active_pane == "commit" then state.active_pane = "branches"
      elseif state.active_pane == "files" then state.active_pane = "commit"
      else state.active_pane = "files" end
    else
      if state.active_pane == "commit" then state.active_pane = "files"
      elseif state.active_pane == "files" then state.active_pane = "branches"
      else state.active_pane = "commit" end
    end
    focus_pane(state.active_pane, true)
  end
  vim.keymap.set("n", CONFIG.mappings.switch_pane[1], function() cycle_pane(false) end, log_opts)
  vim.keymap.set("n", CONFIG.mappings.switch_pane[2], function() cycle_pane(true) end, log_opts)
  vim.keymap.set("n", CONFIG.mappings.nav_left, function() focus_pane("commit", true) end, log_opts)
  vim.keymap.set("n", CONFIG.mappings.nav_down, function() cycle_pane(false) end, log_opts)
  vim.keymap.set("n", CONFIG.mappings.nav_up, function() cycle_pane(true) end, log_opts)
  vim.keymap.set("n", CONFIG.mappings.nav_right, function() focus_pane("preview") end, log_opts)
  
  state.log_visible = true
  render_log()
end

-- =============================================================================
-- 9. UI INIT & EVENT LOOP
-- =============================================================================

local function switch_pane(target)
  if target then
    state.active_pane = target
  else
    -- Cycle: Commit -> Files -> Branches -> Commit
    if state.active_pane == "commit" then state.active_pane = "files"
    elseif state.active_pane == "files" then state.active_pane = "branches"
    else state.active_pane = "commit" end
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
    if type(rhs) == "string" then rhs = function() return rhs end end
    vim.keymap.set(mode, lhs, rhs, opts)
  end
  
  -- Generic (all panes)
  for _, k in ipairs(CONFIG.mappings.close) do map("n", k, M.toggle) end
  for _, k in ipairs(CONFIG.mappings.switch_pane) do map("n", k, function() switch_pane() end) end
  map("n", CONFIG.mappings.help, action_help)
  map("n", CONFIG.mappings.push, action_push)
  map("n", CONFIG.mappings.pull, action_pull)
  map("n", CONFIG.mappings.refresh, refresh)
  map("n", CONFIG.mappings.toggle_log, toggle_log_window) -- Buffer-local!
  
  -- Navigation
  map("n", CONFIG.mappings.nav_right, function() api.nvim_set_current_win(state.wins.preview) end)
  map("n", CONFIG.mappings.nav_left, function() api.nvim_set_current_win(state.wins.commit); state.active_pane = "commit" end)
  
  -- Context Specific
  if pane == "commit" then
    map("n", CONFIG.mappings.nav_down, function() switch_pane("files") end)
    -- Commit on C-CR
    map({"n", "i"}, CONFIG.mappings.commit, action_commit)
    -- Generate commit message with AI
    map({"n", "i"}, CONFIG.mappings.generate_msg, action_generate_commit_msg)
    
  elseif pane == "files" then
    for _, k in ipairs(CONFIG.mappings.action) do map("n", k, action_stage) end
    map("n", CONFIG.mappings.stage_all, action_stage_all)
    map("n", CONFIG.mappings.unstage_all, action_unstage_all)
    map("n", CONFIG.mappings.nav_up, function() switch_pane("commit") end)
    map("n", CONFIG.mappings.nav_down, function() switch_pane("branches") end)
    
  elseif pane == "branches" then
    for _, k in ipairs(CONFIG.mappings.action) do map("n", k, action_checkout) end
    map("n", CONFIG.mappings.nav_up, function() switch_pane("files") end)
  end
  
  -- Auto-update preview on move
  api.nvim_create_autocmd("CursorMoved", {
    buffer = buf,
    callback = function()
      state.active_pane = pane
      vim.defer_fn(update_preview, 5)
    end
  })
end

function M.open()
  if state.wins.files and api.nvim_win_is_valid(state.wins.files) then return end
  
  -- Setup Ollama in background on first open
  setup_ollama()
  
  -- Calculate Layout
  local total_w = vim.o.columns
  local total_h = vim.o.lines - 2
  
  local sidebar_w = math.floor(total_w * CONFIG.layout.sidebar_width)
  local preview_w = total_w - sidebar_w - 4
  
  local h_commit = math.floor(total_h * CONFIG.layout.heights.commit)
  local h_files = math.floor(total_h * CONFIG.layout.heights.files)
  local h_branches = total_h - h_commit - h_files - 6
  
  -- Create Buffers
  for name, _ in pairs(state.bufs) do
    if not api.nvim_buf_is_valid(state.bufs[name]) then
      state.bufs[name] = api.nvim_create_buf(false, true)
      vim.bo[state.bufs[name]].bufhidden = "wipe"
    end
  end
  
  -- Setup commit buffer as editable
  vim.bo[state.bufs.commit].buftype = ""
  api.nvim_buf_set_lines(state.bufs.commit, 0, -1, false, { "" })
  
  -- Set filetypes for syntax highlighting
  vim.bo[state.bufs.files].filetype = "gitstatus"
  vim.bo[state.bufs.branches].filetype = "gitbranch"
  
  -- Open Windows
  local function open_win(buf, r, c, w, h, title, focus)
    return api.nvim_open_win(buf, focus or false, {
      relative = "editor", row = r, col = c, width = w, height = h,
      style = "minimal", border = "rounded", title = " " .. title .. " "
    })
  end
  
  state.wins.commit   = open_win(state.bufs.commit,   0, 0, sidebar_w, h_commit, "Commit Message (Ctrl+Enter)", true)
  state.wins.files    = open_win(state.bufs.files,    h_commit + 2, 0, sidebar_w, h_files, "Changed Files", false)
  state.wins.branches = open_win(state.bufs.branches, h_commit + h_files + 4, 0, sidebar_w, h_branches, "Branches", false)
  state.wins.preview  = open_win(state.bufs.preview,  0, sidebar_w + 2, preview_w, total_h - 2, "Preview", false)
  
  -- Configure Windows
  for name, win in pairs(state.wins) do
    if name ~= "help" and name ~= "log" and win ~= -1 and api.nvim_win_is_valid(win) then
      vim.wo[win].cursorline = true
      vim.wo[win].winhl = "NormalFloat:Normal,CursorLine:Visual"
      if name ~= "preview" and name ~= "commit" then
        setup_buffer_maps(state.bufs[name], name)
      end
    end
  end
  
  -- Setup commit buffer maps (special handling for insert mode)
  setup_buffer_maps(state.bufs.commit, "commit")
  vim.bo[state.bufs.commit].filetype = "gitcommit"
  
  -- Focus Commit initially
  api.nvim_set_current_win(state.wins.commit)
  state.active_pane = "commit"
  
  -- Autoclose mechanism
  state.augroup = api.nvim_create_augroup("GitDashboard", { clear = true })
  api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(state.wins.commit),
    group = state.augroup,
    callback = function()
      for _, win in pairs(state.wins) do pcall(api.nvim_win_close, win, true) end
      state.log_visible = false
    end
  })
  
  refresh()
end

function M.toggle()
  if state.wins.commit and api.nvim_win_is_valid(state.wins.commit) then
    -- Close all windows
    for _, win in pairs(state.wins) do
      if win and api.nvim_win_is_valid(win) then
        api.nvim_win_close(win, true)
      end
    end
    state.wins = { files = -1, branches = -1, commit = -1, preview = -1, help = -1, log = -1 }
    state.log_visible = false
  else
    M.open()
  end
end

return M
