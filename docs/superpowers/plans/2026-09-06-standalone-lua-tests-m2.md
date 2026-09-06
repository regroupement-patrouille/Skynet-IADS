# Standalone Lua Test Suite — Milestone 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the six DCS-independent suites from `unit-tests/` into the standalone `test/lua/` harness, growing `dcs-stub.lua` and adding a shared `dcs-fixtures.lua` for the SAM-shaped setups.

**Architecture:** M1 built `test/lua/` (vendored luaunit, `dcs-stub.lua`, `mist-stub.lua`, `skynet-loader.lua`, `run.lua`) and ported `contact`. This milestone grows the stub with a fake scheduler, `timer.getTime`, `AI.Option`, `land.*`, a `mist` slice, fixture `__destroy()`, and `makeGroup`/`makeStatic`; adds `dcs-fixtures.lua` (SAM group builders keyed to `samTypesDB`, connection-node builders, an `iadsContact` factory); then ports one suite per task. `run.lua`, CI, the loader, and `unit-tests/*.miz` are untouched.

**Tech Stack:** Lua 5.1 (LuaJIT-compatible), luaunit 3.4.

**Spec:** `docs/superpowers/specs/2026-09-06-standalone-lua-tests-m2-design.md`

## Global Constraints

- **Lua 5.1 only.** No `goto`, no `//`, no bitwise operators, `unpack` not `table.unpack`. `os`/`io` allowed ONLY in `run.lua` and `test_*.lua` files — NEVER in `dcs-stub.lua`, `mist-stub.lua`, `dcs-fixtures.lua`, `skynet-loader.lua`.
- **Skynet source under `skynet-iads-source/*.lua` is loaded via the loader, never modified.**
- **Interpreter for local steps:** no `lua5.1` on PATH on this machine. Set once per shell:
  - git-bash: `LUA="/c/Program Files (x86)/Lua/5.1/lua.exe"`
  - CI / Linux: `LUA=lua5.1`
- Every stubbed `mist` function carries a `-- copied from demo-missions/mist_4_5_107.lua : <fn>` comment.
- Magic numbers in ported tests are recomputed from the code-defined fixtures with the arithmetic shown in a comment. Adjust the fixture, not the assertion.
- `run.lua`'s M1 form stands — do not reintroduce a `_find_lua`-style version-candidate search.
- Ported suite files are named `test_skynet_*.lua` (underscores), matching the M1 pilot `test_skynet_iads_contact.lua`, so `run.lua`'s `^test_.+%.lua$` glob picks them up.
- Each ported suite bootstraps with `loader.loadAll()` (loads all 18 source modules in dependency order — simplest, and Task 1 keeps it working). Bootstrap `dofile` paths use explicit `/` separators.
- Commit trailer, exactly:
  `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`

## Orientation for the implementer

- `dcsStub` (from M1 `test/lua/dcs-stub.lua`) already provides: `dcsStub.reset()`, `dcsStub.now()`, `dcsStub.setClock(t)`, `dcsStub.advanceClock(dt)`, `dcsStub.world` (name→object registry backing `Unit.getByName`/`Group.getByName`/`StaticObject.getByName`), `dcsStub.logs`, `dcsStub.eventHandlers`, `dcsStub.makeUnit{ name, type, category, pos={x,y,z}, heading, exists, desc }` → object with `getName/getTypeName/getPosition/isExist/getDesc/__setPos/__setHeading`. `Object.getCategory` returns `nil` for a destroyed (`isExist()==false`) fixture. `timer.getAbsTime()` returns the model clock.
- `mist-stub.lua` provides `mist.utils.round/toDegree/metersToNM/metersToFeet/get2DDist` and `mist.getHeading`.
- `skynet-loader.lua` provides `loader.load(name)`, `loader.loadAll()`, `loader.reset()`. `load` does NOT pull dependencies; `loadAll` walks the full ordered list.
- The source constructors this milestone touches:
  - `SkynetIADS:create(name?)` — needs `SkynetIADSHARMDetection`, `SkynetIADSLogger`, `world.addEventHandler` (all covered by `loadAll` + stub).
  - `SkynetIADSHARMDetection:create(iads)`
  - `SkynetIADSJammer:create(emitter, iads)` — `emitter` is a unit, `iads` a `SkynetIADS` (or a mock with `getDebugSettings`).
  - `SkynetIADSAbstractElement:create(group, iads)`
  - `SkynetIADSSamSite:create(group, iads)` — `group` is a `Group`; `setupElements()` walks `group:getUnits()`, matching each `unit:getTypeName()` against `samTypesDB` and reading `unit:getSensors()` (search radars) / `unit:getAmmo()` (launchers).

---

### Task 1: Grow `dcs-stub.lua`

**Files:**
- Modify: `test/lua/dcs-stub.lua`
- Modify: `test/lua/mist-stub.lua`
- Test: `test/lua/test_dcs_stub.lua` (extend — scheduler, `timer.getTime`, `AI.Option`, `Unit.SensorType`, `__destroy`, controller, `makeGroup`/`makeStatic`)
- Test: `test/lua/test_mist_stub.lua` (extend — `get3DDist`, `random`)

**Interfaces:**
- Consumes: the M1 `dcsStub` internals (the module-local `now`, the `dcsStub` table, `dcsStub.reset`).
- Produces — after `dofile("dcs-stub.lua")`:
  - `mist.scheduleFunction(fn, args, startTime, interval)` → integer id (from 1, increasing)
  - `mist.removeFunction(id)` → the id if a live task was removed, else `nil`. `mist.removeFunction(nil)` → `nil` (no error).
  - `dcsStub.scheduledCount()` → number of live scheduled tasks
  - `dcsStub.reset()` also clears the scheduler task table and resets the id counter
  - `timer.getTime()` → the model clock (same value as `timer.getAbsTime()`)
  - `AI.Option.Ground.id.ENGAGE_AIR_WEAPONS` (20), `AI.Option.Ground.id.ALARM_STATE` (9), `AI.Option.Ground.id.ROE` (0), `AI.Option.Ground.val.ALARM_STATE.RED` (2) / `.GREEN` (1) / `.AUTO` (0), `AI.Option.Ground.val.ROE.WEAPON_HOLD` (4) / `.RETURN_FIRE` (3) / `.OPEN_FIRE` (2), `AI.Option.Air.id.ROE` (0), `AI.Option.Air.val.ROE.WEAPON_FREE` (0) / `.WEAPON_HOLD` (4)
  - `Unit.SensorType` = `{ OPTIC = 0, RADAR = 1, IRST = 2, RWR = 3 }`
  - `Weapon.Category` — already exists from M1 (`{ SHELL = 0, MISSILE = 1, ROCKET = 2, BOMB = 3 }`)
  - `land.getIP(origin, direction, distance)` → `nil`; `land.isVisible(from, to)` → `true`
  - `mist.random(m, n)` → `math.random(m, n)`
  - `mist.utils.get3DDist(a, b)` → `((a.x-b.x)^2 + (a.y-b.y)^2 + (a.z-b.z)^2)^0.5`
  - `dcsStub.makeUnit{...}` object gains `__destroy()` (sets `isExist()` to return `false`) and `getController()` (→ a controller stub `{ setOption = function() end }` that records calls into a list readable via `<unit>.__controllerCalls`), plus `getSensors()` (returns `spec.sensors` or `nil`) and `getAmmo()` (returns `spec.ammo` or `nil`)
  - `dcsStub.makeGroup{ name =, units = { <makeUnit spec>, ... } }` → object with `getName()`, `getUnits()` (returns the live [`isExist()`] unit objects), `getUnit(i)`, `isExist()` (true while any unit exists, or always true if `units` empty), `getController()` (controller stub, shared recording list `<group>.__controllerCalls`), `__destroy()` (destroys every unit). Registered into `dcsStub.world`.
  - `dcsStub.makeStatic{ name =, type =, pos = {x,y,z}, exists = }` → object with `getName/getTypeName/getPosition/isExist/getDesc/__destroy`. Registered into `dcsStub.world`.

