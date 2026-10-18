-- UI/MinimapButton.lua — draggable minimap button (owner request for
-- pre.2): 32px disc with the addon logo, a 12-segment arc.tga bezel
-- (same geometry family as Widgets.ArcGauge; no new assets), and a hover
-- glow. Left-click toggles the window; dragging orbits it around the
-- minimap rim. OnUpdate exists ONLY while the button is held (disclosed
-- in DESIGN.md); otherwise zero idle cost. Preference:
-- settings.ui.minimapButton (default on), angle: ui.minimapAngle.
local ADDON_NAME, ns = ...

local L = ns.L
local atan2 = math.atan2 or function(y, x)
  return math.atan(y, x)
end

local minimapButton = {}
ns.minimapButton = minimapButton

local button = nil

-- Assumption (retail default): the Minimap sits in UIParent at scale 1, so
-- GetCursorPosition (UIParent units) and Minimap:GetCenter (parent units)
-- are directly comparable and GetWidth() equals the on-screen radius basis.
local function position()
  if not button then
    return
  end
  local angle = math.rad(ns.db.ui.minimapAngle or 45)
  local radius = (Minimap:GetWidth() / 2) + 6
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function angleFromCursor()
  local px, py = GetCursorPosition()
  local cx, cy = Minimap:GetCenter()
  return atan2(py - cy, px - cx)
end

local function ensure()
  if button then
    return
  end
  button = CreateFrame("Button", "CrowdCalmLabMinimapButton", Minimap)
  button:SetSize(32, 32)
  button:RegisterForClicks("AnyUp")
  button:RegisterForDrag("LeftButton")

  local p = ns.palette

  local bg = button:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(p.obsidian.r, p.obsidian.g, p.obsidian.b, 0.85)

  -- 12 tangential arc segments = the bezel ring. Sizes mirror
  -- Widgets.ArcGauge scaled to this radius (tangential ~8, thickness
  -- ~radius/4, rotation angle - pi/2).
  for i = 1, 12 do
    local seg = button:CreateTexture(nil, "ARTWORK")
    seg:SetTexture(ns.skin.mediaPath .. "arc.tga")
    seg:SetSize(8, 4)
    local angle = (i / 12) * 2 * math.pi
    seg:SetPoint("CENTER", button, "CENTER", math.cos(angle) * 15, math.sin(angle) * 15)
    pcall(seg.SetRotation, seg, angle - math.pi / 2)
    seg:SetVertexColor(p.line.r, p.line.g, p.line.b, 0.9)
  end

  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(ns.skin.mediaPath .. "icon.tga")
  icon:SetPoint("TOPLEFT", 5, -5)
  icon:SetPoint("BOTTOMRIGHT", -5, 5)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  local glow = button:CreateTexture(nil, "OVERLAY")
  glow:SetAllPoints()
  glow:SetTexture(ns.skin.mediaPath .. "glow.tga")
  glow:SetBlendMode("ADD")
  glow:SetVertexColor(p.gold.r, p.gold.g, p.gold.b, 0.4)
  glow:Hide()

  button:SetScript("OnEnter", function(self)
    glow:Show()
    local tip = GameTooltip
    tip:SetOwner(self, "ANCHOR_LEFT")
    tip:AddLine(L("mm_title"), p.gold.r, p.gold.g, p.gold.b)
    tip:AddLine(L("mm_click"))
    tip:AddLine(L("mm_drag"))
    tip:Show()
  end)
  button:SetScript("OnLeave", function()
    glow:Hide()
    GameTooltip:Hide()
  end)

  button:SetScript("OnClick", function()
    ns.ui.Toggle()
  end)

  -- Orbit drag: OnUpdate lives only between drag start and stop.
  button:SetMovable(true)
  button:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      ns.db.ui.minimapAngle = math.deg(angleFromCursor())
      position()
    end)
  end)
  button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)

  position()
end

-- Called at PLAYER_LOGIN and from the Settings checkbox.
function minimapButton.Refresh()
  local on = ns.db.settings.ui.minimapButton
  if on then
    ensure()
    button:Show()
    position()
  elseif button then
    button:Hide()
  end
end

ns.onLogin(function()
  minimapButton.Refresh()
end)
