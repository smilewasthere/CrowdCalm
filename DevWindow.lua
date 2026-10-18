local ADDON_NAME, ns = ...

local DevWindow = {}
ns.DevWindow = DevWindow

local frame
local widgets = {}
local uiMode = "auto"
local uiLen = 60
local uiRounds = "AB"
local addonVersion

local function currentSettings()
  local core = ns.Core
  if core and core.sv and core.sv.settings then
    return core.sv.settings
  end
  return nil
end

local function devInstance()
  local core = ns.Core
  return core and core.dev
end

local function rebuildSwitch()
  local core = ns.Core
  if core and core.RebuildSwitch then
    core.RebuildSwitch()
  end
end

local function syncStutterHook()
  local core = ns.Core
  if core and core._syncStutterHook then
    core._syncStutterHook()
  end
end

local function makeCheckbox(parent, name, label, x, y, initial, apply)
  local checkbox = parent:CreateCheckButton(name)
  checkbox:SetPoint("TOPLEFT", x, -y)
  checkbox:SetText(label)
  checkbox:SetChecked(initial)
  checkbox:SetScript("OnClick", function(self)
    local settings = currentSettings()
    if not settings then
      return
    end
    apply(settings, self:GetChecked() and true or false)
  end)
  widgets[name] = checkbox
  return checkbox
end

local function makeButton(parent, name, label, x, y, width, apply)
  local button = parent:CreateButton(name)
  button:SetPoint("TOPLEFT", x, -y)
  button:SetSize(width, 22)
  button:SetText(label)
  button:SetScript("OnClick", function()
    local settings = currentSettings()
    if not settings then
      return
    end
    apply(settings)
  end)
  widgets[name] = button
  return button
end

local function makeModeRadio(parent, name, label, x, y, mode)
  local checkbox = parent:CreateCheckButton(name)
  checkbox:SetPoint("TOPLEFT", x, -y)
  checkbox:SetText(label)
  checkbox:SetChecked(uiMode == mode)
  checkbox:SetScript("OnClick", function()
    uiMode = mode
    DevWindow.Refresh()
  end)
  widgets[name] = checkbox
  return checkbox
end

local function makeLengthButton(parent, name, seconds, x, y)
  local button = parent:CreateButton(name)
  button:SetPoint("TOPLEFT", x, -y)
  button:SetSize(60, 22)
  button:SetText(seconds .. "s")
  button:SetScript("OnClick", function()
    uiLen = seconds
    DevWindow.Refresh()
  end)
  widgets[name] = button
  return button
end

