local api = vim.api
local State = require("core.state")
local ui_utils = require("utils.ui")
local icons = require("utils.icons")
local ViewFactory = require("utils.view_factory")

local M = {}

M.wins = { commit = -1, files = -1, branches = -1, stashes = -1, preview = -1, log = -1, help = -1 }

M.components = {
  commit   = ViewFactory.create_component("GIT_COMMIT",   { filetype = "gitcommit" }),
  files    = ViewFactory.create_component("GIT_FILES",    { filetype = "gitstatus" }),
  branches = ViewFactory.create_component("GIT_BRANCHES", { filetype = "gitbranch" }),
  stashes  = ViewFactory.create_component("GIT_STASHES",  { filetype = "git" }),
  preview  = ViewFactory.create_component("GIT_PREVIEW",  { filetype = "diff" }),
  log      = ViewFactory.create_component("GIT_LOG",      { filetype = "git" }),
  help     = ViewFactory.create_component("GIT_HELP",     { filetype = "markdown" })
}

local Config = {
  layout = {
    sidebar_width = 0.35,
    heights = {
      commit = 0.15,
      files = 0.45,
      branches = 0.20,
      stashes = 0.20,
    }
  },
  hl = {
    border = "FloatBorder",
    staged = "GitStatusStaged",
    unstaged = "GitStatusUnstaged",
    added = "GitStatusAdded",
    deleted = "GitStatusDeleted",
    modified = "GitStatusModified",
    untracked = "GitStatusUntracked",
    current_branch = "GitBranchCurrent",
    local_branch = "GitBranchLocal",
    remote_branch = "GitBranchRemote",
    stash_id = "GitStashId",
  }
}

function M.layout()
  if not State.get("git.is_active") then return end

  local total_w = vim.o.columns
  local total_h = vim.o.lines - 2
  
  local sidebar_w = math.floor(total_w * Config.layout.sidebar_width)
  local preview_w = total_w - sidebar_w - 4
  
  local h_commit = math.max(1, math.floor(total_h * Config.layout.heights.commit))
  local h_files = math.max(1, math.floor(total_h * Config.layout.heights.files))
  local h_branches = math.max(1, math.floor(total_h * Config.layout.heights.branches))
  local h_stashes = math.max(1, total_h - h_commit - h_files - h_branches - 8)

  local function open_win(name, component, r, c, w, h, title, focus)
    local cfg = {
      relative = "editor", row = r, col = c, width = w, height = h,
      style = "minimal", border = "rounded", title = " " .. title .. " "
    }
    if M.wins[name] and api.nvim_win_is_valid(M.wins[name]) then
      api.nvim_win_set_config(M.wins[name], cfg)
      api.nvim_win_set_buf(M.wins[name], component.buf)
    else
      M.wins[name] = api.nvim_open_win(component.buf, focus or false, cfg)
    end
    component.win = M.wins[name]
    vim.wo[M.wins[name]].cursorline = true
    vim.wo[M.wins[name]].winhl = "NormalFloat:Normal,CursorLine:Visual"
    return M.wins[name]
  end

  open_win("commit",   M.components.commit,   0, 0, sidebar_w, h_commit, "Commit (Ctrl+Enter)", true)
  open_win("files",    M.components.files,    h_commit + 2, 0, sidebar_w, h_files, "Changes")
  open_win("branches", M.components.branches, h_commit + h_files + 4, 0, sidebar_w, h_branches, "Branches")
  open_win("stashes",  M.components.stashes,  h_commit + h_files + h_branches + 6, 0, sidebar_w, h_stashes, "Stashes")
  open_win("preview",  M.components.preview,  0, sidebar_w + 2, preview_w, total_h - 2, "Preview (s:Stage, u:Unstage)")
  
  -- Apply strict UI mode to list panes using Factory rules
  ViewFactory.apply_ui_rules(M.components.files,    { mode = "strict" })
  ViewFactory.apply_ui_rules(M.components.branches, { mode = "strict" })
  ViewFactory.apply_ui_rules(M.components.stashes,  { mode = "strict" })
  
  M.draw_all()
end

