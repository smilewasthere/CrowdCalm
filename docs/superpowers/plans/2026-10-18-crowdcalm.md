# CrowdCalm v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retail WoW addon that detects crowds by counting player nameplates (hysteresis) and auto-switches a curated graphics profile out of combat, restoring safely across logout/crash, with optional frame cap, spell-density and Target-FPS toggles, plus a lightweight status panel and opt-in stutter log.

**Architecture:** 8 runtime Lua files: pure-logic modules (Crowd hysteresis, Profiles, Restore decisions, Stutter buffer) unit-tested with a zero-dependency harness on LuaJIT; thin glue modules (Switch, Monitor, Panel, Core) driven by WoW events and one 1 s ticker; SavedVariables carry settings + crash-recovery state.

**Tech Stack:** WoW Retail 12.1.5 Lua 5.1 dialect (`## Interface: 120105`), no external libraries; tests via LuaJIT 2.1 (`winget install --id DEVCOM.LuaJIT --source winget`) + hand-rolled harness; git.

**Spec:** `docs/specs/crowdcalm-design.md` (authority; conflicts resolve against it).

**Repo root:** `G:\prog\code\CrowdCalm` (flat layout; only TOC-listed files load in-game, so `spec/`, `docs/` are harmless).

**Test command (every task):** `luajit spec/run.lua` run from the repo root (binary: `C:\Users\Nightly\AppData\Local\Programs\LuaJIT\bin\luajit.exe`).

## Global Constraints

- Retail only; `## Interface: 120105`; out-of-date addons are blocked from loading — bump per patch cycle.
- Lua 5.1-compatible syntax (tests run under LuaJIT; no `goto`, no `//`, alias `local unpack = table.unpack or unpack`).
- Never touch: texture-quality cvars, render scale (`RenderScale`, `DynamicRenderScale`), resolution (`gxResolution`), MSAA, `gxApi`, `uiScale`.
- All cvar writes only when not `InCombatLockdown()` and outside the 2 s post-loading debounce; otherwise queue and flush.
- Runtime cvar validation via `C_Console.GetAllCommands()`; unknown/renamed → skip + log, never error. Never set `isReadOnly` cvars.
- No per-frame code except the opt-in Stutter `OnUpdate`.
- `CrowdCalmDB = { schemaVersion = 1, settings = {...}, restore = { sessionActive, baselines, applied } }`; user-made cvar changes always win.
- Zero embedded libraries; enUS strings inline.
- Each task ends green via `luajit spec/run.lua` and one commit.

## Review Focus

1. User manually changes a managed cvar while crowd mode is active → adopted as new baseline, never overwritten on exit. *(Task 5)*
2. Game killed (crash/Task Manager) during crowd mode → next login restores only cvars still holding crowd values; hand-edited ones respected. *(Tasks 4, 6)*
3. Combat starts between decision and apply → no partial state; desired mode applies when combat ends; no repeated writes. *(Task 5)*
4. A cvar is missing/renamed/read-only on this client (e.g., Target-FPS cvar absent, spell-density cvar renamed) → skipped gracefully with a log line; everything else works. *(Tasks 3, 6)*
5. Rapid zone/loading flapping (`/reload`, portal spam) → loading debounce blocks mid-load writes; spell density re-applied after entering world only when it should be. *(Tasks 5, 6)*

---

### Task 1: Scaffold, tooling, harness, spec + plan docs

**Files:**
- Create: `CrowdCalm.toc`, `.gitignore`, `README.md` (brief), `deploy.ps1` (stub), `docs/specs/crowdcalm-design.md`, `docs/superpowers/plans/2026-10-18-crowdcalm.md`, `spec/framework.lua`, `spec/wow_stub.lua`, `spec/smoke_spec.lua`, `spec/run.lua`

**Interfaces:**
- Produces: `framework.describe(name, fn)`, `framework.it(name, fn)`, `framework.expect(x)` with `:toBe(y)`, `:toBeTruthy()`, `:toBeFalsy()`; runner entry `framework.run()` returning `passed, failed` counts.
- Produces: `stub.install()` (creates all WoW globals used by specs), `stub.reset()` (fresh state), `stub.state` (mutable test state: `inCombat`, `time`, `cvars`, `knownCvars`, `secureCvars`, `readOnlyCvars`, `nameplates`, `playerUnits`, `callLog`, `timers`), `stub.loadAddon(file, ns)` which calls `loadfile(file)(ADDON_NAME, ns)` exactly like the client, `stub.runTimers()` (executes due `C_Timer.After` callbacks).
- `spec/run.lua` holds an explicit ordered list of spec module names (no directory listing dependency); each task appends its new spec file to that list.

