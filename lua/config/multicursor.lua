-- Multi-Cursors Light
-- Sélection multiple native sans plugin lourd
-- Basé sur * (star) et cgn (change next)

local M = {}

-- Sélectionner le mot et trouver le suivant
function M.select_next()
  local mode = vim.fn.mode()
  
  -- Si on est en mode normal, entrer en mode visuel mot
  if mode == 'n' then
    -- Sauvegarder le mot sous le curseur
    local word = vim.fn.expand('<cword>')
    if not word or #word == 0 then
      return
    end
    
    -- Sélectionner le mot
    vim.cmd('normal! viw')
    
    -- Configurer la recherche pour ce mot
    vim.fn.setreg('/', '\\<' .. vim.fn.escape(word, '\\/.*$^~[]') .. '\\>')
    
    -- Aller à l'occurrence suivante (skip la première qui est déjà sélectionnée)
    vim.cmd('normal! n')
    
    -- Sélectionner ce mot aussi
    vim.cmd('normal! viw')
    
    -- Mode visuel multi-ligne pourrait être cool mais complexe
    -- Pour l'instant, on utilise la méthode native
    
  elseif mode == 'v' or mode == 'V' then
    -- Déjà en mode visuel, étendre à la prochaine occurrence
    -- Sortir du mode visuel, chercher suivant, resélectionner
    vim.cmd('normal! <Esc>')
    vim.cmd('normal! n')
    vim.cmd('normal! viw')
  end
end

-- Méthode alternative: Utiliser cgn pour changer
-- * pour chercher, cgn pour changer et aller au prochain
function M.setup_cgn()
  -- * : cherche le mot sous le curseur
  -- cgn : change et prépare pour le prochain
  -- . : répète le changement
  
  -- Mapping optimisé
  vim.keymap.set('n', '<C-n>', function()
    -- Si pas de recherche en cours, initialiser
    if vim.fn.getreg('/') == '' then
      vim.cmd('normal! *')
    else
      -- Aller à l'occurrence suivante et changer
      vim.cmd('normal! *Ncgn')
    end
  end, { desc = 'Change next occurrence' })
end

-- Méthode simple et efficace
function M.setup_simple()
  -- <C-n> en mode normal: sélectionne le mot et met en recherche
  vim.keymap.set('n', '<C-n>', '*', { desc = 'Search word under cursor' })
  
  -- cgn pour changer l'occurrence et préparer le prochain
  -- . pour répéter sur le suivant
  -- C'est natif Vim et très puissant !
  
  -- En mode visuel, étendre la sélection
  vim.keymap.set('v', '<C-n>', function()
    -- Yank la sélection
    vim.cmd('normal! y')
    -- Chercher
    vim.cmd('normal! /<C-r>0<CR>')
    -- Sélectionner
    vim.cmd('normal! gn')
  end, { desc = 'Search selection' })
end

-- Setup (utilise la méthode simple qui est la plus fiable)
M.setup_simple()

-- Instructions pour l'utilisateur:
-- 1. Place le curseur sur un mot
-- 2. <C-n> ou * pour chercher
-- 3. cgn pour changer cette occurrence et aller à la suivante
-- 4. . (point) pour répéter le changement sur la suivante
-- 5. . pour continuer...

return M