- [ ] **Step 1: Write the failing tests** — append these to `test/lua/test_dcs_stub.lua`, before its final `os.exit(...)` line:

```lua
function TestDcsStub:test_scheduler_ids_and_removal()
  dcsStub.reset()
  luaunit.assertEquals(dcsStub.scheduledCount(), 0)
  local id1 = mist.scheduleFunction(function() end, {}, 1, 10)
  local id2 = mist.scheduleFunction(function() end, {}, 1, 10)
  luaunit.assertEquals(id1, 1)
  luaunit.assertEquals(id2, 2)
  luaunit.assertEquals(dcsStub.scheduledCount(), 2)
  luaunit.assertEquals(mist.removeFunction(id1), id1) -- truthy on hit
  luaunit.assertEquals(dcsStub.scheduledCount(), 1)
  luaunit.assertNil(mist.removeFunction(id1)) -- already gone
  luaunit.assertNil(mist.removeFunction(999)) -- unknown
  luaunit.assertNil(mist.removeFunction(nil)) -- nil-safe
end

function TestDcsStub:test_reset_clears_scheduler()
  mist.scheduleFunction(function() end, {}, 1, 1)
  dcsStub.reset()
  luaunit.assertEquals(dcsStub.scheduledCount(), 0)
  luaunit.assertEquals(mist.scheduleFunction(function() end, {}, 1, 1), 1) -- counter reset
end

function TestDcsStub:test_timer_getTime_tracks_clock()
  dcsStub.reset()
  dcsStub.setClock(400)
  luaunit.assertEquals(timer.getTime(), 400)
  luaunit.assertEquals(timer.getTime(), timer.getAbsTime())
end

function TestDcsStub:test_ai_option_values()
  luaunit.assertEquals(AI.Option.Ground.id.ENGAGE_AIR_WEAPONS, 20)
  luaunit.assertEquals(AI.Option.Ground.id.ALARM_STATE, 9)
  luaunit.assertEquals(AI.Option.Ground.val.ALARM_STATE.RED, 2)
  luaunit.assertEquals(AI.Option.Air.id.ROE, 0)
  luaunit.assertEquals(AI.Option.Air.val.ROE.WEAPON_FREE, 0)
  luaunit.assertEquals(AI.Option.Air.val.ROE.WEAPON_HOLD, 4)
end

function TestDcsStub:test_unit_destroy_and_category()
  dcsStub.reset()
  local u = dcsStub.makeUnit({ name = "d1", type = "T", pos = { x = 0, y = 0, z = 0 } })
  luaunit.assertEquals(u:isExist(), true)
  luaunit.assertEquals(Object.getCategory(u), Object.Category.UNIT)
  u:__destroy()
  luaunit.assertEquals(u:isExist(), false)
  luaunit.assertNil(Object.getCategory(u)) -- M1: destroyed => nil
end

function TestDcsStub:test_unit_controller_records_setOption()
  local u = dcsStub.makeUnit({ name = "c1" })
  u:getController():setOption(AI.Option.Air.id.ROE, AI.Option.Air.val.ROE.WEAPON_HOLD)
  luaunit.assertEquals(#u.__controllerCalls, 1)
  luaunit.assertEquals(u.__controllerCalls[1].id, AI.Option.Air.id.ROE)
  luaunit.assertEquals(u.__controllerCalls[1].value, AI.Option.Air.val.ROE.WEAPON_HOLD)
end

function TestDcsStub:test_makeGroup_units_and_destroy()
  dcsStub.reset()
  local g = dcsStub.makeGroup({
    name = "G1",
    units = {
      { name = "G1-1", type = "Kub 1S91 str", pos = { x = 0, y = 0, z = 0 } },
      { name = "G1-2", type = "Kub 2P25 ln", pos = { x = 1, y = 0, z = 0 } },
    },
  })
  luaunit.assertIs(Group.getByName("G1"), g)
  luaunit.assertEquals(g:getName(), "G1")
  luaunit.assertEquals(#g:getUnits(), 2)
  luaunit.assertEquals(g:getUnits()[1]:getTypeName(), "Kub 1S91 str")
  g:getUnits()[1]:__destroy()
  luaunit.assertEquals(#g:getUnits(), 1) -- live units only
  g:__destroy()
  luaunit.assertEquals(#g:getUnits(), 0)
end

function TestDcsStub:test_makeStatic_registry_and_destroy()
  dcsStub.reset()
  local s = dcsStub.makeStatic({ name = "S1", type = "Comms tower M", pos = { x = 0, y = 0, z = 0 } })
  luaunit.assertIs(StaticObject.getByName("S1"), s)
  luaunit.assertEquals(s:isExist(), true)
  s:__destroy()
  luaunit.assertEquals(s:isExist(), false)
end

```

`mist.utils.get3DDist` and `mist.random` are tested in `test/lua/test_mist_stub.lua`
(which loads `mist-stub.lua`; `test_dcs_stub.lua` does not). Append these to
`test_mist_stub.lua` before its final `os.exit(...)` line:

```lua
function TestMistStub:test_get3DDist()
  luaunit.assertAlmostEquals(mist.utils.get3DDist({ x = 0, y = 0, z = 0 }, { x = 3, y = 0, z = 4 }), 5, 1e-9)
  luaunit.assertAlmostEquals(mist.utils.get3DDist({ x = 0, y = 0, z = 0 }, { x = 0, y = 12, z = 0 }), 12, 1e-9)
end

function TestMistStub:test_random_in_range()
  for _ = 1, 20 do
    local r = mist.random(3, 5)
    luaunit.assertEquals(r >= 3 and r <= 5, true)
  end
  luaunit.assertEquals(mist.random(1) >= 1, true)
end
```

- [ ] **Step 2: Run to verify failure**

```bash
"$LUA" test/lua/test_dcs_stub.lua
"$LUA" test/lua/test_mist_stub.lua
```
Expected: both FAIL — `attempt to call field 'scheduleFunction' (a nil value)` / `AI` is nil / `mist.utils.get3DDist` nil / etc.

- [ ] **Step 3: Grow `mist-stub.lua`** — append these, each with the copy comment:

