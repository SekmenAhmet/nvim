local State = require("core.state")
local DockerController = require("modules.docker.controller")
local DockerView = require("modules.docker.view")
local ViewFactory = require("utils.view_factory")

local function sleep(n)
  os.execute("sleep " .. tonumber(n))
end

local function run_monkey_test()
  print("Starting Docker Monkey Test...")

  -- Ensure we start clean
  State.set("docker.is_active", false)
  DockerController.stop_refresh_timer()

  -- 1. Rapid Toggle Test
  print("Step 1: Rapid Toggle Test (Open/Close)")
  for i = 1, 20 do
    DockerController.toggle()
    if i % 5 == 0 then
      vim.cmd("redraw")
    end
  end
  
  -- Ensure it's open for the next tests
  if not State.get("docker.is_active") then
    DockerController.toggle()
  end
  vim.cmd("redraw")

  -- 2. Rapid State Updates Test (containers)
  print("Step 2: Rapid State Updates (containers)")
  local containers = {}
  for i = 1, 50 do
    containers = {}
    for j = 1, 10 do
      table.insert(containers, {
        id = "cont_" .. j .. "_" .. i,
        name = "container_" .. j,
        state = (i + j) % 2 == 0 and "running" or "exited",
        status = "Up 1 hour",
        image = "nginx:latest"
      })
    end
    State.set("docker.entities.containers", containers)
    if i % 10 == 0 then
      vim.cmd("redraw")
    end
  end

  -- 3. Rapid Selected ID Updates
  print("Step 3: Rapid Selected ID Updates")
  for i = 1, 50 do
    local id = "cont_" .. (i % 10 + 1) .. "_" .. 50
    State.set("docker.selected_id", id)
    if i % 10 == 0 then
      vim.cmd("redraw")
    end
  end

  -- 4. Rapid Tab Switching
  print("Step 4: Rapid Tab Switching")
  for i = 1, 20 do
    local current = State.get("docker.active_tab") or 1
    State.set("docker.active_tab", current == 1 and 2 or 1)
    if i % 5 == 0 then
      vim.cmd("redraw")
    end
  end

  -- 5. Mixed Chaos
  print("Step 5: Mixed Chaos")
  for i = 1, 50 do
    local r = math.random(1, 4)
    if r == 1 then
      DockerController.toggle()
    elseif r == 2 then
      State.set("docker.selected_id", "cont_" .. math.random(1, 10) .. "_50")
    elseif r == 3 then
      local current = State.get("docker.active_tab") or 1
      State.set("docker.active_tab", current == 1 and 2 or 1)
    elseif r == 4 then
      State.set("docker.entity_type", ({"containers", "images", "volumes"})[math.random(1, 3)])
    end
    if i % 10 == 0 then
      vim.cmd("redraw")
    end
  end

  print("Monkey Test Completed Successfully!")
  vim.cmd("qa!")
end

-- Run it
vim.schedule(run_monkey_test)
