local M = {}

-- L'état global de l'IDE
M.data = {
  docker = {
    active_containers = 0,
    is_loading = false,
    entities = {
      containers = {},
      images = {},
      volumes = {},
    },
    selected_id = nil,
    active_tab = 1, -- 1: Logs, 2: Terminal
    is_active = false,
  },
  git = {
    is_active = false,
    repo_root = nil,
    active_pane = "files",
    branch = "",
    status = { added = 0, changed = 0, removed = 0 },
    entities = {
      files = {},
      branches = {},
      stashes = {},
      commits = {},
    },
    selected_indices = {
      files = 1,
      branches = 1,
      stashes = 1,
      commit = 1,
    }
  },
  rest = {
    is_active = false,
    is_pending = false,
    last_status = nil,
    req_id = nil,
    active_tab = 1,
    env_name = "local",
    response_meta = { status = "", time = "" },
    side_open = false,
  },
  lsp = {
    clients = {},
    errors = 0,
    warnings = 0,
  }
}

-- Système d'événements pour notifier les changements
local listeners = {
  path = {}, -- Subscriptions to specific paths
  global = {} -- Subscriptions to any change
}

function M.subscribe(path, callback)
  if type(path) == "function" then
    table.insert(listeners.global, path)
    return
  end
  
  if not listeners.path[path] then listeners.path[path] = {} end
  table.insert(listeners.path[path], callback)
end

function M.emit(path, value)
  -- Notify path-specific listeners
  if listeners.path[path] then
    for _, cb in ipairs(listeners.path[path]) do
      cb(value)
    end
  end
  
  -- Notify global listeners
  for _, cb in ipairs(listeners.global) do
    cb(path, value)
  end
end

-- Deep update helper
function M.set(path, value)
  local keys = vim.split(path, ".", { plain = true })
  local current = M.data
  
  for i = 1, #keys - 1 do
    if not current[keys[i]] then
      current[keys[i]] = {}
    end
    current = current[keys[i]]
  end
  
  local last_key = keys[#keys]
  local old_value = current[last_key]
  
  -- Only update and emit if value changed (shallow check for simplicity, deep would be better but expensive)
  if old_value ~= value then
    current[last_key] = value
    M.emit(path, value)
  end
end

function M.get(path)
  local keys = vim.split(path, ".", { plain = true })
  local current = M.data
  for _, key in ipairs(keys) do
    if current == nil or type(current) ~= "table" then return nil end
    current = current[key]
  end
  return current
end

return M
