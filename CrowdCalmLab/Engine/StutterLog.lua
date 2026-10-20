-- Engine/StutterLog.lua — brief section 5.7: a 1 s ticker compares profiler
-- long-frame counters to the previous sample. Pre.7 truthfulness rework
-- (owner: "always says there is stutter but sometimes it's not"): an entry
-- is written only for real stutters — a frame >= 100 ms, three or more
-- frames >= 50 ms in the same second, or two consecutive seconds under the
-- FPS floor. Isolated 50-99 ms frames are noise at 60 fps and are ignored.
-- Nothing is logged for 5 s after loading screens and zone changes.
-- Entries store wall-clock time (at) alongside session time (t); saved
-- entries without a wall-clock stamp are dropped because old
-- session-relative stamps read as "current" after a reload.
-- Preallocated 500-entry ring; counters reset on reload, so negative
-- deltas are skipped.
local ADDON_NAME, ns = ...

local Util = ns.util
local StutterLog = {}
ns.stutterLog = StutterLog

local CAP = 500
local SUPPRESS_SECONDS = 5
local METRICS = { "CountTimeOver50Ms", "CountTimeOver100Ms", "CountTimeOver500Ms", "CountTimeOver1000Ms" }

local ring = nil
local pool = {}
local prev = { 0, 0, 0, 0 }
local prevValid = { false, false, false, false }
local scratch = { 0, 0, 0, 0 }
local enabled = false
local lowStreak = 0
local suppressUntil = 0
local windowScratch = {}

local function newEntry()
  return {
    t = 0,
    at = 0,
    fps = 0,
    d50 = 0,
    d100 = 0,
    d500 = 0,
    d1000 = 0,
    zone = "",
    sub = "",
    crowd = "",
    runId = 0,
    sev = 1,
  }
end

