local api = vim.api
local State = require("core.state")
local ui_utils = require("utils.ui")
local icons = require("utils.icons")

local M = {}

M.wins = { commit = -1, files = -1, branches = -1, stashes = -1, preview = -1, log = -1, help = -1 }
M.bufs = { commit = -1, files = -1, branches = -1, stashes = -1, preview = -1, log = -1, help = -1 }

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

function M.get_buf(name, ft, buftype)
  if M.bufs[name] and api.nvim_buf_is_valid(M.bufs[name]) then
    return M.bufs[name]
  end
  local b = api.nvim_create_buf(false, true)
  M.bufs[name] = b
  vim.bo[b].filetype = ft or "text"
  vim.bo[b].buftype = buftype or "nofile"
  vim.bo[b].bufhidden = "hide"
  return b
end

function M.layout()
  if not State.get("git.is_active") then return end

  local total_w = vim.o.columns
  local total_h = vim.o.lines - 2
  
  local sidebar_w = math.floor(total_w * Config.layout.sidebar_width)
  local preview_w = total_w - sidebar_w - 4
  
  local h_commit = math.floor(total_h * Config.layout.heights.commit)
  local h_files = math.floor(total_h * Config.layout.heights.files)
  local h_branches = math.floor(total_h * Config.layout.heights.branches)
  local h_stashes = total_h - h_commit - h_files - h_branches - 8

  local function open_win(name, buf, r, c, w, h, title, focus)
    local cfg = {
      relative = "editor", row = r, col = c, width = w, height = h,
      style = "minimal", border = "rounded", title = " " .. title .. " "
    }
    if M.wins[name] and api.nvim_win_is_valid(M.wins[name]) then
      api.nvim_win_set_config(M.wins[name], cfg)
      api.nvim_win_set_buf(M.wins[name], buf)
    else
      M.wins[name] = api.nvim_open_win(buf, focus or false, cfg)
    end
    vim.wo[M.wins[name]].cursorline = true
    vim.wo[M.wins[name]].winhl = "NormalFloat:Normal,CursorLine:Visual"
    return M.wins[name]
  end

  open_win("commit",   M.get_buf("commit", "gitcommit", ""), 0, 0, sidebar_w, h_commit, "Commit (Ctrl+Enter)", true)
  open_win("files",    M.get_buf("files", "gitstatus"), h_commit + 2, 0, sidebar_w, h_files, "Changes")
  open_win("branches", M.get_buf("branches", "gitbranch"), h_commit + h_files + 4, 0, sidebar_w, h_branches, "Branches")
  open_win("stashes",  M.get_buf("stashes", "git"), h_commit + h_files + h_branches + 6, 0, sidebar_w, h_stashes, "Stashes")
  open_win("preview",  M.get_buf("preview", "diff"), 0, sidebar_w + 2, preview_w, total_h - 2, "Preview (s:Stage, u:Unstage)")
  
  M.draw_all()
end

function M.set_buf_lines(buf, lines, highlights)
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

function M.draw_files()
  local buf = M.bufs.files
  if not buf or not api.nvim_buf_is_valid(buf) then return end
  
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
  M.set_buf_lines(buf, lines, hls)
end

function M.draw_branches()
  local buf = M.bufs.branches
  if not buf or not api.nvim_buf_is_valid(buf) then return end
  
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
  M.set_buf_lines(buf, lines, hls)
end

function M.draw_stashes()
  local buf = M.bufs.stashes
  if not buf or not api.nvim_buf_is_valid(buf) then return end
  
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
  M.set_buf_lines(buf, lines, hls)
end

function M.draw_log()
  local buf = M.bufs.log
  if not buf or not api.nvim_buf_is_valid(buf) then return end
  
  local commits = State.get("git.entities.commits") or {}
  local lines, hls = {}, {}
  
  for i, c in ipairs(commits) do
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
      end
    end
  end
  M.set_buf_lines(buf, lines, hls)
end

function M.draw_preview()
  local win = M.wins.preview
  local buf = M.bufs.preview
  if not win or not api.nvim_win_is_valid(win) then return end
  
  local pane = State.get("git.active_pane")
  local entities = State.get("git.entities." .. (pane == "commit" and "files" or pane)) or {}
  local idx = State.get("git.selected_indices." .. pane) or 1
  local entity = entities[idx]
  
  vim.bo[buf].filetype = ""
  
  local model = require("modules.git.model")

  if pane == "files" then
    if not entity then return M.set_buf_lines(buf, {""}) end
    if entity.type == "deleted" then
      model.git_exec({ "show", "HEAD:" .. entity.path }, function(code, out)
        M.set_buf_lines(buf, vim.split(out, "\n"))
        vim.bo[buf].filetype = vim.filetype.match({ filename = entity.path }) or ""
      end)
    elseif entity.type == "untracked" then
      require("utils").async_preview(State.get("git.repo_root") .. "/" .. entity.path, buf, win)
    else
      local args = { "diff", "--color=never" }
      if entity.staged then table.insert(args, "--cached") end
      table.insert(args, entity.path)
      model.git_exec(args, function(code, out)
        M.set_buf_lines(buf, vim.split(out, "\n"))
        vim.bo[buf].filetype = "diff"
      end)
    end
  elseif pane == "branches" then
    if not entity then return M.set_buf_lines(buf, {""}) end
    model.git_exec({ "log", "--oneline", "-n", "20", entity.name }, function(code, out)
      M.set_buf_lines(buf, vim.split(out, "\n"))
      vim.bo[buf].filetype = "git"
    end)
  elseif pane == "stashes" then
    if not entity then return M.set_buf_lines(buf, {""}) end
    model.git_exec({ "stash", "show", "-p", entity.id }, function(code, out)
      M.set_buf_lines(buf, vim.split(out, "\n"))
      vim.bo[buf].filetype = "diff"
    end)
  elseif pane == "commit" then
    model.git_exec({ "diff", "--cached", "--color=never" }, function(code, out)
      if out and out:match("%S") then
        M.set_buf_lines(buf, vim.split(out, "\n"))
        vim.bo[buf].filetype = "diff"
      else
        M.set_buf_lines(buf, { "  (No staged changes)" })
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
  
  local width = 60
  local height = math.floor(vim.o.lines * 0.7)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = vim.o.columns - width - 5
  
  local buf = M.get_buf("log", "git")
  M.wins.log = api.nvim_open_win(buf, false, {
    relative = "editor", width = width, height = height, row = row, col = col,
    style = "minimal", border = "rounded", title = " Git Log ", focusable = true
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
