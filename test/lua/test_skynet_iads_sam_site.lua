--- Standalone port of unit-tests/test-skynet-iads-sam-site.lua (14 tests).
--- The DCS-mission version reads SAM groups baked into skynet-unit-tests.miz
--- and kills units with trigger.action.explosion(...). Here the SAM groups are
--- built by dcs-fixtures (F.samGroup), contacts by F.iadsContact, and units are
--- killed with <obj>:__destroy(). Every range magic number is recomputed from
--- the fixture radar range (dcs-fixtures RADAR_RANGE_M = 120000 m) with the
--- arithmetic shown in a comment; positions are adjusted, never the assertions.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
dofile(base .. "/mist-stub.lua")
local loader = dofile(base .. "/skynet-loader.lua")
loader.loadAll()
local F = dofile(base .. "/dcs-fixtures.lua")

-- one-liner from the .miz's skynet-unit-tests.lua
local function createDeadEvent()
  return { id = world.event.S_EVENT_DEAD }
end

-- maps the .miz group names to a fixture NATO short + which SAM it models
local GROUPS = {
  ["SAM-SA-6"] = "SA-6",
  ["SAM-SA-2"] = "SA-2",
  ["test-SAM-SA-2-test"] = "SA-2",
  ["Destruction-test-sam"] = "SA-6",
  ["prefixtest-sam"] = "SA-6",
}

TestSkynetIADSSAMSite = {}

function TestSkynetIADSSAMSite:setUp()
  dcsStub.reset()
  self.skynetIADS = SkynetIADS:create()
  if self.samSiteName then
    local nato = GROUPS[self.samSiteName] or "SA-6"
    local group = F.samGroup(nato, self.samSiteName)
    self.samSite = SkynetIADSSamSite:create(group, self.skynetIADS)
    -- overwritten as in the .miz: the real getDetectedTargets returns DCS world
    -- radar contacts which would interfere with these tests.
    function self.samSite:getDetectedTargets()
      return {}
    end
    self.samSite:setupElements()
    self.samSite:goLive()
  end
end

function TestSkynetIADSSAMSite:tearDown()
  if self.samSite then
    self.samSite:goDark()
    self.samSite:cleanUp()
  end
  if self.skynetIADS then
    self.skynetIADS:deactivate()
  end
  self.samSite = nil
  self.samSiteName = nil
end

