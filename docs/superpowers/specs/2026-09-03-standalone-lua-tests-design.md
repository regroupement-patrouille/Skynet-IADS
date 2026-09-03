# Standalone Lua test suite — design

**Date:** 2026-09-03
**Status:** approved, pending implementation plan
**Branch:** `feat/standalone-lua-tests`

## Problem

Skynet-IADS has one test suite. It runs only inside DCS: the `test-*.lua`
files are packaged into `unit-tests/skynet-unit-tests.miz`, loaded by mission
triggers alongside a built `skynet-iads-compiled.lua`, and executed 1 s after
mission start by `lu.LuaUnit.run()`. Results land in `dcs.log`.

Consequences:

- No CI. Nothing runs on push or PR.
- The feedback loop for a pure-logic change is: edit source → rebuild
  `skynet-iads-compiled.lua` → re-import into the `.miz` via the DCS Mission
  Editor → launch the mission → grep `dcs.log`. Minutes, and manual.
- Most suites are already mock-based (the entire HARM-detection suite, the
  contact HARM/altitude logic, the table delegator). DCS contributes nothing
  to those except the slow loop.
- The minority that genuinely exercise the simulator — terrain elevation,
  position-delta speed math, radar-detection geometry — cannot move out and
  should not.

## Goal

Add a second suite that runs Skynet's **logic** on a plain Lua 5.1 interpreter,
in VSCode and in CI, in seconds. Keep the in-sim suite for what only DCS can
verify, reframed as functional / smoke tests.

This milestone (M1) delivers the harness plus one pilot module. Bulk migration
and the wider tooling floor are later milestones (see "Out of scope").

## Reference

`D:\Projects\DcsLua\VEAF-Mission-Creation-Tools` solves the same problem at
scale (~50 suites, ~5,600 assertions) and is a sister project that already
integrates Skynet. Its approach, adopted here:

| Concern | VEAF |
|---|---|
| Framework | vendored `test/lua/luaunit.lua` — **not** busted, no luarocks |
| Runtime | plain Lua 5.1 |
| Test file | self-contained, self-executing: `dofile`s luaunit + DCS mock + source, ends `os.exit(luaunit.LuaUnit.run())` |
| DCS mock | one `test/lua/dcs_mocks.lua`, global table, controllable clock, captured calls, `reset()` in `setUp` |
| Loader | ordered `loadfile` list mirroring in-game load order |
| CI | GitHub Actions: unit tests, luacheck, StyLua, luacov ratchet |
| Editor | `.luarc.json` for sumneko lua-language-server + a DCS API schema |
| Zero-install | `.devcontainer/` |

The framework question (busted vs luaunit) is settled by this reference:
vendored luaunit, because it needs no toolchain install and matches the sister
project.

## Architecture

### Directory layout

```
test/lua/
  luaunit.lua                    vendored upstream luaunit 3.4 — a CLEAN copy,
                                 not the env.info-patched one in unit-tests/
  dcs-stub.lua                   fake DCS scripting environment + object factories
  mist-stub.lua                  the mist.utils / mist.* functions the loaded source needs
  skynet-loader.lua              ordered loadfile() of skynet-iads-source/, exposes load(name)
  test_skynet_iads_contact.lua   pilot module (ported from unit-tests/test-skynet-iads-contact.lua)
  run.lua                        discovers test_*.lua, runs each, aggregates exit code
  README.md                      how to run; relationship to the .miz suites
```

`test/` is a new top-level directory, mirroring VEAF. `unit-tests/` is left in
place for the `.miz` functional suites.

### Load model

Each `test_*.lua` bootstraps itself, exactly as VEAF's do:

```lua
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")   -- global, for the test methods
dofile(base .. "/dcs-stub.lua")
dofile(base .. "/mist-stub.lua")
local load = dofile(base .. "/skynet-loader.lua")
load("skynet-iads-abstract-dcs-object-wrapper")
load("skynet-iads-contact")

TestSkynetIADSContact = {}
function TestSkynetIADSContact:setUp() dcsStub.reset() end
-- test methods...

os.exit(luaunit.LuaUnit.run())
```

