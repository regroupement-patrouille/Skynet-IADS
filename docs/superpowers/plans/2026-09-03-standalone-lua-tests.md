# Standalone Lua Test Suite — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a plain-Lua-5.1 test harness under `test/lua/` that runs Skynet's logic outside DCS, in VSCode and CI, with the `contact` module as the pilot port.

**Architecture:** Vendored luaunit + a hand-written `dcs-stub.lua` and `mist-stub.lua` + an ordered source loader. Each `test_*.lua` is self-contained and self-executing (`dofile`s the harness and source, ends with `os.exit(luaunit.LuaUnit.run())`), exactly like the sister project VEAF-Mission-Creation-Tools. A `run.lua` aggregates suites for CI. The in-sim `unit-tests/*.miz` suites are untouched and reframed as functional/smoke tests.

**Tech Stack:** Lua 5.1 (LuaJIT-compatible), luaunit 3.4, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-03-standalone-lua-tests-design.md`

## Global Constraints

- **Lua 5.1 only.** No `goto`, no `//`, no bitwise operators, `unpack` not `table.unpack`. `os`/`io` may be used in `run.lua` only — never in `dcs-stub.lua`, `mist-stub.lua`, or any code path the Skynet source reaches.
- **Source is loaded, not modified.** Skynet's `skynet-iads-source/*.lua` files are `do … Global = {} … end` blocks; `loadfile(path)()` in dependency order populates globals. No source refactoring in this milestone. The one source change this work needs (`getTypeName` → WEAPON) is already committed on this branch as `ef37ead`.
- **Loader order** mirrors `build-tools/build-compiled-script.ps1` verbatim.
- **Directory:** everything new lives in `test/lua/` (new top-level `test/`), except the CI workflow (`.github/workflows/`) and the `contributing.md` note.
- **mist stub fidelity:** every stubbed `mist` function is copied from `mist_4_5_107` and carries a comment saying so. North correction is 0 (grid heading, no theatre magnetic model).
- **Interpreter for local steps:** this repo is developed on Windows with "Lua for Windows" at `C:\Program Files (x86)\Lua\5.1\lua.exe`. Steps below use `"$LUA"` — set it once per shell:
  - git-bash: `LUA="/c/Program Files (x86)/Lua/5.1/lua.exe"`
  - CI / Linux: `LUA=lua5.1`
- **Commit trailer:** end every commit message with
  `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`

---

### Task 1: Vendor luaunit + source loader + harness smoke test

**Files:**
- Create: `test/lua/luaunit.lua` (copied verbatim from `D:/Projects/DcsLua/VEAF-Mission-Creation-Tools/test/lua/luaunit.lua` — a clean upstream 3.4, writes to `io.stdout` directly; do **not** copy `unit-tests/luaunit.lua`, which is patched to redirect through `env.info`)
- Create: `test/lua/skynet-loader.lua`
- Create: `test/lua/README.md`
- Test: `test/lua/test_harness_smoke.lua`

**Interfaces:**
- Produces:
  - `luaunit.lua` returns the luaunit module table `M` (has `.assertEquals`, `.assertIs`, `.assertNil`, `.assertAlmostEquals`, `.LuaUnit.run`).
  - `skynet-loader.lua` returns a table `M` with:
    - `M.load(name)` — `name` is a source basename without `.lua`; `loadfile`s `skynet-iads-source/<name>.lua`, calls it once, memoises. Raises on failure.
    - `M.loadAll()` — loads every entry of the internal `ORDER` list in order.
    - `M.reset()` — clears the memo (for suites that need a clean reload).

- [ ] **Step 1: Copy the vendored luaunit**

```bash
mkdir -p test/lua
cp "D:/Projects/DcsLua/VEAF-Mission-Creation-Tools/test/lua/luaunit.lua" test/lua/luaunit.lua
```

Verify it is the clean copy:

```bash
grep -c "io.stdout:write" test/lua/luaunit.lua   # expect: a non-zero number
grep -c "env.info" test/lua/luaunit.lua           # expect: 0
```

- [ ] **Step 2: Write the failing smoke test**

`test/lua/test_harness_smoke.lua`:

```lua
--- Smoke test: the vendored luaunit runs, and skynet-loader loads the two
--- source files the contact pilot needs, populating their globals.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")
local loader = dofile(base .. "/skynet-loader.lua")

-- Group is the only global the wrapper touches at load time (a sentinel it
-- compares metatables against). dcs-stub owns it from Task 2 on; here a bare
-- table is enough to load the file.
Group = Group or {}

TestHarnessSmoke = {}

function TestHarnessSmoke:test_luaunit_is_loaded()
  luaunit.assertEquals(type(luaunit.LuaUnit.run), "function")
end

function TestHarnessSmoke:test_loader_loads_wrapper_and_contact()
  loader.load("skynet-iads-abstract-dcs-object-wrapper")
  loader.load("skynet-iads-contact")
  luaunit.assertEquals(type(inheritsFrom), "function")
  luaunit.assertEquals(type(SkynetIADSAbstractDCSObjectWrapper), "table")
  luaunit.assertEquals(type(SkynetIADSContact), "table")
  luaunit.assertEquals(SkynetIADSContact.HARM, "HARM")
end

function TestHarnessSmoke:test_loader_memoises()
  loader.load("skynet-iads-contact")
  loader.load("skynet-iads-contact") -- second call must be a no-op, not an error
  luaunit.assertEquals(type(SkynetIADSContact), "table")
end

os.exit(luaunit.LuaUnit.run())
```