- [x] **Step 1:** `winget install --id DEVCOM.LuaJIT --source winget --accept-package-agreements --accept-source-agreements` ; verify the binary runs (`luajit -v`).
- [x] **Step 2:** `git init -b main` in the repo root; write `.gitignore` (`dist/`, `*.bak`).
- [x] **Step 3:** Write `CrowdCalm.toc` (runtime files in load order: Crowd, Profiles, Restore, Switch, Stutter, Monitor, Panel, Core; `## SavedVariables: CrowdCalmDB`; `## Version: 0.1.0`), brief `README.md`, `deploy.ps1` stub, `docs/specs/crowdcalm-design.md`, and this plan into `docs/superpowers/plans/`.
- [x] **Step 4:** Write `spec/smoke_spec.lua` plus `spec/run.lua` (loads `spec/framework.lua`, `spec/wow_stub.lua`, then dofiles each listed spec and calls the runner; exits non-zero on failure):

```lua
it("stub GetCVar returns configured value", function()
  stub.reset(); stub.state.cvars.maxFPS = "60"
  expect(GetCVar("maxFPS")):toBe("60")
end)
```
- [x] **Step 5:** Run `luajit spec/run.lua` → FAIL (cannot open `spec/framework.lua` — expected). Implement `spec/framework.lua` and `spec/wow_stub.lua`. Run again → PASS (1/1).
- [x] **Step 6:** Commit: `chore: scaffold repo, toc, test harness, spec and plan docs`.

### Task 2: Crowd hysteresis state machine

**Files:**
- Create: `Crowd.lua`, `spec/crowd_spec.lua`; append `crowd_spec` to the list in `spec/run.lua`.

**Interfaces:**
- Produces: `ns.Crowd.new(settings)` where `settings = {high=15, low=10, enterDelay=3, exitDelay=5}` (missing fields default); `:Update(now, count) -> "normal"|"crowd"`; `:GetMode()`; `:Reset(now)` (back to normal, timers cleared).
- Semantics: enter when `count >= high` sustained for `enterDelay`; exit when `count <= low` sustained for `exitDelay`; the band between is inert; dropping back below `high` (or above `low`) cancels the pending timer.

- [x] **Step 1:** Write failing tests in `spec/crowd_spec.lua`:
  1. Enter delay: `Update(0,20)`→"normal", `Update(2.9,20)`→"normal", `Update(3.1,20)`→"crowd".
  2. Exit delay: from crowd `Update(10,12)`→"crowd" (band inert), `Update(20,8)`→"crowd", `Update(24.9,5)`→"crowd", `Update(25.1,5)`→"normal".
  3. Bounce cancels: `Update(0,20)`, `Update(2,5)`, `Update(4,20)`, `Update(6.9,20)`→"normal", `Update(7.1,20)`→"crowd".
  4. Boundaries inclusive: `Update(0,15)`,`Update(3.1,15)`→"crowd"; then `Update(10,10)`,`Update(15.1,10)`→"normal".
  5. `Reset(now)` returns to "normal" and clears timers: enter pending, `Reset(2)`, `Update(4.5,20)`→"normal", `Update(5.1,20)`→"crowd".
- [x] **Step 2:** Run `luajit spec/run.lua` → FAIL (`Crowd.lua` missing / `Crowd` nil). 
- [x] **Step 3:** Implement `Crowd.lua` minimal to pass.
- [x] **Step 4:** Run → PASS (all specs green).
- [x] **Step 5:** Commit: `feat: crowd hysteresis state machine`.

### Task 3: Curated profile definitions + selection

**Files:**
- Create: `Profiles.lua`, `spec/profiles_spec.lua`; append to `spec/run.lua`.

