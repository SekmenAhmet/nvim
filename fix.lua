local handle = io.popen("grep -r 'open_in_normal_win' /home/ahmet/.config/nvim/lua")
local result = handle:read("*a")
handle:close()
print(result)
