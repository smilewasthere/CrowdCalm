local stub = {}

local widgetMethods = {}

local newWidget

function widgetMethods:Show()
  self.__shown = true
  return self
end

function widgetMethods:Hide()
  self.__shown = false
  return self
end

function widgetMethods:IsShown()
  return self.__shown
end

function widgetMethods:SetShown(shown)
  self.__shown = shown and true or false
  return self
end

function widgetMethods:GetName()
  return self.__name
end

function widgetMethods:SetScript(handler, fn)
  self.__scripts[handler] = fn
  return self
end

function widgetMethods:GetScript(handler)
  return self.__scripts[handler]
end

function widgetMethods:HookScript(handler, fn)
  self.__scripts[handler] = fn
  return self
end

function widgetMethods:RegisterEvent(event)
  self.__events[event] = true
  return self
end

function widgetMethods:UnregisterEvent(event)
  self.__events[event] = nil
  return self
end

function widgetMethods:IsEventRegistered(event)
  return self.__events[event] == true
end

function widgetMethods:RegisterForClicks()
  return self
end

function widgetMethods:SetText(text)
  self.__text = text
  return self
end

function widgetMethods:GetText()
  return self.__text
end

function widgetMethods:SetChecked(checked)
  self.__checked = checked and true or false
  return self
end

function widgetMethods:GetChecked()
  return self.__checked
end

function widgetMethods:Click()
  if self.__kind == "CheckButton" then
    self.__checked = not self.__checked
  end
  if self.__scripts.OnClick then
    self.__scripts.OnClick(self)
  end
  return self
end

function widgetMethods:SetValue(value)
  self.__value = value
  if self.__scripts.OnValueChanged then
    self.__scripts.OnValueChanged(self, value)
  end
  return self
end

function widgetMethods:GetValue()
  return self.__value
end

