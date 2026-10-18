-- UI/Pages/Results.lua — ranked cards from the latest run (brief section
-- 6.3, 5.10): dual teal/amber bars, before/after, Best medal, confidence
-- badge, one plain sentence, an owner-editable visual-cost dropdown
-- (5.6), a Copy report button (5.10), and a permanently disabled
-- "Apply as crowd profile" panel.
local ADDON_NAME, ns = ...

local Widgets = ns.widgets
local Skin = ns.skin
local L = ns.L
local Lfmt = ns.Lfmt

local COST_ORDER = { "None", "Low", "Medium", "High", "Unknown" }

local function rowCard(parent, row, isBest, listWidth)
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

  -- dual bar: sizes from the known list width (review I8 — the card has no
  -- resolved width yet at create time)
  local barWidth = math.max(120, (listWidth or 400) - 24)
  local barBg = card:CreateTexture(nil, "ARTWORK")
  barBg:SetHeight(8)
  barBg:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 12, 32)
  barBg:SetWidth(barWidth)
  barBg:SetColorTexture(ns.palette.obsidian.r, ns.palette.obsidian.g, ns.palette.obsidian.b, 1)
  local maxV = math.max(row.before or 0, row.after or 0, 1)
  local beforeBar = card:CreateTexture(nil, "OVERLAY")
  beforeBar:SetHeight(8)
  beforeBar:SetPoint("LEFT", barBg, "LEFT", 0, 0)
  beforeBar:SetWidth(math.max(1, math.floor(((row.before or 0) / maxV) * barWidth)))
  local cost = ns.palette.costColor()
  beforeBar:SetColorTexture(cost.r, cost.g, cost.b, 0.8)
  local afterBar = card:CreateTexture(nil, "OVERLAY")
  afterBar:SetHeight(4)
  afterBar:SetPoint("BOTTOMLEFT", barBg, "BOTTOMLEFT", 0, -6)
  afterBar:SetWidth(math.max(1, math.floor(((row.after or 0) / maxV) * barWidth)))
  local gain = ns.palette.gainColor()
  afterBar:SetColorTexture(gain.r, gain.g, gain.b, 1)

  -- owner-editable visual-cost tier (brief 5.6, review I13)
  if row.key then
    local currentCost = ns.settings.costOf(row.key)
    local costDrop = Widgets.Dropdown(card, {
      width = 88,
      options = {
        { id = "None", label = L("cost_none") },
        { id = "Low", label = L("cost_low") },
        { id = "Medium", label = L("cost_medium") },
        { id = "High", label = L("cost_high") },
        { id = "Unknown", label = L("cost_unknown") },
      },
      selectedId = currentCost,
      onChange = function(id)
        ns.settings.setCost(row.key, id)
      end,
    })
    costDrop:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -8)
    Widgets.TooltipLines(costDrop, function()
      return { L("cost_edit") .. ": " .. currentCost }
    end)
  end

  if row.noisy then
    local note = Widgets.Text(card, "small", L("noisy_note"))
    note:SetPoint("RIGHT", card, "RIGHT", -110, -12)
    Skin.ColorText(note, ns.palette.costColor())
  elseif row.hitch then
    local note = Widgets.Text(card, "small", L("hitch_note"))
    note:SetPoint("RIGHT", card, "RIGHT", -110, -12)
    Skin.ColorText(note, ns.palette.danger)
  end
  return card
end

local function create(parent)
  local frame = parent
  local pad = 12

  local runHeader = Widgets.Text(frame, "header", "")
  runHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)

  local list = CreateFrame("Frame", nil, frame)
  list:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad - 28)
  list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad + 48)
  list:EnableMouseWheel(true)
  local cardCache = {} -- row -> card (bounded pool; review I9)
  local offset = 0
  local sortedRows = {}

  local function rebuild()
    for _, c in pairs(cardCache) do
      c:Hide()
    end
    local y = 0
    local visibleBottom = list:GetHeight()
    local listWidth = list:GetWidth()
    for i = 1 + offset, #sortedRows do
      if y > visibleBottom then
        break
      end
      local row = sortedRows[i]
      local card = cardCache[i]
      if not card then
        card = rowCard(list, row, i == 1 and row.gain and row.gain > 0.5, listWidth)
        cardCache[i] = card
      end
      card:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -y)
      card:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -y)
      card:Show()
      y = y + card:GetHeight() + 8
    end
  end

  list:SetScript("OnMouseWheel", function(_, delta)
    offset = math.max(0, math.min(offset - delta, math.max(0, #sortedRows - 3)))
    rebuild()
  end)

  -- permanently disabled apply panel (review I7: never Enable() it)
  local applyBtn = Widgets.Button(frame, {
    label = L("apply_coming"),
    small = true,
    onClick = function() end,
  })
  applyBtn:SetWidth(240)
  applyBtn:Disable()
  applyBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
  Skin.ColorText(applyBtn.text, ns.palette.textDim)

  -- Copy report (brief 5.10, review I12)
  local copyBtn = Widgets.Button(frame, {
    label = L("copy_report"),
    small = true,
    onClick = function()
      local run = ns.db.results and ns.db.results[#ns.db.results]
      local lines = {}
      lines[#lines + 1] = "CrowdCalm Lab report"
      lines[#lines + 1] = ns.compat.describe()
      ns.context.Update(true)
      local snap = ns.context.Snapshot()
      lines[#lines + 1] = "Place: " .. tostring(snap and snap.zone or "?")
      lines[#lines + 1] = "Crowd: " .. ns.context.Label()
      if run then
        lines[#lines + 1] = string.format("Run #%d mode=%s", run.id or 0, tostring(run.mode))
        for _, row in ipairs(run.rows) do
          if row.notTestable then
            lines[#lines + 1] = string.format("- %s: not tested (%s)", L(row.labelKey or "?"), tostring(row.reason))
          else
            lines[#lines + 1] = string.format(
              "- %s: %.1f -> %.1f FPS (gain %+.1f, confidence %s%s)",
              L(row.labelKey or "?"),
              row.before or 0,
              row.after or 0,
              row.gain or 0,
              tostring(row.confidence),
              row.noisy and ", NOISY" or ""
            )
          end
        end
      else
        lines[#lines + 1] = "(no runs yet)"
      end
      local text = table.concat(lines, "\n")

      local box = CreateFrame("EditBox", nil, frame)
      -- prefer the scrollable multiline template; fall back to a plain
      -- EditBox on clients that lack it
      pcall(function()
        box:SetScript("OnTextChanged", nil)
      end)
      box:SetHeight(180)
      box:SetWidth(math.max(200, list:GetWidth()))
      box:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pad, pad + 48)
      Skin.ApplyPanel(box, { base = ns.palette.obsidian, borderAlpha = 0.8 })
      box:SetFontObject(Skin.Font("small"))
      box:SetMultiLine(true)
      box:SetText(text)
      box:SetFocus(true)
      box:HighlightText()
      box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        self:Hide()
      end)
      local hint = Widgets.Text(frame, "small", L("report_hint"))
      hint:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 4, 6)
      Skin.ColorText(hint, ns.palette.textDim)
      C_Timer.After(30, function()
        if box then
          box:Hide()
          hint:Hide()
        end
      end)
    end,
  })
  copyBtn:SetWidth(120)
  copyBtn:SetPoint("RIGHT", applyBtn, "LEFT", -8, 0)

  local empty = Widgets.EmptyState(frame, L("results_empty"))
  empty:Hide()

  local function refresh()
    -- the run can change between visits; drop stale cached cards
    for _, c in pairs(cardCache) do
      c:Hide()
    end
    cardCache = {}
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
})
