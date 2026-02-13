local State = require("core.state")
local uv = vim.uv

local M = {}

M.DB_PATH = vim.fn.stdpath("data") .. "/projects.json"

function M.load()
  local fd = uv.fs_open(M.DB_PATH, "r", 438)
  if not fd then 
    State.set("project.list", {})
    return {} 
  end
  
  local stat = uv.fs_fstat(fd)
  local data = uv.fs_read(fd, stat.size, 0)
  uv.fs_close(fd)
  
  local ok, projects = pcall(vim.fn.json_decode, data)
  if not ok then 
    projects = {} 
  end
  
  State.set("project.list", projects)
  return projects
end

function M.save(projects)
  projects = projects or State.get("project.list") or {}
  local data = vim.fn.json_encode(projects)
  local fd = uv.fs_open(M.DB_PATH, "w", 438)
  if fd then
    uv.fs_write(fd, data, 0)
    uv.fs_close(fd)
  end
end

function M.add(path)
  path = path or vim.fn.getcwd()
  local projects = M.load()
  
  -- Check if exists
  for _, p in ipairs(projects) do
    if p.path == path then
      p.last_opened = os.time()
      M.save(projects)
      return
    end
  end
  
  table.insert(projects, {
    path = path,
    name = vim.fn.fnamemodify(path, ":t"),
    last_opened = os.time()
  })
  
  M.save(projects)
  State.set("project.list", projects)
end

function M.remove(path)
  local projects = State.get("project.list") or {}
  for i, p in ipairs(projects) do
    if p.path == path then
      table.remove(projects, i)
      break
    end
  end
  M.save(projects)
  State.set("project.list", projects)
end

return M
