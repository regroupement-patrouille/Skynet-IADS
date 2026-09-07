--- Standalone port of unit-tests/test-skynet-iads-jammer.lua.
--- The DCS-mission version reads a "jammer-source" unit baked into
--- skynet-unit-tests.miz and kills the emitter with
--- trigger.action.explosion(...). Here the emitter is a code-defined
--- dcsStub.makeUnit fixture, killed with emitter:__destroy(), and the
--- "is any task still scheduled?" checks use dcsStub.scheduledCount() in
--- place of the iterate-mist.removeFunction(0..10000) idiom.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
dofile(base .. "/mist-stub.lua")
local loader = dofile(base .. "/skynet-loader.lua")
loader.loadAll()

TestSkynetIADSJammer = {}

function TestSkynetIADSJammer:setUp()
  dcsStub.reset()
  self.emitter = dcsStub.makeUnit({ name = "jammer-source", type = "F-16C", pos = { x = 0, y = 1000, z = 0 } })
  self.mockIADS = {}
  function self.mockIADS:getDebugSettings()
    return {}
  end
  self.jammer = SkynetIADSJammer:create(self.emitter, self.mockIADS)
end

function TestSkynetIADSJammer:tearDown()
  self.jammer:masterArmSafe()
end

-- ---- distance setter (ported verbatim) ------------------------------

function TestSkynetIADSJammer:testSetJammerDistance()
  self.jammer:setMaximumEffectiveDistance(20)
  luaunit.assertEquals(self.jammer.maximumEffectiveDistanceNM, 20)
end

-- ---- full run cycle (ported verbatim) ------------------------------
-- Mocks the SAM/radar/IADS surface exactly as the .miz test does, so the
-- fake scheduler is never fired automatically; runCycle is invoked directly.

function TestSkynetIADSJammer:testSetupJammerAndRunCycle()
  luaunit.assertEquals(self.jammer.jammerTaskID, nil)
  self.jammer:masterArmOn()
  luaunit.assertNotIs(self.jammer.jammerTaskID, nil)

  local mockRadar = {}
  local mockSAM = {}
  local calledJam = false

  function mockSAM:getRadars()
    return { mockRadar }
  end

  function mockSAM:getNatoName()
    return "SA-2"
  end

  function mockSAM:jam(prob)
    calledJam = true
  end

  function self.mockIADS:getActiveSAMSites()
    return { mockSAM }
  end

  function self.jammer:getDistanceNMToRadarUnit(radarUnit)
    return 50
  end

  function self.jammer:hasLineOfSightToRadar(radar)
    return true
  end

  self.jammer.runCycle(self.jammer)
  luaunit.assertEquals(calledJam, true)
end

-- ---- known/unknown radar emitter (ported verbatim) ---------------

function TestSkynetIADSJammer:testIsActiveForUnknownType()
  luaunit.assertEquals(self.jammer:isKnownRadarEmitter('ABC-Test'), false)
end

function TestSkynetIADSJammer:testIsActiveForKnownType()
  luaunit.assertEquals(self.jammer:isKnownRadarEmitter('SA-2'), true)
end

-- ---- scheduler lifecycle (adapted) ------------------------------
-- .miz version scans mist.removeFunction(0..10000) for a live id; here
-- dcsStub.scheduledCount() reports the live task count directly.

function TestSkynetIADSJammer:testCleanUpJammer()
  self.jammer:masterArmOn()
  luaunit.assertEquals(dcsStub.scheduledCount(), 1)

  self.jammer:masterArmSafe()
  luaunit.assertEquals(dcsStub.scheduledCount(), 0)
end

-- ---- custom jammer function (ported verbatim) -------------------

function TestSkynetIADSJammer:testAddJammerFunction()
  local function f(distanceNM)
    return 2 * distanceNM
  end
  self.jammer:addFunction('SA-99', f)
  luaunit.assertEquals(self.jammer:getSuccessProbability(20, 'SA-99'), 40)
  luaunit.assertEquals(self.jammer:isKnownRadarEmitter('SA-99'), true)
  self.jammer:disableFor('SA-99')
  luaunit.assertEquals(self.jammer:isKnownRadarEmitter('SA-99'), false)
end

-- ---- dead emitter stops the cycle (adapted) --------------------
-- .miz version kills the emitter with trigger.action.explosion(pos, 500);
-- here emitter:__destroy() flips isExist() to false. runCycle sees the
-- dead emitter, calls masterArmSafe(), and the scheduled task is gone.

function TestSkynetIADSJammer:testDestroyEmitter()
  self:tearDown()
  local emitter = dcsStub.makeUnit({ name = "jammer-source-2", type = "F-16C", pos = { x = 0, y = 1000, z = 0 } })
  self.jammer = SkynetIADSJammer:create(emitter, SkynetIADS:create())
  self.jammer:masterArmOn()
  luaunit.assertEquals(dcsStub.scheduledCount(), 1)

  emitter:__destroy()
  self.jammer.runCycle(self.jammer)

  luaunit.assertEquals(dcsStub.scheduledCount(), 0)
end

os.exit(luaunit.LuaUnit.run())
