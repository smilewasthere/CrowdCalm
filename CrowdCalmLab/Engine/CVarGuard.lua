-- Engine/CVarGuard.lua — the safety engine (brief sections 4 and 5.5).
-- Implements every hard rule: combat checks before test and before each
-- apply, snapshot before change, read-back after set, CVAR_UPDATE ownership
-- handoff, restore on end/cancel/combat/logout, idle baseline for crash
-- recovery, and scope badges. Never invents CVar names; never touches the
-- deny-list; never tests inside instances (LabRunner checks that too).
local ADDON_NAME, ns = ...

local Guard = {}
ns.cvarGuard = Guard

-- CVars that are never touched, whatever happens (section 4.7).
Guard.denyList = {
  graphicsQuality = true,
  renderScale = true,
}

local held = nil -- { names = { key -> { original, applied, info, released } } }
local queued = nil -- { key -> original } restores waiting for combat to end
local restoringSelf = false
Guard.restorePromptHandler = nil -- set by UI to show the login prompt

-- ------------------------------------------------------------ reading ----

local function valuesEqual(a, b)
  local na = tonumber(a)
  local nb = tonumber(b)
  if na and nb then
    return math.abs(na - nb) < 0.0005
  end
  return tostring(a or "") == tostring(b or "")
end

-- GetCVarInfo's return order is unverified (see docs/VERIFY.md #10). Capture
-- defensively: first return is the value; any boolean in the later slots is
-- interpreted in order as isSecure, storedAccount, storedCharacter. With no
-- booleans at all (or no API), the CVar is treated as SECURE — the
-- conservative direction.
local function interpretInfo(...)
  local n = select("#", ...)
  local raw = { ... }
  local bools = {}
  local boolCount = 0
  for i = 2, n do
    if type(raw[i]) == "boolean" then
      boolCount = boolCount + 1
      bools[boolCount] = raw[i]
    end
  end
  local isSecure
  local interpreted
  if n <= 1 then
    isSecure = true
    interpreted = false
  elseif boolCount == 0 then
    isSecure = true
    interpreted = false
  else
    isSecure = bools[1] == true
    interpreted = true
  end
  return {
    value = raw[1],
    default = raw[2],
    isSecure = isSecure,
    storedAccount = bools[2] == true,
    storedCharacter = bools[3] == true,
    interpreted = interpreted,
    rawN = n,
  }
end

function Guard.Read(name)
  if Guard.denyList[name] then
    return nil
  end
  if not (ns.compat and ns.compat.features and ns.compat.features.cvar) then
    return nil
  end
  local ok, value = pcall(C_CVar.GetCVar, name)
  if ok and value ~= nil then
    return tostring(value)
  end
  return nil
end

function Guard.Info(name)
  if Guard.denyList[name] or not (ns.compat and ns.compat.features and ns.compat.features.cvarInfo) then
    return nil
  end
  local ok, a, b, c, d, e, f = pcall(C_CVar.GetCVarInfo, name)
  if not ok then
    return nil
  end
  local info = interpretInfo(a, b, c, d, e, f)
  info.name = name
  -- prefer the live read for the value; GetCVarInfo's first return may differ in type
  local live = Guard.Read(name)
  if live ~= nil then
    info.value = live
  end
  return info
end

-- scope badge (section 4.10): "server", "local" or "unknown"
function Guard.ScopeOf(info)
  if not info then
    return "unknown"
  end
  if not info.interpreted then
    return "unknown"
  end
  if info.storedAccount or info.storedCharacter then
    return "server"
  end
  return "local"
end

-- ------------------------------------------------------------- holding ----

function Guard.IsHolding()
  return held ~= nil
end

function Guard.HeldCount()
  if not held then
    return 0
  end
  local n = 0
  for _ in pairs(held.names) do
    n = n + 1
  end
  return n
end

function Guard.HasBaseline()
  return type(ns.db) == "table"
    and type(ns.db.baseline) == "table"
    and type(ns.db.baseline.values) == "table"
    and next(ns.db.baseline.values) ~= nil
end

local function ensureHeld()
  if not held then
    held = { names = {} }
  end
  return held
end

-- Snapshot the current value + info for one CVar BEFORE any change.
function Guard.Snapshot(name)
  if Guard.denyList[name] then
    return nil, "denied"
  end
  local value = Guard.Read(name)
  if value == nil then
    return nil, "unreadable"
  end
  local info = Guard.Info(name)
  local entry = ensureHeld().names[name]
  if not entry then
    entry = {}
    held.names[name] = entry
  end
  entry.original = value
  entry.info = info
  entry.applied = nil
  entry.released = false
  return entry
