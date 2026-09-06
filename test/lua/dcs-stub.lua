--- Fake DCS scripting environment for the standalone Lua test suite.
--- Lua 5.1 clean. Defines the DCS globals the loaded Skynet source touches,
--- plus fixture factories. Scoped to what milestone 1 (the contact module)
--- needs; grows as more modules are ported.

local now = 0

local scheduled = {}
local nextScheduleId = 0

dcsStub = {}
dcsStub.world = {}          -- name -> fake object, backs *.getByName
dcsStub.logs = {}           -- { { level=, text= }, ... } from env.*
dcsStub.eventHandlers = {}  -- appended by world.addEventHandler

function dcsStub.now()
  return now
end
function dcsStub.setClock(t)
  now = t
end
function dcsStub.advanceClock(dt)
  now = now + dt
end
function dcsStub.reset()
  now = 0
  dcsStub.world = {}
  dcsStub.logs = {}
  dcsStub.eventHandlers = {}
  scheduled = {}
  nextScheduleId = 0
end

function dcsStub.scheduledCount()
  local n = 0
  for _ in pairs(scheduled) do
    n = n + 1
  end
  return n
end

-- ---- enums / singletons -------------------------------------------------
Object = {
  Category = { UNIT = 1, WEAPON = 2, STATIC = 3, BASE = 4, SCENERY = 5, Cargo = 6 },
}
function Object.getCategory(o)
  if o == nil then
    return nil
  end
  if o.isExist and o:isExist() == false then
    return nil -- DCS: a destroyed object reports no category
  end
  return o.__category or Object.Category.UNIT
end

Weapon = { Category = { SHELL = 0, MISSILE = 1, ROCKET = 2, BOMB = 3 } }

-- Skynet's wrapper does `getmetatable(rep) ~= Group` to tell a Group from a
-- Unit/Static. A plain Unit/Static fixture has a nil metatable, so it takes the
-- Unit/Static branch. `dcsStub.makeGroup` sets `setmetatable(g, Group)` on every
-- group fixture (a real DCS Group carries its class), so group fixtures take the
-- Group branch — needed by setupElements()/getUnitsToAnalyse() and the wrapper's
-- getTypeName guard.
Group = {}
Unit = {}
Unit.SensorType = { OPTIC = 0, RADAR = 1, IRST = 2, RWR = 3 }
StaticObject = {}

world = {
  event = { S_EVENT_SHOT = 1, S_EVENT_HIT = 2, S_EVENT_DEAD = 8, S_EVENT_BIRTH = 15 },
}
function world.addEventHandler(h)
  table.insert(dcsStub.eventHandlers, h)
end

local function _log(level, text)
  table.insert(dcsStub.logs, { level = level, text = tostring(text) })
end
env = {
  info = function(t)
    _log("I", t)
  end,
  warning = function(t)
    _log("W", t)
  end,
  error = function(t)
    _log("E", t)
  end,
}

trigger = { action = { outText = function() end, explosion = function() end } }

timer = { getAbsTime = function()
  return now
end }
timer.getTime = function()
  return now
end

mist = mist or {}
function mist.scheduleFunction(fn, args, startTime, interval)
  nextScheduleId = nextScheduleId + 1
  scheduled[nextScheduleId] = { fn = fn, args = args, startTime = startTime, interval = interval }
  return nextScheduleId
end
function mist.removeFunction(id)
  if id ~= nil and scheduled[id] ~= nil then
    scheduled[id] = nil
    return id
  end
  return nil
end

AI = {
  Option = {
    Air = {
      id = { NO_OPTION = -1, ROE = 0 },
      val = { ROE = { WEAPON_FREE = 0, OPEN_FIRE_WEAPON_FREE = 1, OPEN_FIRE = 2, RETURN_FIRE = 3, WEAPON_HOLD = 4 } },
    },
    Ground = {
      id = { NO_OPTION = -1, ROE = 0, ALARM_STATE = 9, ENGAGE_AIR_WEAPONS = 20 },
      val = {
        ROE = { OPEN_FIRE = 2, RETURN_FIRE = 3, WEAPON_HOLD = 4 },
        ALARM_STATE = { AUTO = 0, GREEN = 1, RED = 2 },
      },
    },
  },
}

land = {
  getIP = function()
    return nil
  end,
  isVisible = function()
    return true
  end,
}

