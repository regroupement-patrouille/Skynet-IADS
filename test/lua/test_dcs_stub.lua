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

function TestDcsStub:test_object_getCategory_nil_for_destroyed_unit()
  -- DCS returns nil for a destroyed-but-non-nil unit; skynet-iads-contact.lua
  -- is defensive about exactly this. The stub honours a dead fixture.
  luaunit.assertNil(Object.getCategory(dcsStub.makeUnit({ exists = false })))
  luaunit.assertEquals(Object.getCategory(dcsStub.makeUnit({ type = "MiG-29" })), Object.Category.UNIT)
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

os.exit(luaunit.LuaUnit.run())
