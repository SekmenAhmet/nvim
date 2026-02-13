local M = {}
local api = vim.api

M.SESSION_DIR = vim.fn.stdpath("data") .. "/sessions/"

-- Ensure session directory exists
if vim.fn.isdirectory(M.SESSION_DIR) == 0 then
  vim.fn.mkdir(M.SESSION_DIR, "p")
end

--- Get a safe filename for a project path
local function get_session_path(project_path)
  local name = project_path:gsub("[^%w]", "%%")
  return M.SESSION_DIR .. name .. ".vim"
end

--- Cleanup UI components before saving/loading
local function cleanup_ui()
  -- 1. Close custom tree
  local ok_tree, tree = pcall(require, "config.netrw")
  if ok_tree and tree.close then tree.close() end
  
  -- 2. Close terminal
  local ok_term, term = pcall(require, "config.terminal")
  if ok_term and term.close then term.close() end
  
  -- 3. Close ALL floating windows (Pickers, AI, etc)
  for _, win in ipairs(api.nvim_list_wins()) do
    local config = api.nvim_win_get_config(win)
    if config.relative ~= "" then
      pcall(api.nvim_win_close, win, true)
    end
  end
end

--- Wipe all buffers to clear the environment
function M.clear_env()
  vim.cmd("silent! %bwipeout!")
end

--- Save current session for a project
function M.save(project_path)
  if not project_path or project_path == "" then return end
  
  -- Before saving, clean up the UI so it's not captured in the session
  cleanup_ui()
  
  -- Configure session options to be clean
  local old_ssop = vim.opt.sessionoptions:get()
  vim.opt.sessionoptions = { "buffers", "curdir", "tabpages", "winsize", "help", "globals", "folds" }
  
  local path = get_session_path(project_path)
  vim.cmd("mksession! " .. vim.fn.fnameescape(path))
  
  -- Restore original session options
  vim.opt.sessionoptions = old_ssop
end

--- Load session for a project
function M.load(project_path)
  if not project_path or project_path == "" then return false end
  
  local path = get_session_path(project_path)
  if vim.fn.filereadable(path) == 1 then
    -- 1. Wipe everything to start from a clean state
    vim.cmd("silent! %bwipeout!")
    
    -- 2. Source the session
    local ok, err = pcall(vim.cmd, "source " .. vim.fn.fnameescape(path))
    if not ok then
      vim.notify("Session load error: " .. tostring(err), vim.log.levels.ERROR)
      return false
    end
    
    -- 3. Final cleanup of residual untitled buffers
    local bufs = api.nvim_list_bufs()
    for _, buf in ipairs(bufs) do
      if api.nvim_buf_is_valid(buf) and api.nvim_buf_get_name(buf) == "" and not vim.bo[buf].modified then
        pcall(api.nvim_buf_delete, buf, { force = true })
      end
    end
    
    return true
  end
  return false
end

--- Delete session for a project
function M.delete(project_path)
  local path = get_session_path(project_path)
  if vim.fn.filereadable(path) == 1 then
    os.remove(path)
  end
end

return M
