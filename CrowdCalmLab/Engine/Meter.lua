-- Engine/Meter.lua — 4 Hz sampler (brief section 5.1): FPS via GetFramerate,
-- long-frame deltas via C_AddOnProfiler.GetApplicationMetric (guarded), a
-- 1 Hz sparkline history, and session rates for the Overview gauges.
-- Runs only while Acquire()'d (window open, a test, or the log is on).
local ADDON_NAME, ns = ...

local Util = ns.util
local Meter = {}
ns.meter = Meter

local PROFILER_METRICS = { "CountTimeOver50Ms", "CountTimeOver100Ms", "CountTimeOver500Ms", "CountTimeOver1000Ms" }
local HISTORY_CAP = 320 -- sparkline window (> 300 s at 1 Hz)
local HISTORY_EVERY = 4 -- every 4th 0.25 s tick ~= 1 Hz

Meter.totals = { 0, 0, 0, 0 } -- session-long profiler counters (delta-accumulated)
Meter.sessionStart = nil
Meter.history = Util.NewRing(HISTORY_CAP) -- fps values, 1 Hz
Meter.spikes = Util.NewRing(HISTORY_CAP) -- 0/1 spike flags aligned with history
Meter.live = { fps = 0, frameMs = 0, d50pm = 0, d100pm = 0, longPerMin = 0 }

local prev = { 0, 0, 0, 0 }
local prevValid = { false, false, false, false }
local scratch = { 0, 0, 0, 0 }
local secAccum = 0
local tickN = 0
local refCount = 0

local function readProfiler()
  if not (ns.compat and ns.compat.features and ns.compat.features.profiler) then
    scratch[1] = 0
    scratch[2] = 0
    scratch[3] = 0
    scratch[4] = 0
    return false
  end
  local any = false
  for i = 1, 4 do
    local ok, v = pcall(C_AddOnProfiler.GetApplicationMetric, PROFILER_METRICS[i])
    if ok and type(v) == "number" then
      any = true
      if not prevValid[i] then
        prev[i] = v
        prevValid[i] = true
        scratch[i] = 0
      else
        local d = v - prev[i]
        if d < 0 then
          d = 0 -- counter reset (reload); ignore the wrap
        end
        prev[i] = v
        scratch[i] = d
      end
    else
      scratch[i] = 0
    end
  end
  return any
end

local function onTick()
  local okProfiler = readProfiler()
  local fps = GetFramerate()
  Meter.live.fps = fps
  if fps > 0 then
    Meter.live.frameMs = 1000 / fps
  else
    Meter.live.frameMs = 0
  end

  ns.stats.Push(fps)
  if okProfiler then
    ns.stats.AddLong(scratch[1], scratch[2], scratch[3], scratch[4])
  end

  -- session rates (counters live for the whole session; rates need >= 5 s)
  local elapsed = 0
  if Meter.sessionStart then
    elapsed = GetTime() - Meter.sessionStart
  end
  if elapsed > 5 then
    local minutes = elapsed / 60
    Meter.live.d50pm = Meter.totals[1] / minutes
    Meter.live.d100pm = Meter.totals[2] / minutes
    Meter.live.longPerMin = (Meter.totals[1] + Meter.totals[2] + Meter.totals[3] + Meter.totals[4]) / minutes
  end

  -- 1 Hz history for the Overview sparkline
  if okProfiler then
    secAccum = secAccum + scratch[2] + scratch[3] + scratch[4]
  end
  tickN = tickN + 1
  if tickN % HISTORY_EVERY == 0 then
    local floorFps = 30
    if ns.db and ns.db.settings and ns.db.settings.lab then
      floorFps = ns.db.settings.lab.fpsStutterFloor or 30
    end
    local spike = 0
    if (fps > 0 and fps < floorFps) or secAccum > 0 then
      spike = 1
    end
    Meter.history:Push(fps)
    Meter.spikes:Push(spike)
    secAccum = 0
  end
end

function Meter.Acquire()
  refCount = refCount + 1
  if refCount == 1 then
    if not Meter.sessionStart then
      Meter.sessionStart = GetTime()
    end
    Util.AcquireTicker("meter", 0.25, onTick)
  end
end

function Meter.Release()
  refCount = refCount - 1
  if refCount <= 0 then
    refCount = 0
    Util.ReleaseTicker("meter")
  end
end

function Meter.IsRunning()
  return refCount > 0
end

function Meter.Totals()
  return Meter.totals[1], Meter.totals[2], Meter.totals[3], Meter.totals[4]
end

function Meter.Snapshot()
  return ns.stats.Snapshot()
end

ns.onLogin(function()
  Meter.sessionStart = GetTime()
end)
