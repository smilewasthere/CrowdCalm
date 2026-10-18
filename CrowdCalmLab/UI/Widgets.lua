-- UI/Widgets.lua — pooled, fallback-first components (brief section 7.6):
-- text, panels, buttons, checkboxes, sliders, dropdowns, tooltips, empty
-- states, confirm popup, sparkline (120 bars), arc gauge (~40 segments),
-- progress ring (cooldown with bar fallback), count-up animation, and a
-- custom wheel-scroll pooled row list (ledgered deviation from ScrollBox:
-- avoids template drift across the two clients).
local ADDON_NAME, ns = ...

local Util = ns.util
local Skin = ns.skin
local Widgets = {}
ns.widgets = Widgets

-- ------------------------------------------------------------ text ----

function Widgets.Text(parent, sizeKey, text)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFontObject(Skin.Font(sizeKey or "body"))
  -- font-size preference applies only to the string itself (never to the
  -- shared Blizzard font objects): override path/height per string.
  local db = ns.db
  if db and db.settings and db.settings.ui and db.settings.ui.fontSize then
    local mult = db.settings.ui.fontSize / 14
    if mult ~= 1 then
      local font = Skin.Font(sizeKey or "body")
      local path, height, flags = font:GetFont()
      if type(path) == "string" and type(height) == "number" then
        fs:SetFont(path, math.floor(height * mult + 0.5), flags)
      end
    end
  end
  fs:SetText(text or "")
  return fs
end

-- muted-aware sound (SOUNDKIT table may be absent on some clients)
function Widgets.PlaySound(skit)
  local db = ns.db
  if db and db.settings and db.settings.ui and db.settings.ui.muted then
    return
  end
  pcall(PlaySound, skit)
end

function Widgets.Panel(parent, opts)
  local frame = CreateFrame("Frame", nil, parent)
  Skin.ApplyPanel(frame, opts)
  return frame
end

function Widgets.Button(parent, opts)
  local btn = CreateFrame("Button", nil, parent)
  Skin.Button(btn, opts)
  if opts and opts.onClick then
    btn:SetScript("OnClick", opts.onClick)
  end
  return btn
end

-- -------------------------------------------------------- checkbox ----

local checkboxTemplateOk = nil

function Widgets.Checkbox(parent, opts)
  opts = opts or {}
  local onToggle = opts.onToggle
  if checkboxTemplateOk == nil then
    local ok, frame = pcall(CreateFrame, "CheckButton", nil, parent, "UICheckButtonTemplate")
    checkboxTemplateOk = ok and (frame ~= nil) and true or false
    if ok and frame then
      frame:Hide()
    end
  end
  local box
  if checkboxTemplateOk then
    box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    box:SetChecked(opts.checked and true or false)
    box:SetScript("OnClick", function(self)
      if onToggle then
        onToggle(self:GetChecked() and true or false)
      end
    end)
  else
    -- custom fallback: 24 px square with a gold fill when checked
    box = CreateFrame("Button", nil, parent)
    box:SetSize(24, 24)
    local border = box:CreateTexture(nil, "ARTWORK")
    border:SetAllPoints()
    border:SetColorTexture(ns.palette.line.r, ns.palette.line.g, ns.palette.line.b, 1)
    local fill = box:CreateTexture(nil, "ARTWORK")
    fill:SetSize(14, 14)
    fill:SetPoint("CENTER")
    fill:SetColorTexture(ns.palette.gold.r, ns.palette.gold.g, ns.palette.gold.b, 1)
    box.fill = fill
    box.checked = opts.checked and true or false
    local function apply()
      if box.checked then
        fill:Show()
      else
        fill:Hide()
      end
    end
    apply()
    box:SetScript("OnClick", function(self)
      self.checked = not self.checked
      apply()
      if onToggle then
        onToggle(self.checked)
      end
    end)
    function box:SetChecked(v)
      self.checked = v and true or false
      apply()
    end
    function box:GetChecked()
      return self.checked
    end
  end
  if opts.label then
    local label = Widgets.Text(box, "body", opts.label)
    label:SetPoint("LEFT", box, "RIGHT", 6, 0)
    box.label = label
  end
  return box