```lua
-- copied from demo-missions/mist_4_5_107.lua : mist.utils.get3DDist (= mist.vec.mag of the delta)
function mist.utils.get3DDist(point1, point2)
  local dx = point1.x - point2.x
  local dy = point1.y - point2.y
  local dz = point1.z - point2.z
  return (dx * dx + dy * dy + dz * dz) ^ 0.5
end

-- copied from demo-missions/mist_4_5_107.lua : mist.random (integer, no decimals) — simplified to the
-- underlying math.random(l, u); the real one biases toward >=50 sample points, which is irrelevant
-- to correctness here.
function mist.random(firstNum, secondNum)
  if not secondNum then
    return math.random(1, firstNum)
  end
  return math.random(firstNum, secondNum)
end
```

- [ ] **Step 4: Grow `dcs-stub.lua`**

4a. **Scheduler** — near the top, after the `now` local, add a task table and counter; extend `dcsStub.reset()`:

```lua
local scheduled = {}
local nextScheduleId = 0
```

In `dcsStub.reset()` add:
```lua
  scheduled = {}
  nextScheduleId = 0
```

Add helper:
```lua
function dcsStub.scheduledCount()
  local n = 0
  for _ in pairs(scheduled) do
    n = n + 1
  end
  return n
end
```

4b. **`mist` on the stub side** — `dcs-stub.lua` owns `mist.scheduleFunction`/`removeFunction` (they are DCS-runtime-shaped, not pure math, so they live with the stub, not `mist-stub.lua`). After the `timer` block:

```lua
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
```

4c. **`timer.getTime`** — in the `timer` table:
```lua
timer.getTime = function()
  return now
end
```

4d. **`AI.Option`** (values from `VEAF-Mission-Creation-Tools/test/lua/dcs_mocks.lua`, itself sourced from the DCS API schema):
```lua
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
```

4e. **`Unit.SensorType`** — after the `Unit = {}` line:
```lua
Unit.SensorType = { OPTIC = 0, RADAR = 1, IRST = 2, RWR = 3 }
```

4f. **`land`**:
```lua
land = {
  getIP = function()
    return nil
  end,
  isVisible = function()
    return true
  end,
}
```

4g. **`makeUnit` additions** — inside `dcsStub.makeUnit`, before `return u`:
```lua
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
```
(The M1 `isExist` already reads `spec.exists` live, so flipping it is enough.)

4h. **`makeGroup`**:
```lua
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
  return g
end
```

4i. **`makeStatic`**:
```lua
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
```

- [ ] **Step 5: Run to verify pass**

```bash
"$LUA" test/lua/test_dcs_stub.lua      # all pass
"$LUA" test/lua/test_mist_stub.lua     # all pass
"$LUA" test/lua/run.lua                # ALL 4 SUITE(S) PASSED — M1 suites still green
```

- [ ] **Step 6: Verify `loadAll()` still works with the grown stub**

```bash
"$LUA" -e 'dofile("test/lua/dcs-stub.lua"); dofile("test/lua/mist-stub.lua"); local L=dofile("test/lua/skynet-loader.lua"); L.loadAll(); print("loadAll OK: ", type(SkynetIADSSamSite), type(SkynetIADSJammer), type(SkynetIADSHARMDetection))'
```
Expected: `loadAll OK:  table  table  table`

- [ ] **Step 7: Commit**

```bash
git add test/lua/dcs-stub.lua test/lua/mist-stub.lua test/lua/test_dcs_stub.lua test/lua/test_mist_stub.lua
git commit -m "$(printf 'test: grow dcs-stub for the M2 suites (scheduler, AI.Option, groups)\n\nAdds a no-fire fake scheduler (mist.scheduleFunction/removeFunction +\ndcsStub.scheduledCount), timer.getTime, AI.Option, Unit.SensorType,\nland.getIP/isVisible, mist.random/get3DDist, fixture __destroy(), and\nmakeGroup/makeStatic with a recording controller stub.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>')"
```

---

### Task 2: `dcs-fixtures.lua`

**Files:**
- Create: `test/lua/dcs-fixtures.lua`
- Test: `test/lua/test_dcs_fixtures.lua`

**Interfaces:**
- Consumes: `dcs-stub.lua` (`dcsStub.makeUnit/makeGroup/makeStatic`, `Unit.SensorType`, `Weapon.Category`), `skynet-loader.lua` (`loader.loadAll`), `mist-stub.lua`.
- Produces — `dofile("dcs-fixtures.lua")` returns a table `F`:
  - `F.samGroup(natoShort, groupName)` → a registered `Group` whose units make `SkynetIADSSamSite:setupElements()` classify it. Supported `natoShort`: `"SA-2"`, `"SA-6"`. Returns the group object.
  - `F.connectionNodeUnit(name)` → a registered plain `Unit` (exists, position `{0,0,0}`).
  - `F.connectionNodeStatic(name)` → a registered plain `StaticObject`.
  - `F.iadsContact(unitName)` → looks up `dcsStub.world[unitName]`, wraps it in `SkynetIADSContact:create({ object = <unit> })`, calls `:refresh()`, returns the contact. Requires `SkynetIADSContact` loaded (the caller has run `loader.loadAll()`).

**Fixture composition reference** (`skynet-iads-source/skynet-iads-supported-types.lua`):
- `samTypesDB['Kub']` — `searchRadar` key `'Kub 1S91 str'`, `launchers` key `'Kub 2P25 ln'`, NATO `'SA-6 Gainful'`. No tracking radar. Matcher accepts `(searchRadar and launchers)`.
- `samTypesDB['S-75']` — `searchRadar` key `'p-19 s-125 sr'`, `trackingRadar` key `'SNR_75V'`, `launchers` key `'S_75M_Volhov'`, NATO `'SA-2 Guideline'`.
- Search radar units need `getSensors()` → `{ { { type = Unit.SensorType.RADAR, detectionDistanceAir = { upperHemisphere = { headOn = R }, lowerHemisphere = { headOn = R } } } } }` (nested one level as the source iterates `data[i]` then `subEntries[j]`). Use `R = 120000` (m).
- Launcher units need `getAmmo()` → `{ { desc = { category = Weapon.Category.MISSILE, rangeMaxAltMin = 40000, rangeMaxAltMax = 40000, altMax = 12000 }, count = C } }`. Use `count = 3` per launcher, two launchers → 6 total (matches the `getInitialNumberOfMissiles() == 6` assertion in the sam-site destruction test).

- [ ] **Step 1: Write the failing test** — `test/lua/test_dcs_fixtures.lua`:

