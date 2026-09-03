--- Minimal `mist` surface for the standalone Lua test suite. Every function
--- here is copied from mist_4_5_107 (mist.utils.* around line 4960, mist.vec.mag
--- ~6165, mist.utils.get2DDist ~5309, mist.getHeading ~2509). Lua 5.1 clean.
---
--- North correction is 0: standalone tests use grid heading, with no theatre
--- magnetic model. Extend this file as more modules are ported.

mist = mist or {}
mist.utils = mist.utils or {}

-- mist_4_5_107: function mist.utils.round(num, idp)
function mist.utils.round(num, idp)
  local mult = 10 ^ (idp or 0)
  return math.floor(num * mult + 0.5) / mult
end

-- mist_4_5_107: function mist.utils.toDegree(angle)
function mist.utils.toDegree(angle)
  return angle * 180 / math.pi
end

-- mist_4_5_107: function mist.utils.metersToNM(meters)
function mist.utils.metersToNM(meters)
  return meters / 1852
end

-- mist_4_5_107: function mist.utils.metersToFeet(meters)
function mist.utils.metersToFeet(meters)
  return meters / 0.3048
end

-- mist_4_5_107: mist.utils.get2DDist == mist.vec.mag of the x/z delta (y zeroed).
-- Skynet always passes a Vec3 {x,y,z}, so the makeVec3 normalisation mist does
-- first is a no-op here.
function mist.utils.get2DDist(point1, point2)
  local dx = point1.x - point2.x
  local dz = point1.z - point2.z
  return (dx * dx + dz * dz) ^ 0.5
end

-- mist_4_5_107: function mist.getHeading(unit, rawHeading) — with the
-- getNorthCorrection term dropped (0 here, see file header).
function mist.getHeading(unit)
  local unitpos = unit:getPosition()
  if not unitpos then
    return nil
  end
  local heading = math.atan2(unitpos.x.z, unitpos.x.x)
  if heading < 0 then
    heading = heading + 2 * math.pi
  end
  return heading
end
