local uv = vim.uv
local State = require("core.state")
local icons = require("utils.icons")
local ai = require("utils.ai")

local M = {}

--- Executes a git command asynchronously
--- @param args string[]
--- @param cb function(code: number, stdout: string, stderr: string)
--- @param stdin_data string?
function M.git_exec(args, cb, stdin_data)
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)
  local stdout_data = {}
  local stderr_data = {}
  
  local repo_root = State.get("git.repo_root") or vim.fn.getcwd()
  
  local handle
  local opts = {
    args = args,
    cwd = repo_root,
    stdio = { nil, stdout, stderr }
  }

  if stdin_data then
    local stdin = uv.new_pipe(false)
    opts.stdio[1] = stdin
    handle = uv.spawn("git", opts, function(code)
      if handle then handle:close() end
      if stdout then stdout:close() end
      if stderr then stderr:close() end
      vim.schedule(function()
        if cb then cb(code, table.concat(stdout_data), table.concat(stderr_data)) end
      end)
    end)
    stdin:write(stdin_data, function() stdin:close() end)
  else
    handle = uv.spawn("git", opts, function(code)
      if handle then handle:close() end
      if stdout then stdout:close() end
      if stderr then stderr:close() end
      vim.schedule(function()
        if cb then cb(code, table.concat(stdout_data), table.concat(stderr_data)) end
      end)
    end)
  end

  if stdout then
    uv.read_start(stdout, function(err, data)
      if data then table.insert(stdout_data, data) end
    end)
  end
  if stderr then
    uv.read_start(stderr, function(err, data)
      if data then table.insert(stderr_data, data) end
    end)
  end
end

function M.refresh_status(cb)
  M.git_exec({ "status", "--porcelain", "--ignored=no" }, function(code, out)
    local files = {}
    local lines = vim.split(out, "\n", { trimempty = true })
    
    local exclude_patterns = {
      "^%.git/", "%.gitignore", "%.env", "node_modules/", 
      "^dist/", "^build/", "^target/", "^bin/", "^out/",
      "package%-lock%.json", "yarn%.lock", "pnpm%-lock%.yaml", "composer%.lock",
      "%.cache/", "%.tmp/", "%.DS_Store"
    }

    local added, changed, removed = 0, 0, 0

    for _, line in ipairs(lines) do
      local status_code = line:sub(1, 2)
      local path = line:sub(4)
      
      local skip = false
      for _, pattern in ipairs(exclude_patterns) do
        if path:match(pattern) then skip = true break end
      end

      if not skip then
        if status_code:match("R") then 
          local arrow = path:find(" -> ")
          if arrow then path = path:sub(arrow + 4) end
        end
        
        local type = "modified"
        local s1, s2 = status_code:sub(1,1), status_code:sub(2,2)
        
        if s1 == "?" then type = "untracked"; added = added + 1
        elseif s1 == "A" or s2 == "A" then type = "added"; added = added + 1
        elseif s1 == "D" or s2 == "D" then type = "deleted"; removed = removed + 1
        else changed = changed + 1 end
        
        local is_staged = (s1 ~= " " and s1 ~= "?")
        local icon_data = icons.get(path)
        
        table.insert(files, {
          path = path, status = status_code, staged = is_staged,
          type = type, icon = icon_data.icon, hl = icon_data.hl
        })
      end
    end
    
    State.set("git.entities.files", files)
    State.set("git.status", { added = added, changed = changed, removed = removed })
    if cb then cb(files) end
  end)
end

function M.refresh_branches(cb)
  M.git_exec({ "branch", "--format=%(HEAD)|%(refname:short)|%(upstream:short)" }, function(code, out)
    local branches = {}
    local lines = vim.split(out, "\n", { trimempty = true })
    local current_branch = ""
    for _, line in ipairs(lines) do
      local parts = vim.split(line, "|")
      local is_head = (parts[1] == "*")
      if is_head then current_branch = parts[2] end
      table.insert(branches, { 
        is_head = is_head, name = parts[2], remote = parts[3] or ""
      })
    end
    State.set("git.entities.branches", branches)
    State.set("git.branch", current_branch)
    if cb then cb(branches) end
  end)
end

function M.refresh_stashes(cb)
  M.git_exec({ "stash", "list" }, function(code, out)
    local stashes = {}
    local lines = vim.split(out, "\n", { trimempty = true })
    for _, line in ipairs(lines) do
      local id, msg = line:match("(stash@{[0-9]+}): (.*)")
      if id then
        table.insert(stashes, { id = id, msg = msg })
      end
    end
    State.set("git.entities.stashes", stashes)
    if cb then cb(stashes) end
  end)
end

function M.refresh_log(cb)
  M.git_exec({ "log", "--oneline", "--graph", "--all", "--color=never", "-n", "100" }, function(code, out)
    local commits = {}
    local lines = vim.split(out, "\n", { trimempty = true })
    for _, line in ipairs(lines) do
      table.insert(commits, { raw_line = line })
    end
    State.set("git.entities.commits", commits)
    if cb then cb(commits) end
  end)
end

function M.refresh_all(cb)
  local count = 0
  local total = 4
  local function done()
    count = count + 1
    if count == total and cb then cb() end
  end
  M.refresh_status(done)
  M.refresh_branches(done)
  M.refresh_stashes(done)
  M.refresh_log(done)
end

