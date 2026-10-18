-- Engine/StutterLog.lua — brief section 5.7: a 1 s ticker compares profiler
-- long-frame counters to the previous sample and writes an entry only when a
-- counter rose or FPS fell under the floor. Preallocated 500-entry ring;
-- counters reset on reload, so negative deltas are skipped.
local ADDON_NAME, ns = ...

local Util = ns.util
local StutterLog = {}
ns.stutterLog = StutterLog

local CAP = 500
local METRICS = { "CountTimeOver50Ms", "CountTimeOver100Ms", "CountTimeOver500Ms", "CountTimeOver1000Ms" }

local ring = nil
local pool = {}
local prev = { 0, 0, 0, 0 }
local prevValid = { false, false, false, false }
local scratch = { 0, 0, 0, 0 }
local enabled = false

local function newEntry()
  return {
    t = 0,
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
    if type(saved) == "table" then
      local e = pool[i]
      e.t = saved.t or 0
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

local function onTick()
  readDeltas()
  local fps = GetFramerate()
  local floorFps = 30
  if ns.db and ns.db.settings and ns.db.settings.lab then
    floorFps = ns.db.settings.lab.fpsStutterFloor or 30
  end
  local lowFps = (fps > 0) and (fps < floorFps)
  local anyRise = scratch[1] > 0 or scratch[2] > 0 or scratch[3] > 0 or scratch[4] > 0
  if not anyRise and not lowFps then
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
  e.fps = fps
  e.d50 = scratch[1]
  e.d100 = scratch[2]
  e.d500 = scratch[3]
  e.d1000 = scratch[4]
  e.runId = (ns.lab and ns.lab.activeRunId) or 0
  e.sev = 1
  if e.d1000 > 0 then
    e.sev = 4
  elseif e.d500 > 0 then
    e.sev = 3
  elseif e.d100 > 0 then
    e.sev = 2
  end
  ring:Push(e)
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

function StutterLog.Save()
  if not ns.db or not ring then
    return
  end
  local out = {}
  local n = ring:Count()
  for i = 1, n do
    out[i] = ring:Get(i)
  end
  ns.db.stutter = out
end

ns.events.Register("PLAYER_LOGOUT", StutterLog.Save)

ns.addInit(function()
  if ns.db and ns.db.settings and ns.db.settings.log and ns.db.settings.log.enabled then
    StutterLog.SetEnabled(true)
  end
end)
