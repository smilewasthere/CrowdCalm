-- UI/Pages/Settings.lua — every owner preference (brief section 6.6):
-- UI scale, reduce motion, colorblind palette, font size, sample length,
-- default mode, stutter floor, compartment preference, minimap button,
-- debug log, mute, and reset-data behind a confirmation.
local ADDON_NAME, ns = ...

local Widgets = ns.widgets
local Skin = ns.skin
local L = ns.L

local function sectionLabel(parent, text, y)
  local label = Widgets.SectionLabel(parent, text)
  label:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y)
  return label
end

local function create(parent)
  local frame = parent
  local ui = ns.db.settings.ui
  local lab = ns.db.settings.lab
  local y = -12

  sectionLabel(frame, L("page_settings"), y)
  y = y - 32

  -- UI scale — applied on release (mid-drag window scaling yanks the thumb
  -- under the cursor; pre.5 fix for "scale resets while dragging")
  local scaleLabel = Widgets.Text(frame, "body", L("set_ui_scale"))
  scaleLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, y)
  local scaleSlider = Widgets.Slider(frame, {
    min = 70,
    max = 140,
    step = 5,
    value = math.floor(((ui.scale or 1) * 100) + 0.5),
    width = 180,
    format = "%d%%",
    onChange = function(v)
      ns.ui.ApplyUIScale(v / 100)
    end,
  })
  scaleSlider:SetPoint("LEFT", scaleLabel, "RIGHT", 24, 0)
  y = y - 36

  -- reduce motion + colorblind + mute (checkbox row)
  local motionBox = Widgets.Checkbox(frame, {
    label = L("set_reduce_motion"),
    checked = ui.reduceMotion,
    onToggle = function(v)
      ui.reduceMotion = v
    end,
  })
  motionBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, y)
  local cbBox = Widgets.Checkbox(frame, {
    label = L("set_colorblind"),
    checked = ui.colorblind,
    onToggle = function(v)
      ui.colorblind = v
      -- colors are captured per-widget at build time; rebuild to apply
      ns.ui.ScheduleRebuild("colorblind")
    end,
  })
  cbBox:SetPoint("LEFT", motionBox, "RIGHT", 240, 0)
  y = y - 36

  local muteBox = Widgets.Checkbox(frame, {
    label = L("set_mute"),
    checked = ui.muted,
    onToggle = function(v)
      ui.muted = v
      -- the toggle click fires before this callback while still audible;
      -- unmuting needs one more sound now that the gate is open
      if not v and ns.sound then
        ns.sound.PlayRaw("toggleOff")
      end
    end,
  })
  muteBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, y)
  local fontBox = Widgets.Checkbox(frame, {
    label = L("set_compartment"),
    checked = ui.compartment,
    onToggle = function(v)
      ui.compartment = v
    end,
  })
  fontBox:SetPoint("LEFT", muteBox, "RIGHT", 240, 0)
  Widgets.TooltipLines(fontBox, function()
    return { L("set_compartment_note") }
  end)
  y = y - 36

  local mmBox = Widgets.Checkbox(frame, {
    label = L("set_minimap"),
    checked = ui.minimapButton,
    onToggle = function(v)
      ui.minimapButton = v
      ns.minimapButton.Refresh()
    end,
  })
  mmBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, y)
  Widgets.TooltipLines(mmBox, function()
    return { L("set_minimap_note") }
  end)
  y = y - 36

  -- font size — applied on release; font objects are baked at build time,
  -- so the window rebuilds to pick the new size up (pre.5)
  local fontLabel = Widgets.Text(frame, "body", L("set_font_size"))
  fontLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, y)
  local fontSlider = Widgets.Slider(frame, {
    min = 10,
    max = 20,
    step = 1,
    value = ui.fontSize or 14,
    width = 140,
    format = "%d",
    onChange = function(v)
      ui.fontSize = math.floor(v + 0.5)
      ns.ui.ScheduleRebuild("font size")
    end,
  })
  fontSlider:SetPoint("LEFT", fontLabel, "RIGHT", 24, 0)
  Widgets.TooltipLines(fontSlider, function()
    return { L("set_font_note") }
  end)
  y = y - 36

  sectionLabel(frame, L("log_section"), y)
  y = y - 32

  -- lab sample length
  local sampleLabel = Widgets.Text(frame, "body", L("set_sample"))
  sampleLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, y)
  local sampleSlider = Widgets.Slider(frame, {
    min = 4,
    max = 12,
    step = 1,
    value = lab.sampleSeconds or 8,
    width = 160,
    format = "%d",
    onChange = function(v)
      lab.sampleSeconds = math.floor(v + 0.5)
    end,
  })
  sampleSlider:SetPoint("LEFT", sampleLabel, "RIGHT", 24, 0)
  y = y - 36

  -- stutter floor
  local floorLabel = Widgets.Text(frame, "body", L("set_stutter_floor"))
  floorLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, y)
  local floorSlider = Widgets.Slider(frame, {
    min = 10,
    max = 60,
    step = 5,
    value = lab.fpsStutterFloor or 30,
    width = 160,
    format = "%d",
    onChange = function(v)
      lab.fpsStutterFloor = math.floor(v + 0.5)
    end,
  })
  floorSlider:SetPoint("LEFT", floorLabel, "RIGHT", 24, 0)
  y = y - 36

  -- default mode dropdown
  local modeLabel = Widgets.Text(frame, "body", L("set_default_mode"))
  modeLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, y)
  local modeDrop = Widgets.Dropdown(frame, {
    width = 160,
    options = {
      { id = "quick", label = L("quick") },
      { id = "thorough", label = L("thorough") },
    },
    selectedId = lab.defaultMode or "quick",
    onChange = function(id)
      lab.defaultMode = id
    end,
  })
  modeDrop:SetPoint("LEFT", modeLabel, "RIGHT", 24, 0)
  y = y - 36

  -- log + debug
  local logBox = Widgets.Checkbox(frame, {
    label = L("stutter_enable"),
    checked = ns.db.settings.log.enabled,
    onToggle = function(v)
      ns.db.settings.log.enabled = v
      ns.stutterLog.SetEnabled(v)
    end,
  })
  logBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, y)
  local debugBox = Widgets.Checkbox(frame, {
    label = L("set_debug"),
    checked = ns.db.settings.debug,
    onToggle = function(v)
      ns.db.settings.debug = v
    end,
  })
  debugBox:SetPoint("LEFT", logBox, "RIGHT", 240, 0)
  y = y - 44

  -- reset
  local resetBtn = Widgets.Button(frame, {
    label = L("set_reset"),
    primary = true,
    onClick = function()
      Widgets.Confirm(L("reset_confirm"), function()
        ns.db.results = {}
        ns.db.stutter = {}
        ns.db.baseline = nil
        ns.db.lastApplied = nil
        ns.stutterLog.Clear()
        ns.ui.ShowBanner(L("reset_done"), "gainColor", 6)
      end)
    end,
  })
  resetBtn:SetWidth(220)
  resetBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, y)

  frame:SetScript("OnShow", function()
    -- reflect live values (another page may have changed them); silent so
    -- the sync never fires a commit (a stray commit would rebuild the
    -- window on every visit to this page)
    if scaleSlider and scaleSlider.SetSilentValue then
      local target = math.floor(((ui.scale or 1) * 100) + 0.5)
      if math.abs((scaleSlider:GetValue() or target) - target) > 0.5 then
        scaleSlider:SetSilentValue(target)
      end
    end
    if fontSlider and fontSlider.SetSilentValue then
      local target = ui.fontSize or 14
      if math.abs((fontSlider:GetValue() or target) - target) > 0.5 then
        fontSlider:SetSilentValue(target)
      end
    end
  end)
  return frame
end

ns.ui.RegisterPage({
  index = 6,
  name = L("page_settings"),
  icon = "icon_settings.tga",
  create = create,
})
