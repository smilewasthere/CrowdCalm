-- UI/Pages/Lab.lua — guided strip, setting-tile grid, Run controls, running
-- overlay with cancel (brief section 6.2). Selection is stored in
-- db.selection[id]; the combine toggle uses the reserved id "__combine__".
local ADDON_NAME, ns = ...

local Widgets = ns.widgets
local Skin = ns.skin
local L = ns.L
local Lfmt = ns.Lfmt

local function scopeBadge(card, text, color)
  local fs = Widgets.Text(card, "small", text)
  fs:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -8)
  Skin.ColorText(fs, color)
  return fs
end

local function tileFor(parent, cand, onSelectionChanged)
  local card = Widgets.Panel(parent, { base = ns.palette.raised, borderAlpha = 0.5 })
  card:SetHeight(72)
  local locked = cand.locked and true or false

  local box
  if not locked then
    box = Widgets.Checkbox(card, {
      checked = ns.db.selection[cand.id] and true or false,
      onToggle = function(checked)
        ns.db.selection[cand.id] = checked
        if onSelectionChanged then
          onSelectionChanged()
        end
      end,
    })
    box:SetPoint("TOPLEFT", 8, -8)
  else
    local lockIcon = card:CreateTexture(nil, "ARTWORK")
    lockIcon:SetTexture(Skin.mediaPath .. "icon.tga")
    lockIcon:SetSize(20, 20)
    lockIcon:SetPoint("TOPLEFT", 10, -10)
  end

  local label = Widgets.Text(card, "body", L(cand.label or cand.id))
  label:SetPoint("TOPLEFT", locked and 10 or 40, -10)
  if locked then
    label:SetPoint("TOPLEFT", card, "TOPLEFT", 36, -10)
  end

  local value = "?"
  if cand.key then
    local v = ns.cvarGuard.Read(cand.key)
    value = tostring(v or "?")
  elseif locked then
    value = "excluded"
  end
  local valueText = Widgets.Text(card, "small", Lfmt("current_value", value))
  valueText:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
  Skin.ColorText(valueText, ns.palette.textDim)
  card.valueText = valueText
  card.candKey = cand.key

  -- badges: safety, scope, cost
  local safetyText, safetyColor
  if locked then
    safetyText, safetyColor = L("badge_locked"), ns.palette.danger
  elseif cand.experimental then
    safetyText, safetyColor = L("badge_experimental"), ns.palette.arcane
  elseif cand.range == "verify" then
    safetyText, safetyColor = L("badge_verify"), ns.palette.costColor()
  else
    safetyText, safetyColor = L("badge_safe"), ns.palette.gainColor()
  end
  local badge = scopeBadge(card, safetyText, safetyColor)
  if cand.key then
    local info = ns.cvarGuard.Info(cand.key)
    local scope = ns.cvarGuard.ScopeOf(info)
    local scopeFs = Widgets.Text(card, "small", scope)
    scopeFs:SetPoint("TOPRIGHT", badge, "BOTTOMRIGHT", 0, -2)
    Skin.ColorText(scopeFs, ns.palette.textDim)
  end
  if cand.key then
    local costTier = ns.settings.costOf(cand.key)
    local costColor = costTier == "High" and ns.palette.costColor()
      or (costTier == "None" and ns.palette.gainColor() or ns.palette.textDim)
    local costFs = Widgets.Text(card, "small", L("cost_" .. costTier:lower()) or costTier)
    costFs:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -8, 8)
    Skin.ColorText(costFs, costColor)
  end

  if not locked then
    local onlyBtn = Widgets.Button(card, {
      small = true,
      label = L("test_only"),
      onClick = function()
        for id in pairs(ns.db.selection) do
          ns.db.selection[id] = false
        end
        ns.db.selection[cand.id] = true
        ns.db.selection["__combine__"] = false
        if onSelectionChanged then
          onSelectionChanged(true)
        end
      end,
    })
    onlyBtn:SetWidth(90)
    onlyBtn:SetHeight(20)
    onlyBtn:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 8, 6)
  end

  if cand.note then
    Widgets.TooltipLines(card, function()
      return { L(cand.note), L("note_unverified_range") }
    end)
  end
  return card
end

