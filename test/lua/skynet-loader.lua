--- Loads Skynet source files (globals, no modules) in dependency order,
--- the same order build-tools/build-compiled-script.ps1 concatenates them.
--- Usage:
---   local loader = dofile(".../skynet-loader.lua")
---   loader.load("skynet-iads-contact")   -- one file
---   loader.loadAll()                      -- everything

local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "./"
local src = (os.getenv("SKYNET_SRC") or (base .. "/../../skynet-iads-source")) .. "/"

-- Verbatim order from build-compiled-script.ps1 (highdigitsams entry omitted:
-- it is a separate suite, not part of the core load).
local ORDER = {
  "skynet-iads-supported-types",
  "skynet-iads-logger",
  "skynet-iads",
  "skynet-mooose-a2a-dispatcher-connector",
  "skynet-iads-table-delegator",
  "skynet-iads-abstract-dcs-object-wrapper",
  "skynet-iads-abstract-element",
  "skynet-iads-abstract-radar-element",
  "skynet-iads-awacs-radar",
  "skynet-iads-command-center",
  "skynet-iads-contact",
  "skynet-iads-early-warning-radar",
  "skynet-iads-jammer",
  "skynet-iads-sam-search-radar",
  "skynet-iads-sam-site",
  "skynet-iads-sam-tracking-radar",
  "syknet-iads-sam-launcher",
  "skynet-iads-harm-detection",
}

local M = { _loaded = {}, ORDER = ORDER }

function M.load(name)
  if M._loaded[name] then
    return
  end
  local path = src .. name .. ".lua"
  local chunk, err = loadfile(path)
  if not chunk then
    error("skynet-loader: cannot load '" .. name .. "' from " .. path .. "\n" .. tostring(err))
  end
  local ok, execErr = pcall(chunk)
  if not ok then
    error("skynet-loader: '" .. name .. "' failed while executing: " .. tostring(execErr))
  end
  M._loaded[name] = true
end

function M.loadAll()
  for _, name in ipairs(ORDER) do
    M.load(name)
  end
end

function M.reset()
  M._loaded = {}
end

return M
