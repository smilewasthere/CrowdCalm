# CrowdCalm Dev Mode — Design

**Date:** 2026-10-18
**Status:** Approved in session (chat design), awaiting implementation
**Depends on:** docs/specs/crowdcalm-design.md (v1 addon, shipped)

## 1. Purpose

A developer-only toolkit inside CrowdCalm, used by the addon's author (the
only "user" of this mode) to answer, with real in-game data:

1. Does the crowd profile actually improve FPS? By how much?
2. Does the addon leak memory or grow unboundedly over long sessions?
3. Does the system work as designed (every switch, write, skip, failure
   visible in one timeline)?
4. Can individual features (or all of them) be turned on/off live and
   compared?

The collected data is exported as a plain-text report that the author
pastes to an analyst (the AI assistant) for interpretation.

Non-goals: no player-facing changes; no telemetry upload; no automation
outside a manually started test.

## 2. Gating and commands

- Dev mode is **off by default**. Normal players are unaffected: when off,
  the only extra runtime cost is a few guarded nil checks per tick.
- `settings.dev.enabled` (persisted) controls the mode.
- Slash command `/ccdev` (registered by Dev.lua via
  `SlashCmdList["CROWDCALMDEV"]`):
  - `/ccdev on` — enable dev mode (persist + log).
  - `/ccdev off` — disable (persist + log; aborts a running test first).
  - `/ccdev` — toggle the dev window (`ns.DevWindow.Toggle`, auto-creates).
  - `/ccdev status` — one status line.
  - `/ccdev report` — hint: use the window's Copy report button, or read
    `CrowdCalmDB.dev.lastReport` in the WTF SavedVariables file.
  - Unknown input — usage line.
- Window commands require dev mode on; otherwise a log hint is printed.

## 3. Dev window

Frame `CrowdCalmDevPanel` (movable, DIALOG strata, centered).
Layout top to bottom:

- Status line: `mode | plates N | FPS | MB | dev v0.2.0`.
- `[Force crowd]` checkbox, `[All features OFF]` / `[All features ON]`
  buttons.
- Feature checkboxes: `Enabled` master, one per category
  (`ns.Profiles.Categories`), `Stutter log`.
- Test section:
  - Mode radios (checkboxes acting as radios): `Auto`, `Guided`, `Passive`.
  - Phase length buttons: `30s` `60s` `120s` (one active).
  - Rounds checkbox: `ABAB (average 2 rounds)` — unchecked means `AB`.
  - `[START]` / `[STOP]` buttons; phase status text
    (`Phase A - 42s left` / `Recording - 123s`).
  - Last-result line (e.g. `ON 58.2 avg / OFF 61.4 avg - profile costs 3.2 fps`).
- `[Copy report]` / `[Copy last test]` buttons.
- Multiline EditBox `CrowdCalmDevReport` (the report text; focus +
  Ctrl+C to copy; click highlights all).

All feature toggles write the same `settings` the player panel uses and
call `ns.Core.RebuildSwitch()` when the managed cvar set changes; stutter
calls `ns.Core._syncStutterHook()`. "All features OFF" is
`settings.enabled = false` (master off: switch restores everything).
"All features ON" sets master true, every category true, then rebuilds.

## 4. Recorder

Engine lives in `Dev.lua` as `ns.Dev.new(settings, deps)`.
deps = `{ getTime, setFrameHook(fnOrNil), log, getSnapshot }` where
`getSnapshot()` returns
`{ mode, plates, applied, baselines, pendingReason }` (effective crowd
mode: forced or real).

### 4.1 Modes

- **Passive**: start -> record until stop. No flipping.
- **Guided**: start -> records phase A (force-crowd ON); `Next phase`
  ends it, flips force-crowd OFF, records phase B; `Stop` ends.
  Phase labels cycle A, B, A, ...
- **Auto**: start -> phases run `phaseSeconds` each (30/60/120, default
  60). `AB` = profile ON then OFF; `ABAB` = ON/OFF/ON/OFF with the A and
  B samples merged for the comparison. The engine flips the force-crowd
  flag itself at each boundary.

### 4.2 Force crowd

`Dev.forceCrowd` (runtime only — never persisted; resets to false on every
login/reload). When true, Core's tick uses mode `"crowd"` regardless of
plate count. Flips at phase boundaries go through `SetForceCrowd` so the
journal records them.

