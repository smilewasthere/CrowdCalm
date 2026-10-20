-- UI/Pages/Overview.lua — three hero cards, the 5-minute sparkline, and the
-- top-3 from the last lab run (brief section 6.1). Ticks once per second
-- while visible; the sparkline has its own 1 s ticker (Widgets.Sparkline).
local ADDON_NAME, ns = ...

local Widgets = ns.widgets
local Skin = ns.skin
local L = ns.L
local Lfmt = ns.Lfmt

local function heroCard(parent, width, titleKey)
  local card = Widgets.Panel(parent, { base = ns.palette.raised, borderAlpha = 0.6, vignette = true, vignetteAlpha = 0.25 })
  card:SetSize(width, 120)
  -- pre.6: gold accent strip along the top edge (accent.tga fades right)
  local accent = card:CreateTexture(nil, "ARTWORK")
  accent:SetTexture(Skin.mediaPath .. "accent.tga")
  accent:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
  accent:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
  accent:SetHeight(3)
  local gold = ns.palette.gold
  accent:SetVertexColor(gold.r, gold.g, gold.b, 0.95)
  local title = Widgets.Text(card, "small", L(titleKey))
  title:SetPoint("TOPLEFT", 12, -10)
  Skin.ColorText(title, ns.palette.textDim)
  card.title = title
  local big = Widgets.Text(card, "numberBig", "—")
  big:SetPoint("TOPLEFT", 12, -32)
  Skin.ColorText(big, ns.palette.text)
  card.big = big
  card.lines = {}
  return card
end