```lua
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
dofile(base .. "/mist-stub.lua")
local loader = dofile(base .. "/skynet-loader.lua")
loader.loadAll()
local F = dofile(base .. "/dcs-fixtures.lua")

TestDcsFixtures = {}

function TestDcsFixtures:setUp()
  dcsStub.reset()
end

function TestDcsFixtures:test_samGroup_SA6_classifies()
  local g = F.samGroup("SA-6", "test-SA-6")
  luaunit.assertIs(Group.getByName("test-SA-6"), g)
  local site = SkynetIADSSamSite:create(g, SkynetIADS:create())
  site:setupElements()
  luaunit.assertEquals(site:getNatoName(), "SA-6 Gainful")
  luaunit.assertEquals(site:getInitialNumberOfMissiles(), 6)
end

function TestDcsFixtures:test_samGroup_SA2_classifies()
  local g = F.samGroup("SA-2", "test-SA-2")
  local site = SkynetIADSSamSite:create(g, SkynetIADS:create())
  site:setupElements()
  luaunit.assertEquals(site:getNatoName(), "SA-2 Guideline")
end

function TestDcsFixtures:test_connectionNode_helpers_register()
  local u = F.connectionNodeUnit("cn-unit")
  local s = F.connectionNodeStatic("cn-static")
  luaunit.assertIs(Unit.getByName("cn-unit"), u)
  luaunit.assertIs(StaticObject.getByName("cn-static"), s)
  luaunit.assertEquals(u:isExist(), true)
  luaunit.assertEquals(s:isExist(), true)
end

function TestDcsFixtures:test_iadsContact_returns_refreshed_contact()
  dcsStub.setClock(100)
  dcsStub.world["ctc"] = dcsStub.makeUnit({ name = "ctc", type = "F-16C", pos = { x = 0, y = 500, z = 0 } })
  local contact = F.iadsContact("ctc")
  luaunit.assertEquals(contact:getTypeName(), "F-16C")
  luaunit.assertEquals(contact:getNumberOfTimesHitByRadar(), 1) -- refresh() ran once
end

os.exit(luaunit.LuaUnit.run())
```

- [ ] **Step 2: Run to verify failure**

```bash
"$LUA" test/lua/test_dcs_fixtures.lua
```
Expected: FAIL — `cannot open test/lua/dcs-fixtures.lua`.

- [ ] **Step 3: Write `dcs-fixtures.lua`**

```lua
--- Reusable fixture builders for the standalone Lua test suite. Uses the
--- dcsStub globals; no os/io. SAM group compositions are keyed to
--- skynet-iads-source/skynet-iads-supported-types.lua (samTypesDB).

local F = {}

local RADAR_RANGE_M = 120000

local function searchRadarSensors()
  -- shape iterated by SkynetIADSSAMSearchRadar:setupRangeData (data[i] -> subEntries[j])
  return {
    {
      {
        type = Unit.SensorType.RADAR,
        detectionDistanceAir = {
          upperHemisphere = { headOn = RADAR_RANGE_M },
          lowerHemisphere = { headOn = RADAR_RANGE_M },
        },
      },
    },
  }
end

local function launcherAmmo(count)
  return {
    {
      desc = {
        category = Weapon.Category.MISSILE,
        rangeMaxAltMin = 40000,
        rangeMaxAltMax = 40000,
        altMax = 12000,
      },
      count = count,
    },
  }
end

-- natoShort -> ordered unit specs (types verbatim from samTypesDB)
local SAM_COMPOSITIONS = {
  ["SA-6"] = function(groupName)
    return {
      { name = groupName .. "-sr", type = "Kub 1S91 str", sensors = searchRadarSensors() },
      { name = groupName .. "-ln1", type = "Kub 2P25 ln", ammo = launcherAmmo(3) },
      { name = groupName .. "-ln2", type = "Kub 2P25 ln", ammo = launcherAmmo(3) },
    }
  end,
  ["SA-2"] = function(groupName)
    return {
      { name = groupName .. "-sr", type = "p-19 s-125 sr", sensors = searchRadarSensors() },
      { name = groupName .. "-tr", type = "SNR_75V", sensors = searchRadarSensors() },
      { name = groupName .. "-ln1", type = "S_75M_Volhov", ammo = launcherAmmo(3) },
      { name = groupName .. "-ln2", type = "S_75M_Volhov", ammo = launcherAmmo(3) },
    }
  end,
}

function F.samGroup(natoShort, groupName)
  local build = SAM_COMPOSITIONS[natoShort]
  if not build then
    error("dcs-fixtures: no SAM composition for '" .. tostring(natoShort) .. "'")
  end
  local units = build(groupName)
  for i = 1, #units do
    units[i].pos = units[i].pos or { x = i, y = 0, z = 0 }
  end
  return dcsStub.makeGroup({ name = groupName, units = units })
end

function F.connectionNodeUnit(name)
  local u = dcsStub.makeUnit({ name = name, type = "Ural-375", pos = { x = 0, y = 0, z = 0 } })
  dcsStub.world[name] = u
  return u
end

function F.connectionNodeStatic(name)
  return dcsStub.makeStatic({ name = name, type = "Comms tower M", pos = { x = 0, y = 0, z = 0 } })
end

function F.iadsContact(unitName)
  local unit = dcsStub.world[unitName]
  if not unit then
    error("dcs-fixtures: no fixture registered as '" .. tostring(unitName) .. "'")
  end
  local contact = SkynetIADSContact:create({ object = unit })
  contact:refresh()
  return contact
end

return F
```

- [ ] **Step 4: Run to verify pass**

```bash
"$LUA" test/lua/test_dcs_fixtures.lua   # all pass
"$LUA" test/lua/run.lua                 # ALL 5 SUITE(S) PASSED
```

If `test_samGroup_*` fails on the NATO name, the unit `type` strings do not match `samTypesDB` — re-check them against `skynet-iads-source/skynet-iads-supported-types.lua` (do not change the assertion).

- [ ] **Step 5: Commit**

```bash
git add test/lua/dcs-fixtures.lua test/lua/test_dcs_fixtures.lua
git commit -m "$(printf 'test: add dcs-fixtures — SAM group builders + connection-node + contact factory\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>')"
```

---

### Task 3: Port `harm-detection`

**Files:**
- Create: `test/lua/test_skynet_iads_harm_detection.lua`
- Port from: `unit-tests/test-skynet-iads-harm-detection.lua` (7 tests, all mock-driven)

**Interfaces:**
- Consumes: `luaunit`, `loader.loadAll`, `dcs-stub`, `mist-stub`.
- Produces: a self-executing suite `TestSkynetIADSHARMDetection`.

- [ ] **Step 1: Write the suite** — bootstrap + port. Bootstrap:

```lua
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
dofile(base .. "/mist-stub.lua")
local loader = dofile(base .. "/skynet-loader.lua")
loader.loadAll()
```

Then copy every `function TestSkynetIADSHARMDetection:...` body from `unit-tests/test-skynet-iads-harm-detection.lua` **verbatim**, with these mechanical substitutions:
- `lu.assertEquals` → `luaunit.assertEquals`, `lu.assertIs` → `luaunit.assertIs`, etc. (the M1 pilot uses the `luaunit` global; `lu` is the `.miz` alias). Do this for every `lu.` in the file.
- `setUp` becomes:
  ```lua
  function TestSkynetIADSHARMDetection:setUp()
    dcsStub.reset()
    local iads = SkynetIADS:create()
    self.harmDetection = SkynetIADSHARMDetection:create(iads)
  end
  ```
- All 7 tests use only local mock tables after that — no other change.

End the file with:
```lua
os.exit(luaunit.LuaUnit.run())
```

- [ ] **Step 2: Run**

```bash
"$LUA" test/lua/test_skynet_iads_harm_detection.lua
```
Expected: `Ran 7 tests ... OK`. If a test fails, it is a real behaviour difference — investigate, do not silence.

