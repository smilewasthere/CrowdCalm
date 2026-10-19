-- UI/Pages/Results.lua — ranked cards from the latest run (brief section
-- 6.3, 5.10 + pre.3 owner feedback): dual teal/amber bars, before/after,
-- Best medal, confidence badge with legend tooltip, an action chip (Worth
-- it / No gain / Re-test / Can't test / Hitch), the tested change ("Change
-- 7 to 6") with the setting's explanation, a What-to-do recommendation
-- panel (5.10), an owner-editable visual-cost dropdown (5.6), a Copy report
-- button that includes the recommendations, and a permanently disabled
-- "Apply as crowd profile" panel.
local ADDON_NAME, ns = ...

local Widgets = ns.widgets
local Skin = ns.skin
local L = ns.L
local Lfmt = ns.Lfmt

-- remove one trailing UTF-8 character (for clipping long explanation text
-- without splitting a multibyte glyph)
local function utf8chop(s)
  return (s:gsub("[%z\1-\127\194-\244][\128-\191]*$", ""))
end

-- pre.5: number-list helpers for the Copy report (baselines/tests/gains)
local function fmtNums(t, signed)
  if type(t) ~= "table" then
    return "?"
  end
  local parts = {}
  for i = 1, #t do
    parts[i] = (type(t[i]) == "number") and string.format(signed and "%+.1f" or "%.1f", t[i]) or "?"
  end
  if #parts == 0 then
    return "?"
  end
  return table.concat(parts, ", ")
end

local function candNote(key)
  if not key or not (ns.settings and ns.settings.candidates) then
    return nil
  end
  for _, cand in ipairs(ns.settings.candidates) do
    if cand.key == key and cand.note then
      return L(cand.note)
    end
  end
  return nil
end

-- chip classification; buildRecommendations uses the same rules so the
-- chip and the What-to-do panel can never disagree (pre.3).
local function classify(row)
  if row.notTestable then
    return "cant"
  end
  if row.hitch then
    return "hitch"
  end
  if row.noisy or row.confidence == "Low" then
    return "retest"
  end
  if row.gain and row.gain >= 0.5 then
    return "worth"
  end
  return "nogain"
end

local function actionChip(card, text, color)
  local chip = Widgets.Panel(card, { base = ns.palette.raised, borderAlpha = 0.9 })
  chip:SetHeight(18)
  local fs = Widgets.Text(chip, "small", text)
  fs:SetPoint("CENTER")
  Skin.ColorText(fs, color)
  local accent = chip:CreateTexture(nil, "OVERLAY")
  accent:SetWidth(2)
  accent:SetPoint("TOPLEFT", 0, -2)
  accent:SetPoint("BOTTOMLEFT", 0, 2)
  accent:SetColorTexture(color.r, color.g, color.b, 1)
  chip:SetWidth(fs:GetStringWidth() + 22)
  return chip
end

local COST_ORDER = { "None", "Low", "Medium", "High", "Unknown" }

local function rowCard(parent, row, isBest, listWidth)
  local kind = classify(row)
  local card = Widgets.Panel(parent, { base = ns.palette.raised, borderAlpha = 0.5 })
  -- pre.5: cards grow for the reliability detail (baseline difference + rerun
  -- tip), the Thorough gain spread, or a movement marker
  local extra = 0
  if not row.notTestable then
    if kind == "retest" and row.baselinePct ~= nil then
      extra = 2
    elseif row.gains and #row.gains > 1 then
      extra = 1
    end
    if row.changed then
      extra = extra + 1
    end
  end
  card:SetHeight(row.notTestable and 44 or (100 + extra * 14))

  local name = Widgets.Text(card, "body", L(row.labelKey or row.key or "?"))
  name:SetPoint("TOPLEFT", 12, -8)
  if isBest and row.gain then
    local medal = Widgets.Text(card, "small", L("best"))
    medal:SetPoint("LEFT", name, "RIGHT", 10, 0)
    Skin.ColorText(medal, ns.palette.goldBright)
  end

  -- action chip, top right
  local chipText, chipColor
  if kind == "worth" then
    chipText, chipColor = L("act_worth"), ns.palette.gainColor()
  elseif kind == "hitch" then
    chipText, chipColor = L("act_hitch"), ns.palette.danger
  elseif kind == "retest" then
    chipText, chipColor = L("act_retest"), ns.palette.costColor()
  elseif kind == "cant" then
    chipText, chipColor = L("act_cant"), ns.palette.textDim
  else
    chipText, chipColor = L("act_nogain"), ns.palette.textDim
  end
  local chip = actionChip(card, chipText, chipColor)
  chip:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -8)
  if kind == "hitch" and row.hitchFps then
    Widgets.TooltipLines(chip, function()
      return {
        L("hitch_note"),
        string.format("Lowest FPS right after the change: %.0f", row.hitchFps or 0),
      }
    end)
  elseif kind == "retest" then
    Widgets.TooltipLines(chip, function()
      local lines = { L("noisy_note") }
      if row.baselinePct ~= nil then
        lines[#lines + 1] = Lfmt("unreliable_pattern", row.baselinePct, ns.stats.UNRELIABLE_PCT)
      end
      return lines
    end)
  end

  if row.notTestable then
    local reason = row.reason == "unreadable" and L("reason_unreadable")
      or row.reason == "already-lowest" and L("reason_already_lowest")
      or Lfmt("reason_failed", tostring(row.reason or "?"))
    local fs = Widgets.Text(card, "small", L("not_testable") .. " — " .. reason)
    fs:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
    Skin.ColorText(fs, ns.palette.textDim)
    return card
  end

  local sentence
  if kind == "worth" then
    sentence = Lfmt("results_sentence_gain", L(row.labelKey or "?"), row.gain)
  else
    sentence = Lfmt("results_sentence_none", L(row.labelKey or "?"))
  end
  local sentenceFs = Widgets.Text(card, "small", sentence)
  sentenceFs:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -6)
  local anchor = sentenceFs

  -- what was actually changed (+ what the setting does); rows from runs
  -- made before pre.3 simply have no stored values and skip this line.
  -- pre.5: the values triple reads from -> to -> after (read back after the
  -- final restore), so the owner can see the value actually landed.
  local changeText, changeTip
  if row.changes and #row.changes > 1 then
    changeText = Lfmt("change_multi", #row.changes)
    changeTip = {}
    for _, ch in ipairs(row.changes) do
      local nm = ch.labelKey and L(ch.labelKey) or tostring(ch.key or "?")
      if ch.after ~= nil then
        changeTip[#changeTip + 1] = string.format("- %s: %s -> %s -> %s", nm, tostring(ch.from), tostring(ch.to), tostring(ch.after))
      else
        changeTip[#changeTip + 1] = string.format("- %s: %s -> %s", nm, tostring(ch.from), tostring(ch.to))
      end
    end
  elseif row.valueFrom ~= nil and row.valueTo ~= nil then
    local note = candNote(row.key)
    if row.valueAfter ~= nil then
      if note then
        changeText = Lfmt("change_note_restored", tostring(row.valueFrom), tostring(row.valueTo), tostring(row.valueAfter), note)
      else
        changeText = Lfmt("change_restored", tostring(row.valueFrom), tostring(row.valueTo), tostring(row.valueAfter))
      end
    elseif note then
      changeText = Lfmt("change_note_pattern", tostring(row.valueFrom), tostring(row.valueTo), note)
    else
      changeText = Lfmt("change_pattern", tostring(row.valueFrom), tostring(row.valueTo))
    end
  else
    changeText = candNote(row.key)
  end
  if changeText and changeText ~= "" then
    local changeFs = Widgets.Text(card, "small", changeText)
    changeFs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
    anchor = changeFs
    local maxW = math.max(200, (listWidth or 400) - 140)
    changeFs:SetWidth(maxW)
    changeFs:SetJustifyH("LEFT")
    if changeFs:GetStringWidth() > maxW then
      local t = changeText
      while t ~= "" and changeFs:GetStringWidth() > maxW - 10 do
        t = utf8chop(t)
        changeFs:SetText(t .. "..")
      end
    end
    if changeTip then
      Widgets.TooltipLines(changeFs, function()
        return changeTip
      end)
    end
  end

  -- pre.5 detail lines: baseline difference + rerun tip (Not reliable),
  -- Thorough per-test spread, movement marker
  if not row.notTestable then
    if kind == "retest" and row.baselinePct ~= nil then
      local pctFs = Widgets.Text(card, "small", Lfmt("unreliable_pattern", row.baselinePct, ns.stats.UNRELIABLE_PCT))
      pctFs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
      Skin.ColorText(pctFs, ns.palette.costColor())
      anchor = pctFs
      local tipFs = Widgets.Text(card, "small", L("unreliable_tip"))
      tipFs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
      Skin.ColorText(tipFs, ns.palette.textDim)
      anchor = tipFs
    elseif row.gains and #row.gains > 1 and row.spreadMin ~= nil then
      local spFs = Widgets.Text(card, "small", Lfmt("spread_pattern", row.spreadMin, row.spreadMax))
      spFs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
      Skin.ColorText(spFs, ns.palette.textDim)
      anchor = spFs
    end
    if row.changed then
      local mvFs = Widgets.Text(card, "small", L("moved_row"))
      mvFs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
      Skin.ColorText(mvFs, ns.palette.danger)
      anchor = mvFs
    end
  end

  -- FPS triple for pre.5 runs (entry baseline -> mean test -> exit
  -- baseline); older stored runs fall back to the plain before -> after
  local beforeAfter
  if row.fpsBefore ~= nil and row.fpsAfter ~= nil then
    beforeAfter = Widgets.Text(card, "small", Lfmt("fps_triple", row.fpsBefore, row.fpsTest or 0, row.fpsAfter))
  else
    beforeAfter = Widgets.Text(card, "small", Lfmt("before_after", row.before or 0, row.after or 0))
  end
  beforeAfter:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 12, 8)

  local conf = Widgets.Text(card, "small", L("confidence") .. ": " .. (row.confidence or "?"))
  conf:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -8, 8)
  Skin.ColorText(conf, row.noisy and ns.palette.costColor() or ns.palette.gainColor())
  Widgets.TooltipLines(conf, function()
    local c = row.confidence
    local tip = { L("conf_tip_1") }
    tip[#tip + 1] = L(c == "Low" and "conf_tip_low" or c == "High" and "conf_tip_high" or "conf_tip_med")
    if row.baselinePct ~= nil then
      tip[#tip + 1] = Lfmt("unreliable_pattern", row.baselinePct, ns.stats.UNRELIABLE_PCT)
    end
    if row.gains and #row.gains > 1 then
      tip[#tip + 1] = Lfmt("spread_pattern", row.spreadMin or 0, row.spreadMax or 0)
    end
    return tip
  end)

  -- dual bar: sizes from the known list width (review I8 — the card has no
  -- resolved width yet at create time)
  local barWidth = math.max(120, (listWidth or 400) - 24)
  local barBg = card:CreateTexture(nil, "ARTWORK")
  barBg:SetHeight(8)
  barBg:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 12, 28)
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

  -- owner-editable visual-cost tier (brief 5.6, review I13); sits under the
  -- action chip since pre.3
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
    costDrop:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -28)
    Widgets.TooltipLines(costDrop, function()
      return { L("cost_edit") .. ": " .. currentCost }
    end)
  end
  return card
end

-- ------------------------------------------------- recommendations ----

local function buildRecommendations(sortedRows)
  -- sortedRows must be gain-desc; filtering keeps that order
  local worth, hasNoisy = {}, false
  for _, r in ipairs(sortedRows) do
    if not r.notTestable then
      if r.noisy or r.confidence == "Low" then
        hasNoisy = true
      end
      if classify(r) == "worth" then
        worth[#worth + 1] = r
      end
    end
  end
  return worth, hasNoisy
end

local function recommendLines(worth, hasNoisy)
  -- shared by the What-to-do panel and the Copy report
  local lines = {}
  if #worth > 0 then
    local best = worth[1]
    local bestName = L(best.labelKey or best.key or "?")
    if best.changes and #best.changes > 1 then
      lines[#lines + 1] = Lfmt("rec_combine", best.gain or 0)
    elseif best.valueTo ~= nil then
      lines[#lines + 1] = Lfmt(
        "rec_primary",
        bestName,
        tostring(best.valueTo),
        best.valueFrom ~= nil and tostring(best.valueFrom) or "?",
        best.gain or 0
      )
    else
      lines[#lines + 1] = Lfmt("results_sentence_gain", bestName, best.gain or 0)
    end
    if #worth > 1 then
      local items = {}
      for i = 2, math.min(#worth, 4) do
        local r = worth[i]
        local nm = L(r.labelKey or r.key or "?")
        local multi = r.changes and #r.changes > 1
        local tgt = (r.valueTo ~= nil and not multi) and (nm .. " to " .. tostring(r.valueTo)) or nm
        items[#items + 1] = string.format("%s (+%.1f)", tgt, r.gain or 0)
      end
      lines[#lines + 1] = L("rec_also") .. ": " .. table.concat(items, ", ")
    end
    lines[#lines + 1] = L("rec_howto")
    lines[#lines + 1] = L("rec_caveat")
  elseif hasNoisy then
    lines[#lines + 1] = L("rec_noisy")
    lines[#lines + 1] = L("rec_caveat")
  else
    lines[#lines + 1] = L("rec_none")
    lines[#lines + 1] = L("rec_caveat")
  end
  return lines
end

-- ---------------------------------------------------------- create ----

local function create(parent)
  local frame = parent
  local pad = 12

  local runHeader = Widgets.Text(frame, "header", "")
  runHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)

  -- What-to-do panel (owner ask: "explain what to change")
  local SUMMARY_H = 104
  local summary = Widgets.Panel(frame, { base = ns.palette.raised, borderAlpha = 0.6 })
  summary:SetHeight(SUMMARY_H)
  summary:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad - 26)
  summary:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad - 26)
  local recTitle = Widgets.Text(summary, "small", L("rec_title"))
  recTitle:SetPoint("TOPLEFT", summary, "TOPLEFT", 12, -8)
  Skin.ColorText(recTitle, ns.palette.goldBright)
  local recLines = {}
  local function showRecLines(lines)
    for i = 1, math.max(#lines, #recLines) do
      local fs = recLines[i]
      if not fs then
        fs = Widgets.Text(summary, i == 1 and "body" or "small", "")
        recLines[i] = fs
      end
      if lines[i] then
        fs:SetText(lines[i])
        fs:SetWidth(math.max(120, summary:GetWidth() - 24))
        fs:SetJustifyH("LEFT")
        fs:Show()
      else
        fs:Hide()
      end
    end
    local prev = recTitle
    for i = 1, #lines do
      recLines[i]:ClearAllPoints()
      recLines[i]:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, i == 1 and -6 or -3)
      prev = recLines[i]
    end
  end
  summary:Hide()

  local list = CreateFrame("Frame", nil, frame)
  list:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad - 26 - SUMMARY_H - 8)
  list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad + 48)
  list:EnableMouseWheel(true)
  local cardCache = {} -- index -> card (bounded pool; review I9)
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
        -- pre.5: caps preflight + movement warning in the report header
        if run.caps then
          local c = run.caps
          local bits = {
            "maxfps=" .. ((c.maxfps and c.maxfps > 0) and tostring(c.maxfps) or "uncapped/unknown"),
            "vsync=" .. (c.vsync and "on" or "off"),
          }
          if c.warnings and #c.warnings > 0 then
            bits[#bits + 1] = "WARNING: a frame cap may limit these results (" .. table.concat(c.warnings, ", ") .. ")"
          end
          lines[#lines + 1] = "Caps: " .. table.concat(bits, " ")
        end
        if run.moved then
          lines[#lines + 1] = "WARNING: movement or camera turning detected during the run"
        end
        local repRows = {}
        for _, r in ipairs(run.rows or {}) do
          repRows[#repRows + 1] = r
        end
        table.sort(repRows, function(a, b)
          return (a.gain or -999) > (b.gain or -999)
        end)
        local worth = buildRecommendations(repRows)
        if #worth > 0 then
          for i = 1, math.min(3, #worth) do
            local r = worth[i]
            if r.changes and #r.changes > 1 then
              lines[#lines + 1] = string.format(
                "- RECOMMEND: apply the top changes together: %+.1f FPS (confidence %s)",
                r.gain or 0,
                tostring(r.confidence)
              )
            else
              lines[#lines + 1] = string.format(
                "- RECOMMEND: set %s to %s (was %s): %+.1f FPS, confidence %s",
                L(r.labelKey or "?"),
                tostring(r.valueTo),
                r.valueFrom ~= nil and tostring(r.valueFrom) or "?",
                r.gain or 0,
                tostring(r.confidence)
              )
            end
          end
        else
          lines[#lines + 1] = "- RECOMMEND: none (no clear wins in this crowd)"
        end
        for _, row in ipairs(repRows) do
          if row.notTestable then
            lines[#lines + 1] = string.format("- %s: not tested (%s)", L(row.labelKey or "?"), tostring(row.reason))
          else
            -- pre.5: full measurement detail — triples, per-test gains,
            -- baseline difference, restored value, movement flag
            local spreadStr = ""
            if row.gains and #row.gains > 1 and row.spreadMin ~= nil then
              spreadStr = string.format(" median of %d tests, range %+.1f..%+.1f", #row.gains, row.spreadMin, row.spreadMax)
            end
            lines[#lines + 1] = string.format(
              "- %s: %.1f -> %.1f FPS (gain %+.1f%s, confidence %s%s%s)",
              L(row.labelKey or "?"),
              row.before or 0,
              row.after or 0,
              row.gain or 0,
              spreadStr,
              tostring(row.confidence),
              row.noisy and ", NOT RELIABLE" or "",
              row.changed and ", MOVED" or ""
            )
            if row.fpsBefore ~= nil then
              lines[#lines + 1] = string.format(
                "  triple: baseline %.1f -> test %.1f -> after %.1f FPS",
                row.fpsBefore,
                row.fpsTest or 0,
                row.fpsAfter or 0
              )
            end
            if row.baselines then
              lines[#lines + 1] = "  baselines: " .. fmtNums(row.baselines)
                .. " | tests: " .. fmtNums(row.tests)
                .. " | per-test gains: " .. fmtNums(row.gains, true)
            end
            if row.baselinePct ~= nil then
              lines[#lines + 1] = string.format(
                "  baselines differ %.1f%% (limit %d%%)",
                row.baselinePct,
                ns.stats.UNRELIABLE_PCT
              )
            end
            if row.valueFrom ~= nil and row.valueTo ~= nil then
              lines[#lines + 1] = string.format(
                "  value: %s -> %s%s",
                tostring(row.valueFrom),
                tostring(row.valueTo),
                row.valueAfter ~= nil and (" -> " .. tostring(row.valueAfter) .. " (restored)") or ""
              )
            end
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
      Widgets.ApplyEditBoxFont(box, "small")
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
      summary:Hide()
      runHeader:SetText("")
      applyBtn:Disable()
      return
    end
    empty:Hide()
    summary:Show()
    local zone = (run.zone or "?")
    if run.subzone and run.subzone ~= "" then
      zone = zone .. " / " .. run.subzone
    end
    runHeader:SetText(Lfmt("zone_pattern", zone, L("crowd_" .. (run.crowd or "quiet")) or "?"))
    local worth, hasNoisy = buildRecommendations(sortedRows)
    showRecLines(recommendLines(worth, hasNoisy))
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