- [ ] **Step 3: Run it to verify it fails**

```bash
"$LUA" test/lua/test_harness_smoke.lua
```

Expected: FAIL — `cannot open test/lua/skynet-loader.lua` (file not created yet).

- [ ] **Step 4: Write `skynet-loader.lua`**

```lua
--- Loads Skynet source files (globals, no modules) in dependency order,
--- the same order build-tools/build-compiled-script.ps1 concatenates them.
--- Usage:
---   local loader = dofile(".../skynet-loader.lua")
---   loader.load("skynet-iads-contact")   -- one file
---   loader.loadAll()                      -- everything

local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "./"
local src = (os.getenv("SKYNET_SRC") or (base .. "../../skynet-iads-source")) .. "/"

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
  chunk()
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
```

- [ ] **Step 5: Run it to verify it passes**

```bash
"$LUA" test/lua/test_harness_smoke.lua
```

Expected: PASS — `Ran 3 tests ... OK`, exit 0.

- [ ] **Step 6: Write `test/lua/README.md`**

```markdown
# Standalone Lua tests

Logic tests for the Skynet-IADS source, run on a plain Lua 5.1 interpreter —
no DCS, no mission editor. This is where new **logic** tests go.

For behaviour that genuinely needs the simulator (terrain elevation, radar
detection geometry, real in-game events) see the in-sim functional/smoke
suites in `unit-tests/*.miz`.

## Run

    # one suite
    lua5.1 test/lua/test_skynet_iads_contact.lua

    # all suites
    lua5.1 test/lua/run.lua

    # suites whose filename contains a string
    lua5.1 test/lua/run.lua contact

On Windows without `lua5.1` on PATH, use the "Lua for Windows" binary:

    "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua

## Files

| File | Purpose |
|------|---------|
| `luaunit.lua` | Vendored luaunit 3.4 (upstream, unmodified) |
| `dcs-stub.lua` | Fake DCS scripting environment + fixture factories |
| `mist-stub.lua` | The slice of `mist` the loaded source calls |
| `skynet-loader.lua` | Loads `skynet-iads-source/*.lua` in dependency order |
| `run.lua` | Discovers and runs every `test_*.lua`, aggregates exit codes |
| `test_*.lua` | Test suites — self-contained, self-executing |
```

- [ ] **Step 7: Commit**

```bash
git add test/lua/luaunit.lua test/lua/skynet-loader.lua test/lua/README.md test/lua/test_harness_smoke.lua
git commit -m "$(printf 'test: vendor luaunit and add standalone Lua source loader\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>')"
```

---

### Task 2: `dcs-stub.lua` — fake DCS scripting environment

**Files:**
- Create: `test/lua/dcs-stub.lua`
- Test: `test/lua/test_dcs_stub.lua`

**Interfaces:**
- Consumes: `luaunit.lua` (Task 1).
- Produces — after `dofile("dcs-stub.lua")` these globals exist:
  - `dcsStub.reset()` — clock→0, clears `dcsStub.world`, `dcsStub.logs`, `dcsStub.eventHandlers`
  - `dcsStub.now()` → number (current model clock)
  - `dcsStub.setClock(t)` / `dcsStub.advanceClock(dt)`
  - `dcsStub.world` — table, `name` → fake object; backs `Unit.getByName` / `Group.getByName` / `StaticObject.getByName`
  - `dcsStub.logs` — array of `{ level = "I"|"W"|"E", text = string }`
  - `dcsStub.eventHandlers` — array, appended by `world.addEventHandler`
  - `dcsStub.makeUnit{ name=, type=, category=, pos={x=,y=,z=}, heading=, exists=, desc= }` → fake object with methods `getName()`, `getTypeName()`, `getPosition()` (returns `{ p = {x,y,z}, x = <fwd unit vec>, y = <up>, z = <right> }`), `isExist()`, `getDesc()`, plus test helpers `__setPos(p)`, `__setHeading(h)`
  - `timer.getAbsTime()` → model clock
  - `Object.Category` = `{ UNIT=1, WEAPON=2, STATIC=3, BASE=4, SCENERY=5, Cargo=6 }`
  - `Object.getCategory(o)` → `o.__category or Object.Category.UNIT`; `nil` for `nil`
  - `Weapon.Category` = `{ SHELL=0, MISSILE=1, ROCKET=2, BOMB=3 }`
  - `Group`, `Unit`, `StaticObject` — tables (also metatable sentinels); each has `.getByName`
  - `world.event` — `{ S_EVENT_SHOT=1, S_EVENT_HIT=2, S_EVENT_DEAD=8, S_EVENT_BIRTH=15 }`
  - `world.addEventHandler(h)`
  - `env.info/warning/error`
  - `trigger.action.outText/explosion` — no-ops

- [ ] **Step 1: Write the failing test**

`test/lua/test_dcs_stub.lua`:

```lua
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")
dofile(base .. "/dcs-stub.lua")

TestDcsStub = {}

function TestDcsStub:setUp()
  dcsStub.reset()
end

function TestDcsStub:test_clock_control()
  luaunit.assertEquals(timer.getAbsTime(), 0)
  dcsStub.setClock(1200)
  luaunit.assertEquals(timer.getAbsTime(), 1200)
  dcsStub.advanceClock(300)
  luaunit.assertEquals(timer.getAbsTime(), 1500)
  luaunit.assertEquals(dcsStub.now(), 1500)
end

function TestDcsStub:test_reset_clears_state()
  dcsStub.setClock(50)
  dcsStub.world["x"] = {}
  env.info("hi")
  dcsStub.reset()
  luaunit.assertEquals(timer.getAbsTime(), 0)
  luaunit.assertNil(dcsStub.world["x"])
  luaunit.assertEquals(#dcsStub.logs, 0)
end

function TestDcsStub:test_object_getCategory()
  luaunit.assertNil(Object.getCategory(nil))
  luaunit.assertEquals(Object.getCategory({}), Object.Category.UNIT)
  luaunit.assertEquals(Object.getCategory({ __category = Object.Category.WEAPON }), Object.Category.WEAPON)
end

function TestDcsStub:test_makeUnit_basic_accessors()
  local u = dcsStub.makeUnit({ name = "u1", type = "MiG-29", pos = { x = 10, y = 500, z = -20 } })
  luaunit.assertEquals(u:getName(), "u1")
  luaunit.assertEquals(u:getTypeName(), "MiG-29")
  luaunit.assertEquals(u:isExist(), true)
  local p = u:getPosition()
  luaunit.assertEquals(p.p.x, 10)
  luaunit.assertEquals(p.p.y, 500)
  luaunit.assertEquals(p.p.z, -20)
end

function TestDcsStub:test_makeUnit_exists_false()
  local u = dcsStub.makeUnit({ exists = false })
  luaunit.assertEquals(u:isExist(), false)
end

function TestDcsStub:test_makeUnit_heading_orientation_vector()
  -- heading 0 => forward vector points along +x (grid north)
  local u = dcsStub.makeUnit({ heading = 0 })
  luaunit.assertAlmostEquals(u:getPosition().x.x, 1, 1e-9)
  luaunit.assertAlmostEquals(u:getPosition().x.z, 0, 1e-9)
  -- heading pi/2 => forward vector points along +z (grid east)
  u:__setHeading(math.pi / 2)
  luaunit.assertAlmostEquals(u:getPosition().x.x, 0, 1e-9)
  luaunit.assertAlmostEquals(u:getPosition().x.z, 1, 1e-9)
end

function TestDcsStub:test_getByName_registry()
  local u = dcsStub.makeUnit({ name = "reg1" })
  dcsStub.world["reg1"] = u
  luaunit.assertIs(Unit.getByName("reg1"), u)
  luaunit.assertIs(Group.getByName("reg1"), u)
  luaunit.assertIs(StaticObject.getByName("reg1"), u)
  luaunit.assertNil(Unit.getByName("missing"))
end

function TestDcsStub:test_addEventHandler_captured()
  local h = {}
  world.addEventHandler(h)
  luaunit.assertEquals(#dcsStub.eventHandlers, 1)
  luaunit.assertIs(dcsStub.eventHandlers[1], h)
end

function TestDcsStub:test_env_captured()
  env.info("info line")
  env.warning("warn line")
  luaunit.assertEquals(#dcsStub.logs, 2)
  luaunit.assertEquals(dcsStub.logs[1].level, "I")
  luaunit.assertEquals(dcsStub.logs[2].text, "warn line")
end

os.exit(luaunit.LuaUnit.run())
```

- [ ] **Step 2: Run it to verify it fails**

```bash
"$LUA" test/lua/test_dcs_stub.lua
```

Expected: FAIL — `cannot open test/lua/dcs-stub.lua`.

- [ ] **Step 3: Write `dcs-stub.lua`**

```lua
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
```

- [ ] **Step 4: Run it to verify it passes**

```bash
"$LUA" test/lua/test_dcs_stub.lua
```

Expected: PASS — `Ran 10 tests ... OK`.

- [ ] **Step 5: Commit**

```bash
git add test/lua/dcs-stub.lua test/lua/test_dcs_stub.lua
git commit -m "$(printf 'test: add dcs-stub, the fake DCS environment for standalone tests\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>')"
```

---

### Task 3: `mist-stub.lua` — the mist slice the source calls

**Files:**
- Create: `test/lua/mist-stub.lua`
- Test: `test/lua/test_mist_stub.lua`

**Interfaces:**
- Consumes: `luaunit.lua` (Task 1), `dcs-stub.lua` (Task 2 — for a fixture unit in the `getHeading` test).
- Produces — after `dofile("mist-stub.lua")`:
  - `mist.utils.round(num, idp)` → number
  - `mist.utils.toDegree(angleRad)` → number
  - `mist.utils.metersToNM(m)` → number
  - `mist.utils.metersToFeet(m)` → number
  - `mist.utils.get2DDist(vec3a, vec3b)` → number (ignores `.y`)
  - `mist.getHeading(unit)` → number in `[0, 2*pi)`, or `nil` if `unit:getPosition()` is falsy

- [ ] **Step 1: Write the failing test**

`test/lua/test_mist_stub.lua`:

```lua
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
dofile(base .. "/mist-stub.lua")

TestMistStub = {}

function TestMistStub:test_round()
  luaunit.assertEquals(mist.utils.round(5015.0), 5015)
  luaunit.assertEquals(mist.utils.round(2.4), 2)
  luaunit.assertEquals(mist.utils.round(2.5), 3)
  luaunit.assertEquals(mist.utils.round(1.2345, 2), 1.23)
end

function TestMistStub:test_toDegree()
  luaunit.assertAlmostEquals(mist.utils.toDegree(math.pi), 180, 1e-9)
end

function TestMistStub:test_conversions()
  luaunit.assertAlmostEquals(mist.utils.metersToNM(1852), 1, 1e-9)
  luaunit.assertAlmostEquals(mist.utils.metersToFeet(0.3048), 1, 1e-9)
end

function TestMistStub:test_get2DDist_ignores_altitude()
  local a = { x = 0, y = 9999, z = 0 }
  local b = { x = 3, y = 0, z = 4 }
  luaunit.assertAlmostEquals(mist.utils.get2DDist(a, b), 5, 1e-9)
end

function TestMistStub:test_getHeading_wraps_into_0_2pi()
  local u = dcsStub.makeUnit({ heading = math.rad(347) })
  luaunit.assertAlmostEquals(mist.getHeading(u), math.rad(347), 1e-6)
  local nofix = { getPosition = function()
    return nil
  end }
  luaunit.assertNil(mist.getHeading(nofix))
end

os.exit(luaunit.LuaUnit.run())
```

- [ ] **Step 2: Run it to verify it fails**

```bash
"$LUA" test/lua/test_mist_stub.lua
```

Expected: FAIL — `cannot open test/lua/mist-stub.lua`.

- [ ] **Step 3: Write `mist-stub.lua`**

```lua
--- Minimal `mist` surface for the standalone Lua test suite. Every function
--- here is copied from mist_4_5_107 (mist.utils.* around line 4960, mist.vec.mag
--- ~6165, mist.utils.get2DDist ~5309, mist.getHeading ~2509). Lua 5.1 clean.
---
--- North correction is 0: standalone tests use grid heading, with no theatre
--- magnetic model. Extend this file as more modules are ported.

mist = mist or {}
mist.utils = mist.utils or {}

-- mist_4_5_107: function mist.utils.round(num, idp)
function mist.utils.round(num, idp)
  local mult = 10 ^ (idp or 0)
  return math.floor(num * mult + 0.5) / mult
end

-- mist_4_5_107: function mist.utils.toDegree(angle)
function mist.utils.toDegree(angle)
  return angle * 180 / math.pi
end

-- mist_4_5_107: function mist.utils.metersToNM(meters)
function mist.utils.metersToNM(meters)
  return meters / 1852
end

-- mist_4_5_107: function mist.utils.metersToFeet(meters)
function mist.utils.metersToFeet(meters)
  return meters / 0.3048
end

-- mist_4_5_107: mist.utils.get2DDist == mist.vec.mag of the x/z delta (y zeroed).
-- Skynet always passes a Vec3 {x,y,z}, so the makeVec3 normalisation mist does
-- first is a no-op here.
function mist.utils.get2DDist(point1, point2)
  local dx = point1.x - point2.x
  local dz = point1.z - point2.z
  return (dx * dx + dz * dz) ^ 0.5
end

-- mist_4_5_107: function mist.getHeading(unit, rawHeading) — with the
-- getNorthCorrection term dropped (0 here, see file header).
function mist.getHeading(unit)
  local unitpos = unit:getPosition()
  if not unitpos then
    return nil
  end
  local heading = math.atan2(unitpos.x.z, unitpos.x.x)
  if heading < 0 then
    heading = heading + 2 * math.pi
  end
  return heading
end
```

- [ ] **Step 4: Run it to verify it passes**

```bash
"$LUA" test/lua/test_mist_stub.lua
```

Expected: PASS — `Ran 5 tests ... OK`.

- [ ] **Step 5: Commit**

```bash
git add test/lua/mist-stub.lua test/lua/test_mist_stub.lua
git commit -m "$(printf 'test: add mist-stub with the mist slice the source calls\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>')"
```

---

### Task 4: Contact pilot suite

**Files:**
- Create: `test/lua/test_skynet_iads_contact.lua`
- Reference (do not modify): `unit-tests/test-skynet-iads-contact.lua`, `skynet-iads-source/skynet-iads-contact.lua`, `skynet-iads-source/skynet-iads-abstract-dcs-object-wrapper.lua`

**Interfaces:**
- Consumes: `luaunit.lua`, `skynet-loader.lua` (Task 1); `dcs-stub.lua` (Task 2); `mist-stub.lua` (Task 3).
- Produces: a self-executing suite `TestSkynetIADSContact`. No exports.

**Behaviour reference — `SkynetIADSContact` (from the source):**
- `create({ object = <unit> })` → wrapper stores `typeName = object:getTypeName()`, `position = object:getPosition()`, `lastTimeSeen = 0`, `numOfTimesRefreshed = 0`, `harmState = HARM_UNKNOWN`.
- `getTypeName()` → `HARM` if identified as HARM; else if `getDCSRepresentation() ~= nil` and `Object.getCategory(...)` is `UNIT` or `WEAPON` → `typeName`; else `"UNKNOWN"`.
- `getHeightInFeetMSL()` → `isExist()` ? `round(metersToFeet(getPosition().p.y), 0)` : `0`.
- `getMagneticHeading()` → `isExist()` ? `round(toDegree(mist.getHeading(rep)))` : `-1`.
- `refresh()` → if `isExist()` and `getAbsTime() - lastTimeSeen > 0`: `numOfTimesRefreshed += 1`; `speed = metersToNM(get2DDist(oldPos, newPos)) / (timeDelta/3600)`; `updateSimpleAltitudeProfile()`; `position = newPos`. Always: `lastTimeSeen = getAbsTime()`.
- `getGroundSpeedInKnots(dp)` → `round(speed, dp)`.
- `getAge()` → `round(getAbsTime() - lastTimeSeen)`.
- `getNumberOfTimesHitByRadar()` → `numOfTimesRefreshed`.
- `updateSimpleAltitudeProfile()` → compares `position.p.y` to `getDCSRepresentation():getPosition().p.y`, appends `DESCEND`/`CLIMB` to `simpleAltitudeProfile` (no duplicate consecutive entries).
- `setHARMState` / `getHARMState` / `isIdentifiedAsHARM` / `isHARMStateUnknown` — plain state on `harmState` (`HARM` / `NOT_HARM` / `HARM_UNKNOWN`).
- `addAbstractRadarElementDetected(r)` / `getAbstractRadarElementsDetected()` — deduped list.

- [ ] **Step 1: Write the suite (the failing test)**

`test/lua/test_skynet_iads_contact.lua`:

```lua
--- Standalone port of unit-tests/test-skynet-iads-contact.lua.
--- The DCS-mission version reads fixtures baked into skynet-unit-tests.miz and
--- asserts the resulting magic numbers ("AH-1W", 989, 5015, 347). Here the
--- fixtures are code-defined and every expected value is recomputed from them
--- (arithmetic shown in comments).
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
dofile(base .. "/mist-stub.lua")
local loader = dofile(base .. "/skynet-loader.lua")
loader.load("skynet-iads-abstract-dcs-object-wrapper")
loader.load("skynet-iads-contact")

TestSkynetIADSContact = {}

function TestSkynetIADSContact:setUp()
  dcsStub.reset()
  dcsStub.setClock(1000)
  -- pos.y = 1528.572 m; 1528.572 / 0.3048 = 5015.0 ft exactly.
  self.unit = dcsStub.makeUnit({
    name = "contact-1",
    type = "AH-1W",
    pos = { x = 0, y = 1528.572, z = 0 },
    heading = math.rad(347),
  })
  dcsStub.world["contact-1"] = self.unit
  self.contact = SkynetIADSContact:create({ object = self.unit })
end

-- ---- getTypeName -----------------------------------------------------

function TestSkynetIADSContact:test_getTypeName_is_unit()
  luaunit.assertEquals(self.contact:getTypeName(), "AH-1W")
end

function TestSkynetIADSContact:test_getTypeName_is_weapon()
  -- The reason skynet-iads-contact.lua's WEAPON change ships on this branch:
  -- an in-flight weapon (e.g. an inbound HARM) is a valid contact and must
  -- report its DCS type, not "UNKNOWN".
  local missile = dcsStub.makeUnit({
    name = "harm-1",
    type = "weapons.missiles.AGM_88",
    category = Object.Category.WEAPON,
    pos = { x = 0, y = 100, z = 0 },
  })
  dcsStub.world["harm-1"] = missile
  local weaponContact = SkynetIADSContact:create({ object = missile })
  luaunit.assertEquals(weaponContact:getTypeName(), "weapons.missiles.AGM_88")
end

function TestSkynetIADSContact:test_getTypeName_unknown_when_no_representation()
  function self.contact:getDCSRepresentation()
    return nil
  end
  luaunit.assertEquals(self.contact:getTypeName(), "UNKNOWN")
end

function TestSkynetIADSContact:test_getTypeName_is_harm_when_identified()
  self.contact:setHARMState(SkynetIADSContact.HARM)
  luaunit.assertEquals(self.contact:getTypeName(), SkynetIADSContact.HARM)
end

-- ---- height / heading ----------------------------------------------

function TestSkynetIADSContact:test_getHeightInFeetMSL()
  -- round(1528.572 / 0.3048, 0) = round(5015.0) = 5015
  luaunit.assertEquals(self.contact:getHeightInFeetMSL(), 5015)
end

function TestSkynetIADSContact:test_getMagneticHeading()
  -- round(toDegree(getHeading)) where getHeading == math.rad(347) => 347
  luaunit.assertEquals(self.contact:getMagneticHeading(), 347)
end

function TestSkynetIADSContact:test_getMagneticHeading_minus_one_when_gone()
  function self.contact:isExist()
    return false
  end
  luaunit.assertEquals(self.contact:getMagneticHeading(), -1)
end

-- ---- refresh / speed / age ---------------------------------------

function TestSkynetIADSContact:test_getNumberOfTimesHitByRadar()
  luaunit.assertEquals(self.contact:getNumberOfTimesHitByRadar(), 0)
  self.contact:refresh() -- clock 1000 > lastTimeSeen 0 => counts
  luaunit.assertEquals(self.contact:getNumberOfTimesHitByRadar(), 1)
end

function TestSkynetIADSContact:test_refresh_calls_updateSimpleAltitudeProfile()
  local called = false
  function self.contact:updateSimpleAltitudeProfile()
    called = true
  end
  self.contact:refresh()
  luaunit.assertEquals(called, true)
end

function TestSkynetIADSContact:test_refresh_computes_ground_speed()
  self.contact:refresh() -- baseline at clock 1000, position (0,_,0)
  -- move 185 200 m over 3600 s: 185200 m = 100 NM; 3600 s = 1 h => 100 kt
  self.unit:__setPos({ x = 185200, y = 1528.572, z = 0 })
  dcsStub.setClock(1000 + 3600)
  self.contact:refresh()
  luaunit.assertEquals(self.contact:getGroundSpeedInKnots(0), 100)
end

function TestSkynetIADSContact:test_getAge()
  -- clock 1000, lastTimeSeen forced to 0 => age 1000
  self.contact.lastTimeSeen = dcsStub.now() - 1000
  luaunit.assertEquals(self.contact:getAge(), 1000)
end

-- ---- altitude profile (ported near-verbatim) --------------------

function TestSkynetIADSContact:test_updateSimpleAltitudeProfile_descend_then_climb()
  local mock = {}
  local y = 100
  function mock:getPosition()
    return { p = { y = y } }
  end
  function self.contact:getDCSRepresentation()
    return mock
  end

  self.contact.position.p.y = 200 -- was higher, now 100 => DESCEND
  self.contact:updateSimpleAltitudeProfile()
  local profile = self.contact:getSimpleAltitudeProfile()
  luaunit.assertEquals(profile[1], SkynetIADSContact.DESCEND)
  luaunit.assertEquals(#profile, 1)

  self.contact.position.p.y = 200
  y = 200 -- no change => no new entry
  self.contact:updateSimpleAltitudeProfile()
  luaunit.assertEquals(#self.contact:getSimpleAltitudeProfile(), 1)

  self.contact.position.p.y = 100
  y = 200 -- was lower, now 200 => CLIMB
  self.contact:updateSimpleAltitudeProfile()
  profile = self.contact:getSimpleAltitudeProfile()
  luaunit.assertEquals(profile[2], SkynetIADSContact.CLIMB)
  luaunit.assertEquals(#profile, 2)
end

-- ---- HARM state (ported verbatim) ------------------------------

function TestSkynetIADSContact:test_setHARMState()
  luaunit.assertEquals(self.contact.harmState, SkynetIADSContact.HARM_UNKNOWN)
  self.contact:setHARMState(SkynetIADSContact.HARM)
  luaunit.assertEquals(self.contact.harmState, SkynetIADSContact.HARM)
end

function TestSkynetIADSContact:test_isIdentifiedAsHARM()
  luaunit.assertEquals(self.contact:isIdentifiedAsHARM(), false)
  self.contact:setHARMState(SkynetIADSContact.HARM)
  luaunit.assertEquals(self.contact:isIdentifiedAsHARM(), true)
end

function TestSkynetIADSContact:test_isHARMStateUnknown()
  luaunit.assertEquals(self.contact:isHARMStateUnknown(), true)
  self.contact:setHARMState(SkynetIADSContact.NOT_HARM)
  luaunit.assertEquals(self.contact:isHARMStateUnknown(), false)
end

-- ---- radar element list (ported verbatim) ---------------------

function TestSkynetIADSContact:test_addAbstractRadarElementDetected_dedupes()
  local radar = {}
  self.contact:addAbstractRadarElementDetected(radar)
  luaunit.assertEquals(#self.contact:getAbstractRadarElementsDetected(), 1)
  self.contact:addAbstractRadarElementDetected(radar) -- same ref, no-op
  luaunit.assertEquals(#self.contact:getAbstractRadarElementsDetected(), 1)
  self.contact:addAbstractRadarElementDetected({})
  luaunit.assertEquals(#self.contact:getAbstractRadarElementsDetected(), 2)
end

os.exit(luaunit.LuaUnit.run())
```

- [ ] **Step 2: Run it to verify it fails, then drives to green**

```bash
"$LUA" test/lua/test_skynet_iads_contact.lua
```

Expected initially: the suite may FAIL while fixture numbers are dialled in. Work each failure to green — do **not** change expected values to match observed output without redoing the arithmetic in the comment. All 16 tests must pass:

```
Ran 16 tests ... OK
```

- [ ] **Step 3: Verify the WEAPON test is a real regression guard**

Temporarily revert the one source hunk, confirm the failure, then restore:

```bash
git checkout f18b919 -- skynet-iads-source/skynet-iads-contact.lua
"$LUA" test/lua/test_skynet_iads_contact.lua   # EXPECT: test_getTypeName_is_weapon FAILS ("UNKNOWN" ~= "weapons.missiles.AGM_88")
git checkout HEAD -- skynet-iads-source/skynet-iads-contact.lua
"$LUA" test/lua/test_skynet_iads_contact.lua   # EXPECT: all 16 pass again
```

- [ ] **Step 4: Commit**

```bash
git add test/lua/test_skynet_iads_contact.lua
git commit -m "$(printf 'test: port the contact suite to the standalone harness (pilot)\n\nCovers getTypeName (unit / weapon / unknown / HARM), height and\nheading conversions, refresh speed/age maths, the altitude profile,\nHARM state, and radar-element dedupe. Fixtures are code-defined; the\n.miz version in unit-tests/ is left as the functional/smoke copy.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>')"
```

---

### Task 5: `run.lua` — suite aggregator

**Files:**
- Create: `test/lua/run.lua`

**Interfaces:**
- Consumes: nothing from earlier tasks at load time; discovers and shells out to `test/lua/test_*.lua`.
- Produces: a script. `lua run.lua [filter]` → prints a per-suite header, runs each suite as a child process with the same interpreter, exits `0` iff all passed, `1` otherwise. `filter` (optional) keeps only suites whose filename contains it (plain substring).

- [ ] **Step 1: Write `run.lua`**

```lua
--- Discover and run every test/lua/test_*.lua as a child process, aggregating
--- exit codes.  Usage:  lua run.lua [filenameSubstring]

local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
local sep = package.config:sub(1, 1) -- "\" on Windows, "/" elsewhere
local isWindows = (sep == "\\")
local interp = arg[-1] or "lua"
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
  local ok = os.execute('"' .. interp .. '" "' .. base .. sep .. name .. '"')
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
```

- [ ] **Step 2: Run the full suite via the aggregator**

```bash
"$LUA" test/lua/run.lua
```

Expected: each of `test_dcs_stub.lua`, `test_harness_smoke.lua`, `test_mist_stub.lua`, `test_skynet_iads_contact.lua` prints a header and `OK`, then:

```
ALL 4 SUITE(S) PASSED
```

Exit code 0 (`echo $?`).

- [ ] **Step 3: Check the filter and the failure path**

```bash
"$LUA" test/lua/run.lua contact          # runs only test_skynet_iads_contact.lua, exits 0
"$LUA" test/lua/run.lua nonesuch ; echo $?   # "no matching suites", exits 0
```

- [ ] **Step 4: Commit**

```bash
git add test/lua/run.lua
git commit -m "$(printf 'test: add run.lua to aggregate the standalone suites for CI\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>')"
```

---

### Task 6: CI workflow + contributing.md note

**Files:**
- Create: `.github/workflows/lua-tests.yml`
- Modify: `contributing.md` (after the "## Writing a unit test" section)

**Interfaces:**
- Consumes: `test/lua/run.lua` (Task 5).
- Produces: a GitHub Actions workflow; a documentation paragraph.

- [ ] **Step 1: Create the workflow**

`.github/workflows/lua-tests.yml`:

```yaml
name: Lua tests

on:
  push:
    branches: [master]
  pull_request:

jobs:
  lua-unit-tests:
    name: Lua unit tests (5.1)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5

      - name: Install Lua 5.1
        run: |
          sudo apt-get update -q
          sudo apt-get install -y lua5.1

      - name: Run the standalone suite
        run: lua5.1 test/lua/run.lua
```

- [ ] **Step 2: Validate the YAML locally**

```bash
"$LUA" -e "print('yaml has no lua check; verifying structure via python')" || true
python -c "import yaml,sys; yaml.safe_load(open('.github/workflows/lua-tests.yml')); print('valid YAML')"
```

Expected: `valid YAML`. (If `python`/`pyyaml` is unavailable, eyeball the indentation against another Actions file.)

- [ ] **Step 3: Confirm the CI command works exactly as the workflow runs it**

```bash
lua5.1 test/lua/run.lua 2>/dev/null || "$LUA" test/lua/run.lua
```

Expected: `ALL 4 SUITE(S) PASSED`, exit 0. This is the literal command the workflow's last step runs.

- [ ] **Step 4: Add the contributing.md note**

In `contributing.md`, immediately after the `## Writing a unit test` section and before `# setting up your editor`, insert:

```markdown
## Two test suites

Skynet has two test suites with different jobs:

| Suite | Runs where | Use for |
|-------|-----------|---------|
| `test/lua/` | plain Lua 5.1 — in VSCode, or `lua5.1 test/lua/run.lua`, and in CI on every push/PR | **logic**: state machines, parsing, maths, branching. No DCS needed. New logic tests go here. |
| `unit-tests/*.miz` | inside DCS — launch the mission, read `dcs.log` | **functional / smoke**: behaviour that needs the simulator — terrain elevation, radar detection geometry, real in-game events. |

For the standalone suite, add a `test/lua/test_<module>.lua` that `dofile`s
`luaunit.lua`, `dcs-stub.lua`, `mist-stub.lua`, loads the source module(s) via
`skynet-loader.lua`, and ends with `os.exit(luaunit.LuaUnit.run())`. See
`test/lua/test_skynet_iads_contact.lua` for the pattern and `test/lua/README.md`
for how to run it.
```

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/lua-tests.yml contributing.md
git commit -m "$(printf 'ci: run the standalone Lua suite on push and PR\n\nAlso documents the split between test/lua/ (logic, CI) and\nunit-tests/*.miz (in-sim functional/smoke) in contributing.md.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>')"
```

- [ ] **Step 6: Push the branch and open the PR**

```bash
git push -u origin feat/standalone-lua-tests
gh pr create --base master --title "Standalone Lua test suite (M1: harness + contact pilot)" --body "$(cat <<'EOF'
## What

Adds `test/lua/` — a standalone Lua 5.1 test harness that runs Skynet's logic
outside DCS, plus a GitHub Actions job that runs it on every push and PR.

- vendored luaunit 3.4, a hand-written `dcs-stub.lua` / `mist-stub.lua`, and an
  ordered `skynet-loader.lua`
- the `contact` module is ported as the pilot (`test_skynet_iads_contact.lua`),
  including a regression test for the `getTypeName` → WEAPON change
- the in-sim `unit-tests/*.miz` suites are untouched and reframed as
  functional/smoke tests in `contributing.md`

Design: `docs/superpowers/specs/2026-09-03-standalone-lua-tests-design.md`
Plan: `docs/superpowers/plans/2026-09-03-standalone-lua-tests.md`

## Out of scope (later milestones)

Bulk migration of the other mock-based suites; luacheck; StyLua; luacov ratchet;
`.luarc.json` + DCS LSP schema; devcontainer.

## Test

`lua5.1 test/lua/run.lua` → `ALL 4 SUITE(S) PASSED`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-Review

**1. Spec coverage**

| Spec section | Task |
|---|---|
| `test/lua/` layout | Tasks 1–5 |
| Vendored clean luaunit (not the `env.info` one) | Task 1, Step 1 + grep checks |
| Self-executing load model | Tasks 1–4 bootstrap blocks |
| `skynet-loader.lua`, order mirrors build script | Task 1, Step 4 (`ORDER` verbatim) |
| `dcs-stub.lua` surface (clock, Object, Weapon, world, env, trigger, timer, makeUnit, getByName) | Task 2 |
| `mist-stub.lua` (round, toDegree, metersToNM, metersToFeet, get2DDist, getHeading) | Task 3 |
| Contact pilot port table (all rows) | Task 4 suite |
| New `testGetTypeNameisWeapon`, no global stubbing | Task 4 `test_getTypeName_is_weapon` + Step 3 regression check |
| Recompute magic numbers from fixtures with arithmetic comments | Task 4 comments; Step 2 instruction |
| `run.lua` (glob, child process, filter, aggregate exit) | Task 5 |
| `.github/workflows/lua-tests.yml` | Task 6 |
| `contributing.md` reframing note | Task 6, Step 4 |
| Existing `.miz` suites untouched | No task modifies `unit-tests/` — stated in Global Constraints and Task 4 Files |
| Lua 5.1 constraints | Global Constraints; every code block is 5.1 |
| Out of scope items | Not in any task; listed in PR body |

No gaps.

**2. Placeholder scan**

No "TBD"/"TODO"/"handle edge cases"/"similar to Task N". Task 4 Step 3 contains an abandoned first approach in a code block — **fix:** the "Simpler check" block is the real instruction; the preceding `git stash` / `git show` block is noise. Keeping only the "Simpler check" block below.

Corrected Task 4 Step 3:

```bash
# Confirm the WEAPON test fails against the pre-change source, then restore.
git checkout f18b919 -- skynet-iads-source/skynet-iads-contact.lua
"$LUA" test/lua/test_skynet_iads_contact.lua   # EXPECT: test_getTypeName_is_weapon FAILS
git checkout HEAD -- skynet-iads-source/skynet-iads-contact.lua
"$LUA" test/lua/test_skynet_iads_contact.lua   # EXPECT: all 16 pass
```

**3. Type consistency**

- `dcsStub.makeUnit` field names (`name/type/category/pos/heading/exists/desc`) and methods (`getName/getTypeName/getPosition/isExist/getDesc/__setPos/__setHeading`) — defined in Task 2, used identically in Tasks 3 and 4. ✔
- `dcsStub.now()` — defined Task 2, used in Task 4 `test_getAge`. ✔
- `dcsStub.setClock` / `advanceClock` / `reset` — consistent across Tasks 2–4. ✔
- `mist.utils.get2DDist` signature `(vec3, vec3)` — Task 3 defines, contact source consumes. ✔
- `skynet-loader` `load` / `loadAll` / `reset` — Task 1 defines, Tasks 1 & 4 use `load`. ✔
- `Object.Category.WEAPON` — Task 2 enum, Task 4 weapon test. ✔
- Suite count "4" in Task 5 Step 2 and Task 6 — `test_harness_smoke`, `test_dcs_stub`, `test_mist_stub`, `test_skynet_iads_contact`. ✔
- Test count "16" in Task 4 — count the `function TestSkynetIADSContact:test_*` entries: unit, weapon, unknown, harm, height, heading, heading_gone, numTimesHit, refresh_calls_update, refresh_speed, age, altitude_profile, setHARMState, isIdentifiedAsHARM, isHARMStateUnknown, addRadarElement = 16. ✔

Fixed inline. Plan ready.
