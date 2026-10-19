-- UI/MinimapButton.lua — draggable minimap button (owner request for
-- pre.2): 32px disc with a small square addon logo and a ring.tga bezel
-- (pre.4: one generated ring replaces the 12 rotated arc segments), plus
-- a hover glow. Left-click toggles the window; dragging orbits it around
-- the minimap rim. OnUpdate exists ONLY while the button is held
-- (disclosed in DESIGN.md); otherwise zero idle cost. Preference:
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

  -- pre.4: one generated ring texture is the bezel (the old design
  -- stacked 12 rotated arc segments around the rim)
  local ring = button:CreateTexture(nil, "ARTWORK")
  ring:SetAllPoints()
  ring:SetTexture(ns.skin.mediaPath .. "ring.tga")
  ring:SetVertexColor(p.line.r, p.line.g, p.line.b, 0.95)

  -- pre.4: smaller, uncropped square logo centered on the disc
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(ns.skin.mediaPath .. "icon.tga")
  icon:SetPoint("TOPLEFT", 7, -7)
  icon:SetPoint("BOTTOMRIGHT", -7, 7)
  icon:SetTexCoord(0, 1, 0, 1)

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

  -- pre.4: follow the minimap when it resizes (UI scale, tracking
  -- options, other addons); HookScript stacks, so guard for one hook
  if not minimapButton._sizeHooked then
    minimapButton._sizeHooked = true
    Minimap:HookScript("OnSizeChanged", position)
  end
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
