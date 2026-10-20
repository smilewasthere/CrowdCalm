-- UI/Pages/Stutter.lua — summary tiles, 10-minute timeline strip, pooled row
-- list, and a detail drawer (brief section 6.4). Pre.7 honesty pass: the
-- list and timeline run off wall-clock timestamps (entries survive reloads
-- and stale saved entries are dropped by the log itself), the list shows
-- only the configured window, and a capture starting suppresses logging for
-- 5 s (loading/zone changes). Logging is controlled here and on the Settings
-- page (same db.settings.log.enabled flag).
local ADDON_NAME, ns = ...

local Widgets = ns.widgets
local Skin = ns.skin
local L = ns.L
local Lfmt = ns.Lfmt

local SEV_COLORS = { "textDim", "gold", "costColor", "danger" }

local function sevColor(sev)
  local name = SEV_COLORS[sev or 1] or "textDim"
  local c = ns.palette[name]
  if type(c) == "function" then
    c = c()
  end
  return c
end

local function formatTime(t)
  local dateTable = date("*t", t)
  return string.format("%02d:%02d:%02d", dateTable.hour, dateTable.min, dateTable.sec)
end

local function create(parent)
  local frame = parent
  local pad = 12
  local windowList = {} -- snapshot of the configured window (pre.7)

  local enableBox = Widgets.Checkbox(frame, {
    label = L("stutter_enable"),
    checked = ns.stutterLog.IsEnabled(),
    onToggle = function(checked)
      ns.db.settings.log.enabled = checked
      ns.stutterLog.SetEnabled(checked)
    end,
  })
  enableBox:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)

  local clearBtn = Widgets.Button(frame, {
    small = true,
    label = L("clear_log"),
    onClick = function()
      Widgets.Confirm(L("clear_log_confirm"), function()
        ns.stutterLog.Clear()
        ns.db.stutter = {}
        if frame.refresh then
          frame.refresh()
        end
      end)
    end,
  })
  clearBtn:SetWidth(90)
  clearBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad)

  local minutes = ns.db.settings.stutterMinutes or 10
  local timelineTitle = Widgets.Text(frame, "small", Lfmt("stutter_timeline", minutes))
  timelineTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad - 28)

  -- pre.7: header summary tiles — what the window actually caught, split by
  -- severity (Freezes >= 1000 ms, Heavy >= 500 ms, Notable >= 100 ms or a
  -- low-FPS streak; isolated 50-99 ms frames are never logged)
  local tileDefs = {
    { key = "stutter_freezes", sev = 4 },
    { key = "stutter_heavy", sev = 3 },
    { key = "stutter_notable", sev = 2 },
  }
  local summaryTiles = {}
  for _, def in ipairs(tileDefs) do
    local panel = Widgets.Panel(frame, { base = ns.palette.raised, borderAlpha = 0.7 })
    panel:SetHeight(18)
    local fs = Widgets.Text(panel, "small", "")
    fs:SetPoint("CENTER")
    summaryTiles[#summaryTiles + 1] = { def = def, panel = panel, fs = fs }
  end

  local timeline = CreateFrame("Frame", nil, frame)
  timeline:SetHeight(48)
  timeline:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad - 46)
  timeline:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad - 46)
  local tlBg = timeline:CreateTexture(nil, "BACKGROUND")
  tlBg:SetAllPoints()
  tlBg:SetColorTexture(ns.palette.obsidian.r, ns.palette.obsidian.g, ns.palette.obsidian.b, 1)
  Skin.DrawEdges(timeline, ns.palette.line, 0.5)
  local columns = {}
  local COLS = 60
  for i = 1, COLS do
    local col = timeline:CreateTexture(nil, "ARTWORK")
    col:SetWidth(2)
    col:SetPoint("BOTTOMLEFT", timeline, "BOTTOMLEFT", (i - 1) * (timeline:GetWidth() / COLS), 0)
    col:SetHeight(1)
    columns[i] = col
  end

  -- pre.7: fixed column positions shared by the header row and the list
  -- rows, so "Time / Severity / FPS / Place" always lines up (the old
  -- chain-anchored columns drifted with the rendered time text)
  local COL_X = { time = 8, sev = 88, fps = 150, place = 196 }

  local header = CreateFrame("Frame", nil, frame)
  header:SetHeight(14)
  header:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad - 98)
  header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad - 98)
  local hTime = Widgets.Text(header, "small", L("col_time"))
  hTime:SetPoint("LEFT", header, "LEFT", COL_X.time, 0)
  local hSev = Widgets.Text(header, "small", L("col_sev"))
  hSev:SetPoint("LEFT", header, "LEFT", COL_X.sev, 0)
  local hFps = Widgets.Text(header, "small", L("col_fps"))
  hFps:SetPoint("LEFT", header, "LEFT", COL_X.fps, 0)
  local hPlace = Widgets.Text(header, "small", L("col_place"))
  hPlace:SetPoint("LEFT", header, "LEFT", COL_X.place, 0)
  for _, fs in ipairs({ hTime, hSev, hFps, hPlace }) do
    Skin.ColorText(fs, ns.palette.textDim)
  end

  local list = Widgets.RowList(frame, {
    width = parent:GetWidth(),
    height = parent:GetHeight() - 158,
    rowHeight = 28,
    count = function()
      return #windowList
    end,
    render = function(row, index)
      local e = windowList[index]
      if not e then
        row:Hide()
        return
      end
      row:Show()
      if not row.built then
        row.built = true
        row.timeFs = Widgets.Text(row, "small", "")
        row.timeFs:SetPoint("LEFT", COL_X.time, 0)
        row.sevFs = Widgets.Text(row, "small", "")
        row.sevFs:SetPoint("LEFT", COL_X.sev, 0)
        row.fpsFs = Widgets.Text(row, "small", "")
        row.fpsFs:SetPoint("LEFT", COL_X.fps, 0)
        row.zoneFs = Widgets.Text(row, "small", "")
        row.zoneFs:SetPoint("LEFT", COL_X.place, 0)
        -- pre.5: rows are plain Frames; SetScript("OnClick") is Button-only
        -- and raised "script type not supported by this object" on the
        -- owner's client (killed the whole list render). Clicks come in
        -- via OnMouseUp; the HIGHLIGHT layer is a Button feature too, so
        -- hover is driven by OnEnter/OnLeave here.
        row:EnableMouse(true)
        row:SetScript("OnMouseUp", function(self, button)
          if button == "LeftButton" and frame.showDetail and self.currentEntry then
            frame.showDetail(self.currentEntry)
            ns.sound.Play("click")
          end
        end)
        row:SetScript("OnEnter", function(self)
          if self.hover then
            self.hover:Show()
          end
        end)
        row:SetScript("OnLeave", function(self)
          if self.hover then
            self.hover:Hide()
          end
        end)
        local hover = row:CreateTexture(nil, "ARTWORK")
        hover:SetAllPoints()
        hover:SetColorTexture(ns.palette.gold.r, ns.palette.gold.g, ns.palette.gold.b, 0.08)
        hover:Hide()
        row.hover = hover
      end
      row.currentEntry = e
      row.timeFs:SetText(formatTime(e.at or e.t))
      row.sevFs:SetText(L("sev" .. tostring(e.sev or 1)))
      Skin.ColorText(row.sevFs, sevColor(e.sev))
      row.fpsFs:SetText(string.format("%.0f", e.fps or 0))
      row.zoneFs:SetText((e.zone or "") .. (e.crowd and e.crowd ~= "" and ("  ·  " .. e.crowd) or ""))
      Skin.ColorText(row.zoneFs, ns.palette.textDim)
    end,
  })
  list:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad - 116)
  list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad + 52)

  local empty = Widgets.EmptyState(frame, L("stutter_empty"))
  empty:Hide()

  local detail = Widgets.Panel(frame, { base = ns.palette.raised, borderAlpha = 0.6 })
  detail:SetHeight(44)
  detail:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pad, pad)
  detail:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
  -- pre.7: severity chip on the drawer (mirrors the row's chip color)
  local detailChip = Widgets.Text(detail, "small", "")
  detailChip:SetPoint("LEFT", 12, 0)
  local detailText = Widgets.Text(detail, "small", "")
  detailText:SetPoint("LEFT", detailChip, "RIGHT", 12, 0)
  detail:Hide()

  function frame.showDetail(e)
    detailChip:SetText(L("sev" .. tostring(e.sev or 1)))
    Skin.ColorText(detailChip, sevColor(e.sev))
    detailText:SetText(Lfmt("stutter_detail", e.d50 or 0, e.d100 or 0, e.d500 or 0, e.d1000 or 0, e.runId or 0))
    detail:Show()
  end

  local function refreshTimeline()
    local ring = ns.stutterLog.Entries()
    local count = ring:Count()
    local m = ns.db.settings.stutterMinutes or 10
    local now = time() -- pre.7: wall clock, so reloads don't scramble ages
    local window = m * 60
    for i = 1, COLS do
      columns[i]:SetHeight(1)
      columns[i]:SetColorTexture(ns.palette.line.r, ns.palette.line.g, ns.palette.line.b, 0.6)
    end
    for i = 1, count do
      local e = ring:Get(i)
      if e.at then
        local age = now - e.at
        if age >= 0 and age <= window then
          local colIndex = COLS - math.floor((age / window) * COLS)
          if colIndex < 1 then
            colIndex = 1
          end
          if colIndex > COLS then
            colIndex = COLS
          end
          local h = 6 + (e.sev or 1) * 10
          columns[colIndex]:SetHeight(h)
          local c = sevColor(e.sev)
          columns[colIndex]:SetColorTexture(c.r, c.g, c.b, 1)
        end
      end
    end
  end

  local function refreshTiles()
    local counts = { [2] = 0, [3] = 0, [4] = 0 }
    for i = 1, #windowList do
      local sev = windowList[i].sev or 1
      if counts[sev] then
        counts[sev] = counts[sev] + 1
      end
    end
    -- anchor the group from the right so it hugs the top-right corner
    local prev = nil
    for i = 1, #summaryTiles do
      local tile = summaryTiles[i]
      tile.fs:SetText(L(tile.def.key) .. ": " .. tostring(counts[tile.def.sev] or 0))
      tile.panel:SetWidth((tile.fs:GetStringWidth() or 60) + 16)
      tile.panel:ClearAllPoints()
      if not prev then
        tile.panel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad - 28)
      else
        tile.panel:SetPoint("TOPRIGHT", prev, "TOPLEFT", -6, 0)
      end
      prev = tile.panel
    end
  end

  frame:SetScript("OnShow", function()
    frame.refresh()
  end)
  frame.refresh = function()
    local m = ns.db.settings.stutterMinutes or 10
    if m ~= minutes then
      minutes = m
      timelineTitle:SetText(Lfmt("stutter_timeline", minutes))
    end
    windowList = ns.stutterLog.Window(minutes)
    refreshTiles()
    list:Refresh()
    refreshTimeline()
    empty:SetShown(#windowList == 0)
  end
  return frame
end

ns.ui.RegisterPage({
  index = 4,
  name = L("page_stutter"),
  icon = "icon_stutter.tga",
  create = create,
  onTick = function(page)
    if page and page.refresh then
      page.refresh()
    end
  end,
})