**Interfaces:**
- Produces: `ns.Profiles.Categories` — ordered array of `{key=..., label=..., defaultEnabled=bool}` for: `particles` (ON), `clutter` (ON), `shadows` (ON), `viewdistance` (OFF), `framecap` (OFF), `spelldensity` (OFF), `targetfps` (OFF).
- Produces: `ns.Profiles.Definitions` — array of entries `{cvar=..., value=..., category=...}`: `particleDensity="25"`, `particleMTDensity="30"`, `groundEffectDensity="16"`, `groundEffectDist="70"`, `graphicsShadowQuality="1"`, `graphicsViewDistance="6"`, `maxFPS="60"`, `maxFPSBk="60"`, `spellVisualDensityFilterSetting="1"`, plus a `targetfps` entry `{category="targetfps", discover="targetfps", value="60"}` (cvar name resolved at runtime).
- Produces: `ns.Profiles.Select(settings, env) -> entries, skipped` where `env = {isKnown(cvar), isSecure(cvar), isReadOnly(cvar), findCvar(name)}`; `entries` = array `{cvar=, value=, category=, secure=bool}`; `skipped` = map `cvar-or-key = "unknown"|"read-only"|"not-found"|"disabled"`. `settings.categories` defaults from `Categories` when absent.
- `findCvar(name)`: exact case-insensitive match among client commands (called by Core with `C_Console` data); absent → "not-found".

- [x] **Step 1:** Write failing tests in `spec/profiles_spec.lua`:
  1. Default selection includes particles/clutter/shadows cvars and excludes viewdistance/framecap/spelldensity/targetfps.
  2. Enabling `framecap` adds `maxFPS`="60" and `maxFPSBk`="60" to entries.
  3. `isKnown` false for `particleDensity` → `skipped.particleDensity == "unknown"`, entry absent, others unaffected.
  4. `isReadOnly` true for `groundEffectDensity` → skipped "read-only".
  5. `isSecure` true for `graphicsShadowQuality` → included with `secure == true`.
  6. `targetfps` enabled: `findCvar("targetfps")` returns nil → `skipped.targetfps == "not-found"`; returns "targetfps" → entry present with that cvar name.
  7. Guard test: every cvar in `Definitions` must not contain any forbidden pattern (`texture`, `scale`, `resolution`, `msaa`, `gxapi`, `uiscale`) — iterating the real table.
- [x] **Step 2:** Run → FAIL. 
- [x] **Step 3:** Implement `Profiles.lua`.
- [x] **Step 4:** Run → PASS.
- [x] **Step 5:** Commit: `feat: curated graphics profile definitions and selection`.

### Task 4: Restore decision logic (pure)

**Files:**
- Create: `Restore.lua`, `spec/restore_spec.lua`; append to `spec/run.lua`.

**Interfaces:**
- Produces: `ns.Restore.Plan(persisted, current) -> plan`; `persisted = {sessionActive, baselines, applied}` (may be nil — treat as no session); `current` = map `cvar -> value|nil` (nil = cvar gone); `plan = {restore={cvar=baseline}, adopt={cvar=value}, clear={cvar=true}, restoreAny=bool}`.
- Rules: only when `sessionActive` truthy; per cvar in `applied`: `current == applied` → restore baseline (if baseline recorded; else clear); `current == baseline` → clear; `current == nil` (gone) → clear; otherwise → adopt current as new baseline. `restoreAny` = at least one restore entry.

- [x] **Step 1:** Write failing tests in `spec/restore_spec.lua`:
  1. `applied={a="1"}, baselines={a="10"}, current={a="1"}` → `restore.a=="10"`, `restoreAny==true`.
  2. `current={a="10"}` (already baseline) → no restore, `clear.a==true`.
  3. `current={a="50"}` (user hand-edited) → `adopt.a=="50"`, no restore.
  4. `current={}` (cvar gone) → `clear.a==true`, no restore.
  5. `sessionActive=false/nil` → empty plan even with data present.
  6. `applied` entry with no recorded baseline and `current==applied` → `clear` (nothing to restore to), no restore.
- [x] **Step 2:** Run → FAIL.
- [x] **Step 3:** Implement `Restore.lua`.
- [x] **Step 4:** Run → PASS.
- [x] **Step 5:** Commit: `feat: crash-recovery restore planner`.

### Task 5: Switch orchestrator (combat gating, queue, user-change adoption)

**Files:**
- Create: `Switch.lua`, `spec/switch_spec.lua`; append to `spec/run.lua`.

