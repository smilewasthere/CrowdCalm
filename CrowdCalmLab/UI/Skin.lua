-- UI/Skin.lua — the Azeroth-native premium look (brief section 7): fonts,
-- palette application, panels, borders, gradients, button states. Every
-- feature-detected call has a plain fallback; no atlas names are invented.
local ADDON_NAME, ns = ...

local Skin = {}
ns.skin = Skin

local MEDIA = "Interface\\AddOns\\CrowdCalmLab\\Media\\"

Skin.mediaPath = MEDIA

-- ------------------------------------------------------------- fonts ----

local fontCache = {}

local FONT_CANDIDATES = {
  title = { "GameFontNormalHuge", "GameFontNormalLarge", "GameFontNormal" },
  header = { "GameFontNormalLarge", "GameFontNormal" },
  body = { "GameFontHighlight", "GameFontNormal" },
  small = { "GameFontHighlightSmall", "GameFontNormalSmall", "GameFontHighlight" },
  number = { "NumberFontNormalLarge", "NumberFontNormalMedium", "GameFontHighlightLarge", "GameFontNormal" },
  numberBig = { "NumberFontNormalHuge", "NumberFontNormalLarge", "GameFontNormalHuge", "GameFontNormalLarge" },
}

local SIZE_BY_KEY = { title = 22, header = 16, body = 14, small = 12, number = 16, numberBig = 32 }

local function makeFallbackFont(name, sizeKey)
  local font = CreateFont(name)
  local path = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
  font:SetFont(path, SIZE_BY_KEY[sizeKey] or 14, "OUTLINE")
  font:SetTextColor(ns.palette.text.r, ns.palette.text.g, ns.palette.text.b, 1)
  return font
end

function Skin.Font(sizeKey)
  local cached = fontCache[sizeKey]
  if cached then
    return cached
  end
  local chosen = nil
  local candidates = FONT_CANDIDATES[sizeKey] or FONT_CANDIDATES.body
  for i = 1, #candidates do
    local font = _G[candidates[i]]
    if type(font) == "table" or type(font) == "userdata" then
      chosen = font
      break
    end
  end
  if not chosen then
    chosen = makeFallbackFont("CCLFont_" .. sizeKey, sizeKey)
  end
  fontCache[sizeKey] = chosen
  return chosen
end

-- motion helper (section 7.1): returns the duration to actually use
function Skin.MotionMs(baseMs)
  local db = ns.db
  if db and db.settings and db.settings.ui and db.settings.ui.reduceMotion then
    return 0
  end
  return baseMs
end

-- ---------------------------------------------------------- gradients ----

function Skin.VerticalGradient(frame, topColor, bottomColor)
  -- SetGradient lives on TextureBase, not Frame: apply it to a dedicated
  -- BACKGROUND texture parented to the frame (review I11).
  local function withAlpha(c)
    return { r = c.r, g = c.g, b = c.b, a = c.a or 1 }
  end
  local top, bottom = withAlpha(topColor), withAlpha(bottomColor)
  local tex = frame:CreateTexture(nil, "BACKGROUND")
  tex:SetAllPoints()
  local ok = pcall(tex.SetGradient, tex, "VERTICAL", top, bottom)
  if ok then
    return tex
  end
  ok = pcall(
    tex.SetGradient,
    tex,
    "VERTICAL",
    top.r, top.g, top.b, top.a,
    bottom.r, bottom.g, bottom.b, bottom.a
  )
  if ok then
    return tex
  end
  tex:Hide()
  return nil
end

-- ----------------------------------------------------------- panels ----

-- Creates the base surface: colored fill on a BACKGROUND texture (frames
-- have no SetColorTexture — review C1), 1 px bronze border anchored to the
-- corners so it follows resizes, optional vignette overlay.
function Skin.ApplyPanel(frame, opts)
  opts = opts or {}
  local p = ns.palette
  local base = opts.base or p.panel
  local alpha = opts.alpha or 1

  local fill = frame:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints()
  fill:SetColorTexture(base.r, base.g, base.b, alpha)

  -- 1 px inner border (four thin edge textures, corner-anchored so they
  -- follow resizes)
  local border = opts.border or p.line
  local function hEdge(topPoint, bottomPoint)
    local tex = frame:CreateTexture(nil, "BORDER")
    tex:SetColorTexture(border.r, border.g, border.b, opts.borderAlpha or 0.9)
    tex:SetPoint(topPoint)
    tex:SetPoint(bottomPoint)
    tex:SetHeight(1)
    return tex
  end
  local function vEdge(leftPoint, rightPoint)
    local tex = frame:CreateTexture(nil, "BORDER")
    tex:SetColorTexture(border.r, border.g, border.b, opts.borderAlpha or 0.9)
    tex:SetPoint(leftPoint)
    tex:SetPoint(rightPoint)
    tex:SetWidth(1)
    return tex
  end
  hEdge("TOPLEFT", "TOPRIGHT")
  hEdge("BOTTOMLEFT", "BOTTOMRIGHT")
  vEdge("TOPLEFT", "BOTTOMLEFT")
  vEdge("TOPRIGHT", "BOTTOMRIGHT")

  if opts.vignette then
    local vign = frame:CreateTexture(nil, "ARTWORK")
    vign:SetAllPoints()
    vign:SetTexture(MEDIA .. "vignette.tga")
    vign:SetVertexColor(1, 1, 1, opts.vignetteAlpha or 0.5)
  end
  if opts.noise then
    local noise = frame:CreateTexture(nil, "OVERLAY")
    noise:SetAllPoints()
    noise:SetTexture(MEDIA .. "noise.tga")
    noise:SetVertexColor(1, 1, 1, opts.noiseAlpha or 0.03)
  end
  return frame
