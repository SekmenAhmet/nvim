local M = {}

-- Icon Configuration (Icon + Hex Color)
M.icons_config = {
  -- Languages & Extensions
  lua  = { icon = "", color = "#51a0cf" },
  py   = { icon = "", color = "#ffbc03" },
  js   = { icon = "", color = "#cbcb41" },
  ts   = { icon = "", color = "#3178c6" },
  jsx  = { icon = "", color = "#61dbfb" },
  tsx  = { icon = "", color = "#3178c6" },
  html = { icon = "", color = "#e34c26" },
  css  = { icon = "", color = "#563d7c" },
  scss = { icon = "", color = "#c6538c" },
  json = { icon = "", color = "#cbcb41" },
  xml  = { icon = "", color = "#e34c26" },
  c    = { icon = "", color = "#599eff" },
  cpp  = { icon = "", color = "#599eff" },
  h    = { icon = "", color = "#a074c4" },
  rs   = { icon = "", color = "#dea584" },
  go   = { icon = "", color = "#00add8" },
  java = { icon = "", color = "#cc3e44" },
  php  = { icon = "", color = "#a074c4" },
  rb   = { icon = "", color = "#701516" },
  sh   = { icon = "", color = "#4d5a5e" },
  bash = { icon = "", color = "#4d5a5e" },
  zsh  = { icon = "", color = "#89e051" },
  md   = { icon = "", color = "#ffffff" },
  txt  = { icon = "", color = "#89e051" },
  yml  = { icon = "", color = "#6d8086" },
  yaml = { icon = "", color = "#6d8086" },
  toml = { icon = "", color = "#6d8086" },
  make = { icon = "", color = "#6d8086" },
  conf = { icon = "", color = "#6d8086" },
  git  = { icon = "", color = "#f14e32" },
  Dockerfile = { icon = "", color = "#384d54" },
  dockerignore = { icon = "", color = "#384d54" },
  sql  = { icon = "", color = "#dadada" },
  rake = { icon = "", color = "#701516" },
  swift = { icon = "", color = "#e37933" },
  lock = { icon = "", color = "#bbbbbb" },
  vue = { icon = "", color = "#42b883" },
  svelte = { icon = "", color = "#ff3e00" },
  jsonc = { icon = "", color = "#cbcb41" },
  json5 = { icon = "", color = "#cbcb41" },
  graphql = { icon = "", color = "#e10098" },
  gql = { icon = "", color = "#e10098" },
  
  -- Common Files (Exact matches)
  [".gitignore"] = { icon = "", color = "#f14e32" },
  [".gitconfig"] = { icon = "", color = "#f14e32" },
  ["Makefile"]   = { icon = "", color = "#6d8086" },
  ["package.json"] = { icon = "", color = "#689f63" },
  ["package-lock.json"] = { icon = "", color = "#7bb077" },
  ["node_modules"] = { icon = "", color = "#E8274B" },
  ["LICENSE"] = { icon = "", color = "#d0bf41" },
  ["README.md"] = { icon = "", color = "#42a5f5" },
  [".env"] = { icon = "", color = "#faf743" },

  -- Media
  png = { icon = "", color = "#a074c4" },
  jpg = { icon = "", color = "#a074c4" },
  jpeg = { icon = "", color = "#a074c4" },
  gif = { icon = "", color = "#a074c4" },
  svg = { icon = "", color = "#ffb13b" },
  pdf = { icon = "", color = "#ff3333" },
  
  -- Archives
  zip = { icon = "", color = "#dcb239" },
  tar = { icon = "", color = "#dcb239" },
  gz = { icon = "", color = "#dcb239" },
  ["7z"] = { icon = "", color = "#dcb239" },
}

-- UI & Diagnostic Icons
M.ui = {
  error   = " ",
  warn    = " ",
  info    = " ",
  hint    = "󰌵 ",
  ok      = " ",
  git     = " ",
  branch  = " ",
  docker  = " ",
  rest    = "󰖟 ",
  spinner = "󱑊 ",
  arrow   = " ",
  chevron = " ",
  lock    = " ",
  circle  = " ",
}

-- Simple LRU cache for icon lookups
local icon_cache = {}
local cache_size = 0
local max_cache_size = 200

function M.setup()
  for name, data in pairs(M.icons_config) do
    local hl_name = "Icon" .. name:gsub("%.", "")
    vim.api.nvim_set_hl(0, hl_name, { fg = data.color })
  end
  vim.api.nvim_set_hl(0, "IconDefault", { fg = "#89e051" })
  vim.api.nvim_set_hl(0, "IconDir", { fg = "#7aa2f7" })
  vim.api.nvim_set_hl(0, "IconDirOpen", { fg = "#9ece6a" })
end

-- Return { icon = "...", hl = "Icon..." }
function M.get(filename)
  -- Check cache first
  if icon_cache[filename] then
    return icon_cache[filename]
  end
  
  local name = vim.fn.fnamemodify(filename, ":t")
  local ext = filename:match("%.([^%.]+)$")
  local result
  
  -- Exact match first
  if M.icons_config[name] then
    result = { icon = M.icons_config[name].icon, hl = "Icon" .. name:gsub("%.", "") }
  -- Extension match
  elseif ext and M.icons_config[ext:lower()] then
    result = { icon = M.icons_config[ext:lower()].icon, hl = "Icon" .. ext:lower():gsub("%.", "") }
  else
    result = { icon = "", hl = "IconDefault" }
  end
  
  -- Simple cache eviction (FIFO)
  if cache_size >= max_cache_size then
    icon_cache = {}
    cache_size = 0
  end
  
  icon_cache[filename] = result
  cache_size = cache_size + 1
  
  return result
end

return M
