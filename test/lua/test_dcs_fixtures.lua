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
  -- buildNatoName() shortens "SA-x ..." database names to the "SA-x" prefix
  -- (see skynet-iads-abstract-radar-element.lua and the mission unit-tests).
  luaunit.assertEquals(site:getNatoName(), "SA-6")
  luaunit.assertEquals(site:getInitialNumberOfMissiles(), 6)
end

function TestDcsFixtures:test_samGroup_SA2_classifies()
  local g = F.samGroup("SA-2", "test-SA-2")
  local site = SkynetIADSSamSite:create(g, SkynetIADS:create())
  site:setupElements()
  luaunit.assertEquals(site:getNatoName(), "SA-2")
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
