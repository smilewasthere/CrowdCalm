-- Data/Settings.lua — SavedVariables defaults, the editable candidate table
-- (brief section 5.4), selection defaults, and visual-cost tiers (5.6).
-- Ranges below were documented for 12.0.1 and are unverified until the owner
-- runs docs/FIRST-RUN-CHECKLIST.md; "verify" entries step down one at a time.
local ADDON_NAME, ns = ...

local settings = {}
ns.settings = settings

settings.defaults = {
  ui = {
    scale = 1,
    reduceMotion = false,
    colorblind = false,
    highContrast = false,
    fontSize = 14,
    muted = false,
    compartment = true,
    minimapButton = true,
  },
  lab = {
    sampleSeconds = 8, -- measured seconds per phase (the slider value)
    settleSeconds = 6, -- pre.5: let the applied setting actually land
    ignoreSeconds = 4, -- pre.5: warm-up tail dropped before measuring
    defaultMode = "quick", -- "quick" | "thorough"
    fpsStutterFloor = 30,
  },
  log = {
    enabled = false,
  },
  debug = false,
  sparklineSeconds = 300,
  stutterMinutes = 10,
}

-- Default visual-cost tiers; owners may edit per setting (section 5.6).
settings.visualCostDefaults = {
  graphicsViewDistance = "High",
  graphicsEnvironmentDetail = "High",
  graphicsGroundClutter = "Medium",
  graphicsShadowQuality = "High",
  graphicsLiquidDetail = "Low",
  graphicsParticleDensity = "Medium",
  graphicsSSAO = "Medium",
  graphicsDepthEffects = "Medium",
  graphicsComputeEffects = "Low",
  graphicsOutlineMode = "None",
  graphicsSpellDensity = "None",
  bodyQuota = "Unknown",
}

-- Testable candidates. "range" = "safe" (documented range) | "verify"
-- (step-down-only care mode). min/max nil means fully unverified.
settings.candidates = {
  {
    id = "view_distance",
    key = "graphicsViewDistance",
    label = "cand_view_distance",
    min = 0,
    max = 9,
    range = "safe",
    locked = false,
    experimental = false,
    note = nil,
  },
  {
    id = "environment_detail",
    key = "graphicsEnvironmentDetail",
    label = "cand_environment_detail",
    min = 0,
    max = 9,
    range = "safe",
    locked = false,
    experimental = false,
    note = nil,
  },
  {
    id = "ground_clutter",
    key = "graphicsGroundClutter",
    label = "cand_ground_clutter",
    min = 0,
    max = 9,
    range = "safe",
    locked = false,
    experimental = false,
    note = nil,
  },
  {
    id = "shadow_quality",
    key = "graphicsShadowQuality",
    label = "cand_shadow_quality",
    min = 0,
    max = 5,
    range = "verify",
    locked = false,
    experimental = false,
    note = "note_shadow_range",
  },
  {
    id = "liquid_detail",
    key = "graphicsLiquidDetail",
    label = "cand_liquid_detail",
    min = nil,
    max = nil,
    range = "verify",
    locked = false,
    experimental = false,
    note = "note_unverified_range",
  },
  {
    id = "particle_density",
    key = "graphicsParticleDensity",
    label = "cand_particle_density",
    min = nil,
    max = nil,
    range = "verify",
    locked = false,
    experimental = false,
    note = "note_unverified_range",
  },
  {
    id = "ssao",
    key = "graphicsSSAO",
    label = "cand_ssao",
    min = nil,
    max = nil,
    range = "verify",
    locked = false,
    experimental = false,
    note = "note_unverified_range",
  },
  {
    id = "depth_effects",
    key = "graphicsDepthEffects",
    label = "cand_depth_effects",
    min = nil,
    max = nil,
    range = "verify",
    locked = false,
    experimental = false,
    note = "note_unverified_range",
  },
  {
    id = "compute_effects",
    key = "graphicsComputeEffects",
    label = "cand_compute_effects",
    min = 0,
    max = 4,
    range = "verify",
    locked = false,
    experimental = false,
    note = "note_unverified_range",
  },
  {
    id = "outline_mode",
    key = "graphicsOutlineMode",
    label = "cand_outline_mode",
    min = 0,
    max = 2,
    range = "safe",
    locked = false,
    experimental = false,
    note = nil,
  },
  {
    id = "spell_density",
    key = "graphicsSpellDensity",
    label = "cand_spell_density",
    min = nil,
    max = nil,
    range = "verify",
    locked = false,
    experimental = false,
    note = "note_spell_density",
  },
  {
    id = "body_quota",
    key = "bodyQuota",
    label = "cand_body_quota",
    min = nil,
    max = nil,
    range = "verify",
    locked = false,
    experimental = true,
    note = "note_body_quota",
  },
}