local function addChild(widget, name)
  stub.state.frames[#stub.state.frames + 1] = widget
  if name then
    stub.state.framesByName[name] = widget
  end
  return widget
end

function widgetMethods:CreateFontString(name)
  local fs = newWidget("FontString")
  fs.__name = name
  return addChild(fs, name)
end

function widgetMethods:CreateTexture(name)
  local tx = newWidget("Texture")
  tx.__name = name
  return addChild(tx, name)
end

function widgetMethods:CreateCheckButton(name)
  local cb = newWidget("CheckButton")
  cb.__name = name
  return addChild(cb, name)
end

function widgetMethods:CreateSlider(name)
  local sl = newWidget("Slider")
  sl.__name = name
  return addChild(sl, name)
end

function newWidget(kind)
  return setmetatable({
    __kind = kind,
    __shown = false,
    __scripts = {},
    __events = {},
  }, {
    __index = function(_, key)
      local m = widgetMethods[key]
      if m then
        return m
      end
      return function(self)
        return self
      end
    end,
  })
end

function stub.reset()
  stub.state = {
    inCombat = false,
    time = 0,
    cvars = {},
    knownCvars = {},
    secureCvars = {},
    readOnlyCvars = {},
    defaults = {},
    setCvarFail = {},
    callLog = {},
    failedSets = 0,
    nameplates = {},
    playerUnits = {},
    resting = false,
    zone = "Test Zone",
    fps = 60,
    timers = {},
    tickers = {},
    frames = {},
    framesByName = {},
    printed = {},
    logged = {},
    gcKB = 1024,
    hasGetAllCommands = true,
    getInfoNilMode = false,
  }
end

function stub.known(name, value, opts)
  opts = opts or {}
  stub.state.knownCvars[name] = true
  if value ~= nil then
    stub.state.cvars[name] = tostring(value)
  end
  if opts.default ~= nil then
    stub.state.defaults[name] = tostring(opts.default)
  end
  if opts.secure then
    stub.state.secureCvars[name] = true
  end
  if opts.readOnly then
    stub.state.readOnlyCvars[name] = true
  end
end

function stub.fireEvent(event, ...)
  local frames = {}
  for i, frame in ipairs(stub.state.frames) do
    frames[i] = frame
  end
  for _, frame in ipairs(frames) do
    if frame.__events[event] and frame.__scripts.OnEvent then
      frame.__scripts.OnEvent(frame, event, ...)
    end
  end
end

local function setCvarImpl(name, value)
  if stub.state.setCvarFail[name] then
    stub.state.failedSets = stub.state.failedSets + 1
    return nil
  end
  stub.state.cvars[name] = tostring(value)
  stub.state.callLog[#stub.state.callLog + 1] = { name = name, value = tostring(value) }
  stub.fireEvent("CVAR_UPDATE", name, tostring(value))
  return true
end

local function getInfoImpl(name)
  if not stub.state.knownCvars[name] then
    if stub.state.getInfoNilMode then
      return nil
    end
    error("Unknown console variable: " .. tostring(name), 0)
  end
  local value = stub.state.cvars[name]
  if value == nil then
    value = stub.state.defaults[name] or ""
  end
  return value,
    stub.state.defaults[name] or "",
    false,
    false,
    false,
    stub.state.secureCvars[name] == true,
    stub.state.readOnlyCvars[name] == true
end

function stub.install()
  stub.reset()

  _G.ADDON_NAME = "CrowdCalm"

  _G.GetCVar = function(name)
    return stub.state.cvars[name]
  end

  _G.SetCVar = setCvarImpl

  _G.GetCVarDefault = function(name)
    return stub.state.defaults[name]
  end

  _G.C_CVar = {
    GetCVar = function(name)
      return stub.state.cvars[name]
    end,
    SetCVar = setCvarImpl,
    GetCVarInfo = function(name)
      return getInfoImpl(name)
    end,
  }

  _G.C_Console = {
    GetAllCommands = function()
      if not stub.state.hasGetAllCommands then
        error("C_Console.GetAllCommands is not available", 0)
      end
      local out = {}
      for name in pairs(stub.state.knownCvars) do
        out[#out + 1] = { command = name, commandType = 0, help = "", category = 1 }
      end
      return out
    end,
  }

  _G.C_NamePlate = {
    GetNamePlates = function()
      local out = {}
      for _, token in ipairs(stub.state.nameplates) do
        out[#out + 1] = { namePlateUnitToken = token }
      end
      return out
    end,
  }

  _G.UnitIsPlayer = function(token)
    return stub.state.playerUnits[token] == true
  end

  _G.IsResting = function()
    return stub.state.resting
  end

  _G.GetTime = function()
    return stub.state.time
  end

  _G.GetFramerate = function()
    return stub.state.fps
  end

  _G.GetZoneText = function()
    return stub.state.zone
  end

  _G.GetLocale = function()
    return "enUS"
  end

  _G.InCombatLockdown = function()
    return stub.state.inCombat
  end

  _G.CreateFrame = function(kind, name, parent, template)
    local f = newWidget(kind)
    f.__name = name
    f.__parent = parent
    f.__template = template
    return addChild(f, name)
  end

  _G.UIParent = newWidget("Frame")

  _G.SlashCmdList = {}

  _G.C_Timer = {
    After = function(delay, fn)
      stub.state.timers[#stub.state.timers + 1] = { at = stub.state.time + delay, fn = fn }
    end,
    NewTicker = function(interval, fn)
      local t = { interval = interval, fn = fn, cancelled = false }
      stub.state.tickers[#stub.state.tickers + 1] = t
      return {
        Cancel = function()
          t.cancelled = true
        end,
      }
    end,
  }

  _G.wipe = function(t)
    for k in pairs(t) do
      t[k] = nil
    end
    return t
  end

  _G.tinsert = table.insert
  _G.tremove = table.remove

  _G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do
      parts[#parts + 1] = tostring((select(i, ...)))
    end
    stub.state.printed[#stub.state.printed + 1] = table.concat(parts, " ")
  end

  _G.DEFAULT_CHAT_FRAME = {
    AddMessage = function(_, msg)
      stub.state.printed[#stub.state.printed + 1] = tostring(msg)
    end,
  }

  _G.collectgarbage = function(what)
    if what == "count" then
      return stub.state.gcKB
    end
    return 0
  end
end

function stub.runTimers()
  local due = {}
  local rest = {}
  for _, t in ipairs(stub.state.timers) do
    if t.at <= stub.state.time then
      due[#due + 1] = t
    else
      rest[#rest + 1] = t
    end
  end
  stub.state.timers = rest
  for _, t in ipairs(due) do
    t.fn()
  end
end

function stub.loadAddon(file, ns)
  local chunk = assert(loadfile(file), "cannot load " .. tostring(file))
  chunk("CrowdCalm", ns)
  return ns
end

function stub.newNs()
  return {}
end

function stub.deps()
  return {
    getTime = function()
      return stub.state.time
    end,
    getCvar = function(name)
      return stub.state.cvars[name]
    end,
    setCvar = setCvarImpl,
    inCombat = function()
      return stub.state.inCombat
    end,
    log = function(msg)
      stub.state.logged[#stub.state.logged + 1] = tostring(msg)
    end,
  }
end

return stub
