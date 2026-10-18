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
