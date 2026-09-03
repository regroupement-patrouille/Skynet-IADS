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
