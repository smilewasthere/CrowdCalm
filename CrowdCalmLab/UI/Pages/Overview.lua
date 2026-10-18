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
  local gauge = Widgets.ArcGauge(crowdCard, 150)
  gauge:SetPoint("BOTTOM", crowdCard, "BOTTOM", 0, 8)
  local zoneText = Widgets.Text(crowdCard, "small", "")
  zoneText:SetPoint("TOP", crowdCard.title, "BOTTOM", 0, -6)
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
  local topLines = {}
  for i = 1, 3 do
    topLines[i] = Widgets.Text(frame, "body", "")
    topLines[i]:SetPoint("TOPLEFT", topTitle, "BOTTOMLEFT", 8, -6 - (i - 1) * 18)
  end

  local CROWD_VALUES = { quiet = 0.25, busy = 0.6, packed = 0.95 }
  local prev = { fps = 0, d50 = 0, d100 = 0, frameMs = 0, p5 = 0 }

  local function refresh()
    local live = ns.meter.live
    Widgets.CountUp(fpsCard.big, prev.fps, live.fps, 400, "%.0f")
    prev.fps = live.fps
    l50:SetText(L("low50") .. ": " .. string.format("%.1f", live.d50pm))
    l100:SetText(L("low100") .. ": " .. string.format("%.1f", live.d100pm))
    Widgets.CountUp(frameCard.big, prev.frameMs, live.frameMs, 400, "%.1f")
    prev.frameMs = live.frameMs
    local snap = ns.stats.Snapshot()
    lms:SetText(L("frame_ms") .. ": " .. string.format("%.1f", live.frameMs))
    lp5:SetText(L("p5_label") .. ": " .. string.format("%.0f", snap.p5))
    ns.context.Update()
    local label = ns.context.Label()
    gauge:SetValue(CROWD_VALUES[label] or 0.25)
    local zone = ns.context.Zone()
    local sub = ns.context.SubZone()
    if sub ~= "" then
      zone = zone .. " / " .. sub
    end
    zoneText:SetText(zone)
    Skin.ColorText(zoneText, ns.palette.textDim)

    local run = ns.db.results and ns.db.results[#ns.db.results]
    for i = 1, 3 do
      local text = ""
      if run and run.rows then
        local sorted = {}
        for _, row in ipairs(run.rows) do
          if not row.notTestable and row.gain then
            sorted[#sorted + 1] = row
          end
        end
        table.sort(sorted, function(a, b)
          return a.gain > b.gain
        end)
        local row = sorted[i]
        if row then
          text = string.format("%s  %+.1f FPS", L(row.labelKey or row.key or "?"), row.gain)
        end
      end
      topLines[i]:SetText(text)
    end
    if not run then
      topLines[1]:SetText(L("no_runs"))
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