end

local function setRaw(name, value)
  restoringSelf = true
  local okSet, setOk = pcall(C_CVar.SetCVar, name, value)
  restoringSelf = false
  if not okSet then
    return false, setOk
  end
  -- SetCVar's return contract is unverified (VERIFY #19); trust the read-back.
  local readBack = Guard.Read(name)
  if readBack == nil then
    return false, "readback-unavailable"
  end
  if not valuesEqual(readBack, value) then
    return false, "mismatch:" .. tostring(readBack)
  end
  return true, readBack
end

-- Apply a new value to a previously snapshotted CVar (rule 1 + 5).
function Guard.Apply(name, value)
  if Guard.denyList[name] then
    return false, "denied"
  end
  if not (ns.compat and ns.compat.features and ns.compat.features.cvar) then
    return false, "no-cvar-api"
  end
  if InCombatLockdown() then
    return false, "combat"
  end
  local entry = held and held.names[name]
  if not entry then
    local snap, err = Guard.Snapshot(name)
    if not snap then
      return false, err
    end
    entry = held.names[name]
  end
  if entry.released then
    return false, "released"
  end
  -- secure CVars: still fine out of combat via SetCVar; re-read info once
  -- in case the client changed the flags.
  -- Mark the applied value BEFORE SetCVar so a synchronously delivered
  -- CVAR_UPDATE for our own change is recognized as ours.
  entry.applied = tostring(value)
  local ok, readBack = setRaw(name, value)
  if not ok then
    entry.applied = nil
    -- rule 5: restore the original and mark not testable
    local restored = false
    if entry.original ~= nil then
      restored = select(1, setRaw(name, entry.original))
    end
    return false, tostring(readBack), restored
  end
  if ns.db then
    if not ns.db.lastApplied then
      ns.db.lastApplied = {}
    end
    ns.db.lastApplied[name] = entry.applied
  end
  return true, readBack
end

-- Restore one CVar (queued automatically while in combat).
function Guard.Restore(name)
  local entry = held and held.names[name]
  if not entry or entry.released then
    return true
  end
  if InCombatLockdown() then
    queued = queued or {}
    queued[name] = entry.original
    -- the restore is committed: it fires at PLAYER_REGEN_ENABLED. Mark the
    -- entry released NOW so RestoreAll/IsHolding reflect reality and the
    -- regen handler can drop it (review I1).
    entry.applied = nil
    entry.released = true
    if ns.db and ns.db.lastApplied then
      ns.db.lastApplied[name] = nil
    end
    return false, "queued"
  end
  restoringSelf = true
  local ok = pcall(C_CVar.SetCVar, name, entry.original)
  restoringSelf = false
  if ok then
    entry.applied = nil
    entry.released = true
    if ns.db and ns.db.lastApplied then
      ns.db.lastApplied[name] = nil
    end
  end
  return ok
end

function Guard.RestoreAll()
  if not held then
    return true
  end
  local allOk = true
  for name in pairs(held.names) do
    local ok = Guard.Restore(name)
    if not ok then
      allOk = false
    end
  end
  if allOk then
    held = nil
    Guard.CaptureBaselineIfIdle()
  end
  return allOk
end

-- Called by LabRunner when a test ends (success, cancel, abort).
function Guard.EndTest()
  local ok = Guard.RestoreAll()
  return ok
end

function Guard.WasForeign(name)
  local entry = held and held.names[name]
  return entry ~= nil and entry.released == true and entry.foreign == true
end

-- ------------------------------------------------- CVAR_UPDATE ownership ----
-- Rule 4: while we hold a CVar, any change we did not make belongs to the
-- owner or another addon. Release ours; never overwrite theirs.

ns.events.Register("CVAR_UPDATE", function(changedName, value)
  if restoringSelf or not held or not changedName then
    return
  end
  local entry = held.names[changedName]
  if not entry or entry.released then
    return
  end
  if valuesEqual(value, entry.applied) or valuesEqual(value, entry.original) then
    return
  end
  -- someone else changed it: their value wins
  entry.original = tostring(value)
  entry.applied = nil
  entry.released = true
  entry.foreign = true
  if ns.db and ns.db.lastApplied then
    ns.db.lastApplied[changedName] = nil
  end
  if Guard.onForeignChange then
    Guard.onForeignChange(changedName)
  end
end)

-- ------------------------------------------------------ combat handling ----

