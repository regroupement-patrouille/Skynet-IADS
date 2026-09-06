# Standalone Lua test suite — milestone 2 design

**Date:** 2026-09-06
**Status:** approved, pending implementation plan
**Predecessor:** `docs/superpowers/specs/2026-09-03-standalone-lua-tests-design.md` (M1 — shipped on `feat/standalone-lua-tests`)

## Problem

M1 built the standalone harness (`test/lua/`: vendored luaunit, `dcs-stub.lua`,
`mist-stub.lua`, `skynet-loader.lua`, `run.lua`) and ported one pilot suite
(`contact`). The other 11 suites in `unit-tests/` still run only inside DCS.
Most are already mock-based or lightly fixture-dependent — DCS adds nothing to
them but the slow edit → rebuild → re-import → fly → grep loop.

## Goal

Port the DCS-independent suites into `test/lua/` so they run in VSCode and CI.
Grow `dcs-stub.lua` for the API surface those suites reach, and add a shared
fixture module for the SAM/EW-shaped setups. The `unit-tests/*.miz` suites are
left untouched this milestone (keep-both; removal is a later decision once the
standalone suite has a release cycle behind it).

## Scope

### In — 6 suites, ~48 tests

| Suite (`unit-tests/…`) | Tests | Fixture work |
|---|---|---|
| `test-skynet-iads-harm-detection.lua` | 7 | none — pure mocks after `SkynetIADS:create()` |
| `test-skynet-iads-abstract-dcs-object-wrapper.lua` | 7 | one unit fixture (`EW-SA-6`, type `Kub 1S91 str`) |
| `test-skynet-moose-a2a-dispatcher-connector.lua` | **1 of 3** | none — only `testAddMooseSetGroupAndUpdate` (pure mock). The other two call `addEarlyWarningRadarsByPrefix`/`addSAMSitesByPrefix` and stay in the `.miz`. |
| `test-skynet-iads-jammer.lua` | 9 | `jammer-source` unit + the fake scheduler |
| `test-skynet-iads-abstract-element.lua` | 10 | a group + named connection-node unit and static fixtures |
| `test-skynet-iads-sam-site.lua` | 14 | SA-2 and SA-6 group fixtures (units typed per `samTypesDB`), a controller stub |

### Out — deferred to a later "demo-IADS-world fixture" milestone

- `test-syknet-early-warning-radar.lua` — `setUp` calls `addEarlyWarningRadarsByPrefix`, which enumerates the 17-EW world; the destruction test builds EW↔SAM associations across named mission groups.
- `test-skynet-iads-abstract-radar-element.lua` (52 tests, detection geometry), `test-skynet-iads.lua` (36, the integration suite), `test-skynet-iads-red-sam-sites-and-ew-radars.lua` (23), `test-skynet-iads-blue-sam-sites-and-ew-radars.lua` (13) — all assert properties of ~17 named sites with real unit types and map positions, or exercise radar-detection geometry that genuinely needs the simulator.

### Unchanged

`run.lua`, `.github/workflows/lua-tests.yml`, `skynet-loader.lua`, the vendored
`luaunit.lua`, and every file under `unit-tests/`.

## Architecture

### `dcs-stub.lua` growth

All additions are Lua 5.1 clean, no `os`/`io`. `dcsStub.reset()` clears the new
mutable state (scheduler task table) alongside the existing clock/world/logs.

**Fake scheduler** — the source uses `mist.scheduleFunction` in
`skynet-iads-jammer.lua`, `skynet-iads-abstract-radar-element.lua`, and
`skynet-iads.lua`.

```lua
-- mist.scheduleFunction(fn, args, startTime, interval) -> integer id
-- mist.removeFunction(id) -> the id if a task was removed, else nil
```

- ids are consecutive integers from 1; the jammer suite iterates
  `mist.removeFunction(i)` for `i` in `0..9999` to answer "is anything still
  scheduled?", so `removeFunction` must return falsy for unknown ids and truthy
  for a hit.
- **No auto-fire.** A suite that needs a scheduled callback to run invokes it
  directly, exactly as the `.miz` originals do
  (`self.jammer.runCycle(self.jammer)`). No time-driven dispatch loop in M2.
- `dcsStub.scheduledCount()` (test helper) returns the number of live tasks —
  the standalone replacement for the iterate-and-count idiom.

**`timer.getTime()`** — returns the model clock (same source as
`timer.getAbsTime`; the source treats `getTime` as mission-relative seconds and
only ever does arithmetic like `timer.getTime() + self.harmShutdownTime`).