-- ---- fixture factory --------------------------------------------------
--- dcsStub.makeUnit{ name=, type=, category=, pos={x=,y=,z=}, heading=, exists=, desc= }
---   pos.y is altitude in metres (DCS convention).
---   heading is radians, grid (0 = +x = grid north; pi/2 = +z = grid east).
function dcsStub.makeUnit(spec)
  spec = spec or {}
  local pos = spec.pos or { x = 0, y = 0, z = 0 }
  local heading = spec.heading or 0
  local u = { __category = spec.category or Object.Category.UNIT }

  function u:getName()
    return spec.name or "unnamed"
  end
  function u:getTypeName()
    return spec.type or "unknown-type"
  end
  function u:getPosition()
    -- p = translation; x/y/z = orientation unit vectors. Skynet reads p.*;
    -- mist.getHeading reads x.x / x.z.
    return {
      p = { x = pos.x, y = pos.y, z = pos.z },
      x = { x = math.cos(heading), y = 0, z = math.sin(heading) },
      y = { x = 0, y = 1, z = 0 },
      z = { x = -math.sin(heading), y = 0, z = math.cos(heading) },
    }
  end
  function u:isExist()
    if spec.exists == nil then
      return true
    end
    return spec.exists
  end
  function u:getDesc()
    return spec.desc or {}
  end
  function u:__setPos(p)
    pos = p
  end
  function u:__setHeading(h)
    heading = h
  end
  u.__controllerCalls = {}
  local controller = {
    setOption = function(_, id, value)
      table.insert(u.__controllerCalls, { id = id, value = value })
    end,
  }
  function u:getController()
    return controller
  end
  function u:getSensors()
    return spec.sensors
  end
  function u:getAmmo()
    return spec.ammo
  end
  function u:__destroy()
    spec.exists = false
  end
  return u
end

function dcsStub.makeGroup(groupSpec)
  groupSpec = groupSpec or {}
  local unitSpecs = groupSpec.units or {}
  local units = {}
  for i = 1, #unitSpecs do
    units[i] = dcsStub.makeUnit(unitSpecs[i])
  end
  local g = {}
  g.__controllerCalls = {}
  local controller = {
    setOption = function(_, id, value)
      table.insert(g.__controllerCalls, { id = id, value = value })
    end,
  }
  function g:getName()
    return groupSpec.name or "unnamed-group"
  end
  function g:getUnits()
    local live = {}
    for i = 1, #units do
      if units[i]:isExist() then
        live[#live + 1] = units[i]
      end
    end
    return live
  end
  function g:getUnit(i)
    return self:getUnits()[i]
  end
  function g:isExist()
    if #units == 0 then
      return true
    end
    return #self:getUnits() > 0
  end
  function g:getController()
    return controller
  end
  function g:__destroy()
    for i = 1, #units do
      units[i]:__destroy()
    end
  end
  if groupSpec.name then
    dcsStub.world[groupSpec.name] = g
  end
  -- A real DCS Group carries its class; Skynet tells a Group from a Unit/Static
  -- via getmetatable(rep) == Group (SkynetIADSAbstractDCSObjectWrapper:create's
  -- getTypeName guard, SkynetIADSAbstractRadarElement:getUnitsToAnalyse). Group
  -- has no __index, so the instance methods defined above still win.
  setmetatable(g, Group)
  return g
end

function dcsStub.makeStatic(spec)
  spec = spec or {}
  local pos = spec.pos or { x = 0, y = 0, z = 0 }
  local s = { __category = Object.Category.STATIC }
  function s:getName()
    return spec.name or "unnamed-static"
  end
  function s:getTypeName()
    return spec.type or "unknown-static"
  end
  function s:getPosition()
    return { p = { x = pos.x, y = pos.y, z = pos.z } }
  end
  function s:isExist()
    if spec.exists == nil then
      return true
    end
    return spec.exists
  end
  function s:getDesc()
    return spec.desc or {}
  end
  function s:__destroy()
    spec.exists = false
  end
  if spec.name then
    dcsStub.world[spec.name] = s
  end
  return s
end

function Unit.getByName(name)
  return dcsStub.world[name]
end
function Group.getByName(name)
  return dcsStub.world[name]
end
function StaticObject.getByName(name)
  return dcsStub.world[name]
end
