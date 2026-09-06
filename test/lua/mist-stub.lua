--- Minimal `mist` surface for the standalone Lua test suite. Every function
--- here is copied from demo-missions/mist_4_5_107.lua, cited per function by
--- name below. Lua 5.1 clean.
---
--- North correction is 0: standalone tests use grid heading, with no theatre
--- magnetic model. Extend this file as more modules are ported.

mist = mist or {}
mist.utils = mist.utils or {}

-- copied from demo-missions/mist_4_5_107.lua : mist.utils.round
function mist.utils.round(num, idp)
  local mult = 10 ^ (idp or 0)
  return math.floor(num * mult + 0.5) / mult
end

-- copied from demo-missions/mist_4_5_107.lua : mist.utils.toDegree
function mist.utils.toDegree(angle)
  return angle * 180 / math.pi
end

-- copied from demo-missions/mist_4_5_107.lua : mist.utils.metersToNM
function mist.utils.metersToNM(meters)
  return meters / 1852
end

-- copied from demo-missions/mist_4_5_107.lua : mist.utils.metersToFeet
function mist.utils.metersToFeet(meters)
  return meters / 0.3048
end

-- copied from demo-missions/mist_4_5_107.lua : mist.utils.get2DDist
--   (inlines demo-missions/mist_4_5_107.lua : mist.vec.mag of the x/z delta,
--   y zeroed). Skynet always passes a Vec3 {x,y,z}, so the makeVec3
--   normalisation mist does first is a no-op here.
function mist.utils.get2DDist(point1, point2)
  local dx = point1.x - point2.x
  local dz = point1.z - point2.z
  return (dx * dx + dz * dz) ^ 0.5
end

-- copied from demo-missions/mist_4_5_107.lua : mist.utils.get3DDist (= mist.vec.mag of the delta)
function mist.utils.get3DDist(point1, point2)
  local dx = point1.x - point2.x
  local dy = point1.y - point2.y
  local dz = point1.z - point2.z
  return (dx * dx + dy * dy + dz * dz) ^ 0.5
end

-- copied from demo-missions/mist_4_5_107.lua : mist.random (integer, no decimals) — simplified to the
-- underlying math.random(l, u); the real one biases toward >=50 sample points, which is irrelevant
-- to correctness here.
function mist.random(firstNum, secondNum)
  if not secondNum then
    return math.random(1, firstNum)
  end
  return math.random(firstNum, secondNum)
end

-- copied from demo-missions/mist_4_5_107.lua : mist.getHeading — with the
-- mist.getNorthCorrection term dropped (0 here, see file header).
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