**`AI.Option`** — the enum tree `setCanEngageAirWeapons` / `goLive` / `goDark`
read:
```lua
AI = { Option = {
  Ground = { id = { ENGAGE_AIR_WEAPONS = ..., ALARM_STATE = ... },
             val = { ALARM_STATE = { RED = ..., GREEN = ... } } },
  Air    = { id = { ROE = ... },
             val = { ROE = { WEAPON_FREE = ..., WEAPON_HOLD = ... } } },
} }
```
Values match the real DCS enum ints.

**`land.getIP(origin, direction, distance)`** → `nil` (no intercept = clear line
of sight). One call site, `skynet-iads-abstract-radar-element.lua:793`.

**`mist` additions** — `mist.random(m, n)` → `math.random(m, n)`;
`mist.utils.get3DDist(a, b)` → `((a.x-b.x)^2 + (a.y-b.y)^2 + (a.z-b.z)^2)^0.5`
(copied from `mist_4_5_107 : mist.utils.get3DDist` / `mist.vec.mag`).

**`__destroy()` on fixtures** — `makeUnit` / `makeGroup` / `makeStatic` each get
a `__destroy()` that flips `isExist()` to `false` (and, for a group, all its
units). `trigger.action.explosion` stays a recorded no-op — the real one is
async and range/armour-dependent, so a ported destruction test calls
`fixture:__destroy()` where the original called
`trigger.action.explosion(unit:getPosition().p, R)`.

**`dcsStub.makeGroup{ name =, units = { <makeUnit spec>, … } }`** →
`getName()`, `getUnits()` (live units only), `getUnit(i)`, `isExist()`,
`getController()` (→ a controller stub whose `setOption(id, val)` is a recorded
no-op), `__destroy()`. Registers into `dcsStub.world`, so
`Group.getByName(name)` resolves it.

**`dcsStub.makeStatic{ name =, type =, pos =, exists = }`** — like `makeUnit`
minus heading/controller; `StaticObject.getByName` already resolves the
registry.

### `test/lua/dcs-fixtures.lua` (new)

Reusable builders. Only the shapes the six suites need — no speculative SAM
types.

- **`fixtures.samGroup(natoShort, groupName)`** — builds and registers a
  `makeGroup` whose unit types satisfy `setupElements`' matcher in
  `skynet-iads-abstract-radar-element.lua` against `samTypesDB`:
  - `"SA-6"` → units `Kub 1S91 str` (search) + `Kub 2P25 ln` ×2 (launcher) → matches `Kub`, NATO `SA-6 Gainful`
  - `"SA-2"` → units `p-19 s-125 sr` (search) + `SNR_75V` (tracking) + `S_75M_Volhov` ×2 (launcher) → matches `S-75`, NATO `SA-2 Guideline`
  A comment ties each type string to its `samTypesDB` line.
- **`fixtures.connectionNodeUnit(name)`** / **`fixtures.connectionNodeStatic(name)`**
  — a plain existing unit / static registered under `name`.
- **`fixtures.iadsContact(unitName)`** — the standalone equivalent of the `.miz`
  suites' shared `IADSContactFactory` (`skynet-unit-tests.lua`): looks up a
  registered fixture, wraps it in `SkynetIADSContact`, `:refresh()`es it,
  returns it. Requires `skynet-iads-contact` + wrapper loaded by the caller.

`dcs-fixtures.lua` may use the `dcsStub`/`Object`/`Unit` globals but not
`os`/`io`.

### Load model — unchanged

Each ported suite is still a self-contained, self-executing file:
`dofile` luaunit + `dcs-stub` + `mist-stub` + (`dcs-fixtures` where needed),
`loader.load(...)` the modules under test, define `Test…` tables, end with
`os.exit(luaunit.LuaUnit.run())`. `run.lua` discovers them by the `test_*.lua`
glob with no change.

`loader.load(name)` does not pull dependencies (M1 decision), so a suite that
exercises `SkynetIADS` / `SkynetIADSSamSite` must `loader.load` the chain
explicitly in dependency order (or call `loader.loadAll()` — simplest, and the
grown stub supports it). The M1 loader wraps execution errors with the module
name, so a wrong order fails legibly. The harm-detection and a2a-connector
suites both build a `SkynetIADS`, so they load the chain, not just one module.

### Module load coverage

The ported suites pull in more of the source than M1 did — `SkynetIADSSamSite`
and `SkynetIADSAbstractElement` inherit from `SkynetIADSAbstractRadarElement`,
whose source touches `AI.Option`, `land.getIP`, `mist.random/scheduleFunction`,
`timer.getTime`, `world.event`. All are covered by the stub growth above.
`loader.loadAll()` must still succeed with the grown stub — the harness smoke
test already asserts this and stays green.

