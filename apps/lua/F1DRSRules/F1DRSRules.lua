--[[
  F1 DRS Rules — CSP Lua app (offline races).

  Rules, applied to every car (player and AI) in Race sessions:
    1. No DRS while a car is on a lap below `enableLap` (default: no DRS on lap 1).
    2. For each zone in the track's data/drs_zones.ini, a car may open DRS in that zone only if,
       when it crossed the zone's DETECTION point, it was within `gap` seconds (default 1.0) of
       the car that crossed that point just before it (the car directly ahead on the road,
       lapped cars included, like F1). The detection crossing itself must also happen on lap
       `enableLap` or later.
    3. Outside of those conditions DRS stays locked for that zone pass.

  Tracks without drs_zones.ini (where AC allows DRS anywhere): the start/finish line acts as
  the detection point and the whole following lap acts as one zone.

  Locking is done with physics.allowCarDRS(), which can only add restrictions on top of AC's own
  zone logic, so AC still decides where the zones physically are. Practice/qualifying are left
  alone (normal AC behaviour) unless "Race sessions only" is unticked.
]]

local sim = ac.getSim()

local cfg = ac.storage{
  enabled = true,      -- master switch
  gap = 1.0,           -- seconds to car ahead at detection
  enableLap = 2,       -- first lap on which DRS can be used
  raceOnly = true,     -- only enforce in Race sessions
  messages = true,     -- on-screen message to the player at each detection point
  beeps = true,        -- drs_armed.wav when DRS is earned at detection, drs_open.wav when the flap opens
  beepVolume = 0.8,
}

local DETECTION_SETTLE_MS = 100  -- wait this long after a crossing before judging the gap, so every
                                 -- car that crossed earlier has reported its own crossing
local ZONE_LEAD_IN = 0.003       -- unlock a touch before the zone's START so it's ready in time

local physicsOk = physics.allowed()
local zones = {}          -- { detection, start, finish, wholeLap }
local zonesSource = ''
local crossHandles = {}

local lastCross = {}      -- lastCross[zoneIndex][carIndex] = time (ms) of latest detection crossing
local pending = {}        -- crossings waiting to be judged: { car, zone, time, lapCount }
local verdict = {}        -- verdict[carIndex][zoneIndex] = { ok, gap, lap }
local prevZone = {}       -- carIndex -> zone index the car was in last frame (or false)
local applied = {}        -- carIndex -> last value passed to physics.allowCarDRS (true = disabled)

local sounds = {}

