-- Engine/Context.lua — cheap crowd signals (brief section 5.2): nameplate
-- count (polled, no NAME_PLATE_* events), zone/subzone, resting, group size,
-- instance type; combined into Quiet / Busy / Packed with per-signal
-- reliability for the "Why?" tooltip. Never reads combat data.
local ADDON_NAME, ns = ...

local Context = {}
ns.context = Context

Context.label = "quiet"
Context.updatedAt = 0

-- read-only view of the last poll (strings are cached references)
local cached = {
  nameplates = -1,
  zone = "",
  sub = "",
  resting = false,
  group = 0,
  instanceType = "none",
}

-- signal rows for the Why tooltip (display path: string building is fine)
local signals = {
  { id = "nameplates", label = "Nameplates", value = "--", reliability = "low", note = "crowd_nameplates_off" },
  { id = "zone", label = "Place", value = "--", reliability = "high", note = nil },
  { id = "resting", label = "Resting", value = "--", reliability = "high", note = nil },
  { id = "group", label = "Group", value = "--", reliability = "medium", note = nil },
  { id = "instance", label = "Instance", value = "--", reliability = "high", note = nil },
}
Context.signals = signals

-- thresholds (unverified caps: friendly nameplates historically cap ~40)
local BUSY_AT = 15
local PACKED_AT = 40

local function refresh()
  -- nameplates (count only; no unit tokens are read from the results)
  if ns.compat and ns.compat.features and ns.compat.features.nameplates then
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if ok and type(plates) == "table" then
      cached.nameplates = #plates
    else
      cached.nameplates = -1
    end
  else
    cached.nameplates = -1
  end

  local okz, z = pcall(GetZoneText)
  if okz and type(z) == "string" and z ~= "" then
    cached.zone = z
  end
  local oks, s = pcall(GetSubZoneText)
  if oks and type(s) == "string" then
    cached.sub = s
  end

  local okr, r = pcall(IsResting)
  cached.resting = okr and r or false

  local okg, g = pcall(GetNumGroupMembers)
  cached.group = okg and tonumber(g) or 0

  local oki, _, instType = pcall(GetInstanceInfo)
  cached.instanceType = oki and (instType or "none") or "none"

  local n = cached.nameplates
  if cached.instanceType ~= "none" then
    -- inside instances the plate count is unreliable; stay honest
    if n >= PACKED_AT then
      Context.label = "packed"
    else
      Context.label = "busy"
    end
  elseif n < 0 then
    Context.label = "quiet"
  elseif n >= PACKED_AT then
    Context.label = "packed"
  elseif n >= BUSY_AT then
    Context.label = "busy"
  else
    Context.label = "quiet"
  end
end

function Context.Update(force)
  local now = GetTime()
  if not force and (now - Context.updatedAt) < 0.5 then
    return
  end
  Context.updatedAt = now
  refresh()
end

function Context.Label()
  return Context.label
end

function Context.Zone()
  return cached.zone
end

function Context.SubZone()
  return cached.sub
end

function Context.Snapshot()
  return cached
end

function Context.FillSignals()
  Context.Update(true)
  signals[1].value = cached.nameplates >= 0 and tostring(cached.nameplates) or "unavailable"
  if cached.zone ~= "" then
    if cached.sub ~= "" then
      signals[2].value = cached.zone .. " / " .. cached.sub
    else
      signals[2].value = cached.zone
    end
  else
    signals[2].value = "?"
  end
  signals[3].value = cached.resting and "Resting" or "Not resting"
  signals[4].value = tostring(cached.group)
  if cached.instanceType == "none" then
    signals[5].value = "World"
    signals[5].note = nil
    signals[5].reliability = "high"
  else
    signals[5].value = cached.instanceType
    signals[5].note = "note_raid_cvar"
    signals[5].reliability = "low"
  end
  return signals
end
