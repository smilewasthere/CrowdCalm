local ADDON_NAME, ns = ...

local Stutter = {}
Stutter.__index = Stutter
ns.Stutter = Stutter

local DEFAULTS = {
  enabled = false,
  thresholdMs = 50,
  minGapMs = 1000,
  maxEntries = 100,
}

function Stutter.new(settings)
  local self = setmetatable({}, Stutter)
  settings = settings or {}
  for key, value in pairs(DEFAULTS) do
    if type(settings[key]) ~= type(value) then
      self[key] = value
    else
      self[key] = settings[key]
    end
  end
  self.entries = {}
  self.lastLogged = nil
  return self
end

function Stutter:ShouldLog(deltaMs, now)
  if not self.enabled then
    return false
  end
  if deltaMs <= self.thresholdMs then
    return false
  end
  if self.lastLogged ~= nil and now - self.lastLogged < self.minGapMs then
    return false
  end
  self.lastLogged = now
  return true
end

function Stutter:Add(entry)
  local entries = self.entries
  entries[#entries + 1] = entry
  while #entries > self.maxEntries do
    table.remove(entries, 1)
  end
end

function Stutter:GetEntries()
  return self.entries
end

function Stutter:SetEnabled(enabled, now)
  self.enabled = enabled and true or false
  if self.enabled then
    self.lastLogged = nil
  end
end