-- Non-looping file events become invalid after one play, so recreate each time (same as CSP's Mumble app)
local function beep(name, force)
  if not force and (not cfg.beeps or sim.isReplayActive) then return end
  if sounds[name] then sounds[name]:dispose() end
  local ok, e = pcall(ac.AudioEvent.fromFile, { filename = name .. '.wav', use3D = false, loop = false }, false)
  if not ok or not e then ac.warn('F1 DRS Rules: cannot play ' .. name .. '.wav'); return end
  e.cameraInteriorMultiplier, e.cameraExteriorMultiplier, e.cameraTrackMultiplier = 1, 1, 1
  e.volume = cfg.beepVolume
  e:resume()
  sounds[name] = e
end

local function inRange(pos, s, e)
  if s <= e then return pos >= s and pos <= e end
  return pos >= s or pos <= e  -- zone wraps over the start/finish line
end

local function zoneAt(pos)
  for i, z in ipairs(zones) do
    if z.wholeLap or inRange(pos, (z.start - ZONE_LEAD_IN) % 1, z.finish) then return i end
  end
  return nil
end

local function setDisabled(carIndex, disabled)
  if applied[carIndex] ~= disabled then
    applied[carIndex] = disabled
    if physicsOk then physics.allowCarDRS(carIndex, disabled) end
  end
end

local function releaseAll()
  for i = 0, sim.carsCount - 1 do setDisabled(i, false) end
end

local function resetState()
  lastCross, pending, verdict, prevZone = {}, {}, {}, {}
  for i = 1, #zones do lastCross[i] = {} end
  for i = 0, sim.carsCount - 1 do verdict[i] = {} end
end

local function onDetection(carIndex, zoneIndex, timeMs)
  lastCross[zoneIndex][carIndex] = timeMs
  local car = ac.getCar(carIndex)
  pending[#pending + 1] = { car = carIndex, zone = zoneIndex, time = timeMs, lapCount = car and car.lapCount or 0 }
end

local function loadZones()
  zones = {}
  local ini = ac.INIConfig.trackData('drs_zones.ini')
  for _, section in ini:iterate('ZONE') do
    local d, s, e = ini:get(section, 'DETECTION', -1), ini:get(section, 'START', -1), ini:get(section, 'END', -1)
    if d >= 0 and s >= 0 and e >= 0 then
      zones[#zones + 1] = { detection = d, start = s, finish = e }
    end
  end
  if #zones > 0 then
    zonesSource = string.format('%d zone(s) from drs_zones.ini', #zones)
  else
    zones[1] = { detection = 0.0005, start = 0, finish = 1, wholeLap = true }
    zonesSource = 'no drs_zones.ini: using start/finish line, whole lap'
  end
  for i, z in ipairs(zones) do
    crossHandles[i] = ac.onTrackPointCrossed(-1, z.detection, function (carIndex, timeMs)
      onDetection(carIndex, i, timeMs)
    end)
  end
end

local function judge(p)
  -- Car ahead = whichever other car crossed this detection point most recently before us
  local ahead, aheadTime = nil, -math.huge
  for other, t in pairs(lastCross[p.zone]) do
    if other ~= p.car and t <= p.time and t > aheadTime then ahead, aheadTime = other, t end
  end
  local gap = ahead and (p.time - aheadTime) / 1000 or math.huge
  local lap = p.lapCount + 1
  local v = { ok = lap >= cfg.enableLap and gap <= cfg.gap, gap = gap, lap = lap }
  verdict[p.car] = verdict[p.car] or {}
  verdict[p.car][p.zone] = v

  if v.ok and p.car == 0 then beep('drs_armed') end

  if cfg.messages and p.car == 0 then
    local where = zones[p.zone].wholeLap and 'start/finish line' or string.format('detection %d', p.zone)
    local gapText = gap < math.huge and string.format('%.2f s', gap) or 'no car ahead'
    if v.ok then
      ac.setMessage('DRS enabled', string.format('%s to car ahead at %s', gapText, where), nil, 3)
    elseif lap < cfg.enableLap then
      ac.setMessage('DRS disabled', string.format('Not available until lap %d', cfg.enableLap), nil, 3)
    else
      ac.setMessage('DRS disabled', string.format('%s to car ahead at %s (need %.1f s)', gapText, where, cfg.gap), nil, 3)
    end
  end
end

local function rulesApply()
  return cfg.enabled and physicsOk and not sim.isOnlineRace
    and (not cfg.raceOnly or sim.raceSessionType == ac.SessionType.Race)
end

if physicsOk then
  loadZones()
  resetState()
else
  ac.warn('F1 DRS Rules: physics API is not available in this session, rules cannot be enforced')
end

ac.onSessionStart(function ()
  resetState()
  applied = {}
  releaseAll()
end)

local wasActive = false
local playerDrsWasOpen = false

function script.update(dt)
  if not physicsOk or sim.isReplayActive then return end

  local player = ac.getCar(0)
  local playerDrsOpen = player ~= nil and player.drsActive
  if playerDrsOpen and not playerDrsWasOpen then beep('drs_open') end
  playerDrsWasOpen = playerDrsOpen

  local active = rulesApply()
  if not active then
    if wasActive then releaseAll() end
    wasActive = false
    pending = {}
    return
  end
  wasActive = true

  -- Judge crossings once later-reporting cars ahead have had time to register
  if #pending > 0 then
    local keep = {}
    for _, p in ipairs(pending) do
      p.frames = (p.frames or 0) + 1
      -- frame count is a fallback in case crossing times ever use a different clock than sim.time
      if sim.time - p.time >= DETECTION_SETTLE_MS or p.frames > 30 then judge(p) else keep[#keep + 1] = p end
    end
    pending = keep
  end

  for i = 0, sim.carsCount - 1 do
    local car = ac.getCar(i)
    if car then
      local v = verdict[i] or {}
      verdict[i] = v
      local z = zoneAt(car.splinePosition)
      local pz = prevZone[i]
      if pz and pz ~= z then v[pz] = nil end  -- zone pass over: that verdict is used up
      if car.isInPitlane and z then v[z] = nil end
      prevZone[i] = z or false

      local allowed = z ~= nil and v[z] ~= nil and v[z].ok and car.lapCount + 1 >= cfg.enableLap
      setDisabled(i, not allowed)
    end
  end
end

local colorOk, colorNo, colorDim = rgbm(0.3, 1, 0.4, 1), rgbm(1, 0.35, 0.3, 1), rgbm(1, 1, 1, 0.55)

function windowMain(dt)
  if not physicsOk then
    ui.textColored('Physics API not available in this session,\nso DRS rules cannot be enforced.', colorNo)
    ui.textColored('(Online races never allow it; offline it\nshould be available.)', colorDim)
    return
  end

  if ui.checkbox('Enforce F1 DRS rules', cfg.enabled) then cfg.enabled = not cfg.enabled end
  if ui.checkbox('Race sessions only', cfg.raceOnly) then cfg.raceOnly = not cfg.raceOnly end
  if ui.checkbox('Messages at detection points', cfg.messages) then cfg.messages = not cfg.messages end
  local g, gChanged = ui.slider('##gap', cfg.gap, 0.2, 3, 'Gap: %.1f s')
  if gChanged then cfg.gap = g end
  local l, lChanged = ui.slider('##lap', cfg.enableLap, 1, 5, 'DRS from lap %.0f', true)
  if lChanged then cfg.enableLap = l end
  if ui.checkbox('Beeps (DRS earned / DRS opened)', cfg.beeps) then cfg.beeps = not cfg.beeps end
  if cfg.beeps then
    local vol, volChanged = ui.slider('##beepVolume', cfg.beepVolume * 100, 0, 150, 'Beep volume: %.0f%%')
    if volChanged then cfg.beepVolume = vol / 100 end
    if ui.button('Test earned') then beep('drs_armed', true) end
    ui.sameLine()
    if ui.button('Test opened') then beep('drs_open', true) end
  end

  ui.separator()
  ui.textColored(zonesSource, colorDim)
  ui.text(rulesApply() and 'Rules active' or 'Rules inactive (normal AC DRS)')

  local player = ac.getCar(0)
  if player and rulesApply() then
    ui.text(string.format('You: lap %d   DRS %s', player.lapCount + 1,
      player.drsActive and 'OPEN' or (player.drsAvailable and 'available' or 'locked')))
    local v = verdict[0] or {}
    for i, z in ipairs(zones) do
      local r = v[i]
      local label = z.wholeLap and 'Lap' or string.format('Zone %d', i)
      if not r then
        ui.textColored(string.format('  %s: no detection yet', label), colorDim)
      else
        local gapText = r.gap < math.huge and string.format('%.2f s', r.gap) or '-'
        ui.textColored(string.format('  %s: %s (gap %s, lap %d)', label, r.ok and 'ENABLED' or 'locked', gapText, r.lap),
          r.ok and colorOk or colorNo)
      end
    end

    local unlocked = 0
    for i = 0, sim.carsCount - 1 do if applied[i] == false then unlocked = unlocked + 1 end end
    ui.textColored(string.format('Cars with DRS unlocked right now: %d / %d', unlocked, sim.carsCount), colorDim)
  end
end
