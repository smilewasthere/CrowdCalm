local ADDON_NAME, ns = ...

local Core = {}
ns.Core = Core

local EVENTS = {
  "PLAYER_REGEN_ENABLED",
  "PLAYER_ENTERING_WORLD",
  "PLAYER_LOGOUT",
  "CVAR_UPDATE",
}

local SPELL_DENSITY_CVAR = "spellVisualDensityFilterSetting"
local SPELL_DENSITY_RESET_VALUE = "4"
local SPELL_DENSITY_REAPPLY_DELAY = 2
local HINT_RESTING_SECONDS = 30

function Core.DEFAULTS()
  return {
    enabled = true,
    countOnlyPlayers = true,
    high = 15,
    low = 10,
    enterDelay = 3,
    exitDelay = 5,
    categories = ns.Profiles.Defaults(),
    framecapValue = 60,
    stutter = {
      enabled = false,
      thresholdMs = 50,
      minGapMs = 1000,
      maxEntries = 100,
    },
    hintShown = false,
    dev = {
      enabled = false,
      lastReport = "",
      tests = {},
    },
  }
end

function Core._log(message)
  print("CrowdCalm: " .. message)
end

local function fillDefaults(settings)
  for key, value in pairs(Core.DEFAULTS()) do
    if type(value) == "table" then
      local dst = settings[key]
      if type(dst) ~= "table" then
        dst = {}
        settings[key] = dst
      end
      for k, v in pairs(value) do
        if dst[k] == nil then
          dst[k] = v
        end
      end
    elseif settings[key] == nil then
      settings[key] = value
    end
  end
end

local function getInfo(cvar)
  local ok, value, _, _, _, _, secure, readOnly = pcall(C_CVar.GetCVarInfo, cvar)
  if not ok or value == nil then
    return nil
  end
  return { value = value, secure = secure == true, readOnly = readOnly == true }
end

local function buildFindCvar()
  local ok, commands = pcall(C_Console.GetAllCommands)
  if not ok or type(commands) ~= "table" then
    return function()
      return nil
    end
  end
  local byLower = {}
  for _, info in ipairs(commands) do
    if type(info) == "table" and info.command then
      byLower[string.lower(tostring(info.command))] = tostring(info.command)
    end
  end
  return function(key)
    return byLower[string.lower(key)]
  end
end

local function buildEnv()
  return {
    isKnown = function(cvar)
      return getInfo(cvar) ~= nil
    end,
    isSecure = function(cvar)
      local info = getInfo(cvar)
      return info ~= nil and info.secure
    end,
    isReadOnly = function(cvar)
      local info = getInfo(cvar)
      return info ~= nil and info.readOnly
    end,
    findCvar = buildFindCvar(),
  }
end

function Core.CountPlates()
  local plates = C_NamePlate.GetNamePlates()
  local total, players = 0, 0
  for _, plate in ipairs(plates) do
    local token = plate and plate.namePlateUnitToken
    if token then
      total = total + 1
      if UnitIsPlayer(token) then
        players = players + 1
      end
    end
  end
  if Core.sv and Core.sv.settings.countOnlyPlayers then
    return players, players
  end
  return total, players
end

function Core.RebuildSwitch()
  local old = Core.switch
  local oldState = old and old:GetState()

  local entries, skipped = ns.Profiles.Select(Core.sv.settings, buildEnv())
  for cvar, reason in pairs(skipped) do
    if reason ~= "disabled" then
      Core._log("skipping '" .. cvar .. "' (" .. reason .. ")")
    end
  end

  local deps = {
    getTime = function()
      return GetTime()
    end,
    getCvar = function(name)
      return GetCVar(name)
    end,
    setCvar = function(name, value)
      return C_CVar.SetCVar(name, value)
    end,
    inCombat = function()
      return InCombatLockdown()
    end,
    log = function(message)
      Core._log(message)
    end,
  }

  local switch = ns.Switch.new(deps, entries, {
    clobberValues = { [SPELL_DENSITY_CVAR] = SPELL_DENSITY_RESET_VALUE },
  })
  if oldState and (oldState.mode == "crowd" or next(oldState.applied) ~= nil) then
    switch.mode = "normal"
    switch.desired = "normal"
    switch.baselines = oldState.baselines
    switch.applied = oldState.applied
    switch.pendingReason = oldState.pendingReason
    switch.lastWrite = old.lastWrite or {}
  end
  Core.switch = switch