### 4.3 Frame capture

While a test runs, the engine installs an OnUpdate hook (via
`deps.setFrameHook`) on a dedicated hidden frame owned by Core
(`CrowdCalmDevFrame`, created at init, no hook when idle). The hook
measures per-frame delta in ms and calls `Dev:OnFrame(now, deltaMs)`.
On stop/abort the hook is removed. No per-frame work exists outside a
running test.

### 4.4 Abort conditions

A test aborts (keeps partial data, journals the reason, resets force-crowd
to false, removes the hook, persists a partial report) when:

- `Stop` is pressed.
- Dev mode is disabled mid-test.
- `PLAYER_LOGOUT` arrives mid-test.
- Auto mode only: at a phase flip, `getSnapshot().pendingReason` is
  `"combat"` or `"failed"`, or the applied-set does not match the phase's
  expectation within 2 seconds (combat blocking an apply/restore).
  Guided/Passive do not abort on this; the report flags detected
  interference instead.

## 5. Metrics

### 5.1 Frame statistics (pure functions, exposed for tests)

`Dev.FrameStats(deltasMs)` -> table:

- `frames` = count; `seconds` = sum/1000 (0 for empty).
- `avgFps` = frames / seconds (`0` for empty).
- `avgMs`, `maxMs` = mean and max delta.
- `minFps` = 1000 / maxMs (0 for empty).
- `p1LowFps` = 1000 / (1% worst delta): sort deltas descending, index
  `math.max(1, math.ceil(frames * 0.01))`.

`Dev.CompareFrameStats(on, off)` -> `{ avgDelta, avgPercent, lowDelta, verdict }`:

- `avgDelta = on.avgFps - off.avgFps`; `avgPercent` relative to off
  (0 when off.avgFps == 0).
- `verdict`: `"clear"` when |avgPercent| >= 5, `"slight"` when
  >= 2 and < 5, `"none"` when < 2. Sign indicates direction
  (negative = profile ON is slower).

Cap: at most 30000 deltas kept per phase group; further frames are
counted but not stored (percentiles degrade gracefully; report notes
`(capped)` when it happened).

### 5.2 Memory

While recording, every 5 seconds: `collectgarbage("count")` in KB is
journaled. Report computes start/end/peak MB, delta over the test, delta
per hour, per-phase deltas, and current buffer sizes (journal entries,
stutter entries, monitor samples) as leak-suspect counters.

### 5.3 Journal

Ring buffer, cap 2000 entries (oldest dropped; a `dropped` counter is
kept and reported). Entry kinds:

- `mode`: `{ from, to, plates }` on effective-mode change.
- `apply`: `{ cvar, value, baseline }` when a cvar enters the applied set.
- `restore`: `{ cvar, value }` when it leaves (value = captured baseline).
- `cvar`: `{ cvar, value, tag }` for CVAR_UPDATE; tag `"echo"` when the
  value equals what we applied for that cvar, else `"user"`.
- `mem`: `{ mb }`.
- `phase`: `{ name, event = start|flip|stop }`.
- `test`: `{ mode, state = started|stopped|aborted, reason }`.
- `note`: `{ text }` (deferred reasons, hints).
- `error`: `{ text }`.

`Dev:OnTick(now)` pulls `getSnapshot()`, journals diffs, samples memory,
advances auto phases, runs abort checks. Core calls it once per tick and
at combat-end / entering-world / logout, so the timeline stays accurate
even outside the 1 s ticker.

## 6. Report and export

`Dev:GetReport()` renders plain text (~100-300 lines):

```
== CrowdCalm Dev Report ==
generated: <date> | addon <version> | char <name> | zone <zone>
test: auto AB 60s | state: complete | features: enabled=.. particles=.. ...
-- PHASE COMPARISON --   (auto/guided with >=1 frame in both groups;
                          otherwise "comparison unavailable: ..." line)
A (profile ON) : 3612 frames / 60.0s | avg 58.2 | 1% low 41.1 | worst 33.0
B (profile OFF): 3701 frames / 60.0s | avg 61.4 | 1% low 44.0 | worst 35.2
verdict: profile ON costs 3.2 fps (-5.2%) - clear difference
-- MEMORY -- lua start/end/peak, +X MB (+Y MB/h), per-phase, buffers
-- SWITCH TIMELINE -- [mm:ss] every mode/apply/restore/phase entry
-- USER CVAR CHANGES -- [mm:ss] tag=user entries only
-- FAILURES & NOTES -- writes failed, skips, aborts, interference
-- SLOW FRAMES -- top 5 worst captured frames of this test, with phase
```