function TestSkynetIADSSAMSite:testCompleteDestructionOfSamSiteAndLoadDestroyedSAMSiteInToIADS()

  F.samGroup("SA-6", "Destruction-test-sam")
  F.samGroup("SA-6", "prefixtest-sam")

  local samSite = SkynetIADSSamSite:create(Group.getByName("Destruction-test-sam"), self.skynetIADS):setActAsEW(true)
  samSite:setupElements()

  local samSite2 = SkynetIADSSamSite:create(Group.getByName('prefixtest-sam'), self.skynetIADS)
  samSite2:setupElements()

  samSite:addChildRadar(samSite2)
  samSite2:addParentRadar(samSite)

  luaunit.assertEquals(samSite2:getAutonomousState(), false)
  luaunit.assertEquals(samSite:isDestroyed(), false)
  luaunit.assertEquals(samSite:hasWorkingRadar(), true)

  local radars = samSite:getRadars()
  for i = 1, #radars do
    local radar = radars[i]
    -- .miz: trigger.action.explosion(radar:getDCSRepresentation():getPosition().p, 500)
    radar:getDCSRepresentation():__destroy()
    --we simulate a call to the event, since in game it is triggered too late for later checks in this unit test
    samSite:onEvent(createDeadEvent())
  end
  local launchers = samSite:getLaunchers()
  for i = 1, #launchers do
    local launcher = launchers[i]
    -- .miz: trigger.action.explosion(launcher:getDCSRepresentation():getPosition().p, 900)
    launcher:getDCSRepresentation():__destroy()
    samSite:onEvent(createDeadEvent())
  end
  luaunit.assertEquals(samSite:isActive(), false)
  luaunit.assertEquals(samSite:isDestroyed(), true)
  luaunit.assertEquals(samSite:hasWorkingRadar(), false)

  luaunit.assertEquals(samSite:getRemainingNumberOfMissiles(), 0)
  -- fixture SA-6: 2 launchers x launcherAmmo(3) => 3 + 3 = 6 initial missiles
  luaunit.assertEquals(samSite:getInitialNumberOfMissiles(), 6)
  luaunit.assertEquals(samSite:hasRemainingAmmo(), false)

  --after destruction of samSite acting as EW samSite2 must be autonomous:
  luaunit.assertEquals(samSite2:getAutonomousState(), true)

  --test build SAM with destroyed elements
  samSite:cleanUp()
  local samSite = SkynetIADSSamSite:create(Group.getByName("Destruction-test-sam"), self.skynetIADS)
  samSite:setupElements()
  luaunit.assertEquals(samSite:getNatoName(), "UNKNOWN")
  luaunit.assertEquals(#samSite:getRadars(), 0)
  luaunit.assertEquals(#samSite:getLaunchers(), 0)

  samSite:cleanUp()
  samSite2:cleanUp()
end

function TestSkynetIADSSAMSite:testInformOfContactInRange()
  self.samSiteName = "SAM-SA-6"
  self:setUp()
  local mockContact = {}
  function mockContact:isIdentifiedAsHARM()
    return false
  end
  function self.samSite:isTargetInRange(target)
    luaunit.assertIs(target, mockContact)
    return true
  end
  self.samSite:goDark()
  self.samSite:targetCycleUpdateStart()
  luaunit.assertEquals(self.samSite:isActive(), false)
  self.samSite:informOfContact(mockContact)
  luaunit.assertEquals(self.samSite:isActive(), true)
  self.samSite:targetCycleUpdateEnd()
  luaunit.assertEquals(self.samSite:isActive(), true)
end

function TestSkynetIADSSAMSite:testInformOfContactNotInRange()
  self.samSiteName = "SAM-SA-6"
  self:setUp()
  local mockContact = {}
  function self.samSite:isTargetInRange(target)
    luaunit.assertIs(target, mockContact)
    return false
  end
  self.samSite:goDark()
  self.samSite:targetCycleUpdateStart()
  luaunit.assertEquals(self.samSite:isActive(), false)
  self.samSite:informOfContact(mockContact)
  luaunit.assertEquals(self.samSite:isActive(), false)
  self.samSite:targetCycleUpdateEnd()
  luaunit.assertEquals(self.samSite:isActive(), false)
end

function TestSkynetIADSSAMSite:testInformOfHARMContactSAMCanEngageHARM()
  self.samSiteName = "test-SAM-SA-2-test"
  self:setUp()
  function self.samSite:isTargetInRange(contact)
    return true
  end
  local mockTarget = {}
  function mockTarget:isIdentifiedAsHARM()
    return true
  end
  self.samSite:goDark()
  luaunit.assertEquals(self.samSite:isActive(), false)
  self.samSite:setCanEngageHARM(true)
  self.samSite:informOfContact(mockTarget)
  luaunit.assertEquals(self.samSite:isActive(), true)
end

function TestSkynetIADSSAMSite:testInformOfHARMContactSAMCanNotEngageHARM()
  self.samSiteName = "test-SAM-SA-2-test"
  self:setUp()
  function self.samSite:isTargetInRange(contact)
    return true
  end
  local mockTarget = {}
  function mockTarget:isIdentifiedAsHARM()
    return true
  end
  self.samSite:goDark()
  luaunit.assertEquals(self.samSite:isActive(), false)
  self.samSite:setCanEngageHARM(false)
  self.samSite:informOfContact(mockTarget)
  luaunit.assertEquals(self.samSite:isActive(), false)
end

function TestSkynetIADSSAMSite:testSA2InformOfContactTargetNotInRange()
  self.samSiteName = "test-SAM-SA-2-test"
  self:setUp()
  self.samSite:goDark()
  -- .miz IADSContactFactory('test-not-in-firing-range-of-sa-2'): place it well
  -- outside the fixture search-radar range. distance from radar at (~0,0) is
  -- sqrt(500000^2) = 500000 m >> 120000 m fixture range => out of range.
  dcsStub.world["test-not-in-firing-range-of-sa-2"] = dcsStub.makeUnit({
    name = "test-not-in-firing-range-of-sa-2", type = "F-16C", pos = { x = 500000, y = 3000, z = 0 } })
  local target = F.iadsContact('test-not-in-firing-range-of-sa-2')
  self.samSite:informOfContact(target)
  luaunit.assertEquals(self.samSite:isTargetInRange(target), false)
  luaunit.assertEquals(self.samSite:isActive(), false)
end

function TestSkynetIADSSAMSite:testSA2InforOfContactInSearchRangeSAMSiteGoLiveWhenSetToSearchRange()
  self.samSiteName = "test-SAM-SA-2-test"
  self:setUp()
  self.samSite:goDark()
  luaunit.assertEquals(self.samSite:isActive(), false)
  self.samSite:setEngagementZone(SkynetIADSAbstractRadarElement.GO_LIVE_WHEN_IN_SEARCH_RANGE)
  luaunit.assertIs(self.samSite:getEngagementZone(), SkynetIADSAbstractRadarElement.GO_LIVE_WHEN_IN_SEARCH_RANGE)
  -- contact INSIDE the search radar range: distance sqrt(50000^2) = 50000 m
  -- < 120000 m fixture range => in search range => GO_LIVE_WHEN_IN_SEARCH_RANGE
  -- goes the SAM live.
  dcsStub.world["test-not-in-firing-range-of-sa-2"] = dcsStub.makeUnit({
    name = "test-not-in-firing-range-of-sa-2", type = "F-16C", pos = { x = 50000, y = 3000, z = 0 } })
  local target = F.iadsContact('test-not-in-firing-range-of-sa-2')
  self.samSite:informOfContact(target)
  luaunit.assertEquals(self.samSite:isActive(), true)
end

function TestSkynetIADSSAMSite:testInformOfContactMultipleTimesOnlyOneIsTargetInRangeCall()
  self.samSiteName = "SAM-SA-6"
  self:setUp()

  local mockContact = {}
  function mockContact:isIdentifiedAsHARM()
    return false
  end
  local numTimesCalledTargetInRange = 0

  function self.samSite:isTargetInRange(target)
    numTimesCalledTargetInRange = numTimesCalledTargetInRange + 1
    luaunit.assertIs(target, mockContact)
    return true
  end
  self.samSite:targetCycleUpdateStart()
  self.samSite:informOfContact(mockContact)
  self.samSite:informOfContact(mockContact)
  luaunit.assertEquals(numTimesCalledTargetInRange, 1)
end

function TestSkynetIADSSAMSite:testSAMStaysActiveWhenInAutonomousMode()
  self.samSiteName = "test-SAM-SA-2-test"
  self:setUp()
  luaunit.assertEquals(self.samSite:isActive(), true)
  luaunit.assertEquals(self.samSite:getAutonomousState(), true)
  self.samSite:targetCycleUpdateEnd()
  luaunit.assertEquals(self.samSite:isActive(), true)
end

function TestSkynetIADSSAMSite:testGoLiveConstraint()
  self.samSiteName = "SAM-SA-2"
  self:setUp()
  -- .miz IADSContactFactory('test-in-firing-range-of-sa-2'): height only matters
  -- here. 2000 m / 0.3048 = 6561.68 ft => round 6562 ft, which is > 4000.
  dcsStub.world["test-in-firing-range-of-sa-2"] = dcsStub.makeUnit({
    name = "test-in-firing-range-of-sa-2", type = "F-16C", pos = { x = 10000, y = 2000, z = 0 } })
  local contact = F.iadsContact('test-in-firing-range-of-sa-2')

  local function goLiveConstraint(contact)
    return (contact:getHeightInFeetMSL() > 4000)
  end

  luaunit.assertEquals(goLiveConstraint(contact), true)

  luaunit.assertEquals(self.samSite:areGoLiveConstraintsSatisfied(contact), true)
  self.samSite:addGoLiveConstraint('helicopter', goLiveConstraint)
  luaunit.assertEquals(self.samSite:areGoLiveConstraintsSatisfied(contact), true)

  local function goLiveConstraintFalse(contact)
    return (contact:getHeightInFeetMSL() < 4000)
  end

  self.samSite:addGoLiveConstraint('helicopter', goLiveConstraintFalse)
  luaunit.assertEquals(self.samSite:areGoLiveConstraintsSatisfied(contact), false)
end

function TestSkynetIADSSAMSite:testRemoveGoLiveConstraint()
  self.samSiteName = "SAM-SA-2"
  self:setUp()
  -- contact value is irrelevant to this test; only getGoLiveConstraints["test"]
  -- is invoked with it, and testMarkerFunction ignores its argument.
  dcsStub.world["test-in-firing-range-of-sa-2"] = dcsStub.makeUnit({
    name = "test-in-firing-range-of-sa-2", type = "F-16C", pos = { x = 10000, y = 2000, z = 0 } })
  local contact = F.iadsContact('test-in-firing-range-of-sa-2')

  self.samSite:addGoLiveConstraint("constraint", {})

  --this marker function is to test if after removing the first function this one will still exist
  function testMarkerFunction(contact)
    return 3
  end

  self.samSite:addGoLiveConstraint("test", testMarkerFunction)

  local count = 0
  for constraintName, constraint in pairs(self.samSite:getGoLiveConstraints()) do
    count = count + 1
  end
  luaunit.assertEquals(count, 2)

  count = 0
  self.samSite:removeGoLiveConstraint("constraint")
  for constraintName, constraint in pairs(self.samSite:getGoLiveConstraints()) do
    count = count + 1
  end
  luaunit.assertEquals(count, 1)

  luaunit.assertEquals(self.samSite:getGoLiveConstraints()["test"](contact), 3)
end

function TestSkynetIADSSAMSite:testSAMSiteWillNotGoLiveIfConstraintFailesAndContactIsInRange()
  self.samSiteName = "SAM-SA-2"
  self:setUp()
  -- contact IN range (distance sqrt(10000^2) = 10000 m < 120000 m fixture
  -- range) but at 2000 m / 0.3048 = 6562 ft, and the constraint requires
  -- < 4000 ft => constraint fails => SAM must not go live.
  dcsStub.world["test-in-firing-range-of-sa-2"] = dcsStub.makeUnit({
    name = "test-in-firing-range-of-sa-2", type = "F-16C", pos = { x = 10000, y = 2000, z = 0 } })
  local contact = F.iadsContact('test-in-firing-range-of-sa-2')

  local function goLiveConstraintFalse(contact)
    return (contact:getHeightInFeetMSL() < 4000)
  end

  self.samSite:addGoLiveConstraint('helicopter', goLiveConstraintFalse)
  self.samSite:goDark()
  self.samSite:targetCycleUpdateStart()
  self.samSite:informOfContact(contact)
  luaunit.assertEquals(self.samSite:isActive(), false)
end

os.exit(luaunit.LuaUnit.run())
