# Changelog

All notable changes to CrowdCalm Lab are documented here.

## 1.0.0 (Unreleased)

### Added

- First complete build: live meter, crowd context, A-B-A lab test runner,
  ranked results with visual-cost tiers and confidence badges, stutter log,
  addon cost panel, self-check, export/copy report.
- Safety engine (CVarGuard): combat guards, snapshot/restore, read-back
  verification, CVAR_UPDATE ownership, crash-recovery restore prompt,
  scope badges for server-stored CVars.
- Azeroth-native premium UI: seven pages, custom gauges (arc gauge,
  sparkline, progress ring), reduce-motion and colorblind options.
- Tooling: `scripts/deploy.ps1` (manual, `-WowRoot` required),
  `scripts/make-textures.py` (generates the committed TGA textures),
  `scripts/check-lua.js` (static syntax/TOC gate).
- Docs: `docs/VERIFY.md`, `docs/FIRST-RUN-CHECKLIST.md`, `docs/DESIGN.md`.