The Skynet source files are `do … Global = {} … end` blocks that assign globals
and `return` nothing, so `loadfile(path)()` in dependency order populates the
same globals the concatenated `skynet-iads-compiled.lua` would. No source
refactoring is required for M1.

### skynet-loader.lua

```lua
-- ordered to match build-tools/build-compiled-script.ps1
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
```

`load(name)` resolves `name` against `skynet-iads-source/` (overridable via the
`SKYNET_SRC` env var), `loadfile`s it, calls it once, and memoises. `loadAll()`
walks `ORDER`. A suite calls only what it needs; the pilot calls two entries.

Files not in the pilot's path (`skynet-iads.lua` touching
`world.addEventHandler` at `create()`, `SkynetIADS.database = samTypesDB` at
load) are covered by dcs-stub as later suites need them — M1 does not load them.

### dcs-stub.lua

A single file defining the DCS globals the loaded source touches. Modelled on
VEAF's `dcs_mocks.lua` but scoped to what M1 loads; grows per milestone.

- **Global `dcsStub` control table**
  - `dcsStub.setClock(t)` / `dcsStub.advanceClock(dt)` — drive `timer.getAbsTime`
  - `dcsStub.reset()` — clock to 0, clear registry and captured calls; called in `setUp`
  - `dcsStub.logs` — captured `env.*` output
  - `dcsStub.world` — name → object registry backing the `getByName` calls
- **`timer`** — `getAbsTime` returns the model clock
- **`Object`** — `Object.Category = { UNIT=1, WEAPON=2, STATIC=3, ... }`;
  `Object.getCategory(o)` returns `o.__category or Object.Category.UNIT`, `nil` for `nil`
- **`Weapon`** — `Weapon.Category = { SHELL=0, MISSILE=1, ROCKET=2, BOMB=3 }`
- **`world`** — `world.event` enum; `world.addEventHandler(h)` captured into `dcsStub`
- **`env`** — `info` / `warning` / `error` capture to `dcsStub.logs`
- **`trigger`** — `trigger.action.outText` / `explosion` no-op (recorded)
- **Object factory** — `dcsStub.makeUnit{ name=, type=, category=, pos={x,y,z}, heading=, exists= }`
  returns a table with `getName`, `getTypeName`, `getPosition` (`{ p = pos }`),
  `isExist`, `getHeading`, `getDesc`, and `__setPos` for mid-test movement
- **Lookups** — `Unit.getByName`, `Group.getByName`, `StaticObject.getByName`
  resolve from `dcsStub.world`; a test registers fixtures with
  `dcsStub.world["name"] = dcsStub.makeUnit{...}`

Lua 5.1 clean: no `goto`, no `//`, no bitwise ops, `unpack` not `table.unpack`;
`os` / `io` only in `run.lua`, never in stub or source paths.

### mist-stub.lua

Skynet calls `mist` directly (VEAF ported the maths into its own module and
avoids mist entirely — Skynet has not). For M1, hand-stub only what the contact
source path uses:

- `mist.utils.round`, `mist.utils.metersToFeet`, `mist.utils.metersToNM`,
  `mist.utils.get2DDist`, `mist.utils.toDegree`
- `mist.getHeading`

Implemented from the real mist formulas. A fuller mist strategy (vendor real
mist vs. keep extending the stub) is deferred — flagged in "Out of scope".

### run.lua

```
lua5.1 test/lua/run.lua            # all suites
lua5.1 test/lua/run.lua contact    # suites whose filename contains "contact"
```

Globs `test/lua/test_*.lua`, runs each in a child process (`os.execute` with the
same interpreter via `arg[-1]`), prints a per-suite line, exits non-zero if any
suite failed. Interpreter discovery matches VEAF's `_find_lua`: `lua5.1`,
`lua51`, `lua`, then `C:\Program Files (x86)\Lua\5.1\lua.exe`, each version-
checked so a stray 5.4 is rejected rather than used.