## Tasks

1. **Stub growth** — scheduler, `timer.getTime`, `AI.Option`, `land.getIP`,
   `mist.random`/`get3DDist`, `__destroy`, `makeGroup`, `makeStatic`. Extend
   `test_dcs_stub.lua` (scheduler id/removal semantics, `scheduledCount`,
   `__destroy` on unit and group, controller `setOption` capture,
   `getCategory` still nil-for-destroyed).
2. **`dcs-fixtures.lua`** + `test_dcs_fixtures.lua` (each builder produces a
   group/unit that `setupElements` classifies to the expected NATO name; the
   contact factory returns a refreshed `SkynetIADSContact`).
3. **`test_skynet_iads_harm_detection.lua`** — port; near-verbatim (mocks).
4. **`test_skynet_iads_abstract_dcs_object_wrapper.lua`** — port; one unit
   fixture.
5. **`test_skynet_moose_a2a_dispatcher_connector.lua`** — port
   `testAddMooseSetGroupAndUpdate` only; a header comment records that the two
   prefix-scan tests remain in the `.miz`.
6. **`test_skynet_iads_jammer.lua`** — port; scheduler + `jammer-source`
   fixture; destruction test uses `emitter:__destroy()`.
7. **`test_skynet_iads_abstract_element.lua`** — port; group + connection-node
   fixtures; destruction tests use `:__destroy()`.
8. **`test_skynet_iads_sam_site.lua`** — port; `fixtures.samGroup` for SA-2 /
   SA-6 / the destruction-test group; `getDetectedTargets` overridden to `{}`
   as in the original; destruction via `:__destroy()`.

Each suite task: adapt the `.miz` suite, wire fixtures, recompute any magic
number from the fixture with the arithmetic in a comment (M1 rule), land it
green under `"$LUA" test/lua/run.lua`.

## Testing

`"$LUA" test/lua/run.lua` runs the M1 suites plus the new ones; every suite
green, exit 0. CI unchanged — the new suites are picked up by the existing
glob. Interpreter: `C:\Program Files (x86)\Lua\5.1\lua.exe` locally, `lua5.1`
in CI.

## Global constraints (carried from M1)

- Lua 5.1 only. No `goto`, `//`, bitwise ops, `table.unpack`. `os`/`io` only in
  `run.lua` and `test_*.lua` — never in `dcs-stub.lua`, `mist-stub.lua`,
  `dcs-fixtures.lua`, `skynet-loader.lua`.
- Skynet source under `skynet-iads-source/*.lua` is loaded, never modified.
- Every stubbed `mist` function carries a `-- copied from
  demo-missions/mist_4_5_107.lua : <fn>` comment.
- Magic numbers in ported tests recomputed from code-defined fixtures with the
  arithmetic shown; adjust the fixture, not the assertion.
- `run.lua`'s M1 fix stands: `_find_lua`-style version-candidate search is not
  reintroduced.
- Commit trailer: `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.

## Out of scope

- Removing any suite from `unit-tests/*.miz`.
- `early-warning-radar`, `abstract-radar-element`, `iads`,
  `red/blue-sam-sites-and-ew-radars` — the demo-IADS-world fixture milestone.
- A time-driven scheduler dispatch loop (`dcsStub.advanceClock` firing due
  tasks). Add it when a ported suite actually needs a callback to fire on its
  own; none of the six do.
- luacheck, StyLua, luacov, `.luarc.json`, devcontainer — still their own later
  milestones.
- `highdigitsams/` suite.

## Risks

- **`setupElements` fixture fidelity** — if a `samGroup` fixture's unit types
  don't exactly match `samTypesDB`, `setupElements` silently classifies the
  group as `UNKNOWN` and the sam-site tests fail in confusing ways. Mitigated
  by `test_dcs_fixtures.lua` asserting the NATO name each builder produces, and
  by citing the `samTypesDB` line for every type string.
- **Scheduler semantics drift** — the jammer suite's iterate-count idiom is
  brittle; the port should use `dcsStub.scheduledCount()` instead, and the task
  must verify the count goes to zero after `masterArmSafe()` / emitter
  destruction, matching the original's intent.
- **Hidden `abstract-radar-element` surface** — a ported sam-site or
  abstract-element test may reach a code path with an unstubbed DCS call. The
  stub grows reactively per failure during the task; if a call needs real
  simulator behaviour (not just a stub), that test is deferred and noted, not
  forced green.
