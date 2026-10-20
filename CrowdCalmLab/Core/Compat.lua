-- Core/Compat.lua — client detection by interface number AND feature checks.
-- Keeps every client branch in one place (brief section 3). Detection is
-- logged once at PLAYER_LOGIN. The exact position of the interface number in
-- GetBuildInfo()'s returns is unverified: see docs/VERIFY.md.
local ADDON_NAME, ns = ...

local Compat = {}
ns.compat = Compat

local function scanInterface(a, b, c, d)
  -- Prefer the 4th return (documented as tocversion on the wiki); fall back to
  -- a scan of all four when it is missing or implausible.
  local ranges = { d, a, b, c }
  for i = 1, 4 do
    local v = tonumber(ranges[i])
    if v and v >= 1000 and v <= 999999 and v == math.floor(v) then
      if i == 1 or v >= 10000 then
        return v, i == 1 and "4th-return" or "scan"
      end
    end
  end
  return nil, "not-found"
end

local ok, a, b, c, d = pcall(GetBuildInfo)
local interface, how
if ok then
  interface, how = scanInterface(a, b, c, d)
else
  interface, how = nil, "GetBuildInfo-failed"
end

local version = ok and tostring(a or "?") or "?"
local build = ok and tostring(b or "?") or "?"
local dateStr = ok and tostring(c or "?") or "?"
local major = tonumber(version:match("^(%d+)"))

Compat.interface = interface or 0
Compat.interfaceSource = how
Compat.version = version
Compat.build = build
Compat.date = dateStr
Compat.isForever = (Compat.interface == 16001) or (major == 1)
Compat.isRetail = not Compat.isForever

if Compat.isForever then
  Compat.chip = "Forever " .. version
elseif Compat.isRetail and (Compat.interface >= 120000) then
  Compat.chip = "Midnight " .. version
else
  Compat.chip = "WoW " .. version
end

-- Feature probes (presence only; every call site still pcalls). Names come
-- from the owner's brief or the Warcraft Wiki; anything assumed is listed in
-- docs/VERIFY.md.
Compat.features = {
  cvar = (C_CVar ~= nil) and (C_CVar.GetCVar ~= nil) and (C_CVar.SetCVar ~= nil),
  cvarInfo = (C_CVar ~= nil) and (C_CVar.GetCVarInfo ~= nil),
  profiler = (C_AddOnProfiler ~= nil) and (C_AddOnProfiler.GetApplicationMetric ~= nil),
  addOnMetric = (C_AddOnProfiler ~= nil) and (C_AddOnProfiler.GetAddOnMetric ~= nil),
  overallMetric = (C_AddOnProfiler ~= nil) and (C_AddOnProfiler.GetOverallMetric ~= nil),
  nameplates = (C_NamePlate ~= nil) and (C_NamePlate.GetNamePlates ~= nil),
  atlasInfo = (C_Texture ~= nil) and (C_Texture.GetAtlasInfo ~= nil),
  memory = ((C_AddOns ~= nil) and (C_AddOns.UpdateAddOnMemoryUsage ~= nil) and (C_AddOns.GetAddOnMemoryUsage ~= nil))
    or ((UpdateAddOnMemoryUsage ~= nil) and (GetAddOnMemoryUsage ~= nil)),
  disableAddOn = (C_AddOns ~= nil) and (C_AddOns.DisableAddOn ~= nil),
}

function Compat.describe()
  local feats = {}
  for name, present in pairs(Compat.features) do
    feats[#feats + 1] = name .. "=" .. (present and "yes" or "no")
  end
  table.sort(feats)
  return Compat.chip
    .. " | interface " .. tostring(Compat.interface)
    .. " (" .. Compat.interfaceSource .. ")"
    .. " | build " .. build
    .. " | " .. table.concat(feats, " ")
end

-- pre.5: the addon-list globals (GetNumAddOns/GetAddOnInfo/...) were removed
-- on modern clients; resolve C_AddOns first with a global fallback so the
-- Addons page works on every supported client. Each resolver pcalls, so an
-- absent function reads as an empty list instead of a load error.
function Compat.GetNumAddOns()
  if C_AddOns and C_AddOns.GetNumAddOns then
    local ok, n = pcall(C_AddOns.GetNumAddOns)
    if ok and type(n) == "number" then
      return n
    end
  end
  if GetNumAddOns then
    local ok, n = pcall(GetNumAddOns)
    if ok and type(n) == "number" then
      return n
    end
  end
  return 0
end

-- returns name, title for index i or nil when unavailable
function Compat.GetAddOnInfo(i)
  if C_AddOns and C_AddOns.GetAddOnInfo then
    local ok, name, title = pcall(C_AddOns.GetAddOnInfo, i)
    if ok and type(name) == "string" and name ~= "" then
      return name, (type(title) == "string" and title) or name
    end
  end
  if GetAddOnInfo then
    local ok, name, title = pcall(GetAddOnInfo, i)
    if ok and type(name) == "string" and name ~= "" then
      return name, (type(title) == "string" and title) or name
    end
  end
  return nil
end

-- pre.7: is this addon enabled right now (for the Addons page's
-- enabled-only list)? Probe order: C_AddOns.IsAddOnEnabled by name, then
-- by index, then the enable-state numerics, then the legacy global. Every
-- path pcalls; when nothing can be determined the answer fails OPEN (true)
-- so the list never silently goes empty on an unfamiliar client
-- (docs/VERIFY.md has the live check).
function Compat.IsAddOnEnabled(name, idx)
  if C_AddOns and C_AddOns.IsAddOnEnabled then
    if type(name) == "string" then
      local ok, v = pcall(C_AddOns.IsAddOnEnabled, name)
      if ok and type(v) == "boolean" then
        return v
      end
    end
    if idx then
      local ok, v = pcall(C_AddOns.IsAddOnEnabled, idx)
      if ok and type(v) == "boolean" then
        return v
      end
    end
  end
  if C_AddOns and C_AddOns.GetAddOnEnableState and type(name) == "string" then
    local ok, v = pcall(C_AddOns.GetAddOnEnableState, name, "player")
    if ok and type(v) == "number" then
      return v ~= 0
    end
  end
  if GetAddOnEnableState and type(name) == "string" then
    local ok, v = pcall(GetAddOnEnableState, name, "player")
    if ok and type(v) == "number" then
      return v ~= 0
    end
  end
  return true
end

ns.onLogin(function()
  ns.util.LogInfo(Compat.describe())
end)
