local function fix_file(path, fn)
  local f = io.open(path, 'r')
  if not f then return end
  local content = f:read('*all')
  f:close()
  local fixed = fn(content)
  f = io.open(path, 'w')
  f:write(fixed)
  f:close()
end

-- Fix model.lua
fix_file('/home/ahmet/.config/nvim/lua/modules/rest/model.lua', function(c)
  -- Replace any corrupted quote matches with safe ones
  c = c:gsub("%:gsub%(%s*\"%[%'\\\"%s*%]\"%,%s*\"\"%)", ":gsub([[['\"]]], '')")
  c = c:gsub("%:gsub%(%s*\"%[%'\"%s*%]\"%,%s*\"\"%)", ":gsub([[['\"]]], '')")
  c = c:gsub("match%(%s*\"%^%[%'\\\"%s*%]%?%/\"%)", "match([[^['\"]?/]])")
  c = c:gsub("match%(%s*\"%^%[%'\"%s*%]%?%/\"%)", "match([[^['\"]?/]])")
  -- Fix line 74 specifically if needed
  c = c:gsub("gsub%(%s*\"%[%['\"%]%], \"\"%)", "gsub([[['\"]]], '')")
  return c
end)

-- Fix controller.lua
fix_file('/home/ahmet/.config/nvim/lua/modules/rest/controller.lua', function(c)
  -- Fix the body_cnt concat
  c = c:gsub('local body_cnt = table.concat%({ table.unpack%(parts, body_idx%) }, \"\n\n\"%)', 
             'local body_cnt = table.concat({ table.unpack(parts, body_idx) }, "\\r\\n\\r\\n")')
  
  -- Fix the status_code match
  -- It has literal newlines and ?
  c = c:gsub('local status_code = header_part:match%(\"%%\^%(HTTP/%%d%%.%%d %%d+ %[^\n%]%*%)%\") or header_part:match%(\"%%\^%(HTTP/%%d%%.%%d %%d+%)%\") or \"Unknown\"',
             'local status_code = header_part:match("^(HTTP/%%d%%.%%d %%d+ [^\\n]*)") or header_part:match("^(HTTP/%%d%%.%%d %%d+)") or "Unknown"')
  
  -- Fix the display function
  c = c:gsub('vim.bo%[br%].modifiable = true\n\", \"\"\n%), \"\n\"\n%)%)',
             'vim.bo[br].modifiable = true\n        api.nvim_buf_set_lines(br, 0, -1, false, vim.split(content:gsub("\\r", ""), "\\n"))')
             
  return c
end)
