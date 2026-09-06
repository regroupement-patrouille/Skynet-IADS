--- Standalone port of unit-tests/test-skynet-iads-abstract-element.lua.
--- Exercises SkynetIADSAbstractElement wrapped around a fixture SA-6 group
--- (SAM-SA-6-2, a Kub 2P25 ln). Connection-node / power-source destruction
--- tests swap the .miz `trigger.action.explosion(...)` for `<obj>:__destroy()`
--- and resolve their fixtures via dcs-fixtures.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
dofile(base .. "/mist-stub.lua")
local loader = dofile(base .. "/skynet-loader.lua")
loader.loadAll()
local F = dofile(base .. "/dcs-fixtures.lua")

TestSkynetIADSAbstractElement = {}

function TestSkynetIADSAbstractElement:setUp()
	dcsStub.reset()
	self.iads = SkynetIADS:create()
	self.group = dcsStub.makeGroup({ name = "SAM-SA-6-2", units = { { name = "SAM-SA-6-2-u1", type = "Kub 2P25 ln" } } })
	self.abstractElement = SkynetIADSAbstractElement:create(self.group, self.iads)

	--mock this function, we test it once in testCheckOneGenericObjectAliveForUnitWorks
	function self.abstractElement:setToCorrectAutonomousState()
	end
end

function TestSkynetIADSAbstractElement:tearDown()
	self.abstractElement:cleanUp()
end

-- by default an abstractElement will return true if no power source or connection node is set
function TestSkynetIADSAbstractElement:testHasActiveConnectionNodeByDefaultIfNoneIsSet()
	luaunit.assertEquals(self.abstractElement:genericCheckOneObjectIsAlive({}), true)
	luaunit.assertEquals(self.abstractElement:hasActiveConnectionNode(), true)
	luaunit.assertEquals(self.abstractElement:hasWorkingPowerSource(), true)
end

function TestSkynetIADSAbstractElement:testCheckOneGenericObjectAliveForUnitWorks()
	local unit = F.connectionNodeUnit('SAM-SA-6-2-connection-node-unit')

	local called = false

	function self.abstractElement:informChildrenOfStateChange()
		called = true
	end

	self.abstractElement:addConnectionNode(unit)
	luaunit.assertEquals(called, true)
	luaunit.assertEquals(self.abstractElement:genericCheckOneObjectIsAlive(self.abstractElement.connectionNodes), true)
	luaunit.assertEquals(self.abstractElement:hasActiveConnectionNode(), true)
	unit:__destroy()
	luaunit.assertEquals(self.abstractElement:genericCheckOneObjectIsAlive(self.abstractElement.connectionNodes), false)
	luaunit.assertEquals(self.abstractElement:hasActiveConnectionNode(), false)
end


function TestSkynetIADSAbstractElement:testCheckOneGenericObjectAliveForStaticObjectsWorks()
	local static = F.connectionNodeStatic('SAM-SA-6-2-coonection-node-static')
	self.abstractElement:addConnectionNode(static)
	luaunit.assertEquals(self.abstractElement:genericCheckOneObjectIsAlive(self.abstractElement.connectionNodes), true)
	luaunit.assertEquals(self.abstractElement:hasActiveConnectionNode(), true)
	static:__destroy()
	luaunit.assertEquals(self.abstractElement:genericCheckOneObjectIsAlive(self.abstractElement.connectionNodes), false)
	luaunit.assertEquals(self.abstractElement:hasActiveConnectionNode(), false)
end

function TestSkynetIADSAbstractElement:testPowerSourceAndConnectionNodeStaticObjectAndDestrutionSuccessful()

	local powerSource = F.connectionNodeStatic("test-ground-vehicle-power-source")
	local connectionNode = F.connectionNodeStatic("test-ground-vehicle-connection-node")

	self.abstractElement:addPowerSource(powerSource)
	self.abstractElement:addConnectionNode(connectionNode)
	luaunit.assertEquals(self.abstractElement:hasWorkingPowerSource(), true)
	luaunit.assertEquals(self.abstractElement:hasActiveConnectionNode(), true)

	powerSource:__destroy()
	connectionNode:__destroy()

	luaunit.assertEquals(self.abstractElement:hasWorkingPowerSource(), false)
	luaunit.assertEquals(self.abstractElement:hasActiveConnectionNode(), false)
end

function TestSkynetIADSAbstractElement:testGetNatoName()
	luaunit.assertEquals(self.abstractElement:getNatoName(), "UNKNOWN")
end

function TestSkynetIADSAbstractElement:testGetDescription()
	luaunit.assertEquals(self.abstractElement:getDescription(), "IADS ELEMENT: SAM-SA-6-2 | Type: UNKNOWN")
end

function TestSkynetIADSAbstractElement:testGetDCSRepresentation()
	luaunit.assertEquals(self.abstractElement:getDCSRepresentation(), self.group)
end

function TestSkynetIADSAbstractElement:testGetDCSName()
	luaunit.assertEquals(self.abstractElement:getDCSName(), "SAM-SA-6-2")

	--overwrite the DCSRepresentation to test caching on the DCS unit / group name
	function self.abstractElement:getDCSRepresentation()
		return nil
	end

	luaunit.assertEquals(self.abstractElement:getDCSName(), "SAM-SA-6-2")

end

os.exit(luaunit.LuaUnit.run())