end

-- ---------------------------------------------------------- slider ----

function Widgets.Slider(parent, opts)
  opts = opts or {}
  local slider = CreateFrame("Slider", nil, parent)
  slider:SetOrientation("HORIZONTAL")
  slider:SetSize(opts.width or 160, 16)
  slider:SetMinMaxValues(opts.min or 0, opts.max or 1)
  if opts.step then
    slider:SetValueStep(opts.step)
  end
  local thumb = slider:CreateTexture(nil, "ARTWORK")
  thumb:SetSize(14, 16)
  thumb:SetColorTexture(ns.palette.gold.r, ns.palette.gold.g, ns.palette.gold.b, 1)
  slider:SetThumbTexture(thumb)
  local bg = slider:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(ns.palette.obsidian.r, ns.palette.obsidian.g, ns.palette.obsidian.b, 0.8)

  local valueText = Widgets.Text(slider, "small", "")
  valueText:SetPoint("LEFT", slider, "RIGHT", 8, 0)
  slider.valueText = valueText

  local guard = false
  local function showValue(v)
    valueText:SetText(string.format("%.2f", v))
  end
  slider:SetScript("OnValueChanged", function(_, value)
    if guard then
      return
    end
    showValue(value)
    if opts.onChange then
      opts.onChange(value)
    end
  end)
  guard = true
  slider:SetValue(opts.value or (opts.min or 0))
  guard = false
  showValue(opts.value or (opts.min or 0))
  return slider
end

-- --------------------------------------------------------- dropdown ----

function Widgets.Dropdown(parent, opts)
  opts = opts or {}
  local options = opts.options or {}
  local selectedId = opts.selectedId
  local menuRows = {}

  local btn = CreateFrame("Button", nil, parent)
  Skin.Button(btn, { height = 26 })
  btn:SetWidth(opts.width or 160)
  local buttonText = btn.text

  local menu = nil
  local catcher = CreateFrame("Button", nil, UIParent)
  catcher:SetAllPoints(UIParent)
  catcher:Hide()
  catcher:SetScript("OnClick", function()
    if menu then
      menu:Hide()
    end
  end)

  menu = CreateFrame("Frame", nil, parent)
  Skin.ApplyPanel(menu, { base = ns.palette.raised })
  menu:SetWidth(opts.width or 160)
  menu:SetHeight(#options * 24 + 8)
  menu:SetFrameStrata("DIALOG")
  menu:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
  menu:Hide()
  menu:SetScript("OnHide", function()
    catcher:Hide()
  end)

  local function labelFor(id)
    for _, opt in ipairs(options) do
      if opt.id == id then
        return opt.label
      end
    end
    return ""
  end

  local function select(id)
    selectedId = id
    buttonText:SetText(labelFor(id))
    if opts.onChange then
      opts.onChange(id)
    end
  end

  for i, opt in ipairs(options) do
    local row = CreateFrame("Button", nil, menu)
    row:SetHeight(24)
    row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 24)
    row:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * 24)
    local rowText = Widgets.Text(row, "body", opt.label)
    rowText:SetPoint("LEFT", 6, 0)
    row:SetScript("OnEnter", function()
      rowText:SetTextColor(ns.palette.goldBright.r, ns.palette.goldBright.g, ns.palette.goldBright.b, 1)
    end)
    row:SetScript("OnLeave", function()
      rowText:SetTextColor(ns.palette.text.r, ns.palette.text.g, ns.palette.text.b, 1)
    end)
    row:SetScript("OnClick", function()
      select(opt.id)
      menu:Hide()
    end)
    menuRows[i] = row
  end

  btn:SetScript("OnClick", function()
    if menu:IsShown() then
      menu:Hide()
    else
      menu:Show()
      catcher:Show()
      menu:Raise()
    end
  end)

  buttonText:SetText(labelFor(selectedId))
  btn.selectedId = selectedId
  return btn
