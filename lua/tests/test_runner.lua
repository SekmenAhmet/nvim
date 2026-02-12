-- Native IDE Health & Test Runner
-- Validates modules and state management

local function test_git()
  print("Testing Git Client...")
  local git = require("config.git")
  if type(git.toggle) ~= "function" then error("Git toggle missing") end
  print("✓ Git module loaded")
end

local function test_rest()
  print("Testing REST Client...")
  local rest = require("config.rest")
  if type(rest.toggle) ~= "function" then error("REST toggle missing") end
  print("✓ REST module loaded")
end

local function test_docker()
  print("Testing Docker Client...")
  local docker = require("config.docker")
  if type(docker.toggle) ~= "function" then error("Docker toggle missing") end
  print("✓ Docker module loaded")
end

local function test_state()
  print("Testing Global State...")
  local state = require("core.state")
  state.set("git.branch", "test-branch")
  if state.data.git.branch ~= "test-branch" then error("State set failed") end
  print("✓ Global state working")
end

local function run_all()
  local ok, err = pcall(function()
    test_state()
    test_git()
    test_rest()
    test_docker()
  end)

  if ok then
    print("\n✨ All core modules are healthy!")
    os.exit(0)
  else
    print("\n❌ Test failed: " .. tostring(err))
    os.exit(1)
  end
end

run_all()
