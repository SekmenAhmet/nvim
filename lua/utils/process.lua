local uv = vim.uv
local M = {}

---@class ProcessOpts
---@field args string[]? Arguments pour la commande
---@field cwd string? Répertoire de travail
---@field stdin string? Données à envoyer sur l'entrée standard
---@field timeout number? Timeout en millisecondes

--- Exécute une commande de manière asynchrone via libuv
---@param cmd string Le binaire à exécuter
---@param opts ProcessOpts Options d'exécution
---@param cb fun(code: number, stdout: string, stderr: string) Callback de fin
function M.exec(cmd, opts, cb)
  opts = opts or {}
  local args = opts.args or {}
  local cwd = opts.cwd or vim.fn.getcwd()
  local stdin_data = opts.stdin
  
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)
  local stdout_data = {}
  local stderr_data = {}
  
  local handle
  local stdio = { nil, stdout, stderr }
  
  local stdin_pipe
  if stdin_data then
    stdin_pipe = uv.new_pipe(false)
    stdio[1] = stdin_pipe
  end

  local timer
  if opts.timeout then
    timer = uv.new_timer()
    timer:start(opts.timeout, 0, function()
      if handle and not handle:is_closing() then
        handle:kill(15) -- SIGTERM
      end
    end)
  end

  handle = uv.spawn(cmd, {
    args = args,
    cwd = cwd,
    stdio = stdio
  }, function(code, signal)
    if handle then handle:close() end
    if stdout then stdout:close() end
    if stderr then stderr:close() end
    if stdin_pipe and not stdin_pipe:is_closing() then stdin_pipe:close() end
    if timer then
      timer:stop()
      timer:close()
    end
    
    vim.schedule(function()
      if cb then
        cb(code, table.concat(stdout_data), table.concat(stderr_data))
      end
    end)
  end)

  if not handle then
    if cb then cb(-1, "", "Failed to spawn " .. cmd) end
    return
  end

  if stdin_pipe and stdin_data then
    stdin_pipe:write(stdin_data, function()
      if not stdin_pipe:is_closing() then
        stdin_pipe:shutdown(function()
          stdin_pipe:close()
        end)
      end
    end)
  end

  uv.read_start(stdout, function(err, data)
    if data then table.insert(stdout_data, data) end
  end)
  
  uv.read_start(stderr, function(err, data)
    if data then table.insert(stderr_data, data) end
  end)
end

return M