function DevWindow.Create()
  if frame then
    return frame
  end
  local settings = currentSettings() or {}

  frame = CreateFrame("Frame", "CrowdCalmDevPanel", UIParent)
  frame:SetSize(360, 620)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    self:StartMoving()
  end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
  end)

  local title = frame:CreateFontString("CrowdCalmDevTitle", "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -14)
  title:SetText("CrowdCalm Dev")

  widgets.CrowdCalmDevStatus = frame:CreateFontString("CrowdCalmDevStatus", "OVERLAY", "GameFontHighlight")
  widgets.CrowdCalmDevStatus:SetPoint("TOPLEFT", 16, -38)

  local dev = devInstance()
  makeCheckbox(frame, "CrowdCalmDevForceCrowd", "Force crowd", 16, 64, dev ~= nil and dev.forceCrowd == true, function(_, checked)
    local instance = devInstance()
    if instance then
      instance:SetForceCrowd(checked)
    end
  end)

  makeButton(frame, "CrowdCalmDevAllOff", "All features OFF", 16, 88, 130, function(s)
    s.enabled = false
    print("CrowdCalm: all features off")
  end)
  makeButton(frame, "CrowdCalmDevAllOn", "All features ON", 156, 88, 130, function(s)
    s.enabled = true
    if type(s.categories) ~= "table" then
      s.categories = {}
    end
    for _, category in ipairs(ns.Profiles.Categories) do
      s.categories[category.key] = true
    end
    rebuildSwitch()
    print("CrowdCalm: all features on")
  end)

  local y = 118
  makeCheckbox(frame, "CrowdCalmDevMaster", "Enabled", 16, y, settings.enabled ~= false, function(s, checked)
    s.enabled = checked
  end)
  for _, category in ipairs(ns.Profiles.Categories) do
    y = y + 22
    local initial = category.defaultEnabled
    if settings.categories and settings.categories[category.key] ~= nil then
      initial = settings.categories[category.key]
    end
    makeCheckbox(frame, "CrowdCalmDevCategory" .. category.key, category.label, 16, y, initial, function(s, checked)
      if type(s.categories) ~= "table" then
        s.categories = {}
      end
      s.categories[category.key] = checked
      rebuildSwitch()
    end)
  end

  y = y + 22
  local stutterInitial = type(settings.stutter) == "table" and settings.stutter.enabled == true
  makeCheckbox(frame, "CrowdCalmDevStutter", "Stutter log", 16, y, stutterInitial, function(s, checked)
    if type(s.stutter) ~= "table" then
      s.stutter = {}
    end
    s.stutter.enabled = checked
    syncStutterHook()
  end)

  y = y + 30
  makeModeRadio(frame, "CrowdCalmDevModeAuto", "Auto", 16, y, "auto")
  makeModeRadio(frame, "CrowdCalmDevModeGuided", "Guided", 96, y, "guided")
  makeModeRadio(frame, "CrowdCalmDevModePassive", "Passive", 190, y, "passive")

  y = y + 26
  makeLengthButton(frame, "CrowdCalmDevLen30", 30, 16, y)
  makeLengthButton(frame, "CrowdCalmDevLen60", 60, 86, y)
  makeLengthButton(frame, "CrowdCalmDevLen120", 120, 156, y)

  y = y + 26
  local rounds = frame:CreateCheckButton("CrowdCalmDevRounds")
  rounds:SetPoint("TOPLEFT", 16, -y)
  rounds:SetText("ABAB (average 2 rounds)")
  rounds:SetChecked(uiRounds == "ABAB")
  rounds:SetScript("OnClick", function(self)
    uiRounds = self:GetChecked() and "ABAB" or "AB"
    DevWindow.Refresh()
  end)
  widgets.CrowdCalmDevRounds = rounds

  y = y + 26
  makeButton(frame, "CrowdCalmDevStart", "START", 16, y, 80, function()
    local instance = devInstance()
    if not instance then
      return
    end
    if uiMode == "auto" then
      instance:StartTest("auto", { phaseSeconds = uiLen, rounds = uiRounds })
    else
      instance:StartTest(uiMode)
    end
    DevWindow.Refresh()
  end)
  makeButton(frame, "CrowdCalmDevStop", "STOP", 110, y, 80, function()
    local instance = devInstance()
    if instance then
      instance:StopTest("manual")
    end
    DevWindow.Refresh()
  end)
  makeButton(frame, "CrowdCalmDevNextPhase", "Next phase", 204, y, 110, function()
    local instance = devInstance()
    if instance and instance.NextPhase then
      instance:NextPhase()
    end
    DevWindow.Refresh()
  end)

  y = y + 28
  widgets.CrowdCalmDevPhase = frame:CreateFontString("CrowdCalmDevPhase", "OVERLAY", "GameFontHighlight")
  widgets.CrowdCalmDevPhase:SetPoint("TOPLEFT", 16, -y)
  y = y + 18
  widgets.CrowdCalmDevResult = frame:CreateFontString("CrowdCalmDevResult", "OVERLAY", "GameFontHighlight")
  widgets.CrowdCalmDevResult:SetPoint("TOPLEFT", 16, -y)

  y = y + 24
  makeButton(frame, "CrowdCalmDevCopyReport", "Copy report", 16, y, 110, function()
    local instance = devInstance()
    if not instance then
      return
    end
    local edit = widgets.CrowdCalmDevReport
    edit:SetText(instance:GetReport())
    edit:HighlightText()
    edit:SetFocus()
    print("CrowdCalm: report copied (Ctrl+C)")
  end)
  makeButton(frame, "CrowdCalmDevCopyTest", "Copy last test", 136, y, 110, function()
    local instance = devInstance()
    if not instance then
      return
    end
    local result = instance:GetLastResult()
    if not result then
      print("CrowdCalm: no test result yet")
      return
    end
    local edit = widgets.CrowdCalmDevReport
    edit:SetText(result)
    edit:HighlightText()
    edit:SetFocus()
    print("CrowdCalm: test result copied (Ctrl+C)")
  end)

  y = y + 26
  local edit = frame:CreateEditBox("CrowdCalmDevReport")
  edit:SetPoint("TOPLEFT", 16, -y)
  edit:SetSize(328, 140)
  edit:SetMultiLine(true)
  edit:SetMaxLetters(60000)
  widgets.CrowdCalmDevReport = edit

  frame:Hide()
  DevWindow.Refresh()
  return frame
end

function DevWindow.Refresh()
  if not frame then
    return
  end
  local core = ns.Core
  local dev = core and core.dev or nil
  local status = dev and dev:GetStatus() or { recording = false, forceCrowd = false }

  local mode = "normal"
  if status.forceCrowd then
    mode = "crowd (forced)"
  elseif core and core.crowd then
    mode = core.crowd:GetMode()
  end
  local count = 0
  if core and core.CountPlates then
    count = core.CountPlates()
  end
  local mb = 0
  if ns.Monitor and ns.Monitor.GetOwnMB then
    mb = ns.Monitor.GetOwnMB()
  end
  if not addonVersion then
    addonVersion = "?"
    if _G.C_AddOns and type(_G.C_AddOns.GetAddOnMetadata) == "function" then
      local ok, value = pcall(_G.C_AddOns.GetAddOnMetadata, ADDON_NAME or "CrowdCalm", "Version")
      if ok and value ~= nil then
        addonVersion = tostring(value)
      end
    end
  end
  widgets.CrowdCalmDevStatus:SetText(string.format("%s | plates %d | FPS %d | %.1f MB | dev v%s", mode, count, GetFramerate(), mb, addonVersion))

  local phaseText = "idle"
  if status.recording then
    if status.phaseEndsAt then
      local left = math.max(0, math.ceil(status.phaseEndsAt - GetTime()))
      phaseText = string.format("Phase %s - %ds left", tostring(status.phase), left)
    else
      phaseText = string.format("Recording - phase %s", tostring(status.phase or "?"))
    end
  end
  widgets.CrowdCalmDevPhase:SetText(phaseText)
  widgets.CrowdCalmDevResult:SetText(dev and dev:GetLastResult() or "-")

  local settings = currentSettings()
  if settings then
    widgets.CrowdCalmDevMaster:SetChecked(settings.enabled ~= false)
    widgets.CrowdCalmDevStutter:SetChecked(type(settings.stutter) == "table" and settings.stutter.enabled == true)
    if type(settings.categories) == "table" then
      for _, category in ipairs(ns.Profiles.Categories) do
        widgets["CrowdCalmDevCategory" .. category.key]:SetChecked(settings.categories[category.key] == true)
      end
    end
  end
  if dev then
    widgets.CrowdCalmDevForceCrowd:SetChecked(dev.forceCrowd == true)
  end
  widgets.CrowdCalmDevModeAuto:SetChecked(uiMode == "auto")
  widgets.CrowdCalmDevModeGuided:SetChecked(uiMode == "guided")
  widgets.CrowdCalmDevModePassive:SetChecked(uiMode == "passive")
  widgets.CrowdCalmDevLen30:SetText(uiLen == 30 and "[30s]" or "30s")
  widgets.CrowdCalmDevLen60:SetText(uiLen == 60 and "[60s]" or "60s")
  widgets.CrowdCalmDevLen120:SetText(uiLen == 120 and "[120s]" or "120s")
  widgets.CrowdCalmDevRounds:SetChecked(uiRounds == "ABAB")
end

function DevWindow.Toggle()
  local dev = devInstance()
  if not (dev and dev.enabled) then
    print("CrowdCalm: dev mode is off - use /ccdev on")
    return
  end
  local f = DevWindow.Create()
  if not f then
    return
  end
  if f:IsShown() then
    f:Hide()
  else
    DevWindow.Refresh()
    f:Show()
  end
end