end

-- ---------------------------------------------------------- tooltip ----

-- getLines() is called on hover (display path; allocation is fine there).
function Widgets.TooltipLines(frame, getLines)
  frame:HookScript("OnEnter", function(self)
    local tip = GameTooltip
    tip:SetOwner(self, "ANCHOR_RIGHT")
    local lines = getLines()
    for i = 1, #lines do
      local line = lines[i]
      if type(line) == "table" then
        tip:AddLine(line.text or "", line.r, line.g, line.b)
      else
        tip:AddLine(line)
      end
    end
    tip:Show()
  end)
  frame:HookScript("OnLeave", function()
    GameTooltip:Hide()
  end)
end

-- ------------------------------------------------------ empty state ----

function Widgets.EmptyState(parent, text)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetAllPoints(parent)
  local icon = frame:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(ns.skin.mediaPath .. "icon.tga")
  icon:SetSize(48, 48)
  icon:SetPoint("TOP", frame, "TOP", 0, -40)
  local label = Widgets.Text(frame, "body", text or "")
  label:SetPoint("TOP", icon, "BOTTOM", 0, -12)
  label:SetJustifyH("CENTER")
  frame.text = label
  return frame
end

-- --------------------------------------------------------- confirm ----

local pendingYes = nil
local confirmRegistered = false

function Widgets.Confirm(text, onYes)
  if not confirmRegistered then
    StaticPopupDialogs["CCL_CONFIRM"] = {
      text = "%s",
      button1 = YES,
      button2 = NO,
      OnAccept = function()
        if pendingYes then
          pendingYes()
        end
        pendingYes = nil
      end,
      OnCancel = function()
        pendingYes = nil
      end,
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
    }
    confirmRegistered = true
  end
  pendingYes = onYes
  StaticPopup_Show("CCL_CONFIRM", text)
end

-- --------------------------------------------------------- count-up ----

local anims = {}
local animTicker = nil

local function easeOut(t)
  local inv = 1 - t
  return 1 - inv * inv
end

local function onAnimTick()
  local now = GetTime()
  for i = #anims, 1, -1 do
    local a = anims[i]
    local t = (now - a.start) / a.dur
    if t >= 1 then
      a.fs:SetFormattedText(a.format, a.to)
      table.remove(anims, i)
    else
      local v = a.from + (a.to - a.from) * easeOut(t)
      a.fs:SetFormattedText(a.format, v)
    end
  end
  if #anims == 0 and animTicker then
    Util.ReleaseTicker("widget-anim")
    animTicker = nil
  end
end

-- format must accept one number, e.g. "%.0f" or "+%.1f"
function Widgets.CountUp(fs, from, to, durMs, format)
  if Skin.MotionMs(durMs or 400) == 0 then
    fs:SetFormattedText(format or "%.0f", to)
    return
  end
  if not animTicker then
    animTicker = Util.AcquireTicker("widget-anim", 0.03, onAnimTick)
  end
  anims[#anims + 1] = {
    fs = fs,
    from = from or 0,
    to = to or 0,
    start = GetTime(),
    dur = (durMs or 400) / 1000,
    format = format or "%.0f",
  }
end

-- -------------------------------------------------------- sparkline ----

local sparkSeq = 0