## Pilot module: contact

Ported from `unit-tests/test-skynet-iads-contact.lua`. That suite leans on
fixtures baked into `skynet-unit-tests.miz` and asserts the resulting magic
numbers (`"AH-1W"`, ground speed `989`, height `5015`, heading `347`). Porting
replaces each with a code-defined fixture — demonstrating the fixture-migration
pattern the later milestones repeat.

| Existing test | Port |
|---|---|
| `testGetTypeNameisUnit` | fixture `type = "AH-1W"`, assert `"AH-1W"` |
| `testGetTypeNameUNKNOWN` | `getDCSRepresentation` → nil, unchanged |
| `testGetTypeNameisHARM` | HARM state set, unchanged |
| **new: `testGetTypeNameisWeapon`** | `makeUnit{ category = Object.Category.WEAPON, type = "weapons.missiles.AGM_88" }`, assert the type name — no global stubbing needed (this is why the source change ships on this branch) |
| `testGetHeightInFeetMSL` | fixture `pos.y`, assert `mist.utils.metersToFeet` of it, rounded |
| `testGetMagneticHeading` | fixture `heading` (radians); assert degrees; second case `isExist` → false → `-1` |
| `testRefresh` | `setClock`, register a second fixture, `advanceClock(1000)`, assert `getAge()` and computed `getGroundSpeedInKnots(0)` from a known 2D distance |
| `testGetNumberOfTimesHitByRadar` | `refresh` twice across a clock tick, assert count |
| `testUpdateSimpleAltitudeProfile` | port near-verbatim (already mock-based) |
| `testSetIsHARM`, `testIsIdentifiedAsHARM`, `testIsHARMStateUnknown` | port verbatim |
| `testAddAbstractRadarElementDetected` | port verbatim |

The `.miz` copy of this suite is left untouched in M1; its removal is part of
the later bulk-migration milestone once the standalone suite has proven out.

## CI

`.github/workflows/lua-tests.yml` — the repo has no `.github/` today.

```yaml
name: Lua tests
on: { push: { branches: [master] }, pull_request: {} }
jobs:
  lua-unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - run: sudo apt-get update -q && sudo apt-get install -y lua5.1
      - run: lua5.1 test/lua/run.lua
```

~15 s. luacheck / StyLua / luacov are separate later jobs.

## Existing `.miz` suites

Unchanged. Add a paragraph to `contributing.md`:

- **`test/lua/`** — standalone logic tests. Run in VSCode or with
  `lua5.1 test/lua/run.lua`. No DCS required. This is where new logic tests go.
- **`unit-tests/*.miz`** — in-sim functional / smoke tests. Run by launching the
  mission in DCS and reading `dcs.log`. For behaviour that needs the simulator
  (terrain, detection geometry, real events).

## Out of scope for M1

Each is its own later milestone:

- Bulk migration of the other mock-based suites (harm-detection, table
  delegator, abstract-element, jammer, …) and their removal from the `.miz`
- luacheck + `.luacheckrc` (`std = "lua51"`, DCS globals allowlist)
- StyLua + `.stylua.toml`
- luacov line coverage with a ratchet floor
- `.luarc.json` + a vendored DCS API schema for lua-language-server autocomplete
- `.devcontainer/` for zero-install onboarding
- mist strategy beyond the hand-stub
- Porting the `highdigitsams/` suite

## Risks

- **dcs-stub drift** — the stub can diverge from real DCS behaviour. Mitigated
  long-term by a mock-coverage audit (VEAF has one); for M1, kept small and
  reviewed against the source call sites.
- **mist-stub fidelity** — wrong formula = green tests, wrong answers.
  Mitigated by copying mist's actual implementations and citing them.
- **Fixture magic numbers** — porting recomputes expected values from the
  fixtures rather than carrying over `.miz`-derived constants; each recomputed
  constant gets a comment showing the arithmetic.