**Interfaces:**
- Consumes: Profiles entries shape `{cvar=, value=, secure=bool}`; Restore plan shape `{restore, adopt, clear, restoreAny}`.
- Produces: `ns.Switch.new(deps, entries)` with `deps = {getTime(), getCvar(name), setCvar(name, value)->true|nil, inCombat(), log(fmt,...)}`; `entries` fixed at construction (Core rebuilds the Switch on settings change).
- Methods: `:Request(mode)` (set desired "normal"|"crowd"), `:TryApply()` (apply desired if allowed; no-op when already in desired state), `:OnCombatEnd()`, `:OnEnteringWorld()` (starts 2 s loading debounce from `getTime()`), `:OnCvarChange(name, value)`, `:OnLogout()` (force restore of everything, ignoring debounce), `:RestorePersisted(plan)` (apply `plan.restore` writes, set baselines from `plan.adopt`, drop `plan.clear`; mode → "normal", applied cleared).
- `:GetState() -> {mode="normal"|"crowd", desired, pendingReason=nil|"combat"|"loading"|"failed", baselines={}, applied={}}`.
- Semantics: applying crowd captures `getCvar` baseline per entry before its first write; `setCvar` returning nil (secure race) keeps the entry applied=false and sets `pendingReason="failed"` (retried on next `TryApply`); our own writes echoed via `OnCvarChange` are ignored (`value == applied[name]`); any other change to a managed cvar updates its baseline (adoption).

- [x] **Step 1:** Write failing tests in `spec/switch_spec.lua` (stub `callLog` records `{name, value}` per set):
  1. `Request("crowd"); TryApply()` → entries written in order; `GetState().mode=="crowd"`; baselines equal pre-values; `applied` equals entry values.
  2. `Request("normal"); TryApply()` → baselines re-written; `applied` empty.
  3. `inCombat=true`; `Request("crowd"); TryApply()` → zero sets, `pendingReason=="combat"`; `OnCombatEnd()` → applied.
  4. `OnEnteringWorld()` at t=10; t=11 `TryApply()` → `pendingReason=="loading"`, zero sets; t=12.1 `TryApply()` → applied.
  5. `setCvar` fails (returns nil) for one entry → that entry not in `applied`, `pendingReason=="failed"`, mode still "normal"; stub starts returning true; `TryApply()` → applied, no re-write of the already-applied other entries.
  6. Echo ignored: crowd mode with `applied.a="1"`; `OnCvarChange("a","1")` → baseline unchanged; `OnCvarChange("b","9")` → `baselines.b=="9"`; `Request("normal"); TryApply()` → writes "9" for b, not the old baseline.
  7. `OnLogout()` in crowd mode inside the loading window → restores all baselines anyway; state `mode=="normal"`.
  8. `TryApply()` twice in a row → second adds no `callLog` entries (idempotent).
  9. `RestorePersisted({restore={a="10"}, adopt={b="50"}, clear={c=true}})` → writes a="10", `baselines.b=="50"`, c dropped, mode "normal".
- [x] **Step 2:** Run → FAIL. 
- [x] **Step 3:** Implement `Switch.lua`.
- [x] **Step 4:** Run → PASS.
- [x] **Step 5:** Commit: `feat: settings switch orchestrator with combat-safe queue`.

### Task 6: Core wiring (events, SavedVariables, ticker, hint, spell-density reapply)

**Files:**
- Create: `Core.lua`, `spec/core_spec.lua`; append to `spec/run.lua`.

**Interfaces:**
- Consumes: all modules above; WoW globals `C_NamePlate.GetNamePlates()`, `UnitIsPlayer(token)`, `IsResting()`, `GetFramerate()`, `C_Timer.NewTicker(interval, fn)`, `C_Timer.After(delay, fn)`, `C_CVar.GetCVarInfo`, `C_Console.GetAllCommands()`, `RegisterEvent`/`CreateFrame` via Core's own frame (created only in-game; tests call `Core._handleEvent(event, ...)` and `Core._tick(now)` directly).
- Produces: `ns.Core._handleEvent(event, ...)`, `ns.Core._tick(now)`, `ns.Core._checkHint(now, playerPlateCount, isResting) -> bool` (one-shot), `ns.Core.DEFAULTS` (full default settings table per spec §5), `ns.Core.CountPlates()` (player plates when `settings.countOnlyPlayers`).
- Tick behavior: advance `Crowd:Update(now, count)`; on change `Switch:Request(mode)`; always `Switch:TryApply()`; every 5th tick `Monitor.Push(now, Monitor.GetOwnMB())`; persist state to `CrowdCalmDB.restore` when it changed (`sessionActive = mode=="crowd" or applied non-empty`; mirror `GetState()` baselines/applied).
- Events: `ADDON_LOADED` (init SV, defaults, `schemaVersion` reset rule, crash recovery via `Restore.Plan` + `Switch:RestorePersisted`, create ticker); `PLAYER_REGEN_ENABLED` → `Switch:OnCombatEnd()`; `PLAYER_ENTERING_WORLD` → `Switch:OnEnteringWorld()` + schedule (`C_Timer.After(2, ...)`) one re-apply of `spellVisualDensityFilterSetting` when the spell-density category is enabled **and** mode is still crowd **and** it was engaged; `PLAYER_LOGOUT` → `Switch:OnLogout()` + `sessionActive=false` persisted; `CVAR_UPDATE` → `Switch:OnCvarChange(cvar, value)` for managed cvars only.
- Hint: `_checkHint` returns true exactly once (persists `settings.hintShown`) when `isResting`, `count==0`, and 30 s have elapsed since first observation.

