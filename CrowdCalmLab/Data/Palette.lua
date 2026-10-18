-- Data/Palette.lua — every color the UI uses, per brief section 7.2.
-- Values are normalized once at load; no hex parsing at runtime.
local ADDON_NAME, ns = ...

local function rgb(hex)
  local r = tonumber(hex:sub(2, 3), 16) / 255
  local g = tonumber(hex:sub(4, 5), 16) / 255
  local b = tonumber(hex:sub(6, 7), 16) / 255
  return { r = r, g = g, b = b, hex = hex }
end

local palette = {
  -- backgrounds
  obsidian = rgb("#0A0C10"),
  panel = rgb("#12151C"),
  raised = rgb("#1A1F2A"),
  obsidianAlpha = 0.94,

  -- lines and accents
  line = rgb("#3A3226"),
  gold = rgb("#D9A441"),
  goldBright = rgb("#FFD25A"),

  -- text
  text = rgb("#ECE7DA"),
  textDim = rgb("#9AA0AD"),

  -- semantic
  gain = rgb("#34D1BF"),
  cost = rgb("#F2A33A"),
  danger = rgb("#E5534B"),
  ok = rgb("#5BD66F"),
  arcane = rgb("#8C6BFF"),

  -- colorblind-safe alternates (gain=blue, cost=orange)
  cbGain = rgb("#4EA3FF"),
  cbCost = rgb("#FF9F43"),
}
ns.palette = palette

local function colorblindActive()
  local db = ns.db
  return db ~= nil and db.settings ~= nil and db.settings.ui ~= nil and db.settings.ui.colorblind == true
end

-- Gain and cost colors swap to the colorblind pair when enabled.
function palette.gainColor()
  if colorblindActive() then
    return palette.cbGain
  end
  return palette.gain
end

function palette.costColor()
  if colorblindActive() then
    return palette.cbCost
  end
  return palette.cost
end