ns.events.Register("PLAYER_REGEN_DISABLED", function()
  -- rule 1: combat started mid-test -> stop and restore (queue if needed).
  -- onCombatAbort fires unconditionally so a run caught during its first
  -- A1 sample (nothing held yet) is still stopped and reported (review I2).
  if held then
    for name in pairs(held.names) do
      Guard.Restore(name) -- queues when the client refuses in combat
    end
  end
  if Guard.onCombatAbort then
    Guard.onCombatAbort()
  end
end)

ns.events.Register("PLAYER_REGEN_ENABLED", function()
  if not queued then
    return
  end
  local names = {}
  local n = 0
  for name, original in pairs(queued) do
    n = n + 1
    names[n] = name
    restoringSelf = true
    pcall(C_CVar.SetCVar, name, original)
    restoringSelf = false
    if ns.db and ns.db.lastApplied then
      ns.db.lastApplied[name] = nil
    end
  end
  for i = 1, n do
    queued[names[i]] = nil
  end
  if next(queued) == nil then
    queued = nil
  end
  -- release the held entries that were queued
  if held then
    for name in pairs(held.names) do
      if held.names[name].released then
        held.names[name] = nil
      end
    end
    if next(held.names) == nil then
      held = nil
    end
  end
  Guard.CaptureBaselineIfIdle()
end)

-- ------------------------------------------------------- baseline (9) ------

function Guard.CaptureBaselineIfIdle()
  if held then
    return false
  end
  if not ns.db then
    return false
  end
  local values = {}
  local any = false
  for _, cand in ipairs(ns.settings.candidates) do
    if cand.key and not Guard.denyList[cand.key] then
      local v = Guard.Read(cand.key)
      if v ~= nil then
        values[cand.key] = v
        any = true
      end
    end
  end
  if any then
    ns.db.baseline = { values = values, t = GetTime() }
  end
  return any
end

-- Returns the mismatch list without prompting (used by the footer button).
function Guard.Mismatches()
  if not ns.db or type(ns.db.baseline) ~= "table" or type(ns.db.baseline.values) ~= "table" then
    return nil
  end
  local mismatches = {}
  local n = 0
  for key, baselineValue in pairs(ns.db.baseline.values) do
    local current = Guard.Read(key)
    if current ~= nil and not valuesEqual(current, baselineValue) then
      n = n + 1
      mismatches[n] = {
        key = key,
        baseline = tostring(baselineValue),
        current = tostring(current),
        testLike = (ns.db.lastApplied and ns.db.lastApplied[key] ~= nil)
          and valuesEqual(current, ns.db.lastApplied[key]) or false,
      }
    end
  end
  if n == 0 then
    return nil
  end
  return mismatches
end

-- At login, compare live values to the baseline saved at the last clean
-- logout. If a mismatch looks like our own test value (db.lastApplied),
-- offer "Restore my settings" — never auto-overwrite (section 4.9).
function Guard.CompareBaselineOnLogin()
  local mismatches = Guard.Mismatches()
  if not mismatches then
    Guard.CaptureBaselineIfIdle()
    return nil
  end
  local n = #mismatches
  local testLike = 0
  for i = 1, n do
    if mismatches[i].testLike then
      testLike = testLike + 1
    end
  end
  local payload = { all = mismatches, count = n, testLike = testLike }
  if testLike > 0 and Guard.restorePromptHandler then
    Guard.restorePromptHandler(payload)
  elseif n > 0 then
    ns.util.LogInfo(n .. " setting(s) differ from your saved baseline (not from a lab test). Open the Lab to inspect.")
  end
  return payload
end

-- Restore a list of {key=..., baseline=...} rows from the prompt (or any
-- subset the owner confirms).
function Guard.RestoreFromBaseline(pairsList)
  if InCombatLockdown() then
    return false, "combat"
  end
  local okAll = true
  for _, row in ipairs(pairsList) do
    if row.key and row.baseline ~= nil then
      local ok = pcall(C_CVar.SetCVar, row.key, row.baseline)
      if not ok then
        okAll = false
      else
        if ns.db and ns.db.lastApplied then
          ns.db.lastApplied[row.key] = nil
        end
      end
    end
  end
  Guard.CaptureBaselineIfIdle()
  return okAll
end

-- rule 3: restore on logout, refresh the baseline while idle
ns.events.Register("PLAYER_LOGOUT", function()
  if held then
    for name in pairs(held.names) do
      restoringSelf = true
      pcall(C_CVar.SetCVar, name, held.names[name].original)
      restoringSelf = false
      if ns.db and ns.db.lastApplied then
        ns.db.lastApplied[name] = nil
      end
    end
    held = nil
  end
  Guard.CaptureBaselineIfIdle()
end)

ns.onLogin(function()
  Guard.CompareBaselineOnLogin()
end)