- [x] **Step 1:** Write failing integration tests in `spec/core_spec.lua` (using `stub.loadAddon` on each runtime file, then `Core._handleEvent("ADDON_LOADED", "CrowdCalm")`):
  1. Fresh login → `CrowdCalmDB.schemaVersion==1`; defaults written; no cvar writes.
  2. Crowd cycle: 16 player plates; `_tick(10)`, `_tick(13.1)` → crowd applied (callLog sets); plates removed; `_tick(20)`, `_tick(25.1)` → restored; `restore.sessionActive==false`.
  3. Combat pending: `inCombat=true` until after the enter delay → `_tick` produces no sets; `_handleEvent("PLAYER_REGEN_ENABLED")` → sets appear.
  4. Logout mid-crowd: `_handleEvent("PLAYER_LOGOUT")` → restore sets present, `sessionActive==false`.
  5. Crash recovery: `CrowdCalmDB.restore={sessionActive=true, baselines={particleDensity="100"}, applied={particleDensity="25"}}`, `cvars.particleDensity="25"` → `ADDON_LOADED` writes "100" and clears `sessionActive`; variant current="50" → adopted as baseline, no write.
  6. Launch with a managed cvar missing (`knownCvars` without it) → skip logged, everything else applies, no error.
  7. Spell density: category enabled + crowd mode; `_handleEvent("PLAYER_ENTERING_WORLD")`; advance time and `stub.runTimers()` → `spellVisualDensityFilterSetting` re-set; when mode is normal → no re-set.
  8. Hint: not resting → false; resting count>0 → false; resting count==0 before 30 s → false; after 30 s → true once, false afterwards; persists.
- [x] **Step 2:** Run → FAIL.
- [x] **Step 3:** Implement `Core.lua`.
- [x] **Step 4:** Run → PASS.
- [x] **Step 5:** Commit: `feat: core event wiring, crash-safe persistence, crowd ticker`.

### Task 7: Stutter log (opt-in)

**Files:**
- Create: `Stutter.lua`, `spec/stutter_spec.lua`; append to `spec/run.lua`; Core hookup in `Core.lua` + test in `spec/core_spec.lua`.

**Interfaces:**
- Produces: `ns.Stutter.new(settings)` with defaults `{enabled=false, thresholdMs=50, minGapMs=1000, maxEntries=100}`; `:ShouldLog(deltaMs, now) -> bool` (true iff `deltaMs > thresholdMs` and `now - lastLogged >= minGapMs`; records `lastLogged` when true); `:Add({t=, deltaMs=, context=})` appends, dropping the oldest beyond `maxEntries`; `:GetEntries() -> array`; `:SetEnabled(enabled, now)` (resets `lastLogged=now` on enable).
- Core: when `settings.stutter.enabled` and the addon frame does not yet have an `OnUpdate`, attach one that computes `deltaMs = (GetTime() - lastFrameTime) * 1000`, calls `ShouldLog`, and on true records context `{zone=GetZoneText(), mode=..., sinceSwitch=...}`.

