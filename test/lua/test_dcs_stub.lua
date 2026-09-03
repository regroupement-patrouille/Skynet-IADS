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
