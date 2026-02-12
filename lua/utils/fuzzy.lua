local M = {}

-- Smart Fuzzy Scoring Algorithm
-- "uc" matches "user_controller", "conf" matches "my_config"
function M.score(str, query)
  if not str or not query then return 0 end
  if query == "" then return 1 end
  
  local str_lower = str:lower()
  local query_lower = query:lower()
  
  -- Exact match first
  if str_lower == query_lower then return 1000 end
  
  -- Extract filename if path
  local filename = str_lower:match("^.+/(.+)$") or str_lower
  if filename == query_lower then return 900 end
  if vim.startswith(filename, query_lower) then return 800 end
  
  -- Fuzzy matching
  local query_idx = 1
  local score = 0
  local last_match = 0
  local consecutive = 0
  
  for i = 1, #str_lower do
    if str_lower:sub(i, i) == query_lower:sub(query_idx, query_idx) then
      -- Bonus start of string
      if i == 1 then score = score + 15 end
      
      -- Bonus start of word (after _ - . /)
      if i > 1 and str_lower:sub(i-1, i-1):match("[%-_%.%/]") then
        score = score + 12
      end
      
      -- Bonus consecutive characters
      if last_match == i - 1 then
        consecutive = consecutive + 1
        score = score + 8 + consecutive * 2
      else
        consecutive = 0
        score = score + 5
      end
      
      -- Malus distance between matches
      if last_match > 0 and i - last_match > 1 then
        score = score - (i - last_match - 1) * 2
      end
      
      query_idx = query_idx + 1
      last_match = i
      
      if query_idx > #query_lower then
        -- Full match! Bonus based on position and length
        local remaining_chars = #str_lower - i
        return score + 100 + math.max(0, 50 - remaining_chars)
      end
    end
  end
  
  -- Fallback: substring if fuzzy fails
  if str_lower:find(query_lower, 1, true) then
    return 100
  end
  
  return 0
end

return M