function Widgets.Sparkline(parent, width, height, barCount)
  sparkSeq = sparkSeq + 1
  local key = "sparkline-" .. sparkSeq
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetSize(width, height)
  local n = barCount or 120
  local bars = {}
  local spikes = {}
  local barW = width / n
  for i = 1, n do
    local bar = frame:CreateTexture(nil, "ARTWORK")
    bar:SetWidth(math.max(1, barW - 1))
    bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", (i - 1) * barW, 0)
    bar:SetHeight(1)
    bar:Hide()
    bars[i] = bar
    local spike = frame:CreateTexture(nil, "OVERLAY")
    spike:SetWidth(math.max(1, barW - 1))
    spike:SetHeight(3)
    spike:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", (i - 1) * barW, height - 3)
    spike:Hide()
    spikes[i] = spike
  end
  local bg = frame:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(ns.palette.obsidian.r, ns.palette.obsidian.g, ns.palette.obsidian.b, 0.6)

  function frame:Update()
    local history = ns.meter.history
    local spikeRing = ns.meter.spikes
    local gain = ns.palette.gainColor()
    local count = history:Count()
    if count == 0 then
      for i = 1, n do
        bars[i]:Hide()
        spikes[i]:Hide()
      end
      return
    end
    local maxFps = 1
    local start = math.max(1, count - n + 1)
    local window = count - start + 1
    for i = 1, window do
      local v = history:Get(start + i - 1)
      if v and v > maxFps then
        maxFps = v
      end
    end
    for i = 1, n do
      if i <= window then
        local histIndex = start + i - 1 -- i = 1 is leftmost = oldest
        local v = history:Get(histIndex) or 0
        bars[i]:Show()
        bars[i]:SetHeight(math.max(1, (v / maxFps) * (height - 4)))
        bars[i]:SetColorTexture(gain.r, gain.g, gain.b, 0.55)
        if spikeRing:Get(histIndex) == 1 then
          spikes[i]:Show()
        else
          spikes[i]:Hide()
        end
      else
        bars[i]:Hide()
        spikes[i]:Hide()
      end
    end
    local danger = ns.palette.danger
    for i = 1, n do
      spikes[i]:SetColorTexture(danger.r, danger.g, danger.b, 1)
    end
  end

  function frame:Play()
    if not Util.HasTicker(key) then
      Util.AcquireTicker(key, 1.0, function()
        frame:Update()
      end)
      frame:Update()
    end
  end

  function frame:Stop()
    if Util.HasTicker(key) then
      Util.ReleaseTicker(key)
    end
  end
  return frame
end

-- -------------------------------------------------------- arc gauge ----

local ARC_SEGMENTS = 40