end

function Core._persistState()
  if not Core.switch or not Core.sv then
    return
  end
  local restore = Core.sv.restore
  local state = Core.switch:GetState()
  restore.sessionActive = state.mode == "crowd" or next(state.applied) ~= nil
  wipe(restore.baselines)
  for cvar, value in pairs(state.baselines) do
    restore.baselines[cvar] = value
  end
  wipe(restore.applied)
  for cvar, value in pairs(state.applied) do
    restore.applied[cvar] = value
  end
end

function Core._checkHint(now, playerPlateCount, isResting)
  if Core.sv.settings.hintShown then
    return false
  end
  if not isResting or playerPlateCount > 0 then
    Core.restingSince = nil
    return false
  end
  if Core.restingSince == nil then
    Core.restingSince = now
    return false
  end
  if now - Core.restingSince >= HINT_RESTING_SECONDS then
    Core.sv.settings.hintShown = true
    Core._log("enable friendly nameplates (Esc > Options) so CrowdCalm can detect crowds")
    return true
  end
  return false
end

function Core._scheduleSpellDensityReapply()
  local settings = Core.sv.settings
  if not (settings.categories and settings.categories.spelldensity) then
    return
  end
  local value = Core.switch:GetState().applied[SPELL_DENSITY_CVAR]
  if value == nil then
    return
  end
  C_Timer.After(SPELL_DENSITY_REAPPLY_DELAY, function()
    if Core.crowd and Core.crowd:GetMode() == "crowd" then
      if Core.switch:Reapply(SPELL_DENSITY_CVAR, value) then
        Core._persistState()
      end
    end
  end)
end

local function stutterOnUpdate()
  local now = GetTime()
  local deltaMs = (now - (Core.lastFrameTime or now)) * 1000
  Core.lastFrameTime = now
  if Core.stutter:ShouldLog(deltaMs, now) then
    Core.stutter:Add({
      t = now,
      deltaMs = deltaMs,
      context = {
        zone = GetZoneText(),
        mode = Core.crowd and Core.crowd:GetMode() or "normal",
        sinceSwitch = now - (Core.lastModeChange or now),
      },
    })
  end
end

function Core._syncStutterHook()
  local settings = Core.sv.settings.stutter
  Core.stutter:SetEnabled(settings.enabled, GetTime())
  Core.lastFrameTime = nil
  if not Core.frame then
    return
  end
  if settings.enabled then
    Core.frame:SetScript("OnUpdate", stutterOnUpdate)
  else
    Core.frame:SetScript("OnUpdate", nil)
  end
end

local function effectiveMode()
  if Core.dev and Core.dev.forceCrowd then
    return "crowd"
  end
  if Core.crowd then
    return Core.crowd:GetMode()
  end
  return "normal"
end

function Core._tick(now)
  if not Core.switch or not Core.sv then
    return
  end
  local settings = Core.sv.settings
  local count, players = Core.CountPlates()

  if not settings.enabled then
    local state = Core.switch:GetState()
    if state.mode == "crowd" or next(state.applied) ~= nil then
      Core.switch:Request("normal")
      Core.switch:TryApply()
      Core._persistState()
    end
    if Core.dev then
      Core.dev:OnTick(now)
    end
    return
  end

  Core.crowd:Update(now, count)
  local mode = effectiveMode()
  if mode ~= Core.lastMode then
    Core.lastMode = mode
    Core.lastModeChange = now
  end
  Core.switch:Request(mode)
  Core.switch:TryApply()

  Core.tickCount = Core.tickCount + 1
  if ns.Monitor and Core.tickCount % 5 == 0 then
    ns.Monitor.Push(now, ns.Monitor.GetOwnMB())
  end

  Core._checkHint(now, players, IsResting())
  Core._persistState()
  if Core.dev then
    Core.dev:OnTick(now)
  end
