--- Discover and run every test/lua/test_*.lua as a child process, aggregating
--- exit codes.  Usage:  lua run.lua [filenameSubstring]

local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
local sep = package.config:sub(1, 1) -- "\" on Windows, "/" elsewhere
local isWindows = (sep == "\\")
-- On Windows, use the basename lua.exe or lua to avoid path quoting issues.
-- On POSIX, arg[-1] is typically "lua" already.
local interp = "lua"
if arg[-1] then
  -- Use just the basename to avoid quoting issues with spaces
  interp = arg[-1]:match("([^\\/]+)$") or "lua"
  if interp:lower() == "lua" or interp:lower() == "lua.exe" then
    -- Already a basename, but on some systems might need .exe
    interp = "lua"
  end
end
local filter = arg[1]

local function listSuites()
  local cmd
  if isWindows then
    cmd = 'dir /b "' .. base .. '\\test_*.lua"'
  else
    cmd = 'ls -1 "' .. base .. '"/test_*.lua'
  end
  local names = {}
  local p = assert(io.popen(cmd))
  for line in p:lines() do
    local name = line:match("([^\\/]+)$")
    if name and name:match("^test_.+%.lua$") then
      if not filter or name:find(filter, 1, true) then
        names[#names + 1] = name
      end
    end
  end
  p:close()
  table.sort(names)
  return names
end

local suites = listSuites()
if #suites == 0 then
  print("run.lua: no matching suites")
  os.exit(0)
end

local failed = {}
for _, name in ipairs(suites) do
  print("\n--- " .. name .. " ---")
  local ok = os.execute(interp .. " " .. base .. sep .. name)
  -- Lua 5.1 os.execute returns the process exit code (0 == success). Some
  -- builds return true/false; treat both non-zero and false as failure.
  if ok ~= 0 and ok ~= true then
    failed[#failed + 1] = name
  end
end

print("\n======================================")
if #failed == 0 then
  print("ALL " .. #suites .. " SUITE(S) PASSED")
  os.exit(0)
end
print(#failed .. " SUITE(S) FAILED:")
for _, n in ipairs(failed) do
  print("  - " .. n)
end
os.exit(1)