end

function Skin.ApplyShadow(textureOwner, parent)
  local shadow = textureOwner:CreateTexture(nil, "BACKGROUND")
  shadow:SetTexture(MEDIA .. "shadow.tga")
  shadow:SetPoint("CENTER", parent, "CENTER", 0, -6)
  shadow:SetSize(parent:GetWidth() * 1.15, parent:GetHeight() * 1.15)
  return shadow
end

-- ---------------------------------------------------------- buttons ----

-- Custom button with four states, shimmer sweep on hover for primary.
function Skin.Button(btn, opts)
  opts = opts or {}
  local p = ns.palette
  btn:SetHeight(opts.height or 28)
  local normal = btn:CreateTexture(nil, "ARTWORK")
  normal:SetAllPoints()
  normal:SetColorTexture(p.raised.r, p.raised.g, p.raised.b, 1)
  btn:SetNormalTexture(normal)

  local hover = btn:CreateTexture(nil, "ARTWORK")
  hover:SetAllPoints()
  hover:SetColorTexture(p.gold.r, p.gold.g, p.gold.b, 0.18)
  hover:Hide()
  btn:SetHighlightTexture(hover)

  local pressed = btn:CreateTexture(nil, "ARTWORK")
  pressed:SetAllPoints()
  pressed:SetColorTexture(p.obsidian.r, p.obsidian.g, p.obsidian.b, 0.5)
  pressed:Hide()
  btn:SetPushedTexture(pressed)

  local borderTex = btn:CreateTexture(nil, "BORDER")
  borderTex:SetColorTexture(p.line.r, p.line.g, p.line.b, 1)
  borderTex:SetPoint("TOPLEFT", 0, 0)
  borderTex:SetPoint("BOTTOMRIGHT", 0, 0)
  borderTex:Hide()
  btn.borderTexture = borderTex

  if opts.primary then
    local glow = btn:CreateTexture(nil, "OVERLAY")
    glow:SetTexture(MEDIA .. "glow.tga")
    glow:SetAllPoints()
    glow:SetVertexColor(p.gold.r, p.gold.g, p.gold.b, 0.25)
    glow:Hide()
    btn.glowTexture = glow
    local sweep = btn:CreateTexture(nil, "OVERLAY")
    sweep:SetTexture(MEDIA .. "sweep.tga")
    sweep:SetWidth(48)
    sweep:SetPoint("TOPLEFT", -48, 0)
    sweep:SetPoint("BOTTOMLEFT", -48, 0)
    sweep:Hide()
    btn.sweepTexture = sweep
    btn:HookScript("OnEnter", function()
      glow:Show()
      if Skin.MotionMs(1) > 0 then
        sweep:Show()
        local x = -48
        local ticker = C_Timer.NewTicker(0.05, function()
          x = x + 6
          if x > btn:GetWidth() + 48 then
            sweep:Hide()
            if ticker.Cancel then
              ticker:Cancel()
            end
            return
          end
          sweep:ClearAllPoints()
          sweep:SetPoint("TOPLEFT", x, 0)
          sweep:SetPoint("BOTTOMLEFT", x, 0)
        end, math.floor((btn:GetWidth() + 96) / 6))
        btn.sweepTicker = ticker
      end
    end)
    btn:HookScript("OnLeave", function()
      glow:Hide()
      sweep:Hide()
      if btn.sweepTicker and btn.sweepTicker.Cancel then
        btn.sweepTicker:Cancel()
      end
      btn.sweepTicker = nil
    end)
  end

  local label = btn:CreateFontString(nil, "OVERLAY")
  label:SetFontObject(Skin.Font(opts.small and "small" or "body"))
  label:SetTextColor(ns.palette.text.r, ns.palette.text.g, ns.palette.text.b, 1)
  label:SetPoint("CENTER")
  label:SetText(opts.label or "")
  btn.text = label

  -- disabled state (review M9): dim the label, drop the glow
  btn:HookScript("OnDisable", function(self)
    label:SetTextColor(ns.palette.textDim.r, ns.palette.textDim.g, ns.palette.textDim.b, 1)
    normal:SetVertexColor(0.5, 0.5, 0.5, 0.6)
  end)
  btn:HookScript("OnEnable", function(self)
    label:SetTextColor(ns.palette.text.r, ns.palette.text.g, ns.palette.text.b, 1)
    normal:SetVertexColor(1, 1, 1, 1)
  end)
  return btn
end

-- colorize a font string to a palette entry
function Skin.ColorText(fontString, color)
  fontString:SetTextColor(color.r, color.g, color.b, color.a or 1)
end

function Skin.AccentLine(parent, point, width)
  local line = parent:CreateTexture(nil, "BORDER")
  line:SetColorTexture(ns.palette.gold.r, ns.palette.gold.g, ns.palette.gold.b, 0.85)
  line:SetHeight(1)
  line:SetWidth(width or parent:GetWidth())
  line:SetPoint(point, parent, point, 0, 0)
  return line
end