- [ ] **Step 3: Full suite + commit**

```bash
"$LUA" test/lua/run.lua                 # ALL 6 SUITE(S) PASSED
git add test/lua/test_skynet_iads_harm_detection.lua
git commit -m "$(printf 'test: port the harm-detection suite to the standalone harness\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>')"
```

---

### Task 4: Port `abstract-dcs-object-wrapper`

**Files:**
- Create: `test/lua/test_skynet_iads_abstract_dcs_object_wrapper.lua`
- Port from: `unit-tests/test-skynet-iads-abstract-dcs-object-wrapper.lua` (7 tests)

**Interfaces:**
- Consumes: `luaunit`, `loader` (needs only `skynet-iads-abstract-dcs-object-wrapper`, but use `loader.loadAll()` for consistency), `dcs-stub`.
- Produces: `TestSkynetIADSAbstractDCSObjectWrapper`.

- [ ] **Step 1: Write the suite**

Bootstrap as in Task 3 (luaunit + dcs-stub + mist-stub + `loader.loadAll()`).

`setUp` — the `.miz` version does `SkynetIADSAbstractDCSObjectWrapper:create(Unit.getByName('EW-SA-6'))`, where `EW-SA-6` is a "Kub 1S91 str" that exists. Port:
```lua
function TestSkynetIADSAbstractDCSObjectWrapper:setUp()
  dcsStub.reset()
  self.unit = dcsStub.makeUnit({ name = "EW-SA-6", type = "Kub 1S91 str", pos = { x = 0, y = 0, z = 0 } })
  dcsStub.world["EW-SA-6"] = self.unit
  self.abstractObjectWrapper = SkynetIADSAbstractDCSObjectWrapper:create(self.unit)
end
```

Port the 7 tests verbatim with `lu.` → `luaunit.` substitution. Notes:
- `testGetName` / `testGetTypeName` / `testIsExist` set `self.abstractObjectWrapper.dcsRepresentation = nil` mid-test and assert the cached name/type still returns — unchanged, works against the fixture.
- `testGetDCSRepresentation` asserts `== Unit.getByName('EW-SA-6')` — resolves from the registry to `self.unit`. Change the literal to `self.unit` for clarity, or leave `Unit.getByName('EW-SA-6')` (both are the same object).
- `testInsertToTableIfNotAlreadyAdded` — pure logic, verbatim.

End with `os.exit(luaunit.LuaUnit.run())`.

- [ ] **Step 2: Run**

```bash
"$LUA" test/lua/test_skynet_iads_abstract_dcs_object_wrapper.lua
```
Expected: `Ran 7 tests ... OK`.

- [ ] **Step 3: Full suite + commit**

```bash
"$LUA" test/lua/run.lua                 # ALL 7 SUITE(S) PASSED
git add test/lua/test_skynet_iads_abstract_dcs_object_wrapper.lua
git commit -m "$(printf 'test: port the abstract-dcs-object-wrapper suite to the standalone harness\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>')"
```

---

### Task 5: Port `moose-a2a-connector` (1 test)

**Files:**
- Create: `test/lua/test_skynet_moose_a2a_dispatcher_connector.lua`
- Port from: `unit-tests/test-skynet-moose-a2a-dispatcher-connector.lua` — **only `testAddMooseSetGroupAndUpdate`**

**Interfaces:**
- Consumes: `luaunit`, `loader.loadAll`, `dcs-stub`.
- Produces: `TestMooseA2ADispatcherConnector` with one test.

- [ ] **Step 1: Write the suite**

Bootstrap as in Task 3. Header comment:
```lua
--- Standalone port of unit-tests/test-skynet-moose-a2a-dispatcher-connector.lua.
--- Only testAddMooseSetGroupAndUpdate ports — it is pure-mock. The other two
--- (testGetEarlyWarningRadarGroupNames / testGetSAMSitesGroupNames) call
--- addEarlyWarningRadarsByPrefix / addSAMSitesByPrefix, which enumerate the
--- 17-EW / 17-SAM demo world; they stay in the .miz suite.
```