local function create(parent)
  local frame = parent
  local pad = 12

  -- guided strip
  local guide = Widgets.Panel(frame, { base = ns.palette.obsidian, borderAlpha = 0.4 })
  guide:SetHeight(28)
  guide:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
  guide:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad)
  local stepTexts = {}
  for i, key in ipairs({ "guide_stand", "guide_pick", "guide_run", "guide_read" }) do
    local fs = Widgets.Text(guide, "small", L(key))
    fs:SetPoint("LEFT", guide, "LEFT", 12 + (i - 1) * 200, 0)
    stepTexts[i] = fs
  end

  -- tile grid (scrollable via row-list wheel on the whole grid container)
  local grid = CreateFrame("Frame", nil, frame)
  grid:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad - 40)
  grid:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad + 90)
  grid:EnableMouseWheel(true)
  local tileFrames = {}
  local offset = 0
  local TILE_H, TILE_GAP = 72, 8
  local allCandidates = {}
  for _, cand in ipairs(ns.settings.candidates) do
    allCandidates[#allCandidates + 1] = cand
  end
  for _, entry in ipairs(ns.settings.lockedEntries) do
    allCandidates[#allCandidates + 1] = entry
  end

  local refreshRunButton -- forward-declared; defined below the controls
  local refreshOverlay -- forward-declared so Run/Cancel can refresh instantly
  local tileCache = {} -- cand.id -> tile (bounded pool; review I9)

  local function rebuildTiles()
    for _, t in pairs(tileCache) do
      t:Hide()
    end
    local visible = math.floor(grid:GetHeight() / (TILE_H + TILE_GAP))
    local n = #allCandidates
    local maxOffset = math.max(0, n - visible)
    if offset > maxOffset then
      offset = maxOffset
    end
    tileFrames = {}
    for i = 1, math.min(visible, n) do
      local cand = allCandidates[offset + i]
      local tile = tileCache[cand.id]
      if not tile then
        tile = tileFor(grid, cand, function()
          if refreshRunButton then
            refreshRunButton()
          end
        end)
        tileCache[cand.id] = tile
      end
      if tile.candKey then
        local v = ns.cvarGuard.Read(tile.candKey)
        tile.valueText:SetText(Lfmt("current_value", tostring(v or "?")))
      end
      tile:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, -((i - 1) * (TILE_H + TILE_GAP)))
      tile:SetPoint("TOPRIGHT", grid, "TOPRIGHT", 0, -((i - 1) * (TILE_H + TILE_GAP)))
      tile:SetHeight(TILE_H)
      tile:Show()
      tileFrames[#tileFrames + 1] = tile
    end
  end

  grid:SetScript("OnMouseWheel", function(_, delta)
    offset = math.max(0, offset - delta)
    rebuildTiles()
  end)

  -- bottom controls: combine toggle on the top row, everything else as one
  -- right-aligned chain [est] [Quick] [Thorough] [Run Lab] on the bottom
  -- row. Before pre.3 the mode buttons and Run button overlapped (owner
  -- screenshot: Thorough drawn through Run Lab).
  local controls = CreateFrame("Frame", nil, frame)
  controls:SetHeight(72)
  controls:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pad, pad)
  controls:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)

  local combineBox = Widgets.Checkbox(controls, {
    label = L("combine_top"),
    checked = ns.db.selection["__combine__"] and true or false,
    onToggle = function(checked)
      ns.db.selection["__combine__"] = checked
      refreshRunButton()
    end,
  })
  combineBox:SetPoint("TOPLEFT", controls, "TOPLEFT", 0, -4)

  local estText = Widgets.Text(controls, "small", "")
  Skin.ColorText(estText, ns.palette.textDim)

  local mode = ns.db.settings.lab.defaultMode or "quick"
  local quickBtn, thoroughBtn
  local function applyMode()
    ns.db.settings.lab.defaultMode = mode
    Skin.ColorText(quickBtn.text, mode == "quick" and ns.palette.goldBright or ns.palette.text)
    Skin.ColorText(thoroughBtn.text, mode == "thorough" and ns.palette.goldBright or ns.palette.text)
    refreshRunButton()
  end
  quickBtn = Widgets.Button(controls, {
    small = true,
    label = L("quick"),
    onClick = function()
      mode = "quick"
      applyMode()
    end,
  })
  quickBtn:SetWidth(80)
  thoroughBtn = Widgets.Button(controls, {
    small = true,
    label = L("thorough"),
    onClick = function()
      mode = "thorough"
      applyMode()
    end,
  })
  thoroughBtn:SetWidth(130)

  local runBtn = Widgets.Button(controls, {
    label = L("run_lab"),
    primary = true,
    height = 32,
    onClick = function()
      local ok, err = ns.lab.Run(mode, ns.db.selection)
      if not ok then
        ns.ui.ShowBanner(L("err_" .. (err or "noselect")) or tostring(err), "danger", 6)
      else
        ns.ui.ShowBanner(L("banner_running"), "gold", 6)
        if refreshOverlay then
          refreshOverlay() -- cover the page now, not on the next 1 Hz tick
        end
      end
    end,
  })
  runBtn:SetWidth(160)
  runBtn:SetPoint("RIGHT", controls, "RIGHT", 0, -10)
  thoroughBtn:SetPoint("RIGHT", runBtn, "LEFT", -6, 0)
  quickBtn:SetPoint("RIGHT", thoroughBtn, "LEFT", -6, 0)
  estText:SetPoint("RIGHT", quickBtn, "LEFT", -10, 0)

  function refreshRunButton()
    local count = 0
    for _, cand in ipairs(ns.settings.testable()) do
      if ns.db.selection[cand.id] then
        count = count + 1
      end
    end
    if ns.db.selection["__combine__"] then
      count = count + 1
    end
    estText:SetText(Lfmt("est_pattern", ns.lab.EstimateSeconds(mode, count) .. " s"))
  end

  -- running overlay: opaque cover that fully blocks the page. The pre.3
  -- build let the tile grid show through and clicks pass to hidden controls
  -- (owner screenshot: Run button visible with Cancel floating on top).
  local overlay = CreateFrame("Frame", nil, frame)
  overlay:SetAllPoints(frame)
  overlay:SetFrameLevel(frame:GetFrameLevel() + 10)
  overlay:EnableMouse(true)
  Skin.ApplyPanel(overlay, { base = ns.palette.obsidian, alpha = 0.96, vignette = true })
  overlay:Hide()
  local ring = Widgets.Ring(overlay, 64)
  ring:SetPoint("TOP", overlay, "TOP", 0, -60)
  local phaseText = Widgets.Text(overlay, "header", "")
  phaseText:SetPoint("TOP", ring, "BOTTOM", 0, -12)
  local stepText = Widgets.Text(overlay, "body", "")
  stepText:SetPoint("TOP", phaseText, "BOTTOM", 0, -6)
  local liveFpsText = Widgets.Text(overlay, "number", "")
  liveFpsText:SetPoint("TOP", stepText, "BOTTOM", 0, -12)
  local passText = Widgets.Text(overlay, "small", "")
  passText:SetPoint("TOP", liveFpsText, "BOTTOM", 0, -6)
  local cancelBtn = Widgets.Button(overlay, {
    label = L("cancel_test"),
    primary = true,
    height = 32,
    onClick = function()
      ns.lab.Cancel()
      if refreshOverlay then
        refreshOverlay()
      end
      ns.ui.ShowBanner(L("err_cancelled"), "gold", 6)
    end,
  })
  cancelBtn:SetWidth(160)
  cancelBtn:SetPoint("BOTTOM", overlay, "BOTTOM", 0, 16)

  local combatBanner = Widgets.Text(overlay, "header", L("err_combat"))
  combatBanner:SetPoint("BOTTOM", cancelBtn, "TOP", 0, 12)
  Skin.ColorText(combatBanner, ns.palette.danger)
  combatBanner:Hide()

  local PHASE_KEYS = {
    sample = "phase_sample",
    settle = "phase_settle",
    applying = "phase_applying",
    restoring = "phase_restoring",
  }
  local lastRunId = ns.db.lastRunId or 0
  local lastCompleted = ns.lab.completedAt
  local lastPhase = nil
  local lastSeenError = nil

  refreshOverlay = function()
    local running = ns.lab.IsRunning()
    overlay:SetShown(running)
    if not running then
      lastPhase = nil
      return
    end
    local p = ns.lab.Progress()
    phaseText:SetText(L(PHASE_KEYS[p.phase] or "") or p.phase)
    local label = p.labelKey and L(p.labelKey) or "?"
    stepText:SetText(Lfmt("step_pattern", p.jobIndex, p.jobCount, label))
    if p.passes > 1 then
      passText:SetText(Lfmt("pass_pattern", p.pass, p.passes))
    else
      passText:SetText("")
    end
    liveFpsText:SetText(string.format("%.0f FPS", ns.meter.live.fps or 0))
    combatBanner:SetShown(InCombatLockdown())
    if p.phase ~= lastPhase then
      lastPhase = p.phase
      local lab = ns.db.settings.lab
      if p.phase == "sample" then
        ring:Start(lab.sampleSeconds or 8)
      elseif p.phase == "settle" then
        ring:Start(lab.settleSeconds or 3)
      else
        ring:Stop()
      end
    end
    ring:UpdateFallback()
  end

  local function refreshGuide()
    local step
    if ns.lab.IsRunning() then
      step = 3
    elseif (ns.db.results and #ns.db.results > 0) then
      step = 4
    else
      step = 2
    end
    for i = 1, 4 do
      Skin.ColorText(stepTexts[i], i == step and ns.palette.goldBright or ns.palette.textDim)
    end
  end

  frame:SetScript("OnShow", function()
    rebuildTiles()
    refreshRunButton()
    applyMode()
    refreshGuide()
    refreshOverlay()
  end)
  frame.refresh = function()
    refreshOverlay()
    refreshGuide()
    -- surface a silent abort (combat/instance/foreign) as a banner (I2)
    local err = ns.lab.lastError
    if not ns.lab.IsRunning() and err and err ~= lastSeenError then
      lastSeenError = err
      local key = "err_" .. (err.key or "?")
      ns.ui.ShowBanner(L(key) or tostring(err.key), "danger", 8)
    end
    if not ns.lab.IsRunning() and ns.lab.completedAt and ns.lab.completedAt ~= lastCompleted then
      lastCompleted = ns.lab.completedAt
      lastSeenError = nil
      ns.ui.ShowBanner(L("lab_done"), "gainColor", 8)
      ns.ui.SwitchPage(3) -- Results (review I10)
    end
  end
  return frame
end

ns.ui.RegisterPage({
  index = 2,
  name = L("page_lab"),
  icon = "icon_lab.tga",
  create = create,
  onTick = function(page)
    if page and page.refresh then
      page.refresh()
    end
  end,
})
