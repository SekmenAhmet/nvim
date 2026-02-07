-- Multi-Cursors Light
-- Simple native search and replace workflow
-- Usage: * to search word, cgn to change, . to repeat

-- <C-n> en mode normal: cherche le mot sous le curseur
vim.keymap.set('n', '<C-n>', '*', { desc = 'Search word under cursor' })

-- En mode visuel: cherche la sélection
vim.keymap.set('v', '<C-n>', function()
  -- Yank la sélection
  vim.cmd('normal! y')
  -- Chercher
  vim.cmd('normal! /<C-r>0<CR>')
  -- Sélectionner
  vim.cmd('normal! gn')
end, { desc = 'Search selection' })

-- Instructions:
-- 1. Place le curseur sur un mot
-- 2. <C-n> ou * pour chercher
-- 3. cgn pour changer cette occurrence et aller à la suivante
-- 4. . (point) pour répéter le changement sur la suivante
-- 5. . pour continuer...
