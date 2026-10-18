local ADDON_NAME, ns = ...

local Panel = {}
ns.Panel = Panel

local frame
local statusText

local function clampNumber(value, min, max)
  if value < min then
    return min
  end
  if value > max then
    return max
  end
  return value
end

local function validateField(settings, label, key, min, max, fallback, issues)
  local value = settings[key]
  if type(value) ~= "number" then
    settings[key] = fallback
    issues[#issues + 1] = string.format("%s reset to %s", label, tostring(fallback))
    return
  end
  local clamped = clampNumber(value, min, max)
  if clamped ~= value then
    settings[key] = clamped
    issues[#issues + 1] = string.format("%s clamped to %s", label, tostring(clamped))
  end
end

function Panel.ValidateSettings(settings)
  local issues = {}
  if type(settings) ~= "table" then
    return settings, issues
  end

  validateField(settings, "high", "high", 2, 40, 15, issues)
  validateField(settings, "low", "low", 1, settings.high - 1, 10, issues)
  validateField(settings, "enterDelay", "enterDelay", 0, 60, 3, issues)
  validateField(settings, "exitDelay", "exitDelay", 0, 60, 5, issues)
  validateField(settings, "framecapValue", "framecapValue", 0, 400, 60, issues)

  if type(settings.stutter) == "table" then
    validateField(settings.stutter, "stutter.thresholdMs", "thresholdMs", 10, 500, 50, issues)
    validateField(settings.stutter, "stutter.maxEntries", "maxEntries", 1, 1000, 100, issues)
  end

  return settings, issues
end

local function currentSettings()
  local core = ns.Core
  if core and core.sv and core.sv.settings then
    return core.sv.settings
  end
  return nil
end

local function reportIssues(issues)
  for _, issue in ipairs(issues) do
    print("CrowdCalm: " .. issue)
  end
end

local function applyNumber(settings, key, value)
  settings[key] = value
  local _, issues = Panel.ValidateSettings(settings)
  reportIssues(issues)
  Panel.Refresh()
end

local function setStutter(enabled)
  local settings = currentSettings()
  if not settings then
    print("CrowdCalm: settings not initialized yet")
    return
  end
  if type(settings.stutter) ~= "table" then
    settings.stutter = {}
  end
  settings.stutter.enabled = enabled and true or false
  local core = ns.Core
  if core and core._syncStutterHook then
    core._syncStutterHook()
  end
  print("CrowdCalm: stutter log " .. (enabled and "enabled" or "disabled"))
end

local function makeCheckbox(parent, name, label, y, initial, apply)
  local checkbox = parent:CreateCheckButton(name)
  checkbox:SetPoint("TOPLEFT", 16, -y)
  checkbox:SetText(label)
  checkbox:SetChecked(initial)
  checkbox:SetScript("OnClick", function(self)
    local settings = currentSettings()
    if not settings then
      return
    end
    apply(settings, self:GetChecked() and true or false)
  end)
  return checkbox
end

local function makeSlider(parent, name, label, y, minValue, maxValue, initial, apply)
  local slider = parent:CreateSlider(name)
  slider:SetPoint("TOPLEFT", 16, -y)
  slider:SetSize(180, 16)
  slider:SetMinMaxValues(minValue, maxValue)
  slider:SetValueStep(1)
  slider:SetValue(initial)
  slider:SetScript("OnValueChanged", function(_, value)
    local settings = currentSettings()
    if not settings then
      return
    end
    apply(settings, math.floor(value + 0.5))
  end)
  local text = parent:CreateFontString(name .. "Label", "OVERLAY", "GameFontNormal")
  text:SetPoint("LEFT", slider, "RIGHT", 8, 0)
  text:SetText(label)
  return slider
end

function Panel.Create()
  if frame then
    return frame
  end
  local settings = currentSettings() or {}

  frame = CreateFrame("Frame", "CrowdCalmPanel", UIParent)
  frame:SetSize(340, 460)
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

  local title = frame:CreateFontString("CrowdCalmPanelTitle", "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -14)
  title:SetText("CrowdCalm")

  statusText = frame:CreateFontString("CrowdCalmPanelStatus", "OVERLAY", "GameFontHighlight")
  statusText:SetPoint("TOPLEFT", 16, -38)

  local y = 64
  makeCheckbox(frame, "CrowdCalmPanelEnabled", "Enabled", y, settings.enabled ~= false, function(s, checked)
    s.enabled = checked
    print("CrowdCalm: " .. (checked and "enabled" or "disabled"))
  end)

  for _, category in ipairs(ns.Profiles.Categories) do
    y = y + 22
    local initial = category.defaultEnabled
    if settings.categories and settings.categories[category.key] ~= nil then
      initial = settings.categories[category.key]
    end
    makeCheckbox(frame, "CrowdCalmPanelCategory" .. category.key, category.label, y, initial, function(s, checked)
      s.categories[category.key] = checked
      local core = ns.Core
      if core and core.RebuildSwitch then
        core.RebuildSwitch()
      end
      print("CrowdCalm: " .. category.label .. (checked and " enabled" or " disabled"))
    end)
  end

  y = y + 22
  local stutterInitial = type(settings.stutter) == "table" and settings.stutter.enabled == true
  makeCheckbox(frame, "CrowdCalmPanelStutter", "Stutter log", y, stutterInitial, function(_, checked)
    setStutter(checked)
  end)

  local sliderDefinitions = {
    { "high", "High threshold", 2, 40, settings.high or 15 },
    { "low", "Low threshold", 1, 40, settings.low or 10 },
    { "enterDelay", "Enter delay (s)", 0, 60, settings.enterDelay or 3 },
    { "exitDelay", "Exit delay (s)", 0, 60, settings.exitDelay or 5 },
    { "framecapValue", "Frame cap", 0, 400, settings.framecapValue or 60 },
  }
  for _, definition in ipairs(sliderDefinitions) do
    y = y + 34
    local key, label, minValue, maxValue, initial = definition[1], definition[2], definition[3], definition[4], definition[5]
    local widgetName = "CrowdCalmPanel" .. key:sub(1, 1):upper() .. key:sub(2)
    makeSlider(frame, widgetName, label, y, minValue, maxValue, initial, function(s, value)
      applyNumber(s, key, value)
    end)
  end

  frame:Hide()
  return frame
end

function Panel.Refresh()
  if not frame then
    return
  end
  local core = ns.Core
  local mode = "normal"
  local count = 0
  if core then
    if core.crowd then
      mode = core.crowd:GetMode()
    end
    if core.CountPlates then
      count = core.CountPlates()
    end
  end
  local lastSwitch = "-"
  if core and core.lastModeChange then
    lastSwitch = string.format("%.0fs ago", GetTime() - core.lastModeChange)
  end
  statusText:SetText(string.format("%s | plates: %d | FPS: %d | %.1f MB | last switch: %s",
    mode, count, GetFramerate(), ns.Monitor.GetOwnMB(), lastSwitch))
end

function Panel.Toggle()
  local f = Panel.Create()
  if not f then
    return
  end
  if f:IsShown() then
    f:Hide()
  else
    Panel.Refresh()
    f:Show()
  end
end

local function printStatus()
  local core = ns.Core
  local mode = "normal"
  local count = 0
  if core then
    if core.crowd then
      mode = core.crowd:GetMode()
    end
    if core.CountPlates then
      count = core.CountPlates()
    end
  end
  print(string.format("CrowdCalm: mode %s, plates %d, FPS %d, own memory %.1f MB",
    mode, count, GetFramerate(), ns.Monitor.GetOwnMB()))
end

local function printLog()
  local core = ns.Core
  local entries = (core and core.stutter and core.stutter:GetEntries()) or {}
  print(string.format("CrowdCalm: stutter log has %d entries", #entries))
  for i = math.max(1, #entries - 4), #entries do
    local entry = entries[i]
    if entry then
      print(string.format("  %.1fs: %.0f ms (%s, %s)", entry.t, entry.deltaMs,
        entry.context.zone, entry.context.mode))
    end
  end
end

local function printMemory()
  print(string.format("CrowdCalm: own memory %.1f MB", ns.Monitor.GetOwnMB()))
end

local function setEnabled(enabled)
  local settings = currentSettings()
  if not settings then
    print("CrowdCalm: settings not initialized yet")
    return
  end
  settings.enabled = enabled and true or false
  print("CrowdCalm: " .. (enabled and "enabled" or "disabled"))
end

function Panel.RunCommand(input)
  local command = tostring(input or ""):lower():match("^%s*(.-)%s*$") or ""
  if command == "" then
    Panel.Toggle()
  elseif command == "status" then
    printStatus()
  elseif command == "log" then
    printLog()
  elseif command == "memory" then
    printMemory()
  elseif command == "on" then
    setEnabled(true)
  elseif command == "off" then
    setEnabled(false)
  elseif command == "stutter" then
    print("CrowdCalm: usage /cc stutter on|off")
  elseif command:match("^stutter%s+on$") then
    setStutter(true)
  elseif command:match("^stutter%s+off$") then
    setStutter(false)
  else
    print("CrowdCalm: unknown command '" .. command .. "'. Usage: /cc [status|log|memory|on|off|stutter on|off]")
  end
end

SlashCmdList["CROWDCALM"] = function(input)
  Panel.RunCommand(input)
end
SLASH_CROWDCALM1 = "/cc"
