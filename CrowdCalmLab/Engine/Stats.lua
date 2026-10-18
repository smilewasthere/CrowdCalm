-- Engine/Stats.lua — preallocated sample ring + snapshot math for meter and
-- lab segments (brief sections 5.1, 5.3). No allocation inside Snapshot for
-- the hot path beyond slot writes into a reused sort buffer.
local ADDON_NAME, ns = ...

local Util = ns.util
local Stats = {}
ns.stats = Stats

local SAMPLE_CAP = 320 -- 80 s at 4 Hz; lab segments are far shorter
local ring = Util.NewRing(SAMPLE_CAP)

local sortBuf = {}
local sortN = 0

-- current segment long-frame accumulators (profiler deltas)
local seg = { d50 = 0, d100 = 0, d500 = 0, d1000 = 0 }

-- last snapshot, reused as the return value (read-only for callers)
local last = {
  count = 0,
  fps = 0,
  avg = 0,
  median = 0,
  p5 = 0,
  min = 0,
  d50 = 0,
  d100 = 0,
  d500 = 0,
  d1000 = 0,
}

function Stats.Reset()
  ring:Clear()
  seg.d50 = 0
  seg.d100 = 0
  seg.d500 = 0
  seg.d1000 = 0
end

function Stats.Push(fps)
  if type(fps) == "number" then
    ring:Push(fps)
  end
end

function Stats.AddLong(d50, d100, d500, d1000)
  if d50 and d50 > 0 then
    seg.d50 = seg.d50 + d50
  end
  if d100 and d100 > 0 then
    seg.d100 = seg.d100 + d100
  end
  if d500 and d500 > 0 then
    seg.d500 = seg.d500 + d500
  end
  if d1000 and d1000 > 0 then
    seg.d1000 = seg.d1000 + d1000
  end
end

function Stats.Count()
  return ring:Count()
end

function Stats.Snapshot()
  local n = ring:Count()
  last.count = n
  last.d50 = seg.d50
  last.d100 = seg.d100
  last.d500 = seg.d500
  last.d1000 = seg.d1000
  if n == 0 then
    last.fps = 0
    last.avg = 0
    last.median = 0
    last.p5 = 0
    last.min = 0
    return last
  end
  local sum = 0
  for i = 1, n do
    local v = ring:Get(i)
    sortBuf[i] = v
    sum = sum + v
  end
  if sortN > n then
    for i = n + 1, sortN do
      sortBuf[i] = nil
    end
  end
  sortN = n
  table.sort(sortBuf)
  last.fps = ring:Get(n)
  last.avg = sum / n
  last.median = sortBuf[math.floor((n + 1) / 2)]
  local p5i = math.floor(n * 0.05)
  if p5i < 1 then
    p5i = 1
  end
  last.p5 = sortBuf[p5i]
  last.min = sortBuf[1]
  return last
end

-- A1 vs A2 diverged by more than 10 percent -> "Noisy, rerun" (section 5.3).
function Stats.noisy(a1, a2)
  local m = (a1 + a2) / 2
  if m <= 0 then
    return true
  end
  return (math.abs(a1 - a2) / m) > 0.10
end

function Stats.confidence(mode, noisyFlag)
  if noisyFlag then
    return "Low"
  end
  if mode == "thorough" then
    return "High"
  end
  return "Medium"
end
