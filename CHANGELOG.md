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

## 1.0.0-pre.3 (2026-10-19)

### Added

- **Results "What to do here" panel:** the lab now stores the tested values
  (from -> to) on every result row and turns them into a ranked
  recommendation: the best "Worth it" row gets a full sentence
  ("set X to Y — about +N FPS here"), other wins are listed together,
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
  addon count ("N addons · sorted by CPU").
- **Empty-state icon overlapped page text** (owner screenshot: the gold
  "C" disc sitting on the Addons caveat): the empty-state icon is now
  smaller (32px) and centered in the page.
- Lab progress now actually stores the "step to" value (`j.lower` was
  never set, so `progress.stepTo` was always nil).

## 1.0.0-pre.2 (2026-10-18)

### Fixed

- **Empty window on open (owner report on pre.1):** `ns.L` was a plain
  table, so every `L("key")` call raised "attempt to call a table value"
  at file scope — all seven pages failed to register and the window came
  up with a header only. `Core/Locale.lua` now defines `__call` alongside
  `__index`, supporting both call styles used across the codebase.
- `Util.CreateFramePool` passed the parent frame in the `CreateFrame`
  name slot (broke every pooled row list — Stutter and Addons pages);
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
  it around the minimap rim (position persisted). Settings → "Show
  minimap button" (default on) hides and shows it.
- **Gate hardening:** `scripts/check-lua.js` now fails if `Locale.lua`
  lacks `__call` (the root-cause class) and warns when a literal
  `L("key")` is not defined in the strings table.

## 1.0.0-pre.1 (2026-10-18)

### Added

- First pre-release: the initial complete build (full notes on the
  GitHub release page).
