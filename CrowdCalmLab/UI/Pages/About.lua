-- UI/Pages/About.lua — version, how it works, the safety promise in plain
-- words, a copyable project URL, the no-donations line, and this addon's
-- own self-check numbers (brief section 6.7 + 5.9).
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
  versionFs:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  Skin.ColorText(versionFs, ns.palette.textDim)

  local how = Widgets.Text(frame, "body", L("about_how"))
  how:SetPoint("TOPLEFT", versionFs, "BOTTOMLEFT", 0, -18)
  how:SetWidth(frame:GetWidth() - pad * 2)
  how:SetJustifyH("LEFT")

  local safety = Widgets.Text(frame, "body", L("about_safety"))
  safety:SetPoint("TOPLEFT", how, "BOTTOMLEFT", 0, -14)
  safety:SetWidth(frame:GetWidth() - pad * 2)
  safety:SetJustifyH("LEFT")
  Skin.ColorText(safety, ns.palette.gainColor())

  -- copyable URL
  local url = L("about_url")
  local urlBox = CreateFrame("EditBox", nil, frame)
  urlBox:SetHeight(26)
  urlBox:SetWidth(360)
  urlBox:SetPoint("TOPLEFT", safety, "BOTTOMLEFT", 0, -18)
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

  local nodon = Widgets.Text(frame, "small", L("about_nodonations"))
  nodon:SetPoint("TOPLEFT", urlBox, "BOTTOMLEFT", 0, -12)
  Skin.ColorText(nodon, ns.palette.textDim)

  -- self check
  local scTitle = Widgets.Text(frame, "header", L("about_selfcheck"))
  scTitle:SetPoint("TOPLEFT", nodon, "BOTTOMLEFT", 0, -24)
  local scLine = Widgets.Text(frame, "small", "")
  scLine:SetPoint("TOPLEFT", scTitle, "BOTTOMLEFT", 0, -8)
  local scTarget = Widgets.Text(frame, "small", L("selfcheck_target"))
  scTarget:SetPoint("TOPLEFT", scLine, "BOTTOMLEFT", 0, -4)
  Skin.ColorText(scTarget, ns.palette.textDim)

  local memBtn = Widgets.Button(frame, {
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