function M.draw_files()
  local files = State.get("git.entities.files") or {}
  local lines, hls = {}, {}
  
  if #files == 0 then
    table.insert(lines, "  (No changes - Clean)")
    table.insert(hls, { group = "Comment", line = 0, col_start = 0, col_end = -1 })
  else
    for i, file in ipairs(files) do
      local checkbox = file.staged and "[x]" or "[ ]"
      local row = i - 1
      table.insert(lines, string.format(" %s %s %s %s", checkbox, file.status, file.icon, file.path))
      
      table.insert(hls, { group = (file.staged and Config.hl.staged or Config.hl.unstaged), line = row, col_start = 1, col_end = 4 })
      
      local status_hl = Config.hl.modified
      if file.type == "untracked" then status_hl = Config.hl.untracked
      elseif file.type == "added" then status_hl = Config.hl.added
      elseif file.type == "deleted" then status_hl = Config.hl.deleted
      end
      table.insert(hls, { group = status_hl, line = row, col_start = 5, col_end = 7 })
      table.insert(hls, { group = file.hl, line = row, col_start = 8, col_end = 8 + #file.icon })
    end
  end
  ViewFactory.render(M.components.files, lines, hls)
end

function M.draw_branches()
  local branches = State.get("git.entities.branches") or {}
  local lines, hls = {}, {}
  
  for i, b in ipairs(branches) do
    local row = i - 1
    local prefix = b.is_head and "* " or "  "
    local text = prefix .. b.name
    if b.remote ~= "" then text = text .. " -> " .. b.remote end
    table.insert(lines, text)
    if b.is_head then
      table.insert(hls, { group = Config.hl.current_branch, line = row, col_start = 0, col_end = -1 })
    else
      table.insert(hls, { group = Config.hl.local_branch, line = row, col_start = 2, col_end = 2 + #b.name })
      if b.remote ~= "" then
        table.insert(hls, { group = Config.hl.remote_branch, line = row, col_start = 2 + #b.name + 4, col_end = -1 })
      end
    end
  end
  ViewFactory.render(M.components.branches, lines, hls)
end

function M.draw_stashes()
  local stashes = State.get("git.entities.stashes") or {}
  local lines, hls = {}, {}
  
  if #stashes == 0 then
    table.insert(lines, "  (No stashes)")
    table.insert(hls, { group = "Comment", line = 0, col_start = 0, col_end = -1 })
  else
    for i, s in ipairs(stashes) do
      local row = i - 1
      table.insert(lines, string.format(" %s: %s", s.id, s.msg))
      table.insert(hls, { group = Config.hl.stash_id, line = row, col_start = 1, col_end = 1 + #s.id })
    end
  end
  ViewFactory.render(M.components.stashes, lines, hls)
end

function M.draw_log()
  local commits = State.get("git.entities.commits") or {}
  local lines, hls = {}, {}
  
  for i, c in ipairs(commits) do
    local raw = c.raw_line
    local row = i - 1
    
    local delim_start = raw:find("DELIM")
    if not delim_start then
      -- Ligne de graphe pur
      table.insert(lines, raw)
      table.insert(hls, { group = "GitLogGraph", line = row, col_start = 0, col_end = -1 })
    else
      local graph = raw:sub(1, delim_start - 1)
      local info = raw:sub(delim_start + 5)
      local parts = vim.split(info, "|")
      
      local author = parts[1] or ""
      local refs = parts[2] or ""
      local msg = parts[3] or ""
      
      -- Format: [Graph] [Author] [Refs] [Msg]
      local line_text = string.format("%s%-12s %s%s", 
        graph, author, (refs ~= "" and refs .. " " or ""), msg)
      
      table.insert(lines, line_text)
      
      local current_col = 0
      -- Graph HL
      table.insert(hls, { group = "GitLogGraph", line = row, col_start = 0, col_end = #graph })
      current_col = #graph
      
      -- Author HL
      table.insert(hls, { group = "GitLogAuthor", line = row, col_start = current_col, col_end = current_col + 12 })
      current_col = current_col + 13
      
      -- Refs HL
      if refs ~= "" then
        table.insert(hls, { group = "GitLogRef", line = row, col_start = current_col, col_end = current_col + #refs })
        current_col = current_col + #refs + 1
      end
      
      -- Message HL (Normal)
      table.insert(hls, { group = "GitLogMsg", line = row, col_start = current_col, col_end = -1 })
    end
  end
  ViewFactory.render(M.components.log, lines, hls)
end

M._preview_request_id = 0

function M.draw_preview()
  local component = M.components.preview
  if not component.win or not api.nvim_win_is_valid(component.win) then return end
  
  local pane = State.get("git.active_pane")
  local entities = State.get("git.entities." .. (pane == "commit" and "files" or pane)) or {}
  local idx = State.get("git.selected_indices." .. pane) or 1
  local entity = entities[idx]
  
  M._preview_request_id = M._preview_request_id + 1
  local request_id = M._preview_request_id

  vim.bo[component.buf].filetype = ""
  
  local model = require("modules.git.model")

  local function render_cb(lines, ft)
    if request_id ~= M._preview_request_id then 
      print(string.format("Ignoring request %d (current %d)", request_id, M._preview_request_id))
      return 
    end
    print(string.format("Processing request %d", request_id))
    ViewFactory.render(component, lines, nil, 0) -- Disable debounce for debug
    vim.bo[component.buf].filetype = ft or ""
  end

  if pane == "files" then
    if not entity then return ViewFactory.render(component, {""}) end
    if entity.type == "deleted" then
      model.git_exec({ "show", "HEAD:" .. entity.path }, function(code, out, err)
        if code ~= 0 then 
          render_cb({ "Error showing file: " .. (err or "") }, "")
        else
          render_cb(vim.split(out, "\n"), vim.filetype.match({ filename = entity.path }))
        end
      end)
    elseif entity.type == "untracked" then
      local path = State.get("git.repo_root") .. "/" .. entity.path
      require("utils.process").exec("cat", { args = { path } }, function(code, out, err)
        if code ~= 0 then
          render_cb({ "Error reading file: " .. (err or "") }, "")
        else
          render_cb(vim.split(out, "\n"), vim.filetype.match({ filename = entity.path }))
        end
      end)
    else
      local args = { "diff", "--color=never" }
      if entity.staged then table.insert(args, "--cached") end
      table.insert(args, entity.path)
      model.git_exec(args, function(code, out, err)
        if code ~= 0 then
          render_cb({ "Error running git diff: " .. (err or "") }, "")
        else
          print("Git output length: " .. #out)
          render_cb(vim.split(out, "\n"), "diff")
        end
      end)
    end
  elseif pane == "branches" then
    if not entity then return ViewFactory.render(component, {""}) end
    model.git_exec({ "log", "--oneline", "-n", "20", entity.name }, function(code, out, err)
      if code ~= 0 then
        render_cb({ "Error showing log: " .. (err or "") }, "")
      else
        render_cb(vim.split(out, "\n"), "git")
      end
    end)
  elseif pane == "stashes" then
    if not entity then return ViewFactory.render(component, {""}) end
    model.git_exec({ "stash", "show", "-p", entity.id }, function(code, out, err)
      if code ~= 0 then
        render_cb({ "Error showing stash: " .. (err or "") }, "")
      else
        render_cb(vim.split(out, "\n"), "diff")
      end
    end)
  elseif pane == "commit" then
    model.git_exec({ "diff", "--cached", "--color=never" }, function(code, out, err)
      if code ~= 0 then
        render_cb({ "Error showing staged changes: " .. (err or "") }, "")
      elseif out and out:match("%S") then
        render_cb(vim.split(out, "\n"), "diff")
      else
        render_cb({ "  (No staged changes)" })
      end
    end)
  end
end

function M.draw_all()
  M.draw_files()
  M.draw_branches()
  M.draw_stashes()
  M.draw_log()
  M.draw_preview()
end

function M.close()
  for name, win in pairs(M.wins) do
    if win and api.nvim_win_is_valid(win) then
      api.nvim_win_close(win, true)
    end
    M.wins[name] = -1
  end
end

function M.toggle_log()
  if M.wins.log and api.nvim_win_is_valid(M.wins.log) then
    api.nvim_win_close(M.wins.log, true)
    M.wins.log = -1
    return
  end
  
  M.wins.log = ViewFactory.show_floating(M.components.log, {
    width = 0.4, height = 0.7, title = " Git Log "
  })
  vim.wo[M.wins.log].cursorline = true
  M.draw_log()
end

-- Subscriptions
State.subscribe("git.entities.files", function() M.draw_files() end)
State.subscribe("git.entities.branches", function() M.draw_branches() end)
State.subscribe("git.entities.stashes", function() M.draw_stashes() end)
State.subscribe("git.entities.commits", function() M.draw_log() end)
State.subscribe("git.selected_indices.files", function() M.draw_preview() end)
State.subscribe("git.selected_indices.branches", function() M.draw_preview() end)
State.subscribe("git.selected_indices.stashes", function() M.draw_preview() end)
State.subscribe("git.selected_indices.commit", function() M.draw_preview() end)
State.subscribe("git.active_pane", function() M.draw_preview() end)

return M
