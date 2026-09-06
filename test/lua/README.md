# Standalone Lua tests

Logic tests for the Skynet-IADS source, run on a plain Lua 5.1 interpreter —
no DCS, no mission editor. This is where new **logic** tests go.

For behaviour that genuinely needs the simulator (terrain elevation, radar
detection geometry, real in-game events) see the in-sim functional/smoke
suites in `unit-tests/*.miz`.

## Run

Where `lua5.1` is on PATH (Linux, macOS, CI):

    lua5.1 test/lua/run.lua                          # all suites
    lua5.1 test/lua/run.lua contact                  # suites whose filename contains "contact"
    lua5.1 test/lua/test_skynet_iads_contact.lua     # one suite directly

On Windows without `lua5.1` on PATH, use the "Lua for Windows" binary
(`C:\Program Files (x86)\Lua\5.1\lua.exe`).

PowerShell needs the call operator `&` because the command line starts with a
quoted path:

    & "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua

cmd.exe takes the quoted path as-is:

    "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua

## Ported suites

These `unit-tests/` suites now also run standalone (their `.miz` copies are kept):
`harm-detection`, `abstract-dcs-object-wrapper`, `moose-a2a-connector` (1 test),
`jammer`, `abstract-element`, `sam-site`, plus the M1 `contact` pilot.

Still DCS-only (need the demo-IADS-world fixture — a later milestone):
`early-warning-radar`, `abstract-radar-element`, `iads`,
`red/blue-sam-sites-and-ew-radars`.

## Files

| File | Purpose |
|------|---------|
| `luaunit.lua` | Vendored luaunit 3.4 (upstream, unmodified) |
| `dcs-stub.lua` | Fake DCS scripting environment + fixture factories |
| `dcs-fixtures.lua` | Reusable fixtures — SAM group builders, connection nodes, the IADS-contact factory |
| `mist-stub.lua` | The slice of `mist` the loaded source calls |
| `skynet-loader.lua` | Loads `skynet-iads-source/*.lua` in dependency order |
| `run.lua` | Discovers and runs every `test_*.lua`, aggregates exit codes |
| `test_*.lua` | Test suites — self-contained, self-executing |
