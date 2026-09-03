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
