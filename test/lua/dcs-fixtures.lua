--- Reusable fixture builders for the standalone Lua test suite. Uses the
--- dcsStub globals; no os/io. SAM group compositions are keyed to
--- skynet-iads-source/skynet-iads-supported-types.lua (samTypesDB).

local F = {}

local RADAR_RANGE_M = 120000

local function searchRadarSensors()
  -- shape iterated by SkynetIADSSAMSearchRadar:setupRangeData (data[i] -> subEntries[j])
  return {
    {
      {
        type = Unit.SensorType.RADAR,
        detectionDistanceAir = {
          upperHemisphere = { headOn = RADAR_RANGE_M },
          lowerHemisphere = { headOn = RADAR_RANGE_M },
        },
      },
    },
  }
end

local function launcherAmmo(count)
  return {
    {
      desc = {
        category = Weapon.Category.MISSILE,
        rangeMaxAltMin = 40000,
        rangeMaxAltMax = 40000,
        altMax = 12000,
      },
      count = count,
    },
  }
end

-- natoShort -> ordered unit specs (types verbatim from samTypesDB)
local SAM_COMPOSITIONS = {
  ["SA-6"] = function(groupName)
    return {
      { name = groupName .. "-sr", type = "Kub 1S91 str", sensors = searchRadarSensors() },
      { name = groupName .. "-ln1", type = "Kub 2P25 ln", ammo = launcherAmmo(3) },
      { name = groupName .. "-ln2", type = "Kub 2P25 ln", ammo = launcherAmmo(3) },
    }
  end,
  ["SA-2"] = function(groupName)
    return {
      { name = groupName .. "-sr", type = "p-19 s-125 sr", sensors = searchRadarSensors() },
      { name = groupName .. "-tr", type = "SNR_75V", sensors = searchRadarSensors() },
      { name = groupName .. "-ln1", type = "S_75M_Volhov", ammo = launcherAmmo(3) },
      { name = groupName .. "-ln2", type = "S_75M_Volhov", ammo = launcherAmmo(3) },
    }
  end,
}

function F.samGroup(natoShort, groupName)
  local build = SAM_COMPOSITIONS[natoShort]
  if not build then
    error("dcs-fixtures: no SAM composition for '" .. tostring(natoShort) .. "'")
  end
  local units = build(groupName)
  for i = 1, #units do
    units[i].pos = units[i].pos or { x = i, y = 0, z = 0 }
  end
  local group = dcsStub.makeGroup({ name = groupName, units = units })
  -- Skynet tells a Group from a Unit/Static via getmetatable(rep) == Group
  -- (SkynetIADSAbstractRadarElement:getUnitsToAnalyse, and the DCS object
  -- wrapper's getTypeName guard). dcsStub.makeGroup leaves the metatable nil;
  -- a group fixture must set it so setupElements iterates the member units.
  setmetatable(group, Group)
  return group
end

function F.connectionNodeUnit(name)
  local u = dcsStub.makeUnit({ name = name, type = "Ural-375", pos = { x = 0, y = 0, z = 0 } })
  dcsStub.world[name] = u
  return u
end

function F.connectionNodeStatic(name)
  return dcsStub.makeStatic({ name = name, type = "Comms tower M", pos = { x = 0, y = 0, z = 0 } })
end

function F.iadsContact(unitName)
  local unit = dcsStub.world[unitName]
  if not unit then
    error("dcs-fixtures: no fixture registered as '" .. tostring(unitName) .. "'")
  end
  local contact = SkynetIADSContact:create({ object = unit })
  contact:refresh()
  return contact
end

return F
