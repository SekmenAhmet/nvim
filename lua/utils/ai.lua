-- Native AI Client (Ollama)
-- Provides a generic interface for local AI generation.

local M = {}
local api = vim.api

-- Default Configuration
local CONFIG = {
  url = "http://localhost:11434",
  model = "llama3.1:8b",
  timeout = 30000, -- 30s
}

local state = {
  ready = false,
  verifying = false,
}

-- Check if Ollama is reachable and model is available
-- @param on_ready function(optional): callback when ready
function M.setup(opts, on_ready)
  if opts then CONFIG = vim.tbl_deep_extend("force", CONFIG, opts) end
  if state.ready then 
    if on_ready then on_ready() end
    return 
  end
  if state.verifying then return end

  state.verifying = true
  
  -- 1. Check Server Connectivity
  local check_cmd = string.format("curl -s -o /dev/null -w '%%{http_code}' %s/api/tags", CONFIG.url)
  
  vim.system({"sh", "-c", check_cmd}, { text = true }, function(obj)
    vim.schedule(function()
      local is_running = obj.stdout and obj.stdout:match("200")
      
      if not is_running then
        vim.notify("Starting Ollama server...", vim.log.levels.INFO)
        vim.system({"sh", "-c", "nohup ollama serve > /dev/null 2>&1 &"}, {}, function()
           -- Wait for server to boot
           vim.defer_fn(function() M._check_model(on_ready) end, 2000)
        end)
      else
        M._check_model(on_ready)
      end
    end)
  end)
end

function M._check_model(on_ready)
  vim.system({"ollama", "list"}, { text = true }, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 then
        vim.notify("Ollama binary not found.", vim.log.levels.WARN)
        state.verifying = false
        return
      end
      
      local has_model = obj.stdout and obj.stdout:match(CONFIG.model:gsub(":", "%%:"))
      
      if not has_model then
        vim.notify("Pulling AI model: " .. CONFIG.model .. "...", vim.log.levels.INFO)
        vim.system({"ollama", "pull", CONFIG.model}, { text = true }, function(pull_obj)
          vim.schedule(function()
            if pull_obj.code == 0 then
              vim.notify("✓ AI Ready: " .. CONFIG.model, vim.log.levels.INFO)
              state.ready = true
              if on_ready then on_ready() end
            else
              vim.notify("Failed to pull model: " .. (pull_obj.stderr or ""), vim.log.levels.ERROR)
            end
            state.verifying = false
          end)
        end)
      else
        state.ready = true
        state.verifying = false
        if on_ready then on_ready() end
      end
    end)
  end)
end

-- Generate text using Ollama
-- @param prompt string: The prompt to send
-- @param opts table: { model, temperature, system }
-- @param callback function(response, error): callback with result
function M.generate(prompt, opts, callback)
  if not state.ready then
    M.setup(nil, function() M.generate(prompt, opts, callback) end)
    vim.notify("Initializing AI...", vim.log.levels.INFO)
    return
  end
  
  opts = opts or {}
  local model = opts.model or CONFIG.model
  
  -- Create temp file for payload (safer for large prompts)
  local tmpfile = os.tmpname()
  local f = io.open(tmpfile, "w")
  if not f then
    if callback then callback(nil, "Failed to create temp file") end
    return
  end
  
  local payload = {
    model = model,
    prompt = prompt,
    stream = false,
    options = {
      temperature = opts.temperature or 0.3,
      num_predict = opts.num_predict or 200,
    }
  }
  
  if opts.system then payload.system = opts.system end

  f:write(vim.fn.json_encode(payload))
  f:close()
  
  local cmd = string.format(
    "curl -s -X POST %s/api/generate -H 'Content-Type: application/json' -d @%s",
    CONFIG.url,
    tmpfile
  )
  
  vim.system({"sh", "-c", cmd}, { text = true }, function(obj)
    os.remove(tmpfile)
    vim.schedule(function()
      if obj.code ~= 0 then
        local err = obj.stderr or "Connection failed"
        if callback then callback(nil, err) end
        return
      end
      
      if not obj.stdout or obj.stdout == "" then
        if callback then callback(nil, "Empty response") end
        return
      end
      
      local ok, response = pcall(vim.fn.json_decode, obj.stdout)
      if not ok then
        if callback then callback(nil, "JSON Parse Error: " .. obj.stdout:sub(1, 50)) end
        return
      end
      
      if response.error then
        if callback then callback(nil, response.error) end
        return
      end
      
      if callback then callback(response.response, nil) end
    end)
  end)
end

function M.is_ready()
  return state.ready
end

return M