end

local function collectCurrent(applied)
  local current = {}
  for cvar in pairs(applied or {}) do
    current[cvar] = GetCVar(cvar)
  end
  return current
end

local function createFrame()
  if Core.frame then
    return
  end
  Core.frame = CreateFrame("Frame", "CrowdCalmFrame", UIParent)
  for _, event in ipairs(EVENTS) do
    Core.frame:RegisterEvent(event)
  end
  Core.frame:SetScript("OnEvent", function(_, event, ...)
    Core._handleEvent(event, ...)
  end)
  Core.devFrame = CreateFrame("Frame", "CrowdCalmDevFrame", UIParent)
  Core.ticker = C_Timer.NewTicker(1, function()
    Core._tick(GetTime())
  end)
end

local function init()
  local db = _G.CrowdCalmDB
  if type(db) ~= "table" or db.schemaVersion ~= 1 then
    db = { schemaVersion = 1 }
  end
  if type(db.settings) ~= "table" then
    db.settings = {}
  end
  fillDefaults(db.settings)
  local _, issues = ns.Panel.ValidateSettings(db.settings)
  for _, issue in ipairs(issues) do
    Core._log(issue)
  end
  if type(db.restore) ~= "table" then
    db.restore = {}
  end
  if type(db.restore.baselines) ~= "table" then
    db.restore.baselines = {}
  end
  if type(db.restore.applied) ~= "table" then
    db.restore.applied = {}
  end
  if db.restore.sessionActive == nil then
    db.restore.sessionActive = false
  end
  _G.CrowdCalmDB = db

  Core.sv = db
  Core.crowd = ns.Crowd.new(db.settings)
  Core.stutter = ns.Stutter.new(db.settings.stutter)
  Core.tickCount = 0
  Core.restingSince = nil
  Core.lastMode = nil
  Core.lastModeChange = GetTime()
  Core.switch = nil

  Core.RebuildSwitch()

  if db.restore.sessionActive then
    local plan = ns.Restore.Plan(db.restore, collectCurrent(db.restore.applied))
    Core.switch:RestorePersisted(plan)
  end
  Core._persistState()

  createFrame()
  Core.dev = ns.Dev.new(db.settings.dev, {
    getTime = function()
      return GetTime()
    end,
    setFrameHook = function(fn)
      if Core.devFrame then
        Core.devFrame:SetScript("OnUpdate", fn)
      end
    end,
    log = function(message)
      Core._log(message)
    end,
    getSnapshot = function()
      local state = Core.switch and Core.switch:GetState()
        or { applied = {}, baselines = {}, mode = "normal", pendingReason = nil }
      return {
        mode = effectiveMode(),
        plates = Core.CountPlates(),
        applied = state.applied,
        baselines = state.baselines,
        pendingReason = state.pendingReason,
      }
    end,
  })
  Core._syncStutterHook()
end

function Core._handleEvent(event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= ADDON_NAME then
      return
    end
    init()
    return
  end
  if not Core.switch then
    return
  end
  if event == "PLAYER_REGEN_ENABLED" then
    Core.switch:OnCombatEnd()
    Core._persistState()
    if Core.dev then
      Core.dev:OnTick(GetTime())
    end
  elseif event == "PLAYER_ENTERING_WORLD" then
    Core.switch:OnEnteringWorld()
    Core._scheduleSpellDensityReapply()
    if Core.dev then
      Core.dev:OnTick(GetTime())
    end
  elseif event == "PLAYER_LOGOUT" then
    Core.switch:OnLogout()
    Core._persistState()
    if Core.dev then
      Core.dev:OnLogout(GetTime())
    end
  elseif event == "CVAR_UPDATE" then
    local cvar, value = ...
    Core.switch:OnCvarChange(cvar, value)
    Core._persistState()
    if Core.dev then
      Core.dev:OnCvar(cvar, value)
    end
  end
end
