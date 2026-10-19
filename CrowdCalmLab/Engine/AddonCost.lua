-- Engine/AddonCost.lua — read-only cost report for every addon (brief
-- section 5.8). CPU comes from C_AddOnProfiler.GetAddOnMetric (cannot query
-- Blizzard addons, does not cover mouse-click handlers). Memory is read only
-- on an explicit, blocking, never-in-combat scan. The addon never changes
-- other addons' code; "disable on next reload" is optional, feature-detected
-- and confirmed by the UI.
local ADDON_NAME, ns = ...

local AddonCost = {}
ns.addonCost = AddonCost

local CPU_METRICS = { "RecentAverageTime", "PeakTime", "CountTimeOver1Ms", "CountTimeOver5Ms" }

-- row pool reused across scans (display data; rows are overwritten in place)
local rows = {}
local rowCount = 0
local scannedAt = nil
local memoryScannedAt = nil
local memorySupported = nil

local function ensureRow(i)
  local row = rows[i]
  if not row then
    row = {
      name = "",
      title = "",
      cpuRecent = nil,
      cpuPeak = nil,
      over1 = nil,
      over5 = nil,
      memory = nil,
      queryable = false,
      isSelf = false,
    }
    rows[i] = row
  end
  return row
end

local function addonNames()
  local out = {}
  local n = 0
  local num = (ns.compat and ns.compat.GetNumAddOns and ns.compat.GetNumAddOns()) or 0
  if type(num) ~= "number" or num <= 0 then
    return out
  end
  for i = 1, num do
    local name, title = ns.compat and ns.compat.GetAddOnInfo and ns.compat.GetAddOnInfo(i)
    if name then
      n = n + 1
      out[n] = { idx = i, name = name, title = (type(title) == "string" and title) or name }
    end
  end
  return out
end

-- pre.5: adaptive C_AddOnProfiler reader. The GetAddOnMetric signature
-- (addon name vs addon index) is not verifiable from the repo, so both
-- forms are tried and the working one is cached (docs/VERIFY.md).
local metricForm = nil -- nil = unknown, "name", "index", false = no API
local profilerSetupDone = false

local function setupProfilerOnce()
  if profilerSetupDone then
    return
  end
  profilerSetupDone = true
  if C_AddOnProfiler and C_AddOnProfiler.SetupProfiler then
    pcall(C_AddOnProfiler.SetupProfiler)
  end
end

local function readMetric(idx, name, metric)
  if metricForm == false then
    return nil
  end
  setupProfilerOnce()
  if metricForm ~= "index" then
    local ok, v = pcall(C_AddOnProfiler.GetAddOnMetric, name, metric)
    if ok and type(v) == "number" then
      metricForm = "name"
      return v
    end
  end
  if metricForm ~= "name" then
    local ok, v = pcall(C_AddOnProfiler.GetAddOnMetric, idx, metric)
    if ok and type(v) == "number" then
      metricForm = "index"
      return v
    end
  end
  if metricForm == nil then
    metricForm = false -- both forms failed; stop probing every addon
  end
  return nil
end

function AddonCost.Refresh()
  if InCombatLockdown() then
    return false, "combat"
  end
  local list = addonNames()
  local canQuery = ns.compat and ns.compat.features and ns.compat.features.addOnMetric
  rowCount = 0
  for i = 1, #list do
    local entry = list[i]
    local row = ensureRow(i)
    rowCount = i
    row.idx = entry.idx
    row.name = entry.name
    row.title = entry.title
    row.isSelf = (entry.name == ADDON_NAME)
    row.queryable = false
    row.cpuRecent = nil
    row.cpuPeak = nil
    row.over1 = nil
    row.over5 = nil
    if canQuery then
      local vR = readMetric(entry.idx, entry.name, CPU_METRICS[1])
      if vR ~= nil then
        row.queryable = true
        row.cpuRecent = vR
        row.cpuPeak = readMetric(entry.idx, entry.name, CPU_METRICS[2])
        row.over1 = readMetric(entry.idx, entry.name, CPU_METRICS[3])
        row.over5 = readMetric(entry.idx, entry.name, CPU_METRICS[4])
      end
    end
  end
  scannedAt = GetTime()
  AddonCost.SortBy("cpu")
  return true
end

-- in-place sort by CPU (unqueryable rows sink to the bottom)
function AddonCost.SortBy(field)
  local list = {}
  for i = 1, rowCount do
    list[i] = rows[i]
  end
  local function key(row)
    if field == "memory" then
      return row.memory or -1
    end
    if field == "name" then
      return nil
    end
    return row.cpuRecent or -1
  end
  table.sort(list, function(a, b)
    if field == "name" then
      return a.title:lower() < b.title:lower()
    end
    local ka, kb = key(a), key(b)
    if ka == kb then
      return a.title:lower() < b.title:lower()
    end
    return ka > kb
  end)
  for i = 1, rowCount do
    rows[i] = list[i]
  end
end

-- Blocking memory read; explicit button only (section 5.8).
function AddonCost.ScanMemory()
  if InCombatLockdown() then
    return false, "combat"
  end
  local features = ns.compat and ns.compat.features
  if not (features and features.memory) then
    memorySupported = false
    return false, "unsupported"
  end
  memorySupported = true
  local okUpdate, updateErr
  if C_AddOns and C_AddOns.UpdateAddOnMemoryUsage then
    okUpdate, updateErr = pcall(C_AddOns.UpdateAddOnMemoryUsage)
  else
    okUpdate, updateErr = pcall(UpdateAddOnMemoryUsage)
  end
  if not okUpdate then
    return false, tostring(updateErr)
  end
  for i = 1, rowCount do
    local row = rows[i]
    local ok, mb
    if C_AddOns and C_AddOns.GetAddOnMemoryUsage then
      ok, mb = pcall(C_AddOns.GetAddOnMemoryUsage, row.name)
      if not (ok and type(mb) == "number") and row.idx then
        -- some builds take the addon index instead of the name
        ok, mb = pcall(C_AddOns.GetAddOnMemoryUsage, row.idx)
      end
    else
      ok, mb = pcall(GetAddOnMemoryUsage, row.name)
    end
    if ok and type(mb) == "number" then
      row.memory = mb
    else
      row.memory = nil
    end
  end
  memoryScannedAt = GetTime()
  return true
end

function AddonCost.CanDisable(name)
  if not (ns.compat and ns.compat.features and ns.compat.features.disableAddOn) then
    return false
  end
  if name == ADDON_NAME then
    return false
  end
  return true
end

function AddonCost.DisableOnReload(name)
  if not AddonCost.CanDisable(name) then
    return false, "unsupported"
  end
  if InCombatLockdown() then
    return false, "combat"
  end
  local ok, err = pcall(C_AddOns.DisableAddOn, name)
  if not ok then
    return false, tostring(err)
  end
  return true
end

function AddonCost.Rows()
  return rows, rowCount
end

function AddonCost.ScannedAt()
  return scannedAt
end

function AddonCost.MemoryScannedAt()
  return memoryScannedAt
end

function AddonCost.MemorySupported()
  if memorySupported == nil then
    local features = ns.compat and ns.compat.features
    memorySupported = (features and features.memory) or false
  end
  return memorySupported
end
