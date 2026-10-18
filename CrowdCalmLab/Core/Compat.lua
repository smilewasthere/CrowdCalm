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

local version = tostring(a or "?")
local build = tostring(b or "?")
local dateStr = tostring(c or "?")
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

ns.onLogin(function()
  ns.util.LogInfo(Compat.describe())
end)