function Widgets.ArcGauge(parent, size)
  size = size or 160
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetSize(size, size / 2 + 8)
  local segs = {}
  local radius = size / 2 - 8
  local cx, cy = size / 2, size / 2
  for i = 1, ARC_SEGMENTS do
    local seg = frame:CreateTexture(nil, "ARTWORK")
    seg:SetTexture(ns.skin.mediaPath .. "arc.tga")
    local angle = math.pi * (1 - (i - 1) / (ARC_SEGMENTS - 1)) -- pi..0
    seg:SetSize(8, 18)
    seg:SetPoint("CENTER", frame, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
    pcall(seg.SetRotation, seg, angle - math.pi / 2)
    segs[i] = seg
  end
  frame.value = 0

  function frame:SetValue(v)
    v = math.max(0, math.min(1, v or 0))
    if math.abs(v - frame.value) < 0.005 then
      return
    end
    frame.value = v
    local lit = math.floor(v * ARC_SEGMENTS + 0.5)
    local gain = ns.palette.gainColor()
    local line = ns.palette.line
    local cost = ns.palette.costColor()
    for i = 1, ARC_SEGMENTS do
      local seg = segs[i]
      if i <= lit then
        local c = (i > ARC_SEGMENTS - 5) and cost or gain
        seg:SetVertexColor(c.r, c.g, c.b, 1)
        seg:Show()
      else
        seg:SetVertexColor(line.r, line.g, line.b, 0.8)
        seg:Show()
      end
    end
  end

  frame:SetValue(0)
  return frame
end

-- ------------------------------------------------------------ ring ----

function Widgets.Ring(parent, size)
  size = size or 48
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetSize(size, size)
  local fallbackBar = nil
  local cooldown = nil
  local ok, cd = pcall(CreateFrame, "Cooldown", frame, nil)
  if ok and cd then
    cd:SetAllPoints()
    pcall(cd.SetSwipeTexture, cd, ns.skin.mediaPath .. "sweep.tga")
    pcall(cd.SetDrawBling, cd, false)
    cooldown = cd
  else
    fallbackBar = frame:CreateTexture(nil, "ARTWORK")
    fallbackBar:SetTexture(ns.skin.mediaPath .. "sweep.tga")
    fallbackBar:SetPoint("BOTTOMLEFT")
    fallbackBar:SetPoint("BOTTOMRIGHT")
    fallbackBar:SetHeight(1)
  end
  frame.cooldown = cooldown
  frame.fallbackBar = fallbackBar

  function frame:Start(durationSeconds)
    local now = GetTime()
    if cooldown then
      cooldown:Clear()
      pcall(cooldown.SetCooldown, cooldown, now, durationSeconds)
    end
    frame.duration = durationSeconds
    frame.startedAt = now
  end

  function frame:Stop()
    if cooldown then
      cooldown:Clear()
    end
    if fallbackBar then
      fallbackBar:SetHeight(1)
    end
    frame.duration = nil
  end

  function frame:UpdateFallback()
    if not fallbackBar or not frame.duration then
      return
    end
    local elapsed = GetTime() - (frame.startedAt or 0)
    local frac = math.max(0, math.min(1, elapsed / frame.duration))
    fallbackBar:SetHeight(math.max(1, frac * size))
  end
  return frame
end

-- -------------------------------------------------------- row list ----

function Widgets.RowList(parent, opts)
  opts = opts or {}
  local rowHeight = opts.rowHeight or 28
  local container = CreateFrame("Frame", nil, parent)
  container:SetSize(opts.width or parent:GetWidth(), opts.height or parent:GetHeight())
  container:EnableMouseWheel(true)
  local pool = Util.CreateFramePool("Frame", container)
  local rows = {}
  local offset = 0

  local function total()
    if opts.count then
      return opts.count()
    end
    return 0
  end

  local function maxOffset()
    local visible = math.floor(container:GetHeight() / rowHeight)
    local n = total()
    local m = n - visible
    if m < 0 then
      m = 0
    end
    return m
  end

  local function layout()
    local n = total()
    local visible = math.min(math.floor(container:GetHeight() / rowHeight), n)
    while #rows < visible do
      rows[#rows + 1] = pool:Acquire()
    end
    while #rows > visible do
      pool:Release(table.remove(rows))
    end
    for i = 1, #rows do
      local row = rows[i]
      local index = offset + i
      row:SetHeight(rowHeight)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -((i - 1) * rowHeight))
      row:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -((i - 1) * rowHeight))
      if index <= n then
        row:Show()
        if opts.render then
          opts.render(row, index)
        end
      else
        row:Hide()
      end
    end
  end

  container:SetScript("OnMouseWheel", function(_, delta)
    local newOffset = offset - delta
    if newOffset < 0 then
      newOffset = 0
    end
    local m = maxOffset()
    if newOffset > m then
      newOffset = m
    end
    if newOffset ~= offset then
      offset = newOffset
      layout()
    end
  end)

  function container:Refresh()
    local m = maxOffset()
    if offset > m then
      offset = m
    end
    layout()
  end

  function container:RowCount()
    return #rows
  end

  container:Refresh()
  return container
end

-- -------------------------------------------------------- section ----

function Widgets.SectionLabel(parent, text)
  local label = Widgets.Text(parent, "header", text)
  local line = Skin.AccentLine(parent, "BOTTOM", label:GetStringWidth() + 12)
  line:SetPoint("BOTTOM", label, "BOTTOM", 0, -3)
  label.accentLine = line
  return label
end
