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

  -- overview
  hero_fps_title = "Average FPS",
  hero_frame_title = "Frame time",
  hero_crowd_title = "Crowd right now",
  low50 = "50ms+ frames / min",
  low100 = "100ms+ frames / min",
  frame_ms = "ms per frame",
  p5_label = "5th percentile FPS",
  sparkline_title = "Last 5 minutes (red = stutter)",
  last_run_top3 = "Best from your last lab run",
  no_runs = "No lab runs yet — open the Lab page.",
  live_fps_short = "FPS",

  -- lab
  guide_stand = "1. Stand still where the crowd matters",
  guide_pick = "2. Pick settings to test",
  guide_run = "3. Run the lab (stay still)",
  guide_read = "4. Read the results",
  test_only = "Test only this",
  combine_top = "Also combine the top 3 (from the last run)",
  run_lab = "Run Lab",
  est_pattern = "About %s",
  quick = "Quick",
  thorough = "Thorough (3× median)",
  cancel_test = "Cancel",
  phase_sample = "Sampling — stand still",
  phase_settle = "Settling",
  phase_applying = "Applying one step down",
  phase_restoring = "Restoring",
  banner_running = "Lab running — avoid moving or opening other windows.",
  err_combat = "Can't start in combat — step out and try again.",
  err_instance = "Not inside instances — step into the open world first.",
  err_noselect = "Pick at least one setting first.",
  err_noapi = "This client has no CVar API — the lab cannot run.",
  err_foreign = "Another addon changed a setting — test cancelled and restored.",
  err_running = "A test is already running.",
  err_cancelled = "Cancelled — your settings were restored.",
  restore_done = "Your held settings were restored.",
  combat_started = "Combat started. Your settings were restored.",
  copy_report = "Copy report",
  report_hint = "Ctrl+C to copy, then paste anywhere.",
  cost_edit = "Visual cost",
  lab_done = "Done — results are on the Results page.",
  step_pattern = "Setting %d of %d: %s",
  pass_pattern = "Pass %d of %d",
  current_value = "Current: %s",

  -- results
  results_sentence_gain = "Turning %s down gained about %.1f FPS here.",
  results_sentence_none = "%s showed no clear gain in this crowd.",
  best = "Best",
  confidence = "Confidence",
  before_after = "Before %.1f → after %.1f FPS",
  apply_coming = "Apply as crowd profile (coming soon)",
  results_empty = "No results yet. Run a lab test from the Lab page.",
  noisy_note = "Noisy — rerun for a clearer number",
  hitch_note = "Applying this change caused a visible hitch",
  not_testable = "Not tested",
  reason_unreadable = "value unreadable",
  reason_already_lowest = "already at the lowest step",
  reason_failed = "apply failed: %s",
  zone_pattern = "%s — %s",

  -- stutter
  stutter_enable = "Log stutters (background, 1s checks)",
  stutter_timeline = "Last %d minutes",
  stutter_empty = "No stutters logged yet. Turn logging on and play normally.",
  sev1 = "Minor", sev2 = "Notable", sev3 = "Heavy", sev4 = "Freeze",
  col_time = "Time",
  col_place = "Place",
  col_sev = "Severity",
  col_fps = "FPS",
  stutter_detail = "%d × 50ms · %d × 100ms · %d × 500ms · %d × 1000ms+ · run #%d",
  clear_log = "Clear log",
  clear_log_confirm = "Clear the stutter log?",

  -- addons
  addons_search = "Search addons",
  addons_refresh = "Refresh CPU",
  addons_top3 = "Top 3",
  addons_empty = "No addons found.",
  addons_unqueryable = "not queryable",
  addons_sorted_by = "Sorted by: %s",
  sort_name = "name", sort_cpu = "CPU", sort_memory = "memory",
  addons_pending_row = "Disable pending",

  -- settings
  set_ui_scale = "UI scale",
  set_reduce_motion = "Reduce motion",
  set_colorblind = "Colorblind-friendly colors",
  set_font_size = "Font size",
  set_sample = "Sample length (seconds)",
  set_default_mode = "Default run mode",
  set_stutter_floor = "Stutter FPS floor",
  set_compartment = "Prefer the addon compartment",
  set_debug = "Debug logging",
  set_reset = "Reset all CrowdCalm data",
  set_mute = "Mute UI sounds",
  set_compartment_note = "Whether the compartment icon shows is up to your client; this stores your preference.",
  set_minimap = "Show minimap button",
  set_minimap_note = "Drag it around the minimap ring to move it; click it to open CrowdCalm Lab.",
  mm_title = "CrowdCalm Lab",
  mm_click = "Left-click: open or close",
  mm_drag = "Drag: move around the minimap",
  set_font_note = "Font size applies to CrowdCalm text; standard game fonts stay untouched.",
  reset_confirm = "Erase all results, the stutter log, and your baseline? This cannot be undone.",
  reset_done = "All CrowdCalm data cleared.",
  log_section = "Logging",

  -- about
  about_version_pattern = "Version %s",
  about_how = "How it works: the Lab measures your FPS for a few seconds, steps one graphics setting down by a single notch, measures again, then restores it and measures once more. Comparing the three windows filters out crowd noise.",
  about_safety = "Safety promise: CrowdCalm Lab never touches your resolution, textures, or audio. Every setting it tests is restored the moment the test ends — on cancel, on combat, on errors, and at logout. If anything looks off, one click restores your saved baseline.",
  about_url = "https://github.com/smilewasthere/CrowdCalmLab",
  about_nodonations = "No donations. The code is open source and yours to keep.",
  about_selfcheck = "This addon's own cost",
  selfcheck_line = "CPU: %.2f ms recent · %.2f ms peak · pooled frames: %d (%d free) · tickers: %d · log entries: %d",
  selfcheck_unavailable = "The profiler cannot report this addon's cost on this client.",
  read_memory = "Read own memory",
}
-- L supports BOTH styles used across the codebase: L( calls (255+ sites)
-- and L[key] indexing (used by Lfmt). Missing keys fall back to the key
-- itself, so a typo shows readable text instead of crashing. The __call
-- metamethod is the load-bearing part: without it every L( call raises
-- "attempt to call a table value" (the pre-1.0.0-pre.2 empty-window bug).
local L = setmetatable(strings, {
  __index = function(_, key)
    return key
  end,
  __call = function(_, key)
    local v = strings[key]
    if v ~= nil then
      return v
    end
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