local function addCardLine(card, textKey)
  local fs = Widgets.Text(card, "small", L(textKey) .. ": —")
  fs:SetPoint("BOTTOMLEFT", 12, 10 + #card.lines * 14)
  card.lines[#card.lines + 1] = fs
  return fs
end

local function create(parent)
  local frame = parent
  local pad = 12
  local cardW = math.floor((parent:GetWidth() - pad * 2 - 24) / 3)

  local fpsCard = heroCard(frame, cardW, "hero_fps_title")
  fpsCard:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
  local l50 = addCardLine(fpsCard, "low50")
  local l100 = addCardLine(fpsCard, "low100")

  local frameCard = heroCard(frame, cardW, "hero_frame_title")
  frameCard:SetPoint("TOPLEFT", fpsCard, "TOPRIGHT", 12, 0)
  local lms = addCardLine(frameCard, "frame_ms")
  local lp5 = addCardLine(frameCard, "p5_label")

  local crowdCard = heroCard(frame, cardW, "hero_crowd_title")
  crowdCard:SetPoint("TOPLEFT", frameCard, "TOPRIGHT", 12, 0)
  -- pre.7: soft glow behind the dome (created before the gauge so the arc
  -- draws over it); tint follows the ramp color each refresh
  local gaugeGlow = crowdCard:CreateTexture(nil, "ARTWORK")
  gaugeGlow:SetTexture(Skin.mediaPath .. "glow.tga")
  gaugeGlow:SetSize(156, 88)
  gaugeGlow:SetPoint("BOTTOM", crowdCard, "BOTTOM", 0, 2)
  local gauge = Widgets.ArcGauge(crowdCard, 130)
  gauge:SetPoint("BOTTOM", crowdCard, "BOTTOM", 0, 6)
  -- Quiet/Packed end labels sit in the two empty corners of the
  -- semicircle rect, beside the dome, never on the band
  local qLab = Widgets.Text(crowdCard, "small", L("crowd_quiet"))
  qLab:SetPoint("TOPLEFT", gauge, "TOPLEFT", 2, -1)
  Skin.ColorText(qLab, ns.palette.textDim)
  local pLab = Widgets.Text(crowdCard, "small", L("crowd_packed"))
  pLab:SetPoint("TOPRIGHT", gauge, "TOPRIGHT", -2, -1)
  Skin.ColorText(pLab, ns.palette.textDim)
  -- pre.6: pivot pip at the arc's baseline center + a crowd word readout
  -- inside the dome, tinted with the active ramp color (pre.7: the zone
  -- line was removed from this card on the owner's request)
  local pip = crowdCard:CreateTexture(nil, "ARTWORK")
  pip:SetTexture(Skin.mediaPath .. "gauge_pip.tga")
  pip:SetSize(10, 10)
  pip:SetPoint("CENTER", gauge, "BOTTOM", 0, 0)
  local readout = Widgets.Text(crowdCard, "header", "")
  readout:SetPoint("BOTTOM", gauge, "BOTTOM", 0, 7)
  readout:SetJustifyH("CENTER")
  crowdCard.readout = readout
  crowdCard.pip = pip
  local whyBtn = Widgets.Button(crowdCard, {
    label = L("crowd_why"),
    small = true,
    onClick = function()
      -- cycle through signal notes in the tooltip on demand; the tooltip
      -- itself carries the live values
      ns.util.LogInfo(table.concat((function()
        local out = {}
        for _, s in ipairs(ns.context.FillSignals()) do
          out[#out + 1] = s.label .. ": " .. tostring(s.value) .. " (" .. s.reliability .. ")"
        end
        return out
      end)(), " | "))
    end,
  })
  whyBtn:SetWidth(56)
  whyBtn:SetHeight(20)
  whyBtn:SetPoint("TOPRIGHT", crowdCard, "TOPRIGHT", -8, -8)
  Widgets.TooltipLines(whyBtn, function()
    local lines = {}
    for _, s in ipairs(ns.context.FillSignals()) do
      lines[#lines + 1] = { text = s.label .. ": " .. tostring(s.value), r = ns.palette.text.r, g = ns.palette.text.g, b = ns.palette.text.b }
      if s.note then
        lines[#lines + 1] = L(s.note)
      end
    end
    return lines
  end)
  Widgets.TooltipLines(gauge, function()
    local label = ns.context.Label()
    return {
      L("crowd_" .. label) or label,
      "Quiet = few players nearby, Packed = nameplate-heavy crowds.",
      L("crowd_nameplates_off"),
    }
  end)

  local sparkTitle = Widgets.Text(frame, "small", L("sparkline_title"))
  sparkTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad - 132)
  local spark = Widgets.Sparkline(frame, parent:GetWidth() - pad * 2, 110, 120)
  spark:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad - 150)

  local topTitle = Widgets.Text(frame, "small", L("last_run_top3"))
  topTitle:SetPoint("TOPLEFT", spark, "BOTTOMLEFT", 0, -16)
  -- pre.6: each last-run row is label | proportional gain bar | value
  local rowW = math.floor(parent:GetWidth() - pad * 2 - 8)
  local labelW = math.floor(rowW * 0.5)
  local valueW = 90
  -- pre.7: the track/fill width is computed from the layout numbers, not
  -- queried from the texture (a 0 px read during the first refresh left the
  -- fill at its 1 px fallback)
  local trackW = rowW - (labelW + 10) - (valueW + 10)
  local topRows = {}
  for i = 1, 3 do
    local row = CreateFrame("Frame", nil, frame)
    row:SetHeight(16)
    row:SetWidth(rowW)
    row:SetPoint("TOPLEFT", topTitle, "BOTTOMLEFT", 8, -6 - (i - 1) * 22)
    local label = Widgets.Text(row, "body", "")
    label:SetPoint("LEFT", row, "LEFT", 0, 0)
    label:SetWidth(labelW)
    label:SetWordWrap(false)
    local value = Widgets.Text(row, "body", "")
    value:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    value:SetWidth(valueW)
    value:SetJustifyH("RIGHT")
    local track = row:CreateTexture(nil, "ARTWORK")
    track:SetTexture(Skin.mediaPath .. "bar_track.tga")
    track:SetPoint("TOPLEFT", row, "TOPLEFT", labelW + 10, -4)
    track:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -(valueW + 10), 4)
    local fill = row:CreateTexture(nil, "OVERLAY")
    fill:SetTexture(Skin.mediaPath .. "bar_fill.tga")
    fill:SetPoint("LEFT", track, "LEFT", 0, 0)
    fill:SetPoint("TOP", track, "TOP", 0, 0)
    fill:SetPoint("BOTTOM", track, "BOTTOM", 0, 0)
    fill:SetWidth(1)
    topRows[i] = { row = row, label = label, value = value, track = track, fill = fill }
  end

  local CROWD_VALUES = { quiet = 0.25, busy = 0.6, packed = 0.95 }
  local prev = { fps = 0, d50 = 0, d100 = 0, frameMs = 0, p5 = 0 }

  local function refresh()
    local live = ns.meter.live
    Widgets.CountUp(fpsCard.big, prev.fps, live.fps, 400, "%.0f FPS")
    prev.fps = live.fps
    l50:SetText(L("low50") .. ": " .. string.format("%.1f", live.d50pm))
    l100:SetText(L("low100") .. ": " .. string.format("%.1f", live.d100pm))
    Widgets.CountUp(frameCard.big, prev.frameMs, live.frameMs, 400, "%.1f ms")
    prev.frameMs = live.frameMs
    local snap = ns.stats.Snapshot()
    lms:SetText(L("frame_ms") .. ": " .. string.format("%.1f", live.frameMs))
    lp5:SetText(L("p5_label") .. ": " .. string.format("%.0f", snap.p5))
    ns.context.Update()
    local label = ns.context.Label()
    local rv = CROWD_VALUES[label] or 0.25
    gauge:SetValue(rv)
    -- pre.6: readout word + pip share the gauge's active ramp color
    local rc = rv < 0.425 and ns.palette.gainColor()
      or (rv < 0.775 and ns.palette.gold or ns.palette.costColor())
    readout:SetText(L("crowd_" .. label) or label)
    Skin.ColorText(readout, rc)
    pip:SetVertexColor(rc.r, rc.g, rc.b, 1)
    gaugeGlow:SetVertexColor(rc.r, rc.g, rc.b, 0.15)

    local run = ns.db.results and ns.db.results[#ns.db.results]
    local sorted = {}
    if run and run.rows then
      for _, row in ipairs(run.rows) do
        if not row.notTestable and row.gain then
          sorted[#sorted + 1] = row
        end
      end
      table.sort(sorted, function(a, b)
        return a.gain > b.gain
      end)
    end
    local maxAbs = 0.01
    for _, r in ipairs(sorted) do
      local ag = math.abs(r.gain)
      if ag > maxAbs then
        maxAbs = ag
      end
    end
    for i = 1, 3 do
      local tr = topRows[i]
      local row = sorted[i]
      if not run then
        tr.label:SetText(i == 1 and L("no_runs") or "")
        tr.value:SetText("")
        tr.track:Hide()
        tr.fill:Hide()
      elseif row then
        local name = L(row.labelKey or row.key or "?")
        tr.label:SetText(name)
        tr.value:SetFormattedText("%+.1f FPS", row.gain)
        tr.track:Show()
        tr.fill:Show()
        local ratio = math.min(1, math.abs(row.gain) / maxAbs)
        tr.fill:SetWidth(math.max(2, math.floor(trackW * ratio)))
        local c = row.gain >= 0 and ns.palette.gainColor() or ns.palette.costColor()
        tr.fill:SetVertexColor(c.r, c.g, c.b, 0.95)
      else
        tr.label:SetText("")
        tr.value:SetText("")
        tr.track:Hide()
        tr.fill:Hide()
      end
    end
  end

  frame:SetScript("OnShow", function()
    spark:Play()
    refresh()
  end)
  frame:SetScript("OnHide", function()
    spark:Stop()
  end)
  frame.refresh = refresh
  return frame
end

ns.ui.RegisterPage({
  index = 1,
  name = L("page_overview"),
  icon = "icon_overview.tga",
  create = create,
  onTick = function(page)
    if page and page.refresh then
      page.refresh()
    end
  end,
})
