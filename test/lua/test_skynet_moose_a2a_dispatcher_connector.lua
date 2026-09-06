--- Standalone port of unit-tests/test-skynet-moose-a2a-dispatcher-connector.lua.
--- Only testAddMooseSetGroupAndUpdate ports -- it is pure-mock. The other two
--- (testGetEarlyWarningRadarGroupNames / testGetSAMSitesGroupNames) call
--- addEarlyWarningRadarsByPrefix / addSAMSitesByPrefix, which enumerate the
--- 17-EW / 17-SAM demo world; they stay in the .miz suite.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
dofile(base .. "/mist-stub.lua")
local loader = dofile(base .. "/skynet-loader.lua")
loader.loadAll()

TestMooseA2ADispatcherConnector = {}

function TestMooseA2ADispatcherConnector:setUp()
	dcsStub.reset()
	self.iads = SkynetIADS:create()
	self.connector = SkynetMooseA2ADispatcherConnector:create(self.iads)
end

function TestMooseA2ADispatcherConnector:tearDown()
	self.iads:deactivate()
end

function TestMooseA2ADispatcherConnector:testAddMooseSetGroupAndUpdate()

	local mockMooseSetGroup = {}
	mockMooseSetGroup.connector = self.connector
	local numRemoveCalls = 0

	function mockMooseSetGroup:RemoveGroupsByName(groupNames)
		numRemoveCalls = numRemoveCalls + 1
		if	numRemoveCalls == 1 then
			luaunit.assertEquals(groupNames, self.connector.ewRadarGroupNames)
		end

		if numRemoveCalls == 2 then
			luaunit.assertEquals(groupNames, self.connector.samSiteGroupNames)
		end
	end

	local samGroups = {}
	function self.connector:getSAMSiteGroupNames()
		return samGroups
	end

	local ewGroups = {}
	function self.connector:getEarlyWarningRadarGroupNames()
		return ewGroups
	end

	local numAddCalls = 0
	function mockMooseSetGroup:AddGroupsByName(groupNames)

		if numAddCalls == 0 then
			luaunit.assertEquals(groupNames, samGroups)
		end

		if numAddCalls == 1 then
			luaunit.assertEquals(groupNames, ewGroups)
		end

		numAddCalls = numAddCalls + 1
	end

	self.connector:addMooseSetGroup(mockMooseSetGroup)


	luaunit.assertEquals(numRemoveCalls, 2)
	luaunit.assertEquals(numAddCalls, 2)
end

os.exit(luaunit.LuaUnit.run())
