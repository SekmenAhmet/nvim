-- Statusline Native Customisée

local M = {}

-- 1. Récupération de la branche Git (Optimisé)
-- On ne le lance que sur BufEnter pour ne pas laguer
local function get_git_branch()
  local branch = vim.fn.system("git branch --show-current 2> /dev/null"):gsub("\n", "")
  if branch ~= "" then
    return "  " .. branch .. " "
  else
    return ""
  end
end

vim.api.nvim_create_autocmd({ "BufEnter", "FocusGained" }, {
  callback = function()
    vim.b.git_branch = get_git_branch()
  end
})

-- 2. Couleurs selon le mode
-- On utilise les groupes de highlight par défaut pour que ça marche avec tous les thèmes
local modes = {
  ['n']  = { 'NORMAL', 'StatusLineNormal' },
  ['no'] = { 'NORMAL', 'StatusLineNormal' },
  ['i']  = { 'INSERT', 'StatusLineInsert' },
  ['v']  = { 'VISUAL', 'StatusLineVisual' },
  ['V']  = { 'V-LINE', 'StatusLineVisual' },
  [''] = { 'V-BLOCK', 'StatusLineVisual' },
  ['c']  = { 'COMMAND', 'StatusLineCmd' },
  ['s']  = { 'SELECT', 'StatusLineVisual' },
  ['S']  = { 'S-LINE', 'StatusLineVisual' },
  ['R']  = { 'REPLACE', 'StatusLineReplace' },
}

-- Définition des highlights (Link vers des groupes standards)
vim.api.nvim_set_hl(0, 'StatusLineNormal', { link = 'Function' })
vim.api.nvim_set_hl(0, 'StatusLineInsert', { link = 'String' })
vim.api.nvim_set_hl(0, 'StatusLineVisual', { link = 'Statement' })
vim.api.nvim_set_hl(0, 'StatusLineCmd',    { link = 'Comment' })
vim.api.nvim_set_hl(0, 'StatusLineReplace', { link = 'Error' })

-- 3. Fonction de construction de la ligne
function M.render()
  local current_mode = vim.api.nvim_get_mode().mode
  local mode_info = modes[current_mode] or { 'UNKNOWN', 'StatusLine' }
  local mode_name = mode_info[1]
  local mode_hl = mode_info[2]

  local git = vim.b.git_branch or ""
  local file_name = "%f" -- Chemin relatif
  local modified = "%m"  -- [+] si modifié
  local line_col = "%l:%c" -- Ligne:Colonne
  local percentage = "%p%%" -- Pourcentage
  
  -- Startup Time (si disponible)
  local startup = ""
  if vim.g.startup_time then
    startup = string.format(" ⚡ %.1fms ", vim.g.startup_time)
  end

  return string.format(
    "%%#%s# %s %%*%%#Comment#%s%%* %%#Normal#%s%s %%= %%#CursorLineNr# %s │ %s%%#Comment#%s",
    mode_hl, mode_name, git, file_name, modified, line_col, percentage, startup
  )
end

-- Activer la statusline
vim.opt.statusline = "%!luaeval('require(\"config.statusline\").render()')"
vim.opt.laststatus = 3 -- Une seule barre globale (optionnel, mets 2 pour une par fenêtre)

return M
