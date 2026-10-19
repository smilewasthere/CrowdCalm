-- UI/Pages/Stutter.lua — 10-minute timeline strip, pooled row list, and a
-- detail drawer (brief section 6.4). Logging is controlled here and on the
-- Settings page (same db.settings.log.enabled flag).
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

  local list = Widgets.RowList(frame, {
    width = parent:GetWidth(),
    height = parent:GetHeight() - 140,
    rowHeight = 28,
    count = function()
      return ns.stutterLog.Count()
    end,
    render = function(row, index)
      local ring = ns.stutterLog.Entries()
      local e = ring:Get(index)
      if not e then
        row:Hide()
        return
      end
      row:Show()
      if not row.built then
        row.built = true
        row.timeFs = Widgets.Text(row, "small", "")
        row.timeFs:SetPoint("LEFT", 8, 0)
        row.sevFs = Widgets.Text(row, "small", "")
        row.sevFs:SetPoint("LEFT", row.timeFs, "RIGHT", 16, 0)
        row.fpsFs = Widgets.Text(row, "small", "")
        row.fpsFs:SetPoint("LEFT", row.sevFs, "RIGHT", 60, 0)
        row.zoneFs = Widgets.Text(row, "small", "")
        row.zoneFs:SetPoint("LEFT", row.fpsFs, "RIGHT", 40, 0)
        row:SetScript("OnClick", function(self)
          if frame.showDetail and self.currentEntry then
            frame.showDetail(self.currentEntry)
          end
        end)
        row:EnableMouse(true)
        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(ns.palette.gold.r, ns.palette.gold.g, ns.palette.gold.b, 0.08)
      end
      row.currentEntry = e
      row.timeFs:SetText(formatTime(e.t))
      row.sevFs:SetText(L("sev" .. tostring(e.sev or 1)))
      Skin.ColorText(row.sevFs, sevColor(e.sev))
      row.fpsFs:SetText(string.format("%.0f", e.fps or 0))
      row.zoneFs:SetText((e.zone or "") .. (e.crowd and e.crowd ~= "" and ("  ·  " .. e.crowd) or ""))
      Skin.ColorText(row.zoneFs, ns.palette.textDim)
    end,
  })
  list:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad - 104)
  list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad + 52)

  local detail = Widgets.Panel(frame, { base = ns.palette.raised, borderAlpha = 0.6 })
  detail:SetHeight(44)
  detail:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pad, pad)
  detail:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
  local detailText = Widgets.Text(detail, "small", "")
  detailText:SetPoint("LEFT", 12, 0)
  detail:Hide()

  function frame.showDetail(e)
    detailText:SetText(Lfmt("stutter_detail", e.d50 or 0, e.d100 or 0, e.d500 or 0, e.d1000 or 0, e.runId or 0))
    detail:Show()
  end

  local function refreshTimeline()
    local ring = ns.stutterLog.Entries()
    local count = ring:Count()
    local now = GetTime()
    local window = minutes * 60
    for i = 1, COLS do
      columns[i]:SetHeight(1)
      columns[i]:SetColorTexture(ns.palette.line.r, ns.palette.line.g, ns.palette.line.b, 0.6)
    end
    for i = 1, count do
      local e = ring:Get(i)
      local age = now - (e.t or 0)
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

  frame:SetScript("OnShow", function()
    list:Refresh()
    refreshTimeline()
  end)
  frame.refresh = function()
    list:Refresh()
    refreshTimeline()
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
