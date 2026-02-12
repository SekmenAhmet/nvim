local M = {}
local icons = require("utils.icons").ui
local state = require("core.state")

-- =============================================================================
-- HELPERS
-- =============================================================================

local function get_mode()
  local mode_map = {
    ['n']      = { name = 'NORMAL',   hl = 'StatusLineNormal' },
    ['no']     = { name = 'OP-PEND',  hl = 'StatusLineNormal' },
    ['v']      = { name = 'VISUAL',   hl = 'StatusLineVisual' },
    ['V']      = { name = 'V-LINE',   hl = 'StatusLineVisual' },
    ['\22']    = { name = 'V-BLOCK',  hl = 'StatusLineVisual' },
    ['s']      = { name = 'SELECT',   hl = 'StatusLineVisual' },
    ['S']      = { name = 'S-LINE',   hl = 'StatusLineVisual' },
    ['\19']    = { name = 'S-BLOCK',  hl = 'StatusLineVisual' },
    ['i']      = { name = 'INSERT',   hl = 'StatusLineInsert' },
    ['ic']     = { name = 'INSERT',   hl = 'StatusLineInsert' },
    ['R']      = { name = 'REPLACE',  hl = 'StatusLineReplace' },
    ['Rv']     = { name = 'V-REPLACE', hl = 'StatusLineReplace' },
    ['c']      = { name = 'COMMAND',  hl = 'StatusLineCmd' },
    ['cv']     = { name = 'VIM EX',   hl = 'StatusLineCmd' },
    ['ce']     = { name = 'EX',       hl = 'StatusLineCmd' },
    ['r']      = { name = 'PROMPT',   hl = 'StatusLineNormal' },
    ['rm']     = { name = 'MOAR',     hl = 'StatusLineNormal' },
    ['r?']     = { name = 'CONFIRM',  hl = 'StatusLineNormal' },
    ['!']      = { name = 'SHELL',    hl = 'StatusLineNormal' },
    ['t']      = { name = 'TERMINAL', hl = 'StatusLineInsert' },
  }
  local m = mode_map[vim.api.nvim_get_mode().mode] or { name = 'UNKNOWN', hl = 'StatusLineNormal' }
  return string.format("%%#%s# %s %%*", m.hl, m.name)
end

local function get_git()
  local git = state.data.git
  if not git.branch or git.branch == "" then return "" end
  
  local parts = {}
  if git.status.added > 0 then table.insert(parts, "%#GitStatusAdded#+" .. git.status.added) end
  if git.status.changed > 0 then table.insert(parts, "%#GitStatusModified#~" .. git.status.changed) end
  if git.status.removed > 0 then table.insert(parts, "%#GitStatusDeleted#-" .. git.status.removed) end
  
  local status_str = #parts > 0 and (" [" .. table.concat(parts, " ") .. "%%*]") or ""
  return string.format("%%#GitBranchCurrent# %s%s %%*%s ", icons.branch, git.branch, status_str)
end

local function get_diagnostics()
  local errors = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.ERROR })
  local warns = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.WARN })
  
  local parts = {}
  if errors > 0 then table.insert(parts, "%#DiagnosticError#" .. icons.error .. errors) end
  if warns > 0 then table.insert(parts, "%#DiagnosticWarn#" .. icons.warn .. warns) end
  
  return #parts > 0 and (" " .. table.concat(parts, " ") .. " %%*") or ""
end

local function get_docker()
  local running = state.data.docker.active_containers
  if running > 0 then
    return string.format("%%#DiagnosticOk# %s%d %%*", icons.docker, running)
  end
  return ""
end

local function get_rest()
  local rest = state.data.rest
  if rest.is_pending then
    return string.format("%%#DiagnosticInfo# %s ... %%*", icons.rest)
  elseif rest.last_status then
    local hl = "DiagnosticInfo"
    if rest.last_status:match(" 2%d%d") then hl = "DiagnosticOk"
    elseif rest.last_status:match(" [45]%d%d") then hl = "DiagnosticError" end
    return string.format("%%#%s# %s %s %%*", hl, icons.rest, rest.last_status:match(" %d%d%d") or rest.last_status)
  end
  return ""
end

-- =============================================================================
-- RENDER
-- =============================================================================

function M.render()
  local parts = {
    get_mode(),
    get_git(),
    "%#StatusLine# %f %m %#StatusLine#",
    get_diagnostics(),
    "%=", -- Right align starts here
    get_docker(),
    get_rest(),
    "%#StatusLine# %l:%c │ %p%% ",
    vim.g.startup_time and string.format("%%#StatusLine#⚡ %.1fms ", vim.g.startup_time) or ""
  }
  
  return table.concat(parts, " ")
end

-- =============================================================================
-- SETUP
-- =============================================================================

vim.opt.statusline = "%!v:lua.require'config.statusline'.render()"
vim.opt.laststatus = 3

return M
