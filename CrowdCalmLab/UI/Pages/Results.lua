-- UI/Pages/Results.lua — ranked cards from the latest run (brief section
-- 6.3): dual teal/amber bars, before/after, Best medal, confidence badge,
-- one plain sentence, and a disabled "Apply as crowd profile" panel.
local ADDON_NAME, ns = ...

local Widgets = ns.widgets
local Skin = ns.skin
local L = ns.L
local Lfmt = ns.Lfmt

local function rowCard(parent, row, isBest)
  local card = Widgets.Panel(parent, { base = ns.palette.raised, borderAlpha = 0.5 })
  card:SetHeight(row.notTestable and 44 or 86)

  local name = Widgets.Text(card, "body", L(row.labelKey or row.key or "?"))
  name:SetPoint("TOPLEFT", 12, -10)
  if isBest and row.gain then
    local medal = Widgets.Text(card, "small", L("best"))
    medal:SetPoint("LEFT", name, "RIGHT", 10, 0)
    Skin.ColorText(medal, ns.palette.goldBright)
  end

  if row.notTestable then
    local reason = row.reason == "unreadable" and L("reason_unreadable")
      or row.reason == "already-lowest" and L("reason_already_lowest")
      or Lfmt("reason_failed", tostring(row.reason or "?"))
    local fs = Widgets.Text(card, "small", L("not_testable") .. " — " .. reason)
    fs:SetPoint("LEFT", name, "RIGHT", 16, 0)
    Skin.ColorText(fs, ns.palette.textDim)
    return card
  end

  local sentence
  if row.gain and row.gain > 0.5 then
    sentence = Lfmt("results_sentence_gain", L(row.labelKey or "?"), row.gain)
  else
    sentence = Lfmt("results_sentence_none", L(row.labelKey or "?"))
  end
  local sentenceFs = Widgets.Text(card, "small", sentence)
  sentenceFs:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)

  local beforeAfter = Widgets.Text(card, "small", Lfmt("before_after", row.before or 0, row.after or 0))
  beforeAfter:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 12, 10)

  local conf = Widgets.Text(card, "small", L("confidence") .. ": " .. (row.confidence or "?"))
  conf:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -12, 10)
  Skin.ColorText(conf, row.noisy and ns.palette.costColor() or ns.palette.gainColor())

  -- dual bar: before (amber-ish dim) vs after (gain)
  local barBg = card:CreateTexture(nil, "ARTWORK")
  barBg:SetHeight(8)
  barBg:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 12, 32)
  barBg:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -12, 32)
  barBg:SetColorTexture(ns.palette.obsidian.r, ns.palette.obsidian.g, ns.palette.obsidian.b, 1)
  local maxV = math.max(row.before or 0, row.after or 0, 1)
  local beforeBar = card:CreateTexture(nil, "OVERLAY")
  beforeBar:SetHeight(8)
  beforeBar:SetPoint("LEFT", barBg, "LEFT", 0, 0)
  beforeBar:SetWidth(math.floor(((row.before or 0) / maxV) * barBg:GetWidth()))
  local cost = ns.palette.costColor()
  beforeBar:SetColorTexture(cost.r, cost.g, cost.b, 0.8)
  local afterBar = card:CreateTexture(nil, "OVERLAY")
  afterBar:SetHeight(4)
  afterBar:SetPoint("BOTTOMLEFT", barBg, "BOTTOMLEFT", 0, -6)
  afterBar:SetWidth(math.floor(((row.after or 0) / maxV) * barBg:GetWidth()))
  local gain = ns.palette.gainColor()
  afterBar:SetColorTexture(gain.r, gain.g, gain.b, 1)

  if row.noisy then
    local note = Widgets.Text(card, "small", L("noisy_note"))
    note:SetPoint("RIGHT", card, "RIGHT", -12, -12)
    Skin.ColorText(note, ns.palette.costColor())
  elseif row.hitch then
    local note = Widgets.Text(card, "small", L("hitch_note"))
    note:SetPoint("RIGHT", card, "RIGHT", -12, -12)
    Skin.ColorText(note, ns.palette.danger)
  end
  return card
end

local function create(parent)
  local frame = CreateFrame("Frame", nil, parent)
  local pad = 12

  local runHeader = Widgets.Text(frame, "header", "")
  runHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)

  local list = CreateFrame("Frame", nil, frame)
  list:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad - 28)
  list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad + 48)
  list:EnableMouseWheel(true)
  local cards = {}
  local offset = 0
  local sortedRows = {}

  local function rebuild()
    for _, c in ipairs(cards) do
      c:Hide()
    end
    cards = {}
    local y = 0
    local visibleBottom = list:GetHeight()
    for i = 1 + offset, #sortedRows do
      if y > visibleBottom then
        break
      end
      local row = sortedRows[i]
      local card = rowCard(list, row, i == 1 and row.gain and row.gain > 0.5)
      card:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -y)
      card:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -y)
      card:Show()
      cards[#cards + 1] = card
      y = y + card:GetHeight() + 8
    end
  end

  list:SetScript("OnMouseWheel", function(_, delta)
    offset = math.max(0, math.min(offset - delta, math.max(0, #sortedRows - 3)))
    rebuild()
  end)

  local applyBtn = Widgets.Button(frame, {
    label = L("apply_coming"),
    small = true,
    onClick = function() end,
  })
  applyBtn:SetWidth(240)
  applyBtn:Disable()
  applyBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
  Skin.ColorText(applyBtn.text, ns.palette.textDim)

  local empty = Widgets.EmptyState(frame, L("results_empty"))
  empty:Hide()

  local function refresh()
    local run = ns.db.results and ns.db.results[#ns.db.results]
    sortedRows = {}
    if run and run.rows then
      for _, row in ipairs(run.rows) do
        sortedRows[#sortedRows + 1] = row
      end
      table.sort(sortedRows, function(a, b)
        local ga = a.gain or -999
        local gb = b.gain or -999
        return ga > gb
      end)
    end
    if #sortedRows == 0 then
      empty:Show()
      runHeader:SetText("")
      applyBtn:Disable()
      return
    end
    empty:Hide()
    applyBtn:Enable()
    local zone = (run.zone or "?")
    if run.subzone and run.subzone ~= "" then
      zone = zone .. " / " .. run.subzone
    end
    runHeader:SetText(Lfmt("zone_pattern", zone, L("crowd_" .. (run.crowd or "quiet")) or "?"))
    offset = 0
    rebuild()
  end

  frame:SetScript("OnShow", refresh)
  frame.refresh = refresh
  return frame
end

ns.ui.RegisterPage({
  index = 3,
  name = L("page_results"),
  icon = "icon_results.tga",
  create = create,
  onTick = function(page)
    -- results are static between runs; refresh only when a run completed
    if page and page.refresh and ns.lab.completedAt then
      -- cheap guard: pages refresh on show; ticking refresh is avoided
    end
  end,
})
