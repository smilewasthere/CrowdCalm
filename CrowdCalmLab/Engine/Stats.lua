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

-- pre.5: samples arriving before this timestamp are dropped (the lab's
-- warm-up window: movement/overlay/drag artifacts settle first, only the
-- tail of each phase is measured)
local ignoreUntil = 0

-- pre.5: baselines drifting further than this share of their mean marks the
-- run "Not reliable" (was 10% inside Stats.noisy; now shared so Results can
-- print the actual difference next to the limit)
Stats.UNRELIABLE_PCT = 8

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
  ignoreUntil = 0
end

-- pre.5: start a measured segment, dropping the first ignoreSeconds (the
-- lab runs this right after the settle period; the warm-up tail feeds the
-- ring but is cleared here and ignored for the window length)
function Stats.Begin(ignoreSeconds)
  Stats.Reset()
  local ign = tonumber(ignoreSeconds) or 0
  if ign > 0 then
    ignoreUntil = GetTime() + ign
  end
end

local function ignoring()
  return ignoreUntil > 0 and GetTime() < ignoreUntil
end

function Stats.Push(fps)
  if ignoring() then
    return
  end
  if type(fps) == "number" then
    ring:Push(fps)
  end
end

function Stats.AddLong(d50, d100, d500, d1000)
  if ignoring() then
    return
  end
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

-- Baseline divergence helper (pre.5): largest difference between any two
-- baselines, as a percent of their mean. Consecutive pairs are always
-- compared; with 3+ baselines the entry and exit are compared too (the
-- before/after drift of a whole run). Returns percent >= 0.
function Stats.baselineDivergence(values)
  local n = 0
  if type(values) ~= "table" then
    return 0
  end
  for i = 1, #values do
    if type(values[i]) == "number" then
      n = i
    else
      break
    end
  end
  if n < 2 then
    return 0
  end
  local function pct(x, y)
    local m = (math.abs(x) + math.abs(y)) / 2
    if m <= 0 then
      return 0
    end
    return (math.abs(x - y) / m) * 100
  end
  local worst = 0
  for i = 2, n do
    local p = pct(values[i - 1], values[i])
    if p > worst then
      worst = p
    end
  end
  if n > 2 then
    local p = pct(values[1], values[n])
    if p > worst then
      worst = p
    end
  end
  return worst
end

-- A1 vs A2 diverged beyond the limit -> "Not reliable" (section 5.3; the
-- limit moved from 10% to Stats.UNRELIABLE_PCT in pre.5 and the LabRunner
-- now feeds every baseline pair through Stats.baselineDivergence).
function Stats.noisy(a1, a2)
  local m = (a1 + a2) / 2
  if m <= 0 then
    return true
  end
  return (math.abs(a1 - a2) / m) > (Stats.UNRELIABLE_PCT / 100)
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
