-- Native AI Client (Ollama)
-- Provides a generic interface for local AI generation.

local M = {}
local api = vim.api

local process = require("utils.process")

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

function M.setup(opts, cb)
  if state.ready then if cb then cb() end return end
  if state.verifying then return end
  
  if opts then
    CONFIG = vim.tbl_deep_extend("force", CONFIG, opts)
  end

  state.verifying = true
  
  -- Check if Ollama is accessible
  process.exec("curl", {
    args = { "-s", CONFIG.url .. "/api/tags" },
    timeout = 2000
  }, function(code, stdout)
    state.verifying = false
    if code == 0 and stdout and stdout:match("models") then
      state.ready = true
      if cb then cb() end
    else
      -- For monkey testing, we might want to just set it to ready if we mock things,
      -- but let's keep it real and see it fail gracefully if no Ollama.
      -- Actually, if we're headless and no Ollama, AI features will keep calling setup.
      -- To stop the loop in tests, we could force it, but let's just log it.
      vim.notify("AI: Ollama not found at " .. CONFIG.url, vim.log.levels.WARN)
    end
  end)
end

-- High-level Helpers
function M.explain(code, cb)
  local prompt = "Explain the following code snippet concisely:\n\n```" .. (vim.bo.filetype or "") .. "\n" .. code .. "\n```"
  M.generate(prompt, { system = "You are a senior developer expert in all programming languages. Be concise." }, cb)
end

function M.refactor(code, cb)
  local prompt = "Refactor the following code to be cleaner, more idiomatic, and more efficient. Only provide the refactored code without explanation:\n\n```" .. (vim.bo.filetype or "") .. "\n" .. code .. "\n```"
  M.generate(prompt, { system = "You are a senior developer. Output ONLY the code blocks." }, cb)
end

function M.fix(code, errors, cb)
  local prompt = "The following code has errors:\n\n```" .. (vim.bo.filetype or "") .. "\n" .. code .. "\n```\n\nErrors:\n" .. errors .. "\n\nFix the code and provide ONLY the corrected code."
  M.generate(prompt, { system = "You are a senior developer. Fix the errors and output ONLY the corrected code." }, cb)
end

-- Updated Generate using process.exec
function M.generate(prompt, opts, callback)
  if not state.ready then
    M.setup(nil, function() M.generate(prompt, opts, callback) end)
    vim.notify("Initializing AI...", vim.log.levels.INFO)
    return
  end
  
  opts = opts or {}
  local payload = {
    model = opts.model or CONFIG.model,
    prompt = prompt,
    stream = false,
    options = {
      temperature = opts.temperature or 0.3,
      num_predict = opts.num_predict or 500,
    }
  }
  if opts.system then payload.system = opts.system end

  local data = vim.fn.json_encode(payload)
  
  process.exec("curl", {
    args = { "-s", "-X", "POST", CONFIG.url .. "/api/generate", "-H", "Content-Type: application/json", "-d", "@-" },
    stdin = data,
    timeout = CONFIG.timeout
  }, function(code, stdout, stderr)
    if code ~= 0 then
      if callback then callback(nil, "Curl failed: " .. stderr) end
      return
    end
    
    local ok, response = pcall(vim.fn.json_decode, stdout)
    if not ok then
      if callback then callback(nil, "JSON Decode failed") end
      return
    end
    
    if response.error then
      if callback then callback(nil, response.error) end
    else
      if callback then callback(response.response, nil) end
    end
  end)
end

function M.is_ready()
  return state.ready
end

return M
