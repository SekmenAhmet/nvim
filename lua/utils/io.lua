local M = {}
local uv = vim.uv

-- Lecture de fichier totalement asynchrone
-- Ne bloque JAMAIS l'interface, même sur des fichiers de 1GB
-- @param path string: Chemin absolu ou relatif
-- @param callback function(data: string|nil): Appelée quand la lecture est finie
-- @param opts table: { max_size: number } (Optionnel, pour lire seulement le début)
function M.read_file(path, callback, opts)
  opts = opts or {}
  
  uv.fs_open(path, "r", 438, function(err, fd)
    if err then 
      -- Échec silencieux ou log debug, mais ne pas crasher
      vim.schedule(function() callback(nil) end)
      return 
    end
    
    uv.fs_fstat(fd, function(err_stat, stat)
      if err_stat or not stat then
        uv.fs_close(fd)
        vim.schedule(function() callback(nil) end)
        return
      end
      
      -- Limite de lecture (pour preview des gros fichiers)
      local read_size = stat.size
      if opts.max_size and read_size > opts.max_size then
        read_size = opts.max_size
      end
      
      if read_size == 0 then
        uv.fs_close(fd)
        vim.schedule(function() callback("") end)
        return
      end

      uv.fs_read(fd, read_size, 0, function(err_read, data)
        uv.fs_close(fd)
        if err_read then
          vim.schedule(function() callback(nil) end)
          return
        end
        
        -- Retour sur le thread principal pour le callback
        vim.schedule(function()
          callback(data)
        end)
      end)
    end)
  end)
end

-- Scan asynchrone d'un dossier (Alternative à vim.fn.glob)
-- Utilise scandir de libuv pour la performance
function M.scandir(path, callback)
  uv.fs_scandir(path, function(err, handle)
    if err then return vim.schedule(function() callback({}) end) end
    
    local files = {}
    while true do
      local name, type = uv.fs_scandir_next(handle)
      if not name then break end
      table.insert(files, { name = name, type = type })
    end
    
    vim.schedule(function() callback(files) end)
  end)
end

-- Écriture de fichier asynchrone
function M.write_file(path, content, callback)
  uv.fs_open(path, "w", 438, function(err, fd)
    if err then 
      if callback then vim.schedule(function() callback(err) end) end
      return 
    end
    
    uv.fs_write(fd, content, 0, function(err_write)
      uv.fs_close(fd)
      if callback then
        vim.schedule(function() callback(err_write) end)
      end
    end)
  end)
end

return M
