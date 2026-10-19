# Changelog

All notable changes to CrowdCalm Lab are documented here.

## 1.0.0 (Unreleased)

### Added

- First complete build: live meter, crowd context, A-B-A lab test runner,
  ranked results with visual-cost tiers and confidence badges, stutter log,
  addon cost panel, self-check.
- Safety engine (CVarGuard): combat guards, snapshot/restore, read-back
  verification, CVAR_UPDATE ownership, crash-recovery restore prompt,
  scope badges for server-stored CVars.
- Azeroth-native premium UI: seven pages, custom gauges (arc gauge,
  sparkline, progress ring), reduce-motion and colorblind options.
- Tooling: `scripts/deploy.ps1` (manual, `-WowRoot` required),
  `scripts/make-textures.py` (generates the committed TGA textures),
  `scripts/check-lua.js` (static syntax/TOC gate).
- Docs: `docs/VERIFY.md`, `docs/FIRST-RUN-CHECKLIST.md`, `docs/DESIGN.md`.

## 1.0.0-pre.6 (2026-10-19)

Visual pass for the two pages the owner called out ("Lab not pretty",
"Overview not good-looking"). Behavior is unchanged; only art, layout
and readouts.

### Added

- **Overview hero cards:** gold accent strip along each top edge; big
  values now carry units ("60 FPS", "16.7 ms"); the crowd gauge gained a
  pivot pip at the arc's baseline and a centered Quiet/Busy/Packed
  readout inside the dome, both tinted with the active ramp color
  (green/gold/red, colorblind-safe).
- **Overview best-from-last-run:** each row is now name | proportional
  gain bar (track + gradient fill) | "+X.X FPS"; bar length tracks the
  top gain, green for positive, red for negative; empty state unchanged.
- **Lab tiles:** selected tiles wear a gold top accent, kept in sync
  across the whole grid (including after "Test only"); tiles now sit two
  per row and the wheel scrolls whole rows.
- **Lab controls:** a visible strip wraps the bottom control area
  (combine toggle top-left; estimate + modes + Run bottom-right), and
  Quick/Thorough are joined into one segmented backing strip with no gap
  (active side keeps the gold face, 1 px overlap reads as one divider).
- **Lab run overlay:** soft glow behind the phase ring tinted per phase
  (dim while settling/warming, gold while measuring), seconds remaining
  counted down inside the ring, headline colored by phase.

### Changed

- **Sparkline v2:** bars draw from a generated vertical gradient
  (brighter at the baseline, tinted green) instead of a flat color, two
  hairline grid lines sit behind the data, and spike markers are tinted
  once at creation instead of every tick.
- 5 new generated textures (accent, spark_bar, bar_fill, bar_track,
  gauge_pip); media manifest now 27 files / 853,156 bytes of the 1 MB
  budget.
## 1.0.0-pre.5 (2026-10-19)

### Fixed