local function loadSaved()
  local db = ns.db
  if not db or type(db.stutter) ~= "table" then
    return
  end
  local n = math.min(#db.stutter, CAP)
  for i = 1, n do
    local saved = db.stutter[i]
    if type(saved) == "table" and saved.at then
      local e = pool[ring:Count() + 1]
      if not e then
        break
      end
      e.t = saved.t or 0
      e.at = saved.at
      e.fps = saved.fps or 0
      e.d50 = saved.d50 or 0
      e.d100 = saved.d100 or 0
      e.d500 = saved.d500 or 0
      e.d1000 = saved.d1000 or 0
      e.zone = saved.zone or ""
      e.sub = saved.sub or ""
      e.crowd = saved.crowd or ""
      e.runId = saved.runId or 0
      e.sev = saved.sev or 1
      ring:Push(e)
    end
  end
end

local function init()
  ring = Util.NewRing(CAP)
  for i = 1, CAP do
    pool[i] = newEntry()
  end
  loadSaved()
end
ns.addInit(init)

local function nextEntry()
  local count = ring:Count()
  if count >= CAP then
    return ring:Get(1) -- oldest slot; Push will overwrite it
  end
  return pool[count + 1]
end

local function readDeltas()
  if not (ns.compat and ns.compat.features and ns.compat.features.profiler) then
    scratch[1] = 0
    scratch[2] = 0
    scratch[3] = 0
    scratch[4] = 0
    return
  end
  for i = 1, 4 do
    local ok, v = pcall(C_AddOnProfiler.GetApplicationMetric, METRICS[i])
    if ok and type(v) == "number" then
      if not prevValid[i] then
        prev[i] = v
        prevValid[i] = true
        scratch[i] = 0
      else
        local d = v - prev[i]
        if d < 0 then
          d = 0
        end
        prev[i] = v
        scratch[i] = d
      end
    else
      scratch[i] = 0
    end
  end
end

local function severityFor(lowNow)
  if scratch[4] > 0 then
    return 4 -- freeze: a frame at or over 1000 ms
  end
  if scratch[3] > 0 then
    return 3 -- heavy: a frame at or over 500 ms
  end
  if scratch[2] > 0 or lowNow then
    return 2 -- notable: a frame at or over 100 ms, or low-FPS streak
  end
  return 1 -- micro: 3+ frames at or over 50 ms in the same second
end

local function onTick()
  readDeltas()
  local fps = GetFramerate()
  if fps <= 0 then
    return
  end
  local floorFps = 30
  if ns.db and ns.db.settings and ns.db.settings.lab then
    floorFps = ns.db.settings.lab.fpsStutterFloor or 30
  end
  local freeze = scratch[2] > 0 or scratch[3] > 0 or scratch[4] > 0
  local micro = scratch[1] >= 3
  local lowNow = (fps > 0) and (fps < floorFps)
  if lowNow then
    lowStreak = lowStreak + 1
  else
    lowStreak = 0
  end
  local low = lowStreak >= 2
  if not freeze and not micro and not low then
    return
  end
  if GetTime() < suppressUntil then
    return
  end

  local e = nextEntry()
  if ns.context then
    ns.context.Update(true)
    e.zone = ns.context.Zone()
    e.sub = ns.context.SubZone()
    e.crowd = ns.context.Label()
  end
  e.t = GetTime()
  e.at = time()
  e.fps = fps
  e.d50 = scratch[1]
  e.d100 = scratch[2]
  e.d500 = scratch[3]
  e.d1000 = scratch[4]
  e.runId = (ns.lab and ns.lab.activeRunId) or 0
  e.sev = severityFor(low and not freeze and not micro)
  ring:Push(e)
end

function StutterLog.SuppressFromNow()
  suppressUntil = GetTime() + SUPPRESS_SECONDS
  lowStreak = 0
end

function StutterLog.SetEnabled(on)
  if on == enabled then
    return
  end
  enabled = not not on
  if enabled then
    Util.AcquireTicker("stutter", 1.0, onTick)
  else
    Util.ReleaseTicker("stutter")
  end
end

function StutterLog.IsEnabled()
  return enabled
end

function StutterLog.Entries()
  return ring
end

function StutterLog.Count()
  if not ring then
    return 0
  end
  return ring:Count()
end

-- Entries within the last `minutes` minutes, NEWEST first (top of the
-- list is "just now", matching the timeline where now sits at the right);
-- entries without a wall-clock stamp are skipped. Rebuilt on demand by the
-- Stutter page; the ring itself keeps the last CAP (oldest first).
function StutterLog.Window(minutes)
  local out = {}
  if not ring then
    return out
  end
  local horizon = time() - ((minutes or 10) * 60)
  local n = ring:Count()
  for i = n, 1, -1 do
    local e = ring:Get(i)
    if e and e.at and e.at >= horizon then
      out[#out + 1] = e
    end
  end
  return out
end

function StutterLog.Clear()
  if not ring then
    return
  end
  ring:Clear()
  prevValid[1], prevValid[2], prevValid[3], prevValid[4] = false, false, false, false
  lowStreak = 0
end

function StutterLog.Save()
  if not ns.db or not ring then
    return
  end
  local out = {}
  local w = 0
  -- keep ring order (oldest first) so a reload doesn't flip the list
  for i = 1, ring:Count() do
    local e = ring:Get(i)
    if e and e.at and e.at > 0 then
      w = w + 1
      out[w] = e
    end
  end
  ns.db.stutter = out
end

ns.events.Register("PLAYER_LOGOUT", StutterLog.Save)

local function suppressSoon()
  StutterLog.SuppressFromNow()
end
ns.events.Register("PLAYER_ENTERING_WORLD", suppressSoon)
ns.events.Register("ZONE_CHANGED", suppressSoon)
ns.events.Register("ZONE_CHANGED_NEW_AREA", suppressSoon)

ns.addInit(function()
  if ns.db and ns.db.settings and ns.db.settings.log and ns.db.settings.log.enabled then
    StutterLog.SetEnabled(true)
  end
end)