`setUp`:
```lua
function TestMooseA2ADispatcherConnector:setUp()
  dcsStub.reset()
  self.iads = SkynetIADS:create()
  self.connector = SkynetMooseA2ADispatcherConnector:create(self.iads)
end

function TestMooseA2ADispatcherConnector:tearDown()
  self.iads:deactivate()
end
```
(The `.miz` `setUp` also calls `addEarlyWarningRadarsByPrefix("EW")` / `addSAMSitesByPrefix("SAM")`; the one ported test overrides `getSAMSiteGroupNames` / `getEarlyWarningRadarGroupNames` and never touches the IADS's real radar lists, so drop those two calls.)

Port `testAddMooseSetGroupAndUpdate` verbatim (`lu.` → `luaunit.`). End with `os.exit(luaunit.LuaUnit.run())`.

- [ ] **Step 2: Run**

```bash
"$LUA" test/lua/test_skynet_moose_a2a_dispatcher_connector.lua
```
Expected: `Ran 1 tests ... OK`. If `SkynetMooseA2ADispatcherConnector:create` or `iads:deactivate()` errors on a missing stub, add the missing surface to `dcs-stub.lua` (and its `test_dcs_stub.lua` coverage) — commit that as a separate small fix, then continue.

- [ ] **Step 3: Full suite + commit**

```bash
"$LUA" test/lua/run.lua                 # ALL 8 SUITE(S) PASSED
git add test/lua/test_skynet_moose_a2a_dispatcher_connector.lua
git commit -m "$(printf 'test: port the moose-a2a-connector mock test to the standalone harness\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>')"
```

---

### Task 6: Port `jammer`

**Files:**
- Create: `test/lua/test_skynet_iads_jammer.lua`
- Port from: `unit-tests/test-skynet-iads-jammer.lua` (9 tests)

**Interfaces:**
- Consumes: `luaunit`, `loader.loadAll`, `dcs-stub` (scheduler, `dcsStub.scheduledCount`, `__destroy`), `mist-stub`.
- Produces: `TestSkynetIADSJammer`.

**Behaviour reference** — `SkynetIADSJammer` (`skynet-iads-source/skynet-iads-jammer.lua`):
- `create(emitter, iads)` — `emitter` is a unit; stores `iads` as `{iads}`; builds `jammerTable` with SA-2/3/6/8/10/11/15 entries.
- `masterArmOn()` → `masterArmSafe()` then `jammerTaskID = mist.scheduleFunction(runCycle, {self}, 1, 10)`.
- `masterArmSafe()` → `mist.removeFunction(self.jammerTaskID)`.
- `runCycle(self)` — if `emitter:isExist() == false` → `masterArmSafe()` and return; else iterate IADS active SAM sites and jam.
- `isKnownRadarEmitter(nato)` / `getSuccessProbability(distNM, nato)` / `addFunction` / `disableFor` — table ops.

- [ ] **Step 1: Write the suite**

Bootstrap as in Task 3. `setUp`:
```lua
function TestSkynetIADSJammer:setUp()
  dcsStub.reset()
  self.emitter = dcsStub.makeUnit({ name = "jammer-source", type = "F-16C", pos = { x = 0, y = 1000, z = 0 } })
  dcsStub.world["jammer-source"] = self.emitter
  self.mockIADS = {}
  function self.mockIADS:getDebugSettings()
    return {}
  end
  self.jammer = SkynetIADSJammer:create(self.emitter, self.mockIADS)
end

function TestSkynetIADSJammer:tearDown()
  self.jammer:masterArmSafe()
end
```

Port the 9 tests with these adaptations:

| Test | Adaptation |
|---|---|
| `testSetJammerDistance` | verbatim |
| `testSetupJammerAndRunCycle` | verbatim — it already mocks `mockSAM`/`mockRadar`, `getDistanceNMToRadarUnit`, `hasLineOfSightToRadar`, and `self.mockIADS:getActiveSAMSites`. Assert `self.jammer.jammerTaskID ~= nil` after `masterArmOn()` (the scheduler returns id `1`). |
| `testIsActiveForUnknownType` / `testIsActiveForKnownType` | verbatim |
| `testCleanUpJammer` | **replace the iterate-`mist.removeFunction` idiom with `dcsStub.scheduledCount()`**: `self.jammer:masterArmOn()`; `luaunit.assertEquals(dcsStub.scheduledCount(), 1)`; `self.jammer:masterArmSafe()`; `luaunit.assertEquals(dcsStub.scheduledCount(), 0)`. |
| `testAddJammerFunction` | verbatim |
| `testDestroyEmitter` | rewrite the kill: replace `self.emitter = Unit.getByName("jammer-source-unit-test")` + `trigger.action.explosion(...)` with — build a fresh emitter fixture, `SkynetIADSJammer:create(emitter, SkynetIADS:create())`, `masterArmOn()`, then `emitter:__destroy()`, then `self.jammer.runCycle(self.jammer)`. Assert `dcsStub.scheduledCount() == 0` (runCycle saw the dead emitter and called `masterArmSafe`). |

`lu.` → `luaunit.` throughout. End with `os.exit(luaunit.LuaUnit.run())`.

- [ ] **Step 2: Run**

```bash
"$LUA" test/lua/test_skynet_iads_jammer.lua
```
Expected: `Ran 9 tests ... OK`.

- [ ] **Step 3: Full suite + commit**

```bash
"$LUA" test/lua/run.lua                 # ALL 9 SUITE(S) PASSED
git add test/lua/test_skynet_iads_jammer.lua
git commit -m "$(printf 'test: port the jammer suite to the standalone harness\n\nUses dcsStub.scheduledCount() in place of the iterate-and-remove idiom\nand emitter:__destroy() in place of trigger.action.explosion.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>')"
```

---

### Task 7: Port `abstract-element`

**Files:**
- Create: `test/lua/test_skynet_iads_abstract_element.lua`
- Port from: `unit-tests/test-skynet-iads-abstract-element.lua` (10 tests)

**Interfaces:**
- Consumes: `luaunit`, `loader.loadAll`, `dcs-stub` (`makeGroup`, `makeStatic`, `__destroy`), `dcs-fixtures` (`connectionNodeUnit`, `connectionNodeStatic`).
- Produces: `TestSkynetIADSAbstractElement`.

- [ ] **Step 1: Write the suite**

Bootstrap as in Task 3, plus:
```lua
local F = dofile(base .. "/dcs-fixtures.lua")
```

`setUp`:
```lua
function TestSkynetIADSAbstractElement:setUp()
  dcsStub.reset()
  self.iads = SkynetIADS:create()
  self.group = dcsStub.makeGroup({ name = "SAM-SA-6-2", units = { { name = "SAM-SA-6-2-u1", type = "Kub 2P25 ln" } } })
  self.abstractElement = SkynetIADSAbstractElement:create(self.group, self.iads)
  function self.abstractElement:setToCorrectAutonomousState() end
end

function TestSkynetIADSAbstractElement:tearDown()
  self.abstractElement:cleanUp()
end
```

Port the 10 tests. Adaptations:

| Test | Adaptation |
|---|---|
| `testHasActiveConnectionNodeByDefaultIfNoneIsSet` | verbatim |
| `testCheckOneGenericObjectAliveForUnitWorks` | `Unit.getByName('SAM-SA-6-2-connection-node-unit')` → `F.connectionNodeUnit("SAM-SA-6-2-connection-node-unit")`; `trigger.action.explosion(unit:getPosition().p, 1000)` → `unit:__destroy()` |
| `testCheckOneGenericObjectAliveForStaticObjectsWorks` | `StaticObject.getByName('SAM-SA-6-2-coonection-node-static')` (keep the `coonection` typo) → `F.connectionNodeStatic("SAM-SA-6-2-coonection-node-static")`; `explosion(...)` → `static:__destroy()` |
| `testPowerSourceAndConnectionNodeStaticObjectAndDestrutionSuccessful` | both statics via `F.connectionNodeStatic("test-ground-vehicle-power-source")` / `("test-ground-vehicle-connection-node")`; both `explosion(...)` → `:__destroy()` |
| `testGetNatoName` | verbatim (`"UNKNOWN"`) |
| `testGetDescription` | verbatim (`"IADS ELEMENT: SAM-SA-6-2 | Type: UNKNOWN"` — depends on the group name, which the fixture sets) |
| `testGetDCSRepresentation` | assert `== self.group` (was `Group.getByName("SAM-SA-6-2")` — same object) |
| `testGetDCSName` | verbatim (`"SAM-SA-6-2"` + caching after `getDCSRepresentation` → nil) |

`lu.` → `luaunit.` throughout. End with `os.exit(luaunit.LuaUnit.run())`.

- [ ] **Step 2: Run**

```bash
"$LUA" test/lua/test_skynet_iads_abstract_element.lua
```
Expected: `Ran 10 tests ... OK`. If `genericCheckOneObjectIsAlive` doesn't flip to `false` after `__destroy()`, confirm the source checks `:isExist()` (it does) and that `__destroy` set `spec.exists = false` (Task 1).

- [ ] **Step 3: Full suite + commit**

```bash
"$LUA" test/lua/run.lua                 # ALL 10 SUITE(S) PASSED
git add test/lua/test_skynet_iads_abstract_element.lua
git commit -m "$(printf 'test: port the abstract-element suite to the standalone harness\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>')"
```

---

### Task 8: Port `sam-site`

**Files:**
- Create: `test/lua/test_skynet_iads_sam_site.lua`
- Port from: `unit-tests/test-skynet-iads-sam-site.lua` (14 tests)

**Interfaces:**
- Consumes: `luaunit`, `loader.loadAll`, `dcs-stub`, `dcs-fixtures` (`samGroup`, `iadsContact`).
- Produces: `TestSkynetIADSSAMSite`.

**Behaviour reference** — `SkynetIADSSamSite` / `SkynetIADSAbstractRadarElement`:
- `create(group, iads)`; `setupElements()` classifies units → sets `natoName`, search radars (range from `getSensors()`), launchers (missile count + range from `getAmmo()`).
- `goLive()` / `goDark()` call `getController():setOption(...)` — recorded, harmless.
- `isActive()`, `isDestroyed()`, `hasWorkingRadar()`, `getRemainingNumberOfMissiles()`, `getInitialNumberOfMissiles()`, `hasRemainingAmmo()`.
- `informOfContact(contact)` → checks `isTargetInRange(contact)` (unless overridden) and `areGoLiveConstraintsSatisfied(contact)`, may `goLive()`.
- `isTargetInRange` → `searchRadar:isInRange(target)` → distance(radar, target) vs `getMaxRangeFindingTarget()` (the `getSensors()` range, 120000 m from the fixture).
- The `.miz` `setUp` is parameterised: it reads `self.samSiteName`, does `Group.getByName(self.samSiteName)`, `SkynetIADSSamSite:create(...)`, overrides `getDetectedTargets` → `{}`, `setupElements()`, `goLive()`. Tests set `self.samSiteName` then call `self:setUp()` again.

- [ ] **Step 1: Write the suite**

Bootstrap as in Task 3, plus `local F = dofile(base .. "/dcs-fixtures.lua")`.

`setUp` / `tearDown` — port the parameterised shape, building the group from a fixture keyed by name:

```lua
-- maps the .miz group names to a fixture NATO short + which SAM it models
local GROUPS = {
  ["SAM-SA-6"] = "SA-6",
  ["SAM-SA-2"] = "SA-2",
  ["test-SAM-SA-2-test"] = "SA-2",
  ["Destruction-test-sam"] = "SA-6",
  ["prefixtest-sam"] = "SA-6",
}

function TestSkynetIADSSAMSite:setUp()
  dcsStub.reset()
  self.skynetIADS = SkynetIADS:create()
  if self.samSiteName then
    local nato = GROUPS[self.samSiteName] or "SA-6"
    local group = F.samGroup(nato, self.samSiteName)
    self.samSite = SkynetIADSSamSite:create(group, self.skynetIADS)
    function self.samSite:getDetectedTargets()
      return {}
    end
    self.samSite:setupElements()
    self.samSite:goLive()
  end
end

function TestSkynetIADSSAMSite:tearDown()
  if self.samSite then
    self.samSite:goDark()
    self.samSite:cleanUp()
  end
  if self.skynetIADS then
    self.skynetIADS:deactivate()
  end
  self.samSite = nil
  self.samSiteName = nil
end
```

Port the 14 tests. Per-test adaptation:

| Test | Adaptation |
|---|---|
| `testCompleteDestructionOfSamSiteAndLoadDestroyedSAMSiteInToIADS` | builds `Destruction-test-sam` + `prefixtest-sam` groups via `F.samGroup`. Replace each `trigger.action.explosion(radar:getDCSRepresentation():getPosition().p, R)` + `samSite:onEvent(createDeadEvent())` with `radar:getDCSRepresentation():__destroy()` then `samSite:onEvent(createDeadEvent())` (keep the event call — the source reacts to it). Same for launchers. `createDeadEvent()` — define it locally in the file (it's a one-liner in the .miz's `skynet-unit-tests.lua`): `local function createDeadEvent() return { id = world.event.S_EVENT_DEAD } end`. Assertions (`getInitialNumberOfMissiles() == 6`, `getNatoName() == "UNKNOWN"` after rebuild on destroyed units, `#getRadars() == 0`) hold with the fixture. |
| `testInformOfContactInRange` / `testInformOfContactNotInRange` | verbatim — they override `self.samSite:isTargetInRange`. |
| `testInformOfHARMContactSAMCanEngageHARM` / `...CanNotEngageHARM` | verbatim — override `isTargetInRange`, mock target. |
| `testSA2InformOfContactTargetNotInRange` | uses real `isTargetInRange`. `IADSContactFactory('test-not-in-firing-range-of-sa-2')` → register a contact fixture far away, then `F.iadsContact(...)`: `dcsStub.world["test-not-in-firing-range-of-sa-2"] = dcsStub.makeUnit({ name = "test-not-in-firing-range-of-sa-2", type = "F-16C", pos = { x = 500000, y = 3000, z = 0 } })` (500 km >> the 120 km fixture radar range). Assert `isTargetInRange(target) == false`, `isActive() == false`. |
| `testSA2InforOfContactInSearchRangeSAMSiteGoLiveWhenSetToSearchRange` | real path. Register `test-not-in-firing-range-of-sa-2` **inside** search range for this one (`pos = { x = 50000, y = 3000, z = 0 }`, 50 km < 120 km) — the test name is misleading; it sets `GO_LIVE_WHEN_IN_SEARCH_RANGE` and expects `isActive() == true`. Recompute: 50000 m < 120000 m ⇒ in search range ⇒ goes live. |
| `testInformOfContactMultipleTimesOnlyOneIsTargetInRangeCall` | verbatim — overrides `isTargetInRange`, counts calls. |
| `testSAMStaysActiveWhenInAutonomousMode` | verbatim — `test-SAM-SA-2-test` fixture; asserts `isActive()`/`getAutonomousState()` true after `setupElements`+`goLive`. |
| `testGoLiveConstraint` | `IADSContactFactory('test-in-firing-range-of-sa-2')` → register at `pos = { x = 10000, y = 2000, z = 0 }`; `2000 m = 6561 ft > 4000` so `goLiveConstraint` (checks `> 4000` ft) is `true`. Verbatim otherwise (adds/replaces constraints, asserts `areGoLiveConstraintsSatisfied`). |
| `testRemoveGoLiveConstraint` | verbatim (constraint table ops; `IADSContactFactory` contact only used in the final assertion `getGoLiveConstraints()["test"](contact) == 3`, contact value irrelevant). Register `test-in-firing-range-of-sa-2` as in the row above. |
| `testSAMSiteWillNotGoLiveIfConstraintFailesAndContactIsInRange` | register `test-in-firing-range-of-sa-2` at `pos = { x = 10000, y = 2000, z = 0 }` (in range, but 6561 ft, and the constraint requires `< 4000` ft ⇒ fails). Assert `isActive() == false`. |

Add `local function createDeadEvent()` near the top of the file. `IADSContactFactory(name)` calls in the ported tests become `F.iadsContact(name)` — register the underlying fixture unit in the test body first (positions per the table above), then call `F.iadsContact(name)`.

`lu.` → `luaunit.` throughout. `SKYNET_UNIT_TESTS_NUM_*` constants are not referenced by this suite. End with `os.exit(luaunit.LuaUnit.run())`.

- [ ] **Step 2: Run, iterate to green**

```bash
"$LUA" test/lua/test_skynet_iads_sam_site.lua
```
Expected: `Ran 14 tests ... OK`. If a range test won't resolve, adjust the **contact fixture position** (not the assertion) and update its arithmetic comment; the fixture radar range is 120000 m (`dcs-fixtures.lua` `RADAR_RANGE_M`). If a test reaches an unstubbed DCS call, add the surface to `dcs-stub.lua` + its `test_dcs_stub.lua` coverage as a small separate commit, then continue. If a single test genuinely needs simulator behaviour that a stub cannot honestly provide, mark it:
```lua
-- DEFERRED (needs <what>): stays in unit-tests/test-skynet-iads-sam-site.lua
```
skip it from the ported file, and record it in the task report — do not force it green.

- [ ] **Step 3: Full suite + commit**

```bash
"$LUA" test/lua/run.lua                 # ALL 11 SUITE(S) PASSED
git add test/lua/test_skynet_iads_sam_site.lua
git commit -m "$(printf 'test: port the sam-site suite to the standalone harness\n\nSAM groups from dcs-fixtures; range tests use code-defined contact\npositions against the fixture radar range; destruction via __destroy().\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>')"
```

---

### Task 9: Update `contributing.md` and `test/lua/README.md`

**Files:**
- Modify: `test/lua/README.md`
- Modify: `contributing.md`

- [ ] **Step 1: `test/lua/README.md`** — the "Files" table gains `dcs-fixtures.lua`; add a line to the intro noting the ported suites. Change the Files table to include:

```markdown
| `dcs-fixtures.lua` | Reusable fixtures — SAM group builders, connection nodes, the IADS-contact factory |
```

And after the "Run" section add:

```markdown
## Ported suites

These `unit-tests/` suites now also run standalone (their `.miz` copies are kept):
`harm-detection`, `abstract-dcs-object-wrapper`, `moose-a2a-connector` (1 test),
`jammer`, `abstract-element`, `sam-site`, plus the M1 `contact` pilot.

Still DCS-only (need the demo-IADS-world fixture — a later milestone):
`early-warning-radar`, `abstract-radar-element`, `iads`,
`red/blue-sam-sites-and-ew-radars`.
```

- [ ] **Step 2: `contributing.md`** — in the "Two test suites" table row for `test/lua/`, the "Use for" cell already says logic tests go there. Add one sentence after the table:

```markdown
As of milestone 2, the DCS-independent suites (`harm-detection`, `jammer`,
`sam-site`, `abstract-element`, `abstract-dcs-object-wrapper`, and one
`moose-a2a-connector` test) have standalone copies under `test/lua/`; their
`unit-tests/*.miz` originals are kept until the standalone suite has a release
cycle behind it.
```

- [ ] **Step 3: Verify + commit**

```bash
"$LUA" test/lua/run.lua                 # ALL 11 SUITE(S) PASSED (unchanged; docs only)
python -c "import yaml; yaml.safe_load(open('.github/workflows/lua-tests.yml')); print('ok')"  # unchanged, sanity only
git add test/lua/README.md contributing.md
git commit -m "$(printf 'docs: record the M2 ported suites in README and contributing.md\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>')"
```

---

## Self-Review

**1. Spec coverage**

| Spec section | Task |
|---|---|
| Fake scheduler (`mist.scheduleFunction`/`removeFunction`, int ids, truthy-on-hit, no auto-fire, `scheduledCount`) | Task 1 (4a, 4b) + `test_dcs_stub` |
| `timer.getTime` | Task 1 (4c) |
| `AI.Option` tree (exact ids) | Task 1 (4d) + test |
| `land.getIP` → nil, `land.isVisible` → true | Task 1 (4f) |
| `mist.random`, `mist.utils.get3DDist` (with copy comment) | Task 1 (Step 3) |
| `__destroy()` on unit/group/static; `explosion` stays no-op | Task 1 (4g, 4h, 4i); ported tests swap in Tasks 6/7/8 |
| `makeGroup` (getUnits live-only, getController recording, `__destroy`) | Task 1 (4h) + test |
| `makeStatic` | Task 1 (4i) + test |
| `dcs-fixtures.lua` — `samGroup` (SA-2/SA-6 keyed to `samTypesDB`), `connectionNodeUnit/Static`, `iadsContact` | Task 2 |
| `samGroup` fidelity risk → assert NATO name per builder | Task 2 Step 1 tests |
| Port harm-detection (7) | Task 3 |
| Port abstract-dcs-object-wrapper (7) | Task 4 |
| Port moose-a2a-connector (1 of 3, header comment on the 2 deferred) | Task 5 |
| Port jammer (9) — `scheduledCount` not the iterate idiom; `__destroy` not explosion | Task 6 |
| Port abstract-element (10) | Task 7 |
| Port sam-site (14) — geometry via fixture radar range + code contact positions; defer clause | Task 8 |
| `run.lua`/CI/loader/`unit-tests/*.miz` unchanged | No task modifies them; stated in Global Constraints |
| Suites named `test_skynet_*.lua`, bootstrap `loadAll()`, explicit `/` paths | Every port task Step 1 |
| Magic numbers recomputed from fixtures with arithmetic comment | Task 8 adaptation table (positions vs 120000 m); Tasks 3–7 have none |
| Docs updated | Task 9 |

No gaps.

**2. Placeholder scan**

- No "TBD"/"handle edge cases"/"similar to Task N". Port tasks say "copy verbatim from `unit-tests/test-X.lua` with `lu.` → `luaunit.`" — the source file is in the repo and named exactly; the per-test *changes* are enumerated in a table with concrete code. This is a port, not a placeholder.
- Task 8's "if a test genuinely needs simulator behaviour, mark DEFERRED" is a decision rule with a concrete action (comment format + report line + skip), matching the spec's risk clause — not an open TODO.
- Task 5 / Task 8 "if you hit an unstubbed call, add it to `dcs-stub.lua`" is expected reactive stub growth, bounded (add + test + separate commit).

**3. Type consistency**

- `dcsStub.scheduledCount()` — Task 1 defines, Task 6 uses. ✓
- `<unit>:__destroy()` / `<group>:__destroy()` / `<static>:__destroy()` — Task 1 defines all three; Tasks 6/7/8 call them. ✓
- `<unit>.__controllerCalls` (list of `{id, value}`) — Task 1 defines; only asserted in `test_dcs_stub`. ✓
- `dcsStub.makeGroup{ name, units }` / `dcsStub.makeStatic{ name, type, pos, exists }` — Task 1 signatures; Tasks 2/7 consume with those exact keys. ✓
- `F.samGroup(natoShort, groupName)` / `F.connectionNodeUnit(name)` / `F.connectionNodeStatic(name)` / `F.iadsContact(unitName)` — Task 2 defines; Tasks 7/8 consume. ✓
- `makeUnit` spec keys `sensors` / `ammo` — Task 1 (4g) reads `spec.sensors`/`spec.ammo`; Task 2 `searchRadarSensors()`/`launcherAmmo()` produce them. ✓
- `RADAR_RANGE_M` = 120000 — Task 2 local; Task 8 references "the 120000 m fixture radar range" in its adaptation arithmetic. ✓
- luaunit assertion names (`assertEquals`, `assertIs`, `assertNil`, `assertNotIs`, `assertAlmostEquals`) — all standard luaunit 3.4, used consistently. ✓
- Suite count in the run.lua checks climbs 5→6→7→8→9→10→11 across Tasks 2–8. Starting point: after M1 there are 4 (`test_harness_smoke`, `test_dcs_stub`, `test_mist_stub`, `test_skynet_iads_contact`); Task 2 adds `test_dcs_fixtures` → 5; Tasks 3–8 add one each → 11. ✓

Fixed inline where noted. Plan ready.