function M.stage(path, staged, cb)
  local cmd = staged and "reset" or "add"
  M.git_exec({ cmd, path }, function() if cb then cb() end end)
end

function M.stage_all(cb)
  M.git_exec({ "add", "." }, function() if cb then cb() end end)
end

function M.unstage_all(cb)
  M.git_exec({ "reset" }, function() if cb then cb() end end)
end

function M.checkout(branch, cb)
  M.git_exec({ "checkout", branch }, function(code, _, err)
    if code == 0 then
      vim.notify("Switched to " .. branch, vim.log.levels.INFO)
    else
      vim.notify("Checkout failed: " .. err, vim.log.levels.ERROR)
    end
    if cb then cb(code == 0) end
  end)
end

function M.discard(path, cb)
  M.git_exec({ "checkout", "--", path }, function() if cb then cb() end end)
end

function M.stash_push(msg, cb)
  local args = { "stash", "push" }
  if msg and msg ~= "" then table.insert(args, "-m"); table.insert(args, msg) end
  M.git_exec(args, function() if cb then cb() end end)
end

function M.stash_apply(id, action, cb)
  -- action: apply, pop, drop
  M.git_exec({ "stash", action, id }, function() if cb then cb() end end)
end

function M.commit(msg, cb)
  M.git_exec({ "commit", "-m", msg }, function(code, _, err)
    if code == 0 then
      vim.notify("Committed!", vim.log.levels.INFO)
    else
      vim.notify("Commit failed: " .. err, vim.log.levels.ERROR)
    end
    if cb then cb(code == 0) end
  end)
end

function M.push(cb)
  M.git_exec({ "push" }, function(code, _, err)
    if code == 0 then
      vim.notify("Push Successful!", vim.log.levels.INFO)
    else
      vim.notify("Push Failed:\n" .. err, vim.log.levels.ERROR)
    end
    if cb then cb(code == 0) end
  end)
end

function M.pull(cb)
  M.git_exec({ "pull" }, function(code, _, err)
    if code == 0 then
      vim.notify("Pull Successful!", vim.log.levels.INFO)
    else
      vim.notify("Pull Failed:\n" .. err, vim.log.levels.ERROR)
    end
    if cb then cb(code == 0) end
  end)
end

function M.apply_hunk(patch, reverse, cb)
  local args = { "apply", "--cached" }
  if reverse then table.insert(args, "--reverse") end
  table.insert(args, "-")
  M.git_exec(args, function(code, _, err)
    if code ~= 0 then
      vim.notify("Failed to apply hunk: " .. err, vim.log.levels.ERROR)
    end
    if cb then cb(code == 0) end
  end, patch)
end

function M.generate_commit_msg(cb)
  local files = State.get("git.entities.files") or {}
  local staged_files = {}
  for _, f in ipairs(files) do
    if f.staged then table.insert(staged_files, f.path) end
  end
  
  if #staged_files == 0 then
    vim.notify("No staged changes. Stage some files first!", vim.log.levels.WARN)
    return
  end

  if not ai.is_ready() then
    vim.notify("🤖 Initializing AI...", vim.log.levels.INFO)
    ai.setup(nil, function()
      M.generate_commit_msg(cb)
    end)
    return
  end

  vim.notify("🤖 Analyzing " .. #staged_files .. " staged files...", vim.log.levels.INFO)

  local diff_args = { "diff", "--cached", "--no-color", "--" }
  for _, p in ipairs(staged_files) do table.insert(diff_args, p) end

  M.git_exec(diff_args, function(code, diff_output)
    if not diff_output or diff_output:match("^%s*$") then
      vim.notify("No diff found for staged files", vim.log.levels.WARN)
      return
    end
    
    -- Smart truncation
    local max_lines = 400
    local diff_lines = vim.split(diff_output, "\n")
    local diff
    if #diff_lines > max_lines then
      local head = { unpack(diff_lines, 1, max_lines / 2) }
      local tail = { unpack(diff_lines, #diff_lines - (max_lines / 2) + 1) }
      diff = table.concat(head, "\n") .. "\n... [truncated] ...\n" .. table.concat(tail, "\n")
    else
      diff = diff_output
    end
    
    local system_prompt = [[You are a professional Git Commit Generator.
Your ONLY task is to output a single line following the Conventional Commits specification.

STRICT FORMAT: <type>(<scope>): <description>
ALLOWED TYPES: feat, fix, docs, style, refactor, perf, test, build, ci, chore.

RULES:
- Use lowercase throughout.
- Use imperative mood (e.g., "add", "fix", "refactor").
- No period at the end.
- Max 50 characters for the first line.
- Output ONLY the commit message. No chat, no markdown blocks, no explanations.]]

    local prompt = string.format("FILES:\n%s\n\nDIFF:\n%s", table.concat(staged_files, "\n"), diff)

    ai.generate(prompt, { system = system_prompt, temperature = 0.1, num_predict = 150 }, function(response, err)
      if err then
        vim.notify("AI Error: " .. err, vim.log.levels.ERROR)
        return
      end
      
      if response then
        -- Cleanup: strip markdown code blocks and whitespace
        local msg = response:gsub("^```%w*\n", ""):gsub("\n```$", "")
        msg = msg:gsub("^%s*", ""):gsub("%s*$", "")
        
        if cb then cb(msg) end
        vim.notify("✨ AI Commit Message Generated", vim.log.levels.INFO)
      end
    end)
  end)
end

return M