- `[Copy report]`: renders the current (or last finished) report into the
  EditBox and calls `HighlightText()` / focuses it.
- `Dev:PersistReport(report)`: stores into `settings.dev.lastReport`
  (capped 60000 chars, tail-kept if longer) and prepends `{ when,
  summary }` to `settings.dev.tests` (cap 5, newest first).

## 7. Persistence

`CrowdCalmDB.settings.dev = { enabled = false, lastReport = "",
tests = {} }` — created by fillDefaults; normalized in `Dev.new`
(type guards: enabled coerced to boolean, lastReport to string,
tests to table of ≤5 string-pair entries). Force-crowd and the live
journal/stats are runtime-only. schemaVersion stays 1 (additive).

## 8. Code shape

- **New:** `Dev.lua` (engine: state machine, stats, journal, report,
  persistence, `/ccdev` handler). `DevWindow.lua` (window + widgets).
- **Modified:** `Core.lua` — defaults gain `dev` table; `createFrame`
  also creates `Core.devFrame`; `init` creates `Core.dev` with real deps;
  tick: force-crowd override + `ns.Dev.OnTick`; event handler: dev hooks
  at `PLAYER_REGEN_ENABLED`, `PLAYER_ENTERING_WORLD`, `PLAYER_LOGOUT`,
  `CVAR_UPDATE` (all `if ns.Dev then` guarded).
- **Modified:** `spec/run.lua` (+`dev_spec`, `+devwindow_spec`),
  `spec/wow_stub.lua` (+`CreateButton`, `+CreateEditBox` factories,
  `+UnitName`, `+date`, `+C_AddOns.GetAddOnMetadata`).
- **Modified:** `CrowdCalm.toc` (version 0.2.0; load order ... Stutter,
  Monitor, Panel, Dev, DevWindow, Core), `deploy.ps1` (+2 files),
  `README.md` (dev-mode section + manual checklist additions).
- `Panel.lua` and all player-facing UI are untouched.

Branding note: the visible window name and error strings use "CrowdCalm"
only; no placeholder names.

## 9. Constraints carried from the v1 design

- Lua 5.1 / LuaJIT; no libraries; enUS inline strings.
- No cvar writes through new paths: flips only set the force flag; all
  writes stay in `Switch` (combat + loading gates intact); forbidden cvars
  still never touched.
- Per-frame code only while a test is recording (the exact opt-in pattern
  of the stutter log).
- Every new behavior lands with tests; the existing suite must stay green.
- File delivery unchanged: TOC-listed files + `deploy.ps1`.

## 10. Testing

- `spec/dev_spec.lua`: stats math, compare verdicts, journal caps and
  kinds, lifecycle (passive/guided/auto incl. rounds), abort conditions,
  echo vs user tagging, memory cadence, report content, persistence caps,
  settings normalization, command handling. Core state comes from an
  injected fake `getSnapshot`.
- `spec/core_spec.lua` additions: force-crowd override applies/restores
  real cvars through the real switch; `/ccdev` slash registered and
  persisted; corrupt dev settings normalized at init; full auto test
  through Core with fake frame calls and ticker time.
- `spec/devwindow_spec.lua`: window idempotent, controls wire to
  settings/Dev/Core spies, copy button fills EditBox, refresh text.

## 11. Manual verification (added to README checklist)

1. `/ccdev on`, `/ccdev` — window opens; `/reload` — still on.
2. Force crowd → profile applies without a real crowd; off restores.
3. Start auto AB 30s standing in an empty area: phases flip, result line
   appears, report shows the comparison; cvars restored afterwards.
4. Click Copy report, paste into chat/editor — full report readable.
5. Crash/logout mid-test: next login force-crowd is off, no stuck cvars,
   partial report in the window's lastReport after Copy.
6. `/ccdev off` — window hint appears, addon behaves exactly like the
   player version.
