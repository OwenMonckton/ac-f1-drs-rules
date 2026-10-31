-- Mock CSP environment + simulated race for F1DRSRules.lua
-- Globals set by runner: APP_SOURCE (string), SCENARIO (table)

local S = SCENARIO
local sim = { carsCount = #S.cars, time = 0, raceSessionType = S.session or 3, isOnlineRace = false, isReplayActive = false }
local cars = {}
for i, c in ipairs(S.cars) do
  cars[i - 1] = { index = i - 1, splinePosition = c.pos, lapCount = 0, isInPitlane = false, drsActive = false, drsAvailable = false,
    lapTime = c.lapTime, pitOnLap = c.pitOnLap }
end
local disabled = {}       -- carIndex -> bool
local callbacks = {}      -- { progress, cb }
local messages = {}

ac = {
  SessionType = { Practice = 1, Qualify = 2, Race = 3 },
  getSim = function () return sim end,
  getCar = function (i) return cars[i] end,
  storage = function (t) return t end,
  warn = function (...) print('WARN', ...) end,
  setMessage = function (t, d) messages[#messages + 1] = string.format('[%.1fs] %s: %s', sim.time / 1000, t, d) end,
  onSessionStart = function () end,
  onTrackPointCrossed = function (car, progress, cb) callbacks[#callbacks + 1] = { progress = progress, cb = cb } end,
  INIConfig = {
    trackData = function ()
      local z = S.zones
      return {
        iterate = function (self, prefix)
          local i = 0
          return function () i = i + 1; if z[i] then return i, 'ZONE_' .. (i - 1) end end
        end,
        get = function (self, section, key, def)
          local idx = tonumber(section:match('%d+')) + 1
          local v = z[idx] and z[idx][key]
          if v == nil then return def end
          return v
        end,
      }
    end,
  },
}
BEEPS = {}
ac.AudioEvent = { fromFile = function (p)
  local e = {}
  function e:dispose() end
  function e:resume() BEEPS[#BEEPS + 1] = string.format('[%.1fs] %s', sim.time / 1000, p.filename) end
  return e
end }
physics = {
  allowed = function () return true end,
  allowCarDRS = function (i, d) disabled[i] = d end,
}
script = {}
ui = setmetatable({}, { __index = function () return function () return false end end })
rgbm = function () return {} end

assert(loadstring(APP_SOURCE, 'F1DRSRules.lua'))()

-- Simulation
local dt = 0.01
local unlockLog = {}  -- unlockLog[car][key] = true where key = 'lapN:zoneZ' while DRS was allowed
local lap1Unlocked = {}

local function crossed(prev, cur, p)
  if cur >= prev then return prev < p and cur >= p end
  return prev < p or cur >= p  -- wrapped over 1.0
end

local function zoneOf(pos)
  for zi, z in ipairs(S.zones) do
    local s, e = z.START, z.END
    if (s <= e and pos >= s and pos <= e) or (s > e and (pos >= s or pos <= e)) then return zi end
  end
end

local steps = math.floor(S.duration / dt)
for _ = 1, steps do
  local t0 = sim.time
  sim.time = sim.time + dt * 1000
  for i = 0, sim.carsCount - 1 do
    local c = cars[i]
    local prev = c.splinePosition
    local cur = (prev + dt / c.lapTime) % 1
    c.isInPitlane = c.pitOnLap ~= nil and c.lapCount + 1 == c.pitOnLap and (cur > 0.85)
      or c.pitOnLap ~= nil and c.lapCount == c.pitOnLap and cur < 0.05
    if crossed(prev, cur, 0) then c.lapCount = c.lapCount + 1 end
    for _, cb in ipairs(callbacks) do
      if not c.isInPitlane and crossed(prev, cur, cb.progress) then
        local frac = ((cb.progress - prev) % 1) / ((cur - prev) % 1)
        cb.cb(i, t0 + frac * dt * 1000)
      end
    end
    c.splinePosition = cur
  end
  script.update(dt)
  -- player opens DRS as soon as it's allowed inside a zone (closes outside / when locked)
  cars[0].drsActive = disabled[0] == false and (zoneOf(cars[0].splinePosition) ~= nil or #S.zones == 0)
  for i = 0, sim.carsCount - 1 do
    local c = cars[i]
    if disabled[i] == false then
      local z = zoneOf(c.splinePosition) or (#S.zones == 0 and 0)
      if z then
        unlockLog[i] = unlockLog[i] or {}
        local k = string.format('lap%d:zone%d', c.lapCount + 1, z); unlockLog[i][k] = unlockLog[i][k] or string.format('%s@%.1f', k, sim.time / 1000)
      end
      if c.lapCount == 0 then lap1Unlocked[i] = true end
    end
  end
end

RESULT = { unlock = {}, lap1 = {}, messages = messages, beeps = BEEPS }
for i = 0, sim.carsCount - 1 do
  local keys = {}
  for k in pairs(unlockLog[i] or {}) do keys[#keys + 1] = unlockLog[i][k] end
  table.sort(keys)
  RESULT.unlock[i] = table.concat(keys, ' ')
  RESULT.lap1[i] = lap1Unlocked[i] and 'YES' or 'no'
end
