--- Standalone port of unit-tests/test-skynet-iads-abstract-dcs-object-wrapper.lua.
--- All 7 tests exercise the wrapper around a fixture unit: EW-SA-6, a Kub 1S91 str.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
dofile(base .. "/mist-stub.lua")
local loader = dofile(base .. "/skynet-loader.lua")
loader.loadAll()

TestSkynetIADSAbstractDCSObjectWrapper = {}

function TestSkynetIADSAbstractDCSObjectWrapper:setUp()
	dcsStub.reset()
	self.unit = dcsStub.makeUnit({ name = "EW-SA-6", type = "Kub 1S91 str", pos = { x = 0, y = 0, z = 0 } })
	dcsStub.world["EW-SA-6"] = self.unit
	self.abstractObjectWrapper = SkynetIADSAbstractDCSObjectWrapper:create(self.unit)
end

function TestSkynetIADSAbstractDCSObjectWrapper:tearDown()

end

function TestSkynetIADSAbstractDCSObjectWrapper:testGetName()
	luaunit.assertEquals(self.abstractObjectWrapper:getName(), 'EW-SA-6')
	self.abstractObjectWrapper.dcsRepresentation = nil
	--test to see if name is still returned after object wrapped is nil
	luaunit.assertEquals(self.abstractObjectWrapper:getName(), 'EW-SA-6')
end

function TestSkynetIADSAbstractDCSObjectWrapper:testGetTypeName()
	luaunit.assertEquals(self.abstractObjectWrapper:getTypeName(), 'Kub 1S91 str')
	self.abstractObjectWrapper.dcsRepresentation = nil
	luaunit.assertEquals(self.abstractObjectWrapper:getTypeName(), 'Kub 1S91 str')
end

function TestSkynetIADSAbstractDCSObjectWrapper:testIsExist()
	luaunit.assertEquals(self.abstractObjectWrapper:isExist(), true)
	self.abstractObjectWrapper.dcsRepresentation = nil
	luaunit.assertEquals(self.abstractObjectWrapper:isExist(), false)
end

function TestSkynetIADSAbstractDCSObjectWrapper:testGetDCSRepresentation()
	luaunit.assertEquals(self.abstractObjectWrapper:getDCSRepresentation(), Unit.getByName('EW-SA-6'))
end

function TestSkynetIADSAbstractDCSObjectWrapper:testInsertToTableIfNotAlreadyAdded()
	local tbl = {}
	local mock = {}
	table.insert(tbl, mock)
	local result = self.abstractObjectWrapper:insertToTableIfNotAlreadyAdded(tbl, mock)
	luaunit.assertEquals(#tbl, 1)
	luaunit.assertEquals(result, false)


	local mock2 = {}
	local result2 = self.abstractObjectWrapper:insertToTableIfNotAlreadyAdded(tbl, mock2)
	luaunit.assertEquals(#tbl, 2)
	luaunit.assertEquals(result2, true)
end

os.exit(luaunit.LuaUnit.run())
