-- Core/Locale.lua — all user-facing strings live here (enUS for now).
-- Missing keys fall back to the key itself, so a typo shows readable text
-- instead of crashing.
local ADDON_NAME, ns = ...

local strings = {
  -- window chrome
  app_title = "CrowdCalm Lab",
  close = "Close",
  client_chip_retail_pattern = "Midnight %s",
  client_chip_forever_pattern = "Forever %s",

  -- pages
  page_overview = "Overview",
  page_lab = "Lab",
  page_results = "Results",
  page_stutter = "Stutter log",
  page_addons = "Addons",
  page_settings = "Settings",
  page_about = "About",

  -- footer status
  status_combat_out = "Combat: out",
  status_combat_in = "Combat: in combat",
  status_instance_none = "Instance: none",
  status_instance_some = "Instance: %s",
  status_baseline_saved = "Baseline saved",
  status_baseline_missing = "No baseline yet",
  btn_restore = "Restore my settings",

  -- safety badges
  badge_safe = "Safe",
  badge_verify = "Verify",
  badge_locked = "Locked",
  badge_experimental = "Experimental",

  -- visual cost tiers
  cost_none = "None",
  cost_low = "Low",
  cost_medium = "Medium",
  cost_high = "High",
  cost_unknown = "Unknown",

  -- candidate settings (labels shown on Lab tiles)
  cand_view_distance = "View Distance",
  cand_environment_detail = "Environment Detail",
  cand_ground_clutter = "Ground Clutter",
  cand_shadow_quality = "Shadow Quality",
  cand_liquid_detail = "Liquid Detail",
  cand_particle_density = "Particle Density",
  cand_ssao = "Ambient Occlusion (SSAO)",
  cand_depth_effects = "Depth Effects",
  cand_compute_effects = "Compute Effects",
  cand_outline_mode = "Outline Mode",
  cand_spell_density = "Spell Density",
  cand_body_quota = "Body Quota",
  cand_projected_textures = "Projected Textures",
  cand_texture_resolution = "Texture Resolution",
  cand_render_scale = "Render Scale / Resolution",
  cand_aa = "Anti-Aliasing (MSAA)",
  cand_vsync = "V-Sync",
  cand_graphics_quality = "Graphics Quality (master slider)",

  -- candidate notes (plain language)
  note_spell_density = "Only affects friendly party and raid members' spell visuals. Expect little or no gain in cities.",
  note_body_quota = "Experimental hidden CVar: maximum number of componented bodies seen at once. Effect unknown.",
  note_projected_textures = "Locked with a warning: turning this off hides ground mechanics (spawn circles, beams). Never tested here.",
  note_texture_resolution = "Excluded on purpose: your textures stay untouched.",
  note_render_scale = "Excluded: resolution and render scale are never touched.",
  note_aa = "Excluded: needs a full graphics restart.",
  note_vsync = "Excluded: needs a full graphics restart.",
  note_graphics_quality = "Excluded: the master slider and presets are not reliably applied by SetCVar.",
  note_shadow_range = "Documented as 0 to 5 on older builds; current range unverified, so it steps down one value at a time.",
  note_unverified_range = "Range unverified: the lab only steps down one value at a time and reads the result back.",
  note_raid_cvar = "Blizzard keeps a separate raid/battleground profile; this addon does not test inside instances.",

  -- crowd context
  crowd_quiet = "Quiet",
  crowd_busy = "Busy",
  crowd_packed = "Packed",
  crowd_why = "Why?",
  crowd_nameplates_off = "Friendly nameplates are off, so the count may look low.",
  crowd_instance_note = "Inside instances friendly nameplates are protected; the count is unreliable here.",

  -- addon cost panel
  cpu_caveat = "CPU numbers come from the client's addon profiler. Blizzard's own addons cannot be queried, and mouse-click handlers are not covered.",
  memory_scan_hint = "Memory scan is one blocking call: it may hitch once. It never runs in combat and never automatically.",
  scan_memory = "Scan memory (may hitch)",
  addons_disable_confirm = "Disable %s on next reload? Re-enable it any time from the game's AddOn list.",
  addons_disable_action = "Disable on next reload",
  addons_disable_pending = "Disable pending",
  selfcheck_own = "CrowdCalm Lab itself",
  selfcheck_target = "Target: well under 0.3 ms average with the window open.",
  col_addon = "Addon",
  col_cpu = "CPU (ms)",
  col_memory = "Memory (MB)",
}
local L = setmetatable(strings, {
  __index = function(_, key)
    return key
  end,
})
ns.L = L

function ns.Lfmt(key, ...)
  local s = L[key] or key
  local n = select("#", ...)
  if n > 0 then
    local ok, formatted = pcall(string.format, s, ...)
    if ok then
      return formatted
    end
  end
  return s
end
