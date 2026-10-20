-- UI/Pages/About.lua — version, four info cards (what it does, safety
-- promise, privacy, this addon's own self-check), a copyable project URL
-- (brief section 6.7 + 5.9). Pre.7 redesign (owner screenshot): loose
-- paragraphs became a 2x2 card grid with short bullets.
local ADDON_NAME, ns = ...

local Widgets = ns.widgets
local Skin = ns.skin
local L = ns.L
local Lfmt = ns.Lfmt

local function create(parent)
  local frame = parent
  local pad = 16

  local version = "1.0.0"
  local ok, v = pcall(GetAddOnMetadata, ADDON_NAME, "Version")
  if ok and type(v) == "string" and v ~= "" then
    version = v
  end
  local title = Widgets.Text(frame, "title", L("app_title"))
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
  Skin.ColorText(title, ns.palette.goldBright)
  local versionFs = Widgets.Text(frame, "body", Lfmt("about_version_pattern", version))
  versionFs:SetPoint("LEFT", title, "RIGHT", 14, 0)
  Skin.ColorText(versionFs, ns.palette.textDim)
  local chipFs = Widgets.Text(frame, "small", ns.compat and ns.compat.chip or "")
  chipFs:SetPoint("LEFT", versionFs, "RIGHT", 14, 0)
  Skin.ColorText(chipFs, ns.palette.textDim)

  -- ------------------------------------------------------------ cards ----
  local CARD_W, CARD_H = 336, 152
  local ROW1_Y, ROW2_Y = -72, -238

  local function makeCard(x, y, titleText)
    local c = Widgets.Panel(frame, { base = ns.palette.raised, borderAlpha = 0.6 })
    c:SetSize(CARD_W, CARD_H)
    c:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
    local t = Widgets.Text(c, "small", titleText)
    t:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -10)
    Skin.ColorText(t, ns.palette.goldBright)
    return c, t
  end

  -- bullets stack downward from the card title; "-" keeps the glyph gate
  -- happy (no fancy bullets)
  local function addBullets(titleFs, card, firstText, rest, color)
    local prev = titleFs
    local all = {}
    if firstText then
      all[#all + 1] = firstText
    end
    for _, b in ipairs(rest or {}) do
      all[#all + 1] = b
    end
    for i, text in ipairs(all) do
      local fs = Widgets.Text(card, "small", "- " .. text)
      fs:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, i == 1 and -12 or -6)
      fs:SetWidth(CARD_W - 24)
      fs:SetJustifyH("LEFT")
      if color then
        Skin.ColorText(fs, color)
      end
      prev = fs
    end
    return prev
  end

  local whatCard, whatTitle = makeCard(pad, ROW1_Y, L("about_what_title"))
  addBullets(whatTitle, whatCard, nil, { L("about_what_1"), L("about_what_2"), L("about_what_3") })

  local safetyCard, safetyTitle = makeCard(pad + CARD_W + 16, ROW1_Y, L("about_safety_title"))
  addBullets(
    safetyTitle,
    safetyCard,
    nil,
    { L("about_safety_1"), L("about_safety_2"), L("about_safety_3") },
    ns.palette.gainColor()
  )

  local privacyCard, privacyTitle = makeCard(pad, ROW2_Y, L("about_privacy_title"))
  addBullets(privacyTitle, privacyCard, L("about_privacy_1"), { L("about_nodonations") }, ns.palette.textDim)

  -- self check lives in the fourth card (pre.7: moved out of the loose
  -- paragraph flow, same numbers and the Read memory button)
  local scCard, scTitle = makeCard(pad + CARD_W + 16, ROW2_Y, L("about_selfcheck"))
  local scLine = Widgets.Text(scCard, "small", "")
  scLine:SetPoint("TOPLEFT", scCard, "TOPLEFT", 12, -32)
  scLine:SetWidth(CARD_W - 24)
  scLine:SetJustifyH("LEFT")
  local scTarget = Widgets.Text(scCard, "small", L("selfcheck_target"))
  scTarget:SetPoint("TOPLEFT", scLine, "BOTTOMLEFT", 0, -6)
  Skin.ColorText(scTarget, ns.palette.textDim)

  local memBtn = Widgets.Button(scCard, {
    small = true,
    label = L("read_memory"),
    onClick = function()
      local mb = ns.selfCheck.ReadMemory()
      if frame.refreshSelfcheck then
        frame.refreshSelfcheck()
      end
      if mb then
        ns.ui.ShowBanner(string.format("Own memory: %.1f MB", mb), "gainColor", 5)
      end
    end,
  })
  memBtn:SetWidth(140)
  memBtn:SetPoint("TOPLEFT", scTarget, "BOTTOMLEFT", 0, -10)

  function frame.refreshSelfcheck()
    local snap = ns.selfCheck.Snapshot(ns.ui.IsShown())
    if snap.recentMs then
      scLine:SetText(Lfmt("selfcheck_line", snap.recentMs, snap.peakMs or 0, snap.pooled or 0, snap.pooledFree or 0, snap.tickers or 0, snap.logSize or 0))
      local meets = ns.selfCheck.MeetsTarget()
      if meets == false then
        Skin.ColorText(scLine, ns.palette.costColor())
      else
        Skin.ColorText(scLine, ns.palette.gainColor())
      end
    else
      scLine:SetText(L("selfcheck_unavailable"))
      Skin.ColorText(scLine, ns.palette.textDim)
    end
  end

  -- ------------------------------------------------------------ URL ----
  local url = L("about_url")
  local urlBox = CreateFrame("EditBox", nil, frame)
  urlBox:SetHeight(26)
  urlBox:SetWidth(360)
  urlBox:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, ROW2_Y - CARD_H - 18)
  Skin.ApplyPanel(urlBox, { base = ns.palette.obsidian, borderAlpha = 0.6 })
  Widgets.ApplyEditBoxFont(urlBox, "small")
  urlBox:SetText(url)
  urlBox:SetFocus(false)
  urlBox:HighlightText()
  urlBox:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  local urlHint = Widgets.Text(frame, "small", "Ctrl+C to copy")
  urlHint:SetPoint("LEFT", urlBox, "RIGHT", 10, 0)
  Skin.ColorText(urlHint, ns.palette.textDim)

  frame:SetScript("OnShow", function()
    if frame.refreshSelfcheck then
      frame.refreshSelfcheck()
    end
  end)
  frame.refresh = function()
    if frame.refreshSelfcheck then
      frame.refreshSelfcheck()
    end
  end
  return frame
end

ns.ui.RegisterPage({
  index = 7,
  name = L("page_about"),
  icon = "icon_about.tga",
  create = create,
  onTick = function(page)
    if page and page.refresh then
      page.refresh()
    end
  end,
})
