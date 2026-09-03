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
