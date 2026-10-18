-- UI/Pages/Addons.lua — sortable addon cost table with search, CPU bars,
-- top-3 badges, explicit memory scan, and per-row disable-on-reload behind
-- confirmation (brief section 6.5).
local ADDON_NAME, ns = ...

local Widgets = ns.widgets
local Skin = ns.skin
local L = ns.L
local Lfmt = ns.Lfmt

local function create(parent)
  local frame = parent
  local pad = 12

  -- toolbar
  local searchBox = CreateFrame("EditBox", nil, frame)
  searchBox:SetHeight(24)
  searchBox:SetWidth(200)
  searchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
  Skin.ApplyPanel(searchBox, { base = ns.palette.obsidian, borderAlpha = 0.6 })
  local searchText = Widgets.Text(searchBox, "small", L("addons_search"))
  searchText:SetPoint("LEFT", 8, 0)
  Skin.ColorText(searchText, ns.palette.textDim)
  searchBox:SetFontObject(Skin.Font("small"))
  searchBox:SetText("")
  searchBox:SetScript("OnEditFocusGained", function()
    searchText:Hide()
  end)
  searchBox:SetScript("OnEditFocusLost", function()
    if searchBox:GetText() == "" then
      searchText:Show()
    end
  end)
  searchBox:SetScript("OnTextChanged", function(self)
    local q = self:GetText() or ""
    if frame.applyFilter then
      frame.applyFilter(q)
    end
  end)

  local refreshBtn = Widgets.Button(frame, {
    small = true,
    label = L("addons_refresh"),
    onClick = function()
      if not ns.addonCost.Refresh() then
        ns.ui.ShowBanner(L("err_combat"), "danger", 5)
      end
      if frame.refresh then
        frame.refresh()
      end
    end,
  })
  refreshBtn:SetWidth(110)
  refreshBtn:SetPoint("LEFT", searchBox, "RIGHT", 8, 0)

  local memoryBtn = Widgets.Button(frame, {
    small = true,
    label = L("scan_memory"),
    onClick = function()
      local ok, err = ns.addonCost.ScanMemory()
      if ok then
        ns.ui.ShowBanner("Memory scanned.", "gainColor", 5)
      elseif err == "combat" then
        ns.ui.ShowBanner(L("err_combat"), "danger", 5)
      else
        ns.ui.ShowBanner(tostring(err), "danger", 5)
      end
      if frame.refresh then
        frame.refresh()
      end
    end,
  })
  memoryBtn:SetWidth(150)
  memoryBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 8, 0)
  Widgets.TooltipLines(memoryBtn, function()
    return { L("memory_scan_hint") }
  end)

  local sortLabel = Widgets.Text(frame, "small", "")
  sortLabel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad - 4)
  Skin.ColorText(sortLabel, ns.palette.textDim)

  -- column headers (click to sort)
  local headerY = -pad - 36
  local headers = { { "col_addon", "name" }, { "col_cpu", "cpu" }, { "col_memory", "memory" } }
  local headerXs = { pad, pad + 320, pad + 420 }
  local sortField = "cpu"
  for i, h in ipairs(headers) do
    local btn = Widgets.Button(frame, {
      small = true,
      label = L(h[1]),
      onClick = function()
        sortField = h[2]
        ns.addonCost.SortBy(sortField)
        if frame.refresh then
          frame.refresh()
        end
      end,
    })
    btn:SetWidth(90)
    btn:SetHeight(20)
    btn:SetPoint("TOPLEFT", frame, "TOPLEFT", headerXs[i], headerY)
  end

  local caveat = Widgets.Text(frame, "small", L("cpu_caveat"))
  caveat:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, headerY - 24)
  Skin.ColorText(caveat, ns.palette.textDim)

  frame.filtered = {}
  frame.filteredRank = {}

  local list = Widgets.RowList(frame, {
    width = parent:GetWidth(),
    height = parent:GetHeight() - 140,
    rowHeight = 30,
    count = function()
      return #frame.filtered
    end,
    render = function(row, index)
      local entry = frame.filtered[index]
      if not entry then
        row:Hide()
        return
      end
      row:Show()
      if not row.built then
        row.built = true
        row.nameFs = Widgets.Text(row, "small", "")
        row.nameFs:SetPoint("LEFT", 10, 0)
        row.nameFs:SetWidth(300)
        row.nameFs:SetJustifyH("LEFT")
        row.cpuBarBg = row:CreateTexture(nil, "ARTWORK")
        row.cpuBarBg:SetHeight(10)
        row.cpuBarBg:SetPoint("LEFT", row.nameFs, "RIGHT", 12, 0)
        row.cpuBarBg:SetWidth(80)
        row.cpuBarBg:SetColorTexture(ns.palette.obsidian.r, ns.palette.obsidian.g, ns.palette.obsidian.b, 1)
        row.cpuBar = row:CreateTexture(nil, "OVERLAY")
        row.cpuBar:SetHeight(10)
        row.cpuBar:SetPoint("LEFT", row.cpuBarBg, "LEFT", 0, 0)
        row.cpuFs = Widgets.Text(row, "small", "")
        row.cpuFs:SetPoint("LEFT", row.cpuBarBg, "RIGHT", 8, 0)
        row.memFs = Widgets.Text(row, "small", "")
        row.memFs:SetPoint("LEFT", row.cpuFs, "RIGHT", 40, 0)
        row.badge = Widgets.Text(row, "small", "")
        row.badge:SetPoint("LEFT", row.memFs, "RIGHT", 16, 0)
        row.disableBtn = Widgets.Button(row, {
          small = true,
          label = L("addons_disable_action"),
          onClick = function(self)
            local entry2 = row.currentEntry
            if not entry2 then
              return
            end
            Widgets.Confirm(Lfmt("addons_disable_confirm", entry2.title), function()
              local ok = ns.addonCost.DisableOnReload(entry2.name)
              if ok then
                entry2.pendingDisable = true -- survives re-render (review M2)
                row.badge:SetText(L("addons_disable_pending"))
                Skin.ColorText(row.badge, ns.palette.danger)
              end
            end)
          end,
        })
        row.disableBtn:SetWidth(130)
        row.disableBtn:SetHeight(20)
        row.disableBtn:SetPoint("RIGHT", row, "RIGHT", -10, 0)
      end
      row.currentEntry = entry
      row.nameFs:SetText(entry.title or entry.name or "?")
      local cpu = entry.cpuRecent
      row.cpuFs:SetText(cpu and string.format("%.2f", cpu) or L("addons_unqueryable"))
      if cpu then
        row.cpuBar:SetWidth(math.max(1, math.min(80, (cpu / 2) * 80)))
        local gain = ns.palette.gainColor()
        row.cpuBar:SetColorTexture(gain.r, gain.g, gain.b, 0.8)
      else
        row.cpuBar:SetWidth(1)
      end
      row.memFs:SetText(entry.memory and string.format("%.1f", entry.memory) or "—")
      if frame.filteredRank[index] and frame.filteredRank[index] <= 3 and sortField == "cpu" then
        row.badge:SetText(L("addons_top3") .. " #" .. frame.filteredRank[index])
        Skin.ColorText(row.badge, ns.palette.goldBright)
      elseif entry.pendingDisable then
        row.badge:SetText(L("addons_disable_pending"))
        Skin.ColorText(row.badge, ns.palette.danger)
      else
        row.badge:SetText("")
      end
      if ns.addonCost.CanDisable(entry.name) then
        row.disableBtn:Show()
      else
        row.disableBtn:Hide()
      end
    end,
  })
  list:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad - 90)
  list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)

  local empty = Widgets.EmptyState(frame, L("addons_empty"))
  empty:Hide()

  function frame.applyFilter(query)
    query = (query or ""):lower()
    local rows, n = ns.addonCost.Rows()
    frame.filtered = {}
    for i = 1, n do
      local row = rows[i]
      local title = (row.title or row.name or ""):lower()
      if query == "" or title:find(query, 1, true) then
        frame.filtered[#frame.filtered + 1] = row
      end
    end
    frame.filteredRank = {}
    if sortField == "cpu" then
      for i = 1, math.min(3, #frame.filtered) do
        frame.filteredRank[i] = i
      end
    end
    if #frame.filtered == 0 then
      empty:Show()
    else
      empty:Hide()
    end
    if list.Refresh then
      list:Refresh()
    end
    sortLabel:SetText(Lfmt("addons_sorted_by", L("sort_" .. sortField) or sortField))
  end

  function frame.refresh()
    frame.applyFilter(searchBox:GetText() or "")
  end

  frame:SetScript("OnShow", function()
    ns.addonCost.Refresh()
    frame.refresh()
  end)
  return frame
end

ns.ui.RegisterPage({
  index = 5,
  name = L("page_addons"),
  icon = "icon_addons.tga",
  create = create,
})