- [x] **Step 1:** Write failing tests:
  1. delta exactly at threshold → false; above → true.
  2. Two hits within `minGapMs` → second false; after gap → true.
  3. 105 adds with `maxEntries=100` → `GetEntries()` length 100 and oldest dropped (first entry t no longer present).
  4. Disabled: `ShouldLog` false regardless; `SetEnabled(true, now)` resets lastLogged so an immediate hit logs.
  5. Core hookup: with stutter enabled, after `ADDON_LOADED` simulate two `OnUpdate` calls (frame captured by stub `CreateFrame`) with delta 80 ms → one entry with context; disabled → frame's `OnUpdate` nil.
- [x] **Step 2:** Run → FAIL.
- [x] **Step 3:** Implement `Stutter.lua` + Core hookup.
- [x] **Step 4:** Run → PASS.
- [x] **Step 5:** Commit: `feat: opt-in stutter log with ring buffer`.

### Task 8: Monitor + Panel (status, config UI, validation)

**Files:**
- Create: `Monitor.lua`, `Panel.lua`, `spec/monitor_spec.lua`, `spec/panel_spec.lua`; append both to `spec/run.lua`.

**Interfaces:**
- Produces: `ns.Monitor.GetOwnMB() -> number` (`collectgarbage("count")/1024`); `ns.Monitor.Push(now, mb)` (12-sample ring); `ns.Monitor.GetSamples() -> array`; `ns.Monitor.GetLast() -> mb|nil`.
- Produces: `ns.Panel.ValidateSettings(s) -> sanitized, issues` where `issues` is an array of human-readable corrections; clamps `low >= high` → `low = high-1` (min 1), `enterDelay`/`exitDelay` to 0–60, `high` to 2–40, `framecapValue` to 0–400, `high` to 1–40, `stutter.thresholdMs` 10–500, `maxEntries` 1–1000.
- Produces: `ns.Panel.Create()` (builds the frame once; no-op widget stubs in tests), `ns.Panel.Toggle()`, `ns.Panel.Refresh()` (status text: mode, crowd count, FPS, memory MB, last switch), `ns.Panel.RunCommand(input)` handling `/cc` subcommands `status|log|memory|on|off` and bare toggle.

- [x] **Step 1:** Write failing tests:
  1. Monitor: stub `collectgarbage` to return 2048 (KB) → `GetOwnMB()==2`; `Push` 13 samples → ring holds 12, oldest dropped.
  2. Validate: `{high=5, low=9}` → sanitized `low` < `high` with issue recorded; delays 61 → clamped to 60 with issue; negative cap → 0; valid input → `issues` empty and values unchanged.
  3. Panel: `Create()` under stubbed `CreateFrame` runs without error and is idempotent (second call no-op); `RunCommand("status")` prints without error; `RunCommand("on")`/`("off")` flips `settings.enabled`.
- [x] **Step 2:** Run → FAIL.
- [x] **Step 3:** Implement `Monitor.lua`, `Panel.lua`.
- [x] **Step 4:** Run → PASS.
- [x] **Step 5:** Commit: `feat: status panel, config UI, settings validation`.

### Task 9: Deploy script, README, manual in-game verification

**Files:**
- Replace: `deploy.ps1` (real); rewrite `README.md` (full); update plan checklists if done inline.

- [x] **Step 1:** Implement `deploy.ps1 -WowRoot <path to _retail_>`: validates the path looks like a WoW install (`Interface` directory co-located or creatable), creates `Interface\AddOns\CrowdCalm`, copies the TOC + the 8 runtime lua files only (never `spec/`, `docs/`), prints each copied file; `-WhatIf`-style `-DryRun` optional.
- [x] **Step 2:** README: install (manual + script), friendly-nameplates requirement (and its instance limitation), settings reference, crash-recovery explanation, caveats (spell density instance-only + client reset bug; Target-FPS availability; settings UI won't reflect cvar changes until `/reload`), dev workflow (`luajit spec/run.lua`), and the manual in-game checklist below.
- [x] **Step 3:** Run `luajit spec/run.lua` → all green.
- [x] **Step 4:** Manual in-game checklist (runs on the player's machine, documented in README): `/console scriptErrors 1`; enable friendly nameplates; `/cc` opens panel; stand in a city → flips to crowd per thresholds; start combat during a pending flip (dummy) → applies after combat; `/reload` in crowd → settings restored, no re-apply mid-load; Task-Kill WoW mid-crowd → relaunch → restored (or hand-edited values kept); spell-density toggle re-applied after instance load; `/cc log` readable after a stutter session; no Lua errors or taint.
- [x] **Step 5:** Commit: `docs: readme, deploy script, manual test checklist`.