- **Stutter page Lua error (owner report #1):** row clicks now run
  through `OnMouseUp` on the row frames. `SetScript("OnClick")` is
  Button-only and raised "script type not supported by this object" on
  12.1.5, which killed the whole list render. Hover highlighting moved
  off the Button-only HIGHLIGHT layer to explicit OnEnter/OnLeave.
- **Addons page dead (owner report #3):** `GetNumAddOns`,
  `GetAddOnInfo` and friends no longer exist on modern clients. Every
  addon-list read now goes through new `Compat.GetNumAddOns` /
  `Compat.GetAddOnInfo` resolvers (`C_AddOns` first, global fallback,
  all pcall'd). CPU metric reads probe the `GetAddOnMetric`
  name/index forms once and cache whichever works; memory reads accept
  name or index. When the list API yields nothing, the page says
  "Addon list API unavailable on this client" instead of pretending
  the user has no addons.
- **Font size and colorblind settings did nothing (owner report #2):**
  font sizes are baked into shared font objects and colors are captured
  at build time, so both now trigger `UI.ScheduleRebuild()`: the window
  rebuilds in place after 0.15 s (deferred while a lab run is active,
  restoring scale, position, and the current page) and confirms with
  "Setting applied". EditBoxes (Addons search, report box, About URL)
  follow the font-size preference too, via `Widgets.ApplyEditBoxFont`.
- **UI scale resets while dragging (owner report #2):** sliders apply on
  release instead of mid-drag â€” resizing the window under the cursor
  used to yank the thumb to a wrong value before mouse-up. Keyboard
  changes commit after a 0.35 s debounce, the value text formats
  properly ("110%", "14"), and Settings re-syncs sliders silently on
  show so no stray commit rebuilds the window on every visit.

### Added

- **UI sounds and a working mute (owner request):** new `Core/Sound.lua`
  with click / toggle / done / error sounds (SOUNDKIT names with classic
  SoundKit IDs as fallback). Buttons, checkboxes and dropdowns play
  through it, and "Mute UI sounds" finally gates every playback â€”
  unmuting confirms with one last click.
- **Header FPS panel (owner report #7):** the bare top-right number is
  now a chip â€” status dot, colored number, dim "FPS" label, tooltip, and
  a click through to the Overview page. The client chip moved left and
  sizes itself to its text.
- **Minimap icon like before (owner report #6):** icon inset restored to
  5 px (22 px logo) while keeping the uncropped square and the ring
  bezel.
- **Measurement stability engine v2 (owner spec):** every phase is now
  [apply or restore] -> 6 s settle -> 4 s warm-up (dropped by the new
  `Stats.Begin(ignoreSeconds)` window) -> measured sample (the slider's
  seconds). Quick runs A-B-A; Thorough runs A-B-A-B-A-B-A â€” 7 phases,
  4 shared baselines â€” and each test is compared against the average of
  its two neighbouring baselines, reported as the median gain plus the
  min..max spread. Baselines drifting more than 8% now flag the row
  "Not reliable", and the card shows the actual difference plus a rerun
  tip.
- **Movement watchdog:** `GetUnitSpeed` and `GetPlayerFacing` (probed
  once at load, warn-only) flag a row when the player moves for more
  than 2.5 s or turns more than 120 degrees during a run. Once per run a
  banner warns; cards show a marker; the report gets a WARNING line.
- **Caps preflight, read-only:** before each run the lab reads Max FPS
  (`maxfps`, falling back to `renderFrameRateCap`) and `gxVSync` â€” it
  never writes them. A cap shows a banner, a persistent overlay line,
  and a `Caps:` line in the report.
- **Lab overlay:** keep-still advisory line ("Don't move, turn the
  camera or touch the mouse during the run"), a warm-up countdown phase,
  the cap warning line, and "Phase x of y" progress (3 or 7 phases per
  setting). The estimate now matches the real phase timings.
- **Results cards and report:** FPS triple (entry baseline -> mean test
  -> exit baseline), values triple (from -> to -> read back after the
  final restore), per-test gains and spread for Thorough, the baseline
  difference percent, and movement flags â€” on the cards and in the Copy
  report.

### Changed

- Settings defaults: `settleSeconds` 3 -> 6, new `ignoreSeconds` = 4;
  the slider is relabeled "Measured seconds per phase".
- Copy: "Re-test" chip -> "Not reliable"; pass counter -> "Phase x of
  y"; About's how-it-works paragraph updated for the new phase flow.

## 1.0.0-pre.4 (2026-10-19)

### Changed

- **Visual refresh across the window** (owner feedback):
  - Buttons now wear generated gradient faces (`btn_dark.tga`,
    `btn_gold.tga`) with a 1 px outline instead of the flat raised
    block. Primary CTAs (Run Lab, Start/Save test, Restore) show the
    gold face with a dark label.
  - **Quick / Thorough is a segmented control**: the active mode wears
    the gold face, the inactive one stays on the dark gradient.
  - **Addons column headers are ghost buttons** (text only); the active
    sort column is gold.
- **Crowd gauge v2 (Overview):** a clean semicircle drawn from
  generated art (`gauge_dim.tga` plus one baked mask per state) replaces
  the 40 rotated segments -- no rotation API, nothing to pcall. The lit
  arc ramps quiet = gain green, busy = gold, packed = cost orange (still
  swapped by colorblind mode), with Quiet / Packed end labels beside
  the dome. The zone line no longer sits on top of the arc.
- **Row lists have zebra stripes** (Stutter, Results, Settings); the
  Stutter timeline strip got a hairline border.
- **Minimap button** (owner request): smaller uncropped square logo on
  the disc, one generated `ring.tga` bezel replaces the 12 rotated arc
  segments, and the button re-anchors automatically when the minimap
  resizes (UI scale, tracking options, other addons).

### Added

- Seven generated textures (`make-textures.py`): button gradients, the
  bezel ring, and the four gauge layers; all committed and counted by
  the media manifest gate (22 files, well under the 1 MB budget).

## 1.0.0-pre.3 (2026-10-19)

### Added

- **Results "What to do here" panel:** the lab now stores the tested values
  (from -> to) on every result row and turns them into a ranked
  recommendation: the best "Worth it" row gets a full sentence
  ("set X to Y â€” about +N FPS here"), other wins are listed together,
  and every card carries a short explanation of what the setting does.
  Noisy runs get a "re-run in Thorough mode" instruction instead of a
  false recommendation.
- **Action chips** on every Results card (Worth it / No gain / Re-test /
  Can't test / Hitch) with hover tooltips; the Confidence text now has a
  legend explaining Low / Medium / High. The Copy report button includes
  explicit `RECOMMEND:` lines.
- **G5 glyph gate:** `scripts/check-lua.js` now walks the parsed AST and
  fails on any string literal containing characters outside Latin-1 plus
  the em dash (the WoW font subset renders nothing else).

### Fixed

- **"Before -> after FPS" rendered as a tofu box** (owner screenshot):
  the arrow was U+2192, which the client font cannot draw. The sentence
  is now plain ASCII; the gate prevents the class of bug from returning.
- **The window could not be moved from the title bar or footer** (owner
  report): only mouse-free gaps accepted the drag. The header, footer and
  frame now all drag, with a hover tooltip explaining it, and the window
  sits on the HIGH strata with an explicit raise so game UI (action bars,
  minimap, coordinates) no longer draws over it.
- **Running-state confusion on the Lab page** (owner screenshot: page
  visible with a floating Cancel): the cover is now nearly opaque,
  blocks mouse input to the page beneath, sits above every page element,
  and Cancel is a wide centered button at the bottom. Run/Cancel refresh
  the overlay immediately instead of on the next 1 Hz tick; the
  "Lab running" banner raises above the cover.
- **Quick/Thorough buttons overlapped Run Lab** (owner screenshot): the
  bottom controls are now one right-aligned chain
  [estimate] [Quick] [Thorough] [Run Lab] with the combine checkbox on
  its own row above.
- **Addons page empty until "Refresh CPU"** (owner screenshot): the
  auto-scan on first show was silently blocked in combat; the page now
  retries automatically when combat ends, and the sort label shows the
  addon count ("N addons Â· sorted by CPU").
- **Empty-state icon overlapped page text** (owner screenshot: the gold
  "C" disc sitting on the Addons caveat): the empty-state icon is now
  smaller (32px) and centered in the page.
- Lab progress now actually stores the "step to" value (`j.lower` was
  never set, so `progress.stepTo` was always nil).

## 1.0.0-pre.2 (2026-10-18)

### Fixed

- **Empty window on open (owner report on pre.1):** `ns.L` was a plain
  table, so every `L("key")` call raised "attempt to call a table value"
  at file scope â€” all seven pages failed to register and the window came
  up with a header only. `Core/Locale.lua` now defines `__call` alongside
  `__index`, supporting both call styles used across the codebase.
- `Util.CreateFramePool` passed the parent frame in the `CreateFrame`
  name slot (broke every pooled row list â€” Stutter and Addons pages);
  the Lab progress ring passed the frame in the name slot of its Cooldown
  (silently fell back to a bar every time).
- **Error surface:** a failed window build now discards the partial
  frame, prints the error, and shows a Blizzard popup instead of leaving
  a half-built window re-shown; broken pages render a readable
  "page failed to load" message, page scripts are `pcall`ed, and the
  update ticker self-disables after an error instead of flooding at 1 Hz.

### Added

- **Minimap button** (owner request): 32px logo disc with a 12-segment
  arc bezel and hover glow, left-click toggles the window, drag orbits
  it around the minimap rim (position persisted). Settings â†’ "Show
  minimap button" (default on) hides and shows it.
- **Gate hardening:** `scripts/check-lua.js` now fails if `Locale.lua`
  lacks `__call` (the root-cause class) and warns when a literal
  `L("key")` is not defined in the strings table.

## 1.0.0-pre.1 (2026-10-18)

### Added

- First pre-release: the initial complete build (full notes on the
  GitHub release page).
