-- UI/MainWindow.lua — the one window, lazy-created on first show (brief
-- sections 6.4, 7.3, 7.4): 920×600, resize 760×500, drag+clamp, Esc close
-- via UISpecialFrames, scale 0.7–1.4 persisted, header with client chip
-- and FPS pill, 200 px left rail (keys 1–7), footer with status lights and
-- Restore. Pages are registered by UI/Pages/*.lua via ns.ui.RegisterPage.
local ADDON_NAME, ns = ...

local Util = ns.util
local Skin = ns.skin
local Widgets = ns.widgets

local UI = {}
ns.ui = UI

local MAIN_W, MAIN_H = 920, 600
local MIN_W, MIN_H = 760, 500
local HEADER_H, RAIL_W, FOOTER_H = 56, 200, 44

-- ----------------------------------------------------------- pages ----

local pageDefs = {} -- index -> def
local pageFrames = {} -- index -> frame (lazy)
local currentPage = nil
local frame = nil
local railButtons = {}
local contentArea = nil
local bannerFrame = nil
local bannerTimer = nil
local fpsText, fpsDot
local statusCombat, statusInstance, statusBaseline
local updateTicker = nil

function UI.RegisterPage(def)
  pageDefs[def.index] = def
end

-- --------------------------------------------------------- header ----

local function buildHeader(parent)
  local header = CreateFrame("Frame", nil, parent)
  header:SetPoint("TOPLEFT")
  header:SetPoint("TOPRIGHT")
  header:SetHeight(HEADER_H)
  Skin.ApplyPanel(header, {
    base = ns.palette.obsidian,
    vignette = true,
    vignetteAlpha = 0.35,
    borderAlpha = 0.4,
  })
  Skin.VerticalGradient(
    header,
    { r = ns.palette.obsidian.r + 0.04, g = ns.palette.obsidian.g + 0.04, b = ns.palette.obsidian.b + 0.04, a = 1 },
    ns.palette.obsidian
  )

  local emblem = header:CreateTexture(nil, "ARTWORK")
  emblem:SetTexture(Skin.mediaPath .. "emblem.tga")
  emblem:SetSize(32, 32)
  emblem:SetPoint("LEFT", 16, 0)

  local title = Widgets.Text(header, "title", "CrowdCalmLab")
  title:SetPoint("LEFT", emblem, "RIGHT", 12, 0)
  Skin.ColorText(title, ns.palette.goldBright)

  local sub = Widgets.Text(header, "small", "In-world performance measurement lab")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
  Skin.ColorText(sub, ns.palette.textDim)

  local chip = CreateFrame("Frame", nil, header)
  chip:SetSize(150, 22)
  chip:SetPoint("RIGHT", header, "RIGHT", -140, 0)
  Skin.ApplyPanel(chip, { base = ns.palette.panel, borderAlpha = 0.6 })
  local chipText = Widgets.Text(chip, "small", ns.compat.chip or "")
  chipText:SetPoint("CENTER")
  Skin.ColorText(chipText, ns.compat.chipColor or ns.palette.gainColor())
  Widgets.TooltipLines(chip, function()
    return {
      "Target client: " .. (ns.compat.chip or "?"),
      "Interface: " .. tostring(ns.compat.interface or "?") .. " (" .. tostring(ns.compat.interfaceSource or "?") .. ")",
    }
  end)

  fpsDot = header:CreateTexture(nil, "ARTWORK")
  fpsDot:SetSize(8, 8)
  fpsDot:SetPoint("RIGHT", header, "RIGHT", -100, 0)
  fpsDot:SetColorTexture(ns.palette.gainColor().r, ns.palette.gainColor().g, ns.palette.gainColor().b, 1)

  fpsText = Widgets.Text(header, "number", "--")
  fpsText:SetPoint("LEFT", fpsDot, "RIGHT", 6, 0)
  Widgets.TooltipLines(fpsText, function()
    ns.context.Update()
    local t = (ns.context and ns.context.Label() or "—")
    return {
      "Live framerate while the window is open",
      "Crowd traffic: " .. t,
    }
  end)

  local closeBtn = Widgets.Button(header, {
    height = 24,
    label = "Close",
    onClick = function()
      frame:Hide()
    end,
  })
  closeBtn:SetWidth(64)
  closeBtn:SetPoint("RIGHT", header, "RIGHT", -14, 0)
  return header
end

-- ----------------------------------------------------------- rail ----

local function highlightRail(index)
  for i, btn in pairs(railButtons) do
    if i == index then
      btn.text:SetTextColor(ns.palette.goldBright.r, ns.palette.goldBright.g, ns.palette.goldBright.b, 1)
      if btn.bar then
        btn.bar:Show()
      end
      if btn.glow then
        btn.glow:Show()
      end
    else
      btn.text:SetTextColor(ns.palette.text.r, ns.palette.text.g, ns.palette.text.b, 1)
      if btn.bar then
        btn.bar:Hide()
      end
      if btn.glow then
        btn.glow:Hide()
      end
    end
  end
end

local function buildRail(parent)
  local rail = CreateFrame("Frame", nil, parent)
  rail:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -HEADER_H)
  rail:SetWidth(RAIL_W)
  rail:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, FOOTER_H)
  Skin.ApplyPanel(rail, { base = ns.palette.panel, borderAlpha = 0.4 })
  local ordered = {}
  for index, def in pairs(pageDefs) do
    ordered[#ordered + 1] = def
  end
  table.sort(ordered, function(a, b)
    return a.index < b.index
  end)
  for i, def in ipairs(ordered) do
    local btn = CreateFrame("Button", nil, rail)
    btn:SetHeight(40)
    btn:SetPoint("TOPLEFT", rail, "TOPLEFT", 4, -8 - (i - 1) * 44)
    btn:SetPoint("TOPRIGHT", rail, "TOPRIGHT", -4, -8 - (i - 1) * 44)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(Skin.mediaPath .. (def.icon or "icon.tga"))
    icon:SetSize(20, 20)
    icon:SetPoint("LEFT", 10, 0)
    local label = Widgets.Text(btn, "body", def.name or ("Page " .. def.index))
    label:SetPoint("LEFT", icon, "RIGHT", 10, 0)
    btn.text = label
    local bar = btn:CreateTexture(nil, "ARTWORK")
    bar:SetWidth(3)
    bar:SetPoint("TOPLEFT", 0, 4)
    bar:SetPoint("BOTTOMLEFT", 0, -4)
    bar:SetColorTexture(ns.palette.gold.r, ns.palette.gold.g, ns.palette.gold.b, 1)
    bar:Hide()
    btn.bar = bar
    local glow = btn:CreateTexture(nil, "OVERLAY")
    glow:SetTexture(Skin.mediaPath .. "glow.tga")
    glow:SetAllPoints()
    glow:SetVertexColor(ns.palette.gold.r, ns.palette.gold.g, ns.palette.gold.b, 0.12)
    glow:Hide()
    btn.glow = glow
    btn:SetScript("OnClick", function()
      UI.SwitchPage(def.index)
    end)
    railButtons[def.index] = btn
  end
  return rail
end

-- --------------------------------------------------------- banner ----

local function buildBanner(parent)
  local banner = CreateFrame("Frame", nil, parent)
  banner:SetHeight(28)
  banner:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  banner:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
  Skin.ApplyPanel(banner, { base = ns.palette.obsidian, borderAlpha = 0.5 })
  local text = Widgets.Text(banner, "body", "")
  text:SetPoint("CENTER")
  banner.text = text
  banner:Hide()
  return banner
end

function UI.ShowBanner(text, colorName, seconds)
  if not bannerFrame then
    return
  end
  local color = ns.palette[colorName] or ns.palette.gold
  if type(color) == "function" then
    color = color()
  end
  bannerFrame.text:SetText(text or "")
  Skin.ColorText(bannerFrame.text, color)
  bannerFrame:Show()
  if bannerTimer then
    bannerTimer:Cancel()
    bannerTimer = nil
  end
  local dur = Skin.MotionMs(1) > 0 and (seconds or 6) or 0
  bannerTimer = C_Timer.After(dur, function()
    bannerFrame:Hide()
    bannerTimer = nil
  end)
end

-- -------------------------------------------------------- footer ----

local function buildFooter(parent)
  local footer = CreateFrame("Frame", nil, parent)
  footer:SetPoint("BOTTOMLEFT")
  footer:SetPoint("BOTTOMRIGHT")
  footer:SetHeight(FOOTER_H)
  Skin.ApplyPanel(footer, { base = ns.palette.obsidian, borderAlpha = 0.4 })

  statusCombat = Widgets.Text(footer, "small", "Combat: —")
  statusCombat:SetPoint("LEFT", footer, "LEFT", 16, 0)
  statusInstance = Widgets.Text(footer, "small", "Traffic: —")
  statusInstance:SetPoint("LEFT", statusCombat, "RIGHT", 24, 0)
  statusBaseline = Widgets.Text(footer, "small", "Baseline: —")
  statusBaseline:SetPoint("LEFT", statusInstance, "RIGHT", 24, 0)

  local restore = Widgets.Button(footer, {
    label = "Restore my settings",
    primary = true,
    onClick = function()
      UI.RequestRestore()
    end,
  })
  restore:SetWidth(180)
  restore:SetPoint("RIGHT", footer, "RIGHT", -14, 0)
  return footer
end

-- ------------------------------------------------------- restore ----

function UI.RequestRestore()
  if ns.cvarGuard.IsHolding() then
    ns.lab.Cancel()
    UI.ShowBanner("Test ended — settings restored.", "gainColor", 6)
    return
  end
  local mismatches = ns.cvarGuard.Mismatches()
  if not mismatches then
    UI.ShowBanner("Nothing to restore — your settings match your saved baseline.", "textDim", 6)
    return
  end
  ns.cvarGuard.RestoreFromBaseline(mismatches)
  UI.ShowBanner("Restored " .. #mismatches .. " setting(s) from your baseline.", "gainColor", 6)
end

function UI.ShowRestorePrompt(payload)
  local lines = { "Some graphics settings differ from your saved baseline." }
  local show = math.min(6, payload.count)
  for i = 1, show do
    local m = payload.all[i]
    lines[#lines + 1] = ("- %s: %s (baseline %s)"):format(m.key, m.current, m.baseline)
  end
  if payload.count > show then
    lines[#lines + 1] = ("...and %d more."):format(payload.count - show)
  end
  lines[#lines + 1] = "Restore now?"
  Widgets.Confirm(table.concat(lines, "\n"), function()
    ns.cvarGuard.RestoreFromBaseline(payload.all)
    UI.ShowBanner("Restored your settings from the last clean logout baseline.", "gainColor", 8)
  end)
end

-- -------------------------------------------------------- pages ----

function UI.SwitchPage(index)
  local def = pageDefs[index]
  if not def or not frame then
    return
  end
  if currentPage and pageDefs[currentPage] and pageFrames[currentPage] then
    local old = pageDefs[currentPage]
    if old.onHide then
      old.onHide(pageFrames[currentPage])
    end
    pageFrames[currentPage]:Hide()
  end
  currentPage = index
  ns.db.ui.page = index
  if not pageFrames[index] then
    pageFrames[index] = def.create(contentArea)
    pageFrames[index]:Hide()
    pageFrames[index]:SetAllPoints(contentArea)
  end
  pageFrames[index]:Show()
  if def.onShow then
    def.onShow(pageFrames[index])
  end
  highlightRail(index)
end

local function ensureWindow()
  if frame then
    return frame
  end
  frame = CreateFrame("Frame", "CrowdCalmLabFrame", UIParent)
  frame:SetSize(MAIN_W, MAIN_H)
  frame:SetPoint("CENTER")
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    self:StartMoving()
  end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    ns.db.ui.point = { point = point, x = x, y = y }
  end)
  pcall(frame.SetClampedToScreen, frame, true)
  if not pcall(frame.SetResizeBounds, frame, MIN_W, MIN_H, 2400, 1600) then
    pcall(frame.SetMinResize, frame, MIN_W, MIN_H)
    pcall(frame.SetMaxResize, frame, 2400, 1600)
  end

  Skin.ApplyShadow(frame, frame)

  local bg = CreateFrame("Frame", nil, frame)
  bg:SetAllPoints()
  Skin.ApplyPanel(bg, { base = ns.palette.panel, vignette = true, noise = true })

  buildHeader(frame)

  contentArea = CreateFrame("Frame", nil, frame)
  contentArea:SetPoint("TOPLEFT", frame, "TOPLEFT", RAIL_W, -HEADER_H)
  contentArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, FOOTER_H)
  bannerFrame = buildBanner(contentArea)

  buildRail(frame)
  buildFooter(frame)

  -- Esc closes (ledgered: UISpecialFrames is the client-supported path)
  local registered = false
  for _, name in ipairs(UISpecialFrames) do
    if name == "CrowdCalmLabFrame" then
      registered = true
      break
    end
  end
  if not registered then
    table.insert(UISpecialFrames, "CrowdCalmLabFrame")
  end

  frame:EnableKeyboard(true)
  frame:SetScript("OnKeyDown", function(_, key)
    if key == "ESCAPE" then
      frame:Hide()
      return
    end
    local n = tonumber(key)
    if n and n >= 1 and n <= 7 and pageDefs[n] then
      UI.SwitchPage(n)
    end
  end)

  frame:SetScript("OnShow", function()
    if not updateTicker then
      updateTicker = Util.AcquireTicker("mainwindow-update", 1.0, function()
        local fps = (ns.meter and ns.meter.live and ns.meter.live.fps) or 0
        local gain = ns.palette.gainColor()
        local danger = ns.palette.danger
        local c = fps >= 50 and gain or (fps >= 30 and ns.palette.gold or danger)
        fpsDot:SetColorTexture(c.r, c.g, c.b, 1)
        fpsText:SetText(string.format("%.0f", fps))
        ns.context.Update()
        if statusCombat then
          statusCombat:SetText(InCombatLockdown() and "Combat: yes" or "Combat: no")
        end
        if statusInstance then
          statusInstance:SetText("Traffic: " .. (ns.context and ns.context.Label() or "—"))
        end
        if statusBaseline then
          statusBaseline:SetText(ns.cvarGuard.HasBaseline() and "Baseline: saved" or "Baseline: none")
        end
        local def = pageDefs[currentPage]
        if def and def.onTick then
          def.onTick(pageFrames[currentPage])
        end
      end)
    end
    ns.meter.Acquire()
    local saved = ns.db.ui and ns.db.ui.page
    if saved and pageDefs[saved] then
      UI.SwitchPage(saved)
    elseif pageDefs[1] then
      UI.SwitchPage(1)
    end
  end)

  frame:SetScript("OnHide", function()
    if updateTicker then
      Util.ReleaseTicker("mainwindow-update")
      updateTicker = nil
    end
    for index, pageFrame in pairs(pageFrames) do
      local def = pageDefs[index]
      if def and def.onHide then
        def.onHide(pageFrame)
      end
    end
    ns.meter.Release()
  end)

  local scale = ns.db.ui.scale or 1
  frame:SetScale(math.max(0.7, math.min(1.4, scale)))
  if ns.db.ui.point and ns.db.ui.point.x then
    frame:ClearAllPoints()
    frame:SetPoint(ns.db.ui.point.point or "CENTER", UIParent, ns.db.ui.point.point or "CENTER", ns.db.ui.point.x, ns.db.ui.point.y)
  end
  return frame
end

function UI.ApplyUIScale(scale)
  scale = math.max(0.7, math.min(1.4, scale or 1))
  ns.db.ui.scale = scale
  if frame then
    frame:SetScale(scale)
  end
end

function UI.Toggle()
  local f = ensureWindow()
  if f:IsShown() then
    f:Hide()
  else
    f:Show()
  end
end

function UI.Show()
  ensureWindow():Show()
end

function UI.Hide()
  if frame then
    frame:Hide()
  end
end

function UI.IsShown()
  return frame ~= nil and frame:IsShown()
end

-- Wired by MainWindow so CVarGuard's login prompt lands in the UI.
ns.cvarGuard.restorePromptHandler = UI.ShowRestorePrompt
