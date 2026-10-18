local ADDON_NAME, ns = ...

local Crowd = {}
Crowd.__index = Crowd

ns.Crowd = Crowd

local DEFAULTS = { high = 15, low = 10, enterDelay = 3, exitDelay = 5 }

function ns.Crowd.new(settings)
  local self = setmetatable({}, Crowd)
  settings = settings or {}
  for key, value in pairs(DEFAULTS) do
    self[key] = settings[key] or value
  end
  self.mode = "normal"
  self.pendingEnter = nil
  self.pendingExit = nil
  return self
end

function Crowd:GetMode()
  return self.mode
end

function Crowd:Reset()
  self.mode = "normal"
  self.pendingEnter = nil
  self.pendingExit = nil
end

function Crowd:Update(now, count)
  if self.mode == "normal" then
    if count >= self.high then
      if self.pendingEnter == nil then
        self.pendingEnter = now
      elseif now - self.pendingEnter >= self.enterDelay then
        self.mode = "crowd"
        self.pendingEnter = nil
      end
    else
      self.pendingEnter = nil
    end
  else
    if count <= self.low then
      if self.pendingExit == nil then
        self.pendingExit = now
      elseif now - self.pendingExit >= self.exitDelay then
        self.mode = "normal"
        self.pendingExit = nil
      end
    else
      self.pendingExit = nil
    end
  end
  return self.mode
end
