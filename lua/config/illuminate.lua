-- Illumination Word - Surligne toutes les occurrences du mot sous le curseur
-- Style VSCode, très subtil et performant

local M = {}
local api = vim.api
local ns = api.nvim_create_namespace('illuminate')

-- Configuration
local config = {
  delay = 300,              -- Délai avant highlight (ms)
  min_word_length = 2,      -- Longueur minimale du mot
  max_occurrences = 100,    -- Limite pour performance
}

local timer = nil

-- Vérifier si un caractère est un mot
local function is_word_char(char)
  return char and char:match('[%w_]') ~= nil
end

-- Surligner toutes les occurrences
function M.highlight()
  -- Nettoyer d'abord
  M.clear()
  
  -- Récupérer le mot sous le curseur
  local word = vim.fn.expand('<cword>')
  
  -- Vérifications
  if not word or #word < config.min_word_length then
    return
  end
  
  -- Ne pas surligner si on est en mode insert
  local mode = vim.fn.mode()
  if mode == 'i' or mode == 'I' or mode == 'a' or mode == 'A' then
    return
  end
  
  local bufnr = api.nvim_get_current_buf()
  local line_count = api.nvim_buf_line_count(bufnr)
  local pattern = vim.fn.escape(word, '\\.*^$[]')
  local occurrence_count = 0
  
  -- Parcourir les lignes
  for line_num = 0, math.min(line_count - 1, 500) do  -- Limiter à 500 lignes pour perf
    if occurrence_count >= config.max_occurrences then
      break
    end
    
    local line_text = api.nvim_buf_get_lines(bufnr, line_num, line_num + 1, false)[1]
    if line_text then
      local col = 0
      while true do
        local start_pos = line_text:find(word, col + 1, true)
        if not start_pos then break end
        
        -- Vérifier que c'est un mot entier
        local before = line_text:sub(start_pos - 1, start_pos - 1)
        local after = line_text:sub(start_pos + #word, start_pos + #word)
        
        if not is_word_char(before) and not is_word_char(after) then
          -- C'est un mot entier
          api.nvim_buf_add_highlight(bufnr, ns, 'IlluminatedWord', 
            line_num, start_pos - 1, start_pos + #word - 1)
          occurrence_count = occurrence_count + 1
          
          if occurrence_count >= config.max_occurrences then
            break
          end
        end
        
        col = start_pos
      end
    end
  end
end

-- Nettoyer les highlights
function M.clear()
  local bufnr = api.nvim_get_current_buf()
  if api.nvim_buf_is_valid(bufnr) then
    api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  end
end

-- Débounced highlight
function M.debounced_highlight()
  -- Annuler timer précédent
  if timer then
    vim.fn.timer_stop(timer)
    timer = nil
  end
  
  -- Créer nouveau timer
  timer = vim.fn.timer_start(config.delay, function()
    vim.schedule(function()
      M.highlight()
    end)
  end)
end

-- Setup
function M.setup()
  -- Autocmd pour highlight après délai
  api.nvim_create_autocmd('CursorHold', {
    callback = M.debounced_highlight,
    desc = 'Illuminate word under cursor',
  })
  
  -- Autocmd pour nettoyer quand on bouge
  api.nvim_create_autocmd({'CursorMoved', 'InsertEnter', 'BufLeave'}, {
    callback = M.clear,
    desc = 'Clear word illumination',
  })
  
  -- Highlight group (très subtil)
  api.nvim_set_hl(0, 'IlluminatedWord', { 
    bg = '#2f3346',
    fg = '#c0caf5',
  })
end

-- Initialiser
M.setup()

return M
