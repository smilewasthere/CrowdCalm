local ADDON_NAME, ns = ...

local Switch = {}
Switch.__index = Switch
ns.Switch = Switch

local LOADING_DEBOUNCE = 2

function Switch.new(deps, entries)
  local self = setmetatable({}, Switch)
  self.deps = deps
  self.entries = entries or {}
  self.managed = {}
  for _, entry in ipairs(self.entries) do
    self.managed[entry.cvar] = entry
  end
  self.mode = "normal"
  self.desired = "normal"
  self.pendingReason = nil
  self.baselines = {}
  self.applied = {}
  self.lastWrite = {}
  self.loadingUntil = nil
  return self
end

function Switch:GetState()
  return {
    mode = self.mode,
    desired = self.desired,
    pendingReason = self.pendingReason,
    baselines = self.baselines,
    applied = self.applied,
  }
end

function Switch:Request(mode)
  self.desired = mode
end

local function blockedReason(self)
  if self.deps.inCombat() then
    return "combat"
  end
  if self.loadingUntil and self.deps.getTime() < self.loadingUntil then
    return "loading"
  end
  return nil
end

local function applyCrowd(self)
  local failed = false
  for _, entry in ipairs(self.entries) do
    if self.applied[entry.cvar] == nil then
      local baseline = self.deps.getCvar(entry.cvar)
      if self.deps.setCvar(entry.cvar, entry.value) then
        self.applied[entry.cvar] = entry.value
        self.lastWrite[entry.cvar] = entry.value
        if self.baselines[entry.cvar] == nil then
          self.baselines[entry.cvar] = baseline
        end
      else
        failed = true
      end
    end
  end
  if failed then
    return false
  end
  self.mode = "crowd"
  return true
end

local function applyNormal(self)
  local failed = false
  for cvar in pairs(self.applied) do
    local baseline = self.baselines[cvar]
    if self.deps.setCvar(cvar, baseline) then
      self.applied[cvar] = nil
      self.baselines[cvar] = nil
      self.lastWrite[cvar] = baseline
    else
      failed = true
    end
  end
  if failed then
    return false
  end
  self.mode = "normal"
  return true
end

function Switch:TryApply(force)
  if self.desired == "crowd" then
    if self.mode == "crowd" then
      self.pendingReason = nil
      return
    end
    if not force then
      local blocked = blockedReason(self)
      if blocked then
        self.pendingReason = blocked
        return
      end
    end
    if applyCrowd(self) then
      self.pendingReason = nil
    else
      self.pendingReason = "failed"
    end
  else
    if self.mode == "normal" and next(self.applied) == nil then
      self.pendingReason = nil
      return
    end
    if not force then
      local blocked = blockedReason(self)
      if blocked then
        self.pendingReason = blocked
        return
      end
    end
    if applyNormal(self) then
      self.pendingReason = nil
    else
      self.pendingReason = "failed"
    end
  end
end

function Switch:OnCombatEnd()
  self:TryApply()
end

function Switch:OnEnteringWorld()
  self.loadingUntil = self.deps.getTime() + LOADING_DEBOUNCE
end

function Switch:OnCvarChange(name, value)
  if not self.managed[name] then
    return
  end
  if self.lastWrite[name] == value then
    return
  end
  self.baselines[name] = value
end

function Switch:OnLogout()
  self.desired = "normal"
  self.loadingUntil = nil
  self:TryApply(true)
end

function Switch:RestorePersisted(plan)
  plan = plan or {}
  for cvar, value in pairs(plan.restore or {}) do
    if self.deps.setCvar(cvar, value) then
      self.lastWrite[cvar] = value
    end
  end
  for cvar, value in pairs(plan.adopt or {}) do
    self.baselines[cvar] = value
  end
  for cvar in pairs(plan.clear or {}) do
    self.baselines[cvar] = nil
    self.lastWrite[cvar] = nil
  end
  self.applied = {}
  self.mode = "normal"
  self.desired = "normal"
  self.pendingReason = nil
  self.loadingUntil = nil
end
