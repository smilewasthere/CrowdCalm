-- Engine/SelfCheck.lua — the addon's own numbers (brief section 5.9): recent
-- and peak CPU from the profiler, pooled frame counts, stutter log size,
-- active ticker count, memory on demand. Target: well under 0.3 ms average
-- with the window open, near zero with it closed.
local ADDON_NAME, ns = ...

local SelfCheck = {}
ns.selfCheck = SelfCheck

local last = {
  recentMs = nil,
  peakMs = nil,
  pooled = 0,
  pooledFree = 0,
  logSize = 0,
  tickers = 0,
  memoryMB = nil,
  windowOpen = false,
}

function SelfCheck.Snapshot(windowOpen)
  local canQuery = ns.compat and ns.compat.features and ns.compat.features.addOnMetric
  if canQuery then
    local okR, vR = pcall(C_AddOnProfiler.GetAddOnMetric, ADDON_NAME, "RecentAverageTime")
    local okP, vP = pcall(C_AddOnProfiler.GetAddOnMetric, ADDON_NAME, "PeakTime")
    last.recentMs = (okR and type(vR) == "number") and vR or nil
    last.peakMs = (okP and type(vP) == "number") and vP or nil
  end
  last.pooled, last.pooledFree = ns.util.PoolStats()
  last.logSize = ns.stutterLog.Count()
  last.tickers = ns.util.ActiveTickerCount()
  last.windowOpen = windowOpen and true or false
  return last
end

-- blocking; explicit call only
function SelfCheck.ReadMemory()
  local features = ns.compat and ns.compat.features
  if not (features and features.memory) then
    return nil
  end
  local ok, mb
  if C_AddOns and C_AddOns.GetAddOnMemoryUsage then
    ok, mb = pcall(C_AddOns.GetAddOnMemoryUsage, ADDON_NAME)
  else
    ok, mb = pcall(GetAddOnMemoryUsage, ADDON_NAME)
  end
  if ok and type(mb) == "number" then
    last.memoryMB = mb
    return mb
  end
  return nil
end

function SelfCheck.MeetsTarget()
  if last.recentMs == nil then
    return nil
  end
  return last.recentMs < 0.3
end
