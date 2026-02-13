local State = require("core.state")
local process = require("utils.process")

local M = {}

--- Executes a docker command asynchronously using the unified process engine
--- @param args string[]
--- @param cb function(code: number, stdout: string, stderr: string)
--- @param opts table?
function M.docker_exec(args, cb, opts)
  opts = opts or {}
  process.exec("docker", {
    args = args,
    cwd = opts.cwd,
    stdin = opts.stdin
  }, cb)
end

function M.list_containers(cb)
  local fmt = "{{.ID}}|{{.Names}}|{{.Image}}|{{.State}}|{{.Status}}|{{.Ports}}|{{.Labels}}"
  M.docker_exec({"ps", "-a", "--format", fmt}, function(code, out)
    local list = {}
    local lines = vim.split(out, "\n", { trimempty = true })
    local running_count = 0
    
    for _, line in ipairs(lines) do
      local p = vim.split(line, "|")
      if #p >= 7 then
        local labels = {}
        for item in p[7]:gmatch("[^,]+") do
          local k, v = item:match("([^=]+)=(.*)")
          if k and v then labels[k] = v end
        end
        
        local is_running = p[4]:lower():match("up") or p[4]:lower():match("running")
        if is_running then running_count = running_count + 1 end
        
        table.insert(list, { 
          id = p[1], name = p[2], image = p[3], state = p[4], 
          status = p[5], ports = p[6] or "", 
          service = labels["com.docker.compose.service"],
          workdir = labels["com.docker.compose.project.working_dir"]
        }) 
      end
    end
    
    State.set("docker.entities.containers", list)
    State.set("docker.active_containers", running_count)
    if cb then cb(list) end
  end)
end

function M.list_images(cb)
  M.docker_exec({"images", "--format", "{{.ID}}|{{.Repository}}|{{.Tag}}|{{.Size}}|{{.CreatedAt}}"}, function(code, out)
    local list = {}
    local lines = vim.split(out, "\n", { trimempty = true })
    for _, line in ipairs(lines) do
      local p = vim.split(line, "|")
      if #p >= 5 then
        table.insert(list, { id = p[1], repo = p[2], tag = p[3], size = p[4], created = p[5] })
      end
    end
    State.set("docker.entities.images", list)
    if cb then cb(list) end
  end)
end

function M.list_volumes(cb)
  M.docker_exec({"volume", "ls", "--format", "{{.Name}}|{{.Driver}}|{{.Scope}}"}, function(code, out)
    local list = {}
    local lines = vim.split(out, "\n", { trimempty = true })
    for _, line in ipairs(lines) do
      local p = vim.split(line, "|")
      if #p >= 3 then
        table.insert(list, { name = p[1], driver = p[2], scope = p[3] })
      end
    end
    State.set("docker.entities.volumes", list)
    if cb then cb(list) end
  end)
end

function M.get_stats(id, cb)
  M.docker_exec({"stats", "--no-stream", "--format", "{{.CPUPerc}}|{{.MemUsage}}|{{.NetIO}}", id}, function(code, out)
    if code == 0 and out ~= "" then
      local p = vim.split(out, "|")
      if #p >= 3 then
        cb({ cpu = p[1], mem = p[2], net = p[3] })
      end
    end
  end)
end

return M
