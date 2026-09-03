--- Fake DCS scripting environment for the standalone Lua test suite.
--- Lua 5.1 clean. Defines the DCS globals the loaded Skynet source touches,
--- plus fixture factories. Scoped to what milestone 1 (the contact module)
--- needs; grows as more modules are ported.

local now = 0

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
end

-- ---- enums / singletons -------------------------------------------------
Object = {
  Category = { UNIT = 1, WEAPON = 2, STATIC = 3, BASE = 4, SCENERY = 5, Cargo = 6 },
}
function Object.getCategory(o)
  if o == nil then
    return nil
  end
  return o.__category or Object.Category.UNIT
end

Weapon = { Category = { SHELL = 0, MISSILE = 1, ROCKET = 2, BOMB = 3 } }

-- Skynet's wrapper does `getmetatable(rep) ~= Group` to tell a Group from a
-- Unit/Static. Fixtures are plain tables (metatable nil), and Group here is a
-- non-nil table, so the comparison is always "not a Group" — the Unit/Static
-- branch, which is what milestone 1 needs. A later milestone that tests Group
-- wrappers gives its Group fixtures `setmetatable(g, Group)`.
Group = {}
Unit = {}
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
  return u
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
