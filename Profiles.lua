local ADDON_NAME, ns = ...

local Profiles = {}
ns.Profiles = Profiles

local function def(cvar, value, category)
  return { cvar = cvar, value = value, category = category }
end

Profiles.Categories = {
  { key = "particles", label = "Particle Density", defaultEnabled = true },
  { key = "clutter", label = "Ground Clutter", defaultEnabled = true },
  { key = "shadows", label = "Shadow Quality", defaultEnabled = true },
  { key = "viewdistance", label = "View Distance", defaultEnabled = false },
  { key = "framecap", label = "Frame Cap", defaultEnabled = false },
  { key = "spelldensity", label = "Spell Density", defaultEnabled = false },
  { key = "targetfps", label = "Target FPS (experimental)", defaultEnabled = false },
}

Profiles.Definitions = {
  def("particleDensity", "25", "particles"),
  def("particleMTDensity", "30", "particles"),
  def("groundEffectDensity", "16", "clutter"),
  def("groundEffectDist", "70", "clutter"),
  def("graphicsShadowQuality", "1", "shadows"),
  def("graphicsViewDistance", "6", "viewdistance"),
  def("maxFPS", "60", "framecap"),
  def("maxFPSBk", "60", "framecap"),
  def("spellVisualDensityFilterSetting", "1", "spelldensity"),
  { category = "targetfps", discover = "targetfps", value = "60" },
}

function Profiles.Defaults()
  local out = {}
  for _, category in ipairs(Profiles.Categories) do
    out[category.key] = category.defaultEnabled
  end
  return out
end

local function enabledMap(settings)
  local enabled = {}
  for _, category in ipairs(Profiles.Categories) do
    local value
    if settings.categories then
      value = settings.categories[category.key]
    end
    if value == nil then
      value = category.defaultEnabled
    end
    enabled[category.key] = value
  end
  return enabled
end

function Profiles.Select(settings, env)
  settings = settings or {}
  env = env or {}
  local enabled = enabledMap(settings)
  local entries, skipped = {}, {}

  for _, definition in ipairs(Profiles.Definitions) do
    local key = definition.cvar or definition.discover
    if not enabled[definition.category] then
      skipped[key] = "disabled"
    else
      local cvar = definition.cvar
      if not cvar and definition.discover then
        cvar = env.findCvar and env.findCvar(definition.discover) or nil
        if not cvar then
          skipped[definition.discover] = "not-found"
        end
      end
      if cvar then
        if env.isKnown and not env.isKnown(cvar) then
          skipped[cvar] = "unknown"
        elseif env.isReadOnly and env.isReadOnly(cvar) then
          skipped[cvar] = "read-only"
        else
          entries[#entries + 1] = {
            cvar = cvar,
            value = definition.value,
            category = definition.category,
            secure = (env.isSecure and env.isSecure(cvar)) or false,
          }
        end
      end
    end
  end

  return entries, skipped
end
