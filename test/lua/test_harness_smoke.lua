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

function TestHarnessSmoke:test_loader_reset_forces_reload()
  loader.load("skynet-iads-abstract-dcs-object-wrapper")
  loader.load("skynet-iads-contact")
  luaunit.assertEquals(type(SkynetIADSContact), "table")

  -- wipe the global the file defines; a memoised load would NOT bring it back
  SkynetIADSContact = nil
  loader.load("skynet-iads-contact") -- still memoised => no-op
  luaunit.assertNil(SkynetIADSContact)

  -- reset drops the memo; the next load genuinely re-runs the file
  loader.reset()
  loader.load("skynet-iads-contact")
  luaunit.assertEquals(type(SkynetIADSContact), "table")
end

os.exit(luaunit.LuaUnit.run())