-- Display-only exclusions: never read, never written, shown so the owner
-- knows why they are absent. CVars listed here were confirmed to exist on
-- 12.1.5 by the wiki research; names without a verified CVar keep key = nil.
settings.lockedEntries = {
  {
    id = "projected_textures",
    key = "projectedTextures",
    label = "cand_projected_textures",
    locked = true,
    note = "note_projected_textures",
  },
  {
    id = "texture_resolution",
    key = "graphicsTextureResolution",
    label = "cand_texture_resolution",
    locked = true,
    note = "note_texture_resolution",
  },
  {
    id = "graphics_quality",
    key = "graphicsQuality",
    label = "cand_graphics_quality",
    locked = true,
    note = "note_graphics_quality",
  },
  {
    id = "render_scale",
    key = nil,
    label = "cand_render_scale",
    locked = true,
    note = "note_render_scale",
  },
  {
    id = "anti_aliasing",
    key = nil,
    label = "cand_aa",
    locked = true,
    note = "note_aa",
  },
  {
    id = "vsync",
    key = nil,
    label = "cand_vsync",
    locked = true,
    note = "note_vsync",
  },
}

function settings.initialize(db)
  local util = ns.util
  util.deepMerge(db, {
    settings = util.deepCopy(settings.defaults),
    visualCost = {},
    selection = {},
    ui = { point = nil, x = 0, y = 0, page = 1, minimapAngle = 45 },
    results = {},
    stutter = {},
    baseline = nil,
  })
  -- fill visual-cost overrides from shipped defaults
  for key, tier in pairs(settings.visualCostDefaults) do
    if db.visualCost[key] == nil then
      db.visualCost[key] = tier
    end
  end
  -- default selection: safe, non-experimental, non-locked candidates on
  for _, cand in ipairs(settings.candidates) do
    if db.selection[cand.id] == nil then
      db.selection[cand.id] = (cand.range == "safe") and (not cand.experimental) and (not cand.locked)
    end
  end
  return db
end

function settings.costOf(key)
  local db = ns.db
  if db and db.visualCost and db.visualCost[key] then
    return db.visualCost[key]
  end
  return settings.visualCostDefaults[key] or "Unknown"
end

function settings.setCost(key, tier)
  if not ns.db then
    return
  end
  ns.db.visualCost[key] = tier
end

function settings.byId(id)
  for _, cand in ipairs(settings.candidates) do
    if cand.id == id then
      return cand
    end
  end
  for _, entry in ipairs(settings.lockedEntries) do
    if entry.id == id then
      return entry
    end
  end
  return nil
end

function settings.byKey(key)
  for _, cand in ipairs(settings.candidates) do
    if cand.key == key then
      return cand
    end
  end
  return nil
end

-- candidates the lab may test (not locked; experimental only if selected)
function settings.testable()
  local out = {}
  for _, cand in ipairs(settings.candidates) do
    if not cand.locked then
      out[#out + 1] = cand
    end
  end
  return out
end
