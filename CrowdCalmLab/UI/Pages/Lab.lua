-- UI/Pages/Lab.lua — guided strip (pre.7: numbered badge chips), setting-
-- tile grid, Run controls (pre.7: Big step toggle), running overlay with
-- cancel (brief section 6.2, pre.7: 15 s prewarm phase, no pre-run cap
-- advisory). Selection is stored in db.selection[id]; the combine toggle
-- uses the reserved id "__combine__".
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
  -- pre.6: selected tiles wear a gold top accent (accent.tga, fades right);
  -- the selection refresh below keeps it in sync after "Test only" too
  local accent = card:CreateTexture(nil, "ARTWORK")
  accent:SetTexture(Skin.mediaPath .. "accent.tga")
  accent:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
  accent:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
  accent:SetHeight(3)
  local gold = ns.palette.gold
  accent:SetVertexColor(gold.r, gold.g, gold.b, 0.95)
  accent:SetShown(not locked and ns.db.selection[cand.id] and true or false)
  card.accent = accent

  local box
  if not locked then
    box = Widgets.Checkbox(card, {
      checked = ns.db.selection[cand.id] and true or false,
      onToggle = function(checked)
        ns.db.selection[cand.id] = checked
        accent:SetShown(checked)
        if onSelectionChanged then
          onSelectionChanged()
        end
      end,
    })
    box:SetPoint("TOPLEFT", 8, -8)
    card.box = box
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

  -- guided strip (pre.7 restyle: numbered badge chips; labels dropped the
  -- leading "N." so four chips fit the 696 px strip — layout follows the
  -- real text widths instead of a fixed 200 px pitch)
  local guide = Widgets.Panel(frame, { base = ns.palette.obsidian, borderAlpha = 0.4 })
  guide:SetHeight(28)
  guide:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
  guide:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad)
  local stepChips = {}
  local x = 12
  for i, key in ipairs({ "guide_stand", "guide_pick", "guide_run", "guide_read" }) do
    local badge = guide:CreateTexture(nil, "ARTWORK")
    badge:SetSize(16, 16)
    badge:SetPoint("LEFT", guide, "LEFT", x, 0)
    local num = Widgets.Text(guide, "small", tostring(i))
    num:SetPoint("CENTER", badge, "CENTER", 0, 0)
    local fs = Widgets.Text(guide, "small", L(key))
    fs:SetPoint("LEFT", badge, "RIGHT", 6, 0)
    stepChips[i] = { badge = badge, num = num, text = fs }
    x = x + 16 + 6 + (fs:GetStringWidth() or 60) + 26
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
  local combineBox -- forward-declared; syncTileVisuals keeps its face truthful
  local tileCache = {} -- cand.id -> tile (bounded pool; review I9)
  local COLS = 2 -- pre.6: two tiles per row

  -- pre.6: one refresh keeps every checkbox and accent strip truthful after
  -- any programmatic selection change ("Test only" flips the whole grid,
  -- including the combine toggle, which lives outside the tile cache)
  local function syncTileVisuals()
    for id, tile in pairs(tileCache) do
      local sel = ns.db.selection[id] and true or false
      if tile.box then
        tile.box:SetChecked(sel)
      end
      if tile.accent then
        tile.accent:SetShown(sel)
      end
    end
    if combineBox then
      combineBox:SetChecked(ns.db.selection["__combine__"] and true or false)
    end
  end

  local function rebuildTiles()
    for _, t in pairs(tileCache) do
      t:Hide()
    end
    local gapX = 8
    local tileW = math.floor((grid:GetWidth() - gapX * (COLS - 1)) / COLS)
    local rows = math.floor(grid:GetHeight() / (TILE_H + TILE_GAP))
    local visible = rows * COLS
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
          syncTileVisuals()
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
      local col = (i - 1) % COLS
      local rowi = math.floor((i - 1) / COLS)
      tile:ClearAllPoints()
      tile:SetPoint(
        "TOPLEFT",
        grid,
        "TOPLEFT",
        col * (tileW + gapX),
        -(rowi * (TILE_H + TILE_GAP))
      )
      tile:SetWidth(tileW)
      tile:SetHeight(TILE_H)
      tile:Show()
      tileFrames[#tileFrames + 1] = tile
    end
  end

  grid:SetScript("OnMouseWheel", function(_, delta)
    -- pre.6: whole rows at a time (two tiles per notch)
    offset = math.max(0, offset - delta * COLS)
    rebuildTiles()
  end)

  -- bottom controls: pre.6 wraps the whole area in a visible strip —
  -- combine toggle on the top row (left), estimate + joined Quick/
  -- Thorough segmented control + Run on the bottom row (right).
  local controls = CreateFrame("Frame", nil, frame)
  controls:SetHeight(72)
  controls:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pad, pad)
  controls:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
  local controlsBg = Widgets.Panel(controls, { base = ns.palette.obsidian, borderAlpha = 0.45 })
  controlsBg:SetAllPoints(controls)

  combineBox = Widgets.Checkbox(controls, {
    label = L("combine_top"),
    checked = ns.db.selection["__combine__"] and true or false,
    onToggle = function(checked)
      ns.db.selection["__combine__"] = checked
      refreshRunButton()
    end,
  })
  combineBox:SetPoint("TOPLEFT", controls, "TOPLEFT", 8, -4)

  -- pre.7: remembered Big step toggle (owner item 3) — every setting jumps
  -- to its lowest value (Body Quota at half) to show whether it matters at all
  local bigBox = Widgets.Checkbox(controls, {
    label = L("big_step"),
    checked = ns.db.settings.lab.bigStep and true or false,
    onToggle = function(checked)
      ns.db.settings.lab.bigStep = checked and true or false
    end,
  })
  bigBox:SetPoint("LEFT", combineBox, "RIGHT", 20, 0)
  Widgets.TooltipLines(bigBox, function()
    return { L("big_step_hint") }
  end)

  local estText = Widgets.Text(controls, "small", "")
  Skin.ColorText(estText, ns.palette.textDim)

  local mode = ns.db.settings.lab.defaultMode or "quick"
  local quickBtn, thoroughBtn
  local function applyMode()
    ns.db.settings.lab.defaultMode = mode
    -- segmented look (pre.4): active mode wears the gold face, inactive
    -- stays on the dark gradient; pre.6 both sit in one joined strip
    Skin.SetButtonPrimary(quickBtn, mode == "quick")
    Skin.SetButtonPrimary(thoroughBtn, mode == "thorough")
    refreshRunButton()
  end

  local runBtn = Widgets.Button(controls, {
    label = L("run_lab"),
    primary = true,
    height = 32,
    onClick = function()
      local ok, err = ns.lab.Run(mode, ns.db.selection)
      if not ok then
        ns.ui.ShowBanner(L("err_" .. (err or "noselect")) or tostring(err), "danger", 6)
      else
        -- pre.7: no pre-run cap banner — the warning is decided after the
        -- run against the measured FPS (Results + completion banner)
        ns.ui.ShowBanner(L("banner_running"), "gold", 6)
        if refreshOverlay then
          refreshOverlay() -- cover the page now, not on the next 1 Hz tick
        end
      end
    end,
  })
  runBtn:SetWidth(160)
  runBtn:SetPoint("RIGHT", controls, "RIGHT", -8, -10)

  -- joined segmented control: one backing strip, no gap; the buttons
  -- overlap by 1 px so their 1 px edges read as a single divider
  local modeStrip = Widgets.Panel(controls, { base = ns.palette.obsidian, borderAlpha = 0.5 })
  modeStrip:SetSize(80 + 130 - 1, 30)
  modeStrip:SetPoint("RIGHT", runBtn, "LEFT", -12, 0)

  quickBtn = Widgets.Button(modeStrip, {
    small = true,
    label = L("quick"),
    onClick = function()
      mode = "quick"
      applyMode()
    end,
  })
  quickBtn:SetSize(80, 28)
  quickBtn:SetPoint("TOPLEFT", modeStrip, "TOPLEFT", 0, -1)
  thoroughBtn = Widgets.Button(modeStrip, {
    small = true,
    label = L("thorough"),
    onClick = function()
      mode = "thorough"
      applyMode()
    end,
  })
  thoroughBtn:SetSize(130, 28)
  thoroughBtn:SetPoint("TOPLEFT", quickBtn, "TOPRIGHT", -1, 0)

  estText:SetPoint("RIGHT", modeStrip, "LEFT", -12, 0)

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
  -- pre.6: soft glow behind the ring (created first, so the ring draws
  -- over it); tint follows the active phase in refreshOverlay
  local ringGlow = overlay:CreateTexture(nil, "ARTWORK")
  ringGlow:SetTexture(Skin.mediaPath .. "glow.tga")
  ringGlow:SetSize(170, 170)
  ringGlow:SetPoint("TOP", overlay, "TOP", 0, -7) -- center lands on the ring
  local gold = ns.palette.gold
  ringGlow:SetVertexColor(gold.r, gold.g, gold.b, 0.16)
  local ring = Widgets.Ring(overlay, 64)
  ring:SetPoint("TOP", overlay, "TOP", 0, -60)
  local countdown = Widgets.Text(overlay, "number", "")
  countdown:SetPoint("CENTER", ring, "CENTER", 0, 0)
  countdown:SetJustifyH("CENTER")
  local phaseText = Widgets.Text(overlay, "header", "")
  phaseText:SetPoint("TOP", ring, "BOTTOM", 0, -12)
  local stepText = Widgets.Text(overlay, "body", "")
  stepText:SetPoint("TOP", phaseText, "BOTTOM", 0, -6)
  local liveFpsText = Widgets.Text(overlay, "number", "")
  liveFpsText:SetPoint("TOP", stepText, "BOTTOM", 0, -12)
  local passText = Widgets.Text(overlay, "small", "")
  passText:SetPoint("TOP", liveFpsText, "BOTTOM", 0, -6)
  -- pre.5/7: one persistent advisory line (owner request: keep still during
  -- the run). The pre-run cap advisory moved out of the overlay — cap
  -- warnings are a post-run verdict now (Results + completion banner).
  local keepStillText = Widgets.Text(overlay, "small", L("overlay_keep_still"))
  keepStillText:SetPoint("TOP", passText, "BOTTOM", 0, -10)
  keepStillText:SetJustifyH("CENTER")
  Skin.ColorText(keepStillText, ns.palette.textDim)
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
    prewarm = "phase_prewarm",
    sample = "phase_sample",
    settle = "phase_settle",
    warmup = "phase_warmup",
    applying = "phase_applying",
    restoring = "phase_restoring",
  }
  -- pre.6: headline + glow color per phase (measuring = gold, waiting = dim)
  local PHASE_TINT = {
    prewarm = ns.palette.textDim,
    sample = ns.palette.goldBright,
    settle = ns.palette.textDim,
    warmup = ns.palette.textDim,
    applying = ns.palette.gold,
    restoring = ns.palette.gold,
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
      countdown:SetText("")
      return
    end
    local p = ns.lab.Progress()
    phaseText:SetText(L(PHASE_KEYS[p.phase] or "") or p.phase)
    if p.phase == "prewarm" then
      -- pre-roll: no job step or pass line yet (the crowd is settling)
      stepText:SetText("")
      passText:SetText("")
    else
      local label = p.labelKey and L(p.labelKey) or "?"
      stepText:SetText(Lfmt("step_pattern", p.jobIndex, p.jobCount, label))
      if p.passes > 1 then
        passText:SetText(Lfmt("pass_pattern", p.pass, p.passes))
      else
        passText:SetText("")
      end
    end
    liveFpsText:SetText(string.format("%.0f FPS", ns.meter.live.fps or 0))
    combatBanner:SetShown(InCombatLockdown())
    if p.phase ~= lastPhase then
      lastPhase = p.phase
      local tint = PHASE_TINT[p.phase] or ns.palette.gold
      Skin.ColorText(phaseText, tint)
      ringGlow:SetVertexColor(tint.r, tint.g, tint.b, 0.18)
      local lab = ns.db.settings.lab
      if p.phase == "prewarm" then
        ring:Start(15) -- pre.7: 15 s warm-up before the first baseline
      elseif p.phase == "sample" then
        ring:Start(lab.sampleSeconds or 8)
      elseif p.phase == "settle" then
        ring:Start(lab.settleSeconds or 6)
      elseif p.phase == "warmup" then
        ring:Start(lab.ignoreSeconds or 4)
      else
        ring:Stop()
      end
    end
    ring:UpdateFallback()
    -- pre.6: seconds remaining inside the ring (1 Hz refresh)
    if ring.duration and ring.startedAt then
      local left = ring.duration - (GetTime() - ring.startedAt)
      if left < 0 then
        left = 0
      end
      countdown:SetFormattedText("%d", math.ceil(left))
    else
      countdown:SetText("")
    end
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
    local colors = ns.palette
    for i = 1, 4 do
      local chip = stepChips[i]
      local isDone = i < step
      local isActive = i == step
      local fill = isActive and colors.gold or isDone and colors.gainColor() or colors.raised
      chip.badge:SetColorTexture(fill.r, fill.g, fill.b, 1)
      Skin.ColorText(chip.num, (isActive or isDone) and colors.obsidian or colors.textDim)
      Skin.ColorText(
        chip.text,
        isActive and colors.goldBright or isDone and colors.text or colors.textDim
      )
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
      -- pre.7: a failed restore outranks a capped run, which outranks done
      local r = ns.lab.lastRun
      if r and r.restoreFailed then
        ns.ui.ShowBanner(L("restore_failed_banner"), "danger", 10)
      elseif r and r.caps and r.caps.limited then
        ns.ui.ShowBanner(L("cap_banner_limited"), "costColor", 8)
      else
        ns.ui.ShowBanner(L("lab_done"), "gainColor", 8)
      end
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
