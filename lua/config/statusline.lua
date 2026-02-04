-- Statusline Native Customisée (Optimisée)

local M = {}

-- 1. Récupération Git Optimisée (Lecture Fichier)
local function get_git_branch()
  local git_dir = vim.fn.finddir(".git", ";")
  if git_dir == "" then return "" end
  
  local head_file = git_dir .. "/HEAD"
  local f = io.open(head_file, "r")
  if not f then return "" end
  
  local content = f:read("*all")
  f:close()
  
  -- Parse "ref: refs/heads/master"
  local branch = content:match("ref: refs/heads/(.+)")
  if branch then
    return "  " .. branch:gsub("\n", "") .. " "
  end
  return "" -- Detached head or other state, ignored for simplicity
end

-- Update branch only on BufEnter/DirChanged, not every redraw
vim.api.nvim_create_autocmd({ "BufEnter", "FocusGained", "DirChanged" }, {
  callback = function()
    vim.b.git_branch = get_git_branch()
  end
})

-- 2. Fonction de rendu
function M.render()
  local current_mode = vim.api.nvim_get_mode().mode
  -- Highlights are now in colors.lua (StatusLineNormal, etc)
  
  local mode_map = {
    ['n'] = 'NORMAL', ['no'] = 'NORMAL', ['v'] = 'VISUAL', ['V'] = 'V-LINE',
    [''] = 'V-BLOCK', ['s'] = 'SELECT', ['S'] = 'S-LINE', [''] = 'S-BLOCK',
    ['i'] = 'INSERT', ['ic'] = 'INSERT', ['R'] = 'REPLACE', ['Rv'] = 'V-REPLACE',
    ['c'] = 'COMMAND', ['cv'] = 'VIM EX', ['ce'] = 'EX', ['r'] = 'PROMPT',
    ['rm'] = 'MOAR', ['r?'] = 'CONFIRM', ['!'] = 'SHELL', ['t'] = 'TERMINAL',
  }
  
  local mode_name = mode_map[current_mode] or 'UNKNOWN'
  
  -- Dynamic Highlight based on mode
  local mode_hl = "StatusLineNormal"
  if current_mode:match("^i") then mode_hl = "StatusLineInsert"
  elseif current_mode:match("^[vV]") then mode_hl = "StatusLineVisual"
  elseif current_mode == "R" then mode_hl = "StatusLineReplace"
  elseif current_mode == "c" then mode_hl = "StatusLineCmd"
  end

  local git = vim.b.git_branch or ""
  local file_name = "%f"
  local modified = "%m"
  local line_col = "%l:%c"
  local percentage = "%p%%"
  
  local startup = ""
  if vim.g.startup_time then
    startup = string.format(" ⚡ %.1fms ", vim.g.startup_time)
  end

  return string.format(
    "%%#%s# %s %%*%%#Comment#%s%%* %%#Normal#%s%s %%= %%#CursorLineNr# %s │ %s%%#Comment#%s",
    mode_hl, mode_name, git, file_name, modified, line_col, percentage, startup
  )
end

vim.opt.statusline = "%!luaeval('require(\"config.statusline\").render()')"
vim.opt.laststatus = 3

return M