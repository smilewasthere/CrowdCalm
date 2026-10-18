# CrowdCalm Dev Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a gated developer mode to CrowdCalm: live feature toggles, a force-crowd switch, an FPS/memory recorder with three test modes, and a copyable text report — all inside two new files, invisible when off.

**Architecture:** `Dev.lua` is a self-contained engine (state machine, pure stats math, journal, report builder, `/ccdev` commands) that receives injected deps from `Core.lua`; `DevWindow.lua` is the in-game UI driving the engine and the existing settings/switch plumbing. Core pokes the engine at tick/event boundaries with guarded one-liners; the player path is byte-identical when dev mode is off.

**Tech Stack:** WoW Retail 12.1.5 Lua 5.1 dialect, LuaJIT test harness (`luajit spec/run.lua`), hand-rolled WoW API stub.

**Spec:** `docs/specs/crowdcalm-dev-mode-design.md` — the plan argues from it; read both.

## Global Constraints

- `## Interface: 120105`; TOC version becomes `0.2.0`.
- Lua 5.1-compatible under LuaJIT: no `goto`, no `//`.
- No cvar writes through new paths: phase flips only set the force flag; all writes stay in `Switch` (combat + loading gates intact); forbidden cvars (textures, render scale, resolution, MSAA, gxApi, uiScale) remain untouched.
- Per-frame code only while a dev test is recording (opt-in, like the stutter hook); dev mode off = zero added per-frame work and only guarded one-line checks per tick.
- `Dev.forceCrowd` is runtime-only; it never appears in SavedVariables and is false on every login.
- Ring/caps: journal 2000 entries, 30000 deltas per phase group, `lastReport` 60000 chars (tail-kept), `tests` list 5 entries newest-first.
- Defaults: auto phase length 60 s (allowed 30/60/120), rounds `AB` (or `ABAB`), memory sample every 5 s, verdict thresholds 2% (slight) / 5% (clear).
- Suite must be green after every task (`luajit spec/run.lua`); TDD order: failing test first, watch it fail.
- String-format style follows existing files (`string.format`, enUS inline); no libraries.

## Review Focus

1. Reload/logout/crash mid-test: no dangling OnUpdate hook, force-crowd false, partial report persisted, no stuck applied cvars. *(Task 1 abort tests + Task 2 logout test)*
2. Combat blocking a flip mid auto-test: test aborts with `"combat"` reason instead of silently comparing garbage; cvars left consistent. *(Task 1 `auto abort on combat`, Task 2 integration)*
3. Long sessions: journal/deltas/report/tests caps hold so SavedVariables cannot balloon or leak. *(Task 1 cap tests)*
4. Real (unforced) crowd during passive/guided runs: mode/apply/restore timeline still correct. *(Task 1 diff tests, Task 2 journal test)*
5. Dev disabled or Core missing: `/ccdev` hints instead of erroring; window refuses to open; tick journals nothing. *(Task 2 `player path unaffected`, Task 3 guard tests)*

## File Structure

- Create `Dev.lua` — engine: constants, `FrameStats`, `CompareFrameStats`, `Dev.new(settings, deps)`, lifecycle (`StartTest/NextPhase/StopTest/SetEnabled/SetForceCrowd`), ingest (`OnFrame/OnTick/OnCvar/OnLogout`), output (`GetStatus/GetReport/GetLastResult/PersistReport/GetJournal`), `/ccdev` slash + `RunCommand`.
- Create `DevWindow.lua` — window frame `CrowdCalmDevPanel`, controls, `Toggle/Create/Refresh`.
- Create `spec/dev_spec.lua`, `spec/devwindow_spec.lua`.
- Modify `Core.lua` — DEFAULTS `dev` table; `Core.devFrame` in `createFrame`; `Core.dev` instance in `init`; force-crowd override + `Dev:OnTick` in `_tick`; four guarded event hooks.
- Modify `spec/core_spec.lua` — load `Dev.lua` before `Core.lua`; integration tests.
- Modify `spec/wow_stub.lua` — `CreateButton`, `CreateEditBox`, `HighlightText`, `SetFocus`, `UnitName`, `date`, `C_AddOns.GetAddOnMetadata`.
- Modify `spec/run.lua` — add `devwindow_spec`, `dev_spec`.
- Modify `CrowdCalm.toc` (0.2.0 + Dev/DevWindow before Core), `deploy.ps1` (+2 files), `README.md`.

---

### Task 1: Dev engine (`Dev.lua`)

**Files:**
- Create: `Dev.lua`
- Create: `spec/dev_spec.lua`
- Modify: `spec/run.lua` (append `"dev_spec"` to the `specs` list)

**Interfaces:**
- Consumes: nothing (standalone module `ns.Dev`).
- Produces (later tasks rely on exactly these):
  - `Dev.FrameStats(deltas) -> { frames, seconds, avgFps, avgMs, maxMs, minFps, p1LowFps, capped }` (empty input: all zeros, `capped=false`).
  - `Dev.CompareFrameStats(on, off) -> { avgDelta, avgPercent, lowDelta, verdict }`, `verdict` in `"clear" | "slight" | "none"`; `avgPercent` 0 when `off.avgFps == 0`.
  - `Dev.new(settings, deps) -> dev` with `deps = { getTime, setFrameHook(fnOrNil), log(msg), getSnapshot() }`; `getSnapshot()` returns `{ mode, plates, applied, baselines, pendingReason }`.
  - Fields: `dev.enabled` (bool), `dev.forceCrowd` (bool).
  - Methods: `dev:SetEnabled(bool)`, `dev:SetForceCrowd(bool)`, `dev:StartTest(mode, opts)`, `dev:NextPhase()`, `dev:StopTest(reason)`, `dev:OnFrame(now, deltaMs)`, `dev:OnTick(now)`, `dev:OnCvar(cvar, value)`, `dev:OnLogout(now)`, `dev:GetStatus() -> { mode, phase, phaseEndsAt, recording, forceCrowd, result }`, `dev:GetReport() -> string`, `dev:GetLastResult() -> string|nil`, `dev:PersistReport(report)`, `dev:GetJournal() -> entries`.
  - `Dev.RunCommand(input)` module function (reads `ns.Core.dev`; delegates `""` window toggle to `ns.DevWindow.Toggle` when `ns.DevWindow` exists).
  - Registered `SlashCmdList["CROWDCALMDEV"]` / `SLASH_CROWDCALMDEV1 = "/ccdev"`.

- [ ] **Step 1: Write the failing spec `spec/dev_spec.lua`**

Header follows the existing pattern:

```lua
describe("Dev", function()
  local ns = stub.newNs()
  stub.loadAddon("Dev.lua", ns)

  local SNAP = { mode = "normal", plates = 0, applied = {}, baselines = {}, pendingReason = nil }

  local function fakeDeps(overrides)
    local deps = {
      getTime = function()
        return stub.state.time
      end,
      setFrameHook = function(fn)
        deps.hook = fn
      end,
      log = function(msg)
        stub.state.logged[#stub.state.logged + 1] = tostring(msg)
      end,
      getSnapshot = function()
        return deps.snapshot or SNAP
      end,
    }
    deps.snapshot = SNAP
    for key, value in pairs(overrides or {}) do
      deps[key] = value
    end
    return deps
  end

  local function newDev(settings, overrides)
    return ns.Dev.new(settings or {}, fakeDeps(overrides))
  end
  -- tests below
```

Test list (names and the exact assertions that matter):

1. `"FrameStats computes avg, min, 1% low and worst"` — 80 deltas of `12.5` ms plus one of `100` ms → `frames=81`? No: use 79×12.5 + 1×100 = 1087.5 ms… keep it exact: **79 deltas of 12.5 and one of 100** → `frames=80`, `seconds=1.0875`? floating. Prefer: **80 deltas of 12.5** → `frames=80, seconds=1, avgFps=80, avgMs=12.5, maxMs=12.5, minFps=80, p1LowFps=80` (12.5 and 80 are binary-exact). Second call with `{100, 12.5, 12.5, 12.5, 12.5}` → `frames=5, maxMs=100, minFps=10, p1LowFps=10` (`ceil(5*0.01)=1`).
2. `"FrameStats handles empty and capped input"` — `{}` → all zeros, `capped=false`; 30005 deltas of 1.0 → `frames=30005` counted? No — `frames` = stored count and `capped=true`; assert `#deltas` stored length is 30000 via `Dev.FrameStats` returning `capped=true` and `frames=30000` (spec: further frames counted but not stored — simplest faithful read: `frames` counts stored frames; report notes capped). Implement `Dev.FrameStats` on the internal stored list, and the recorder sets `capped`.
3. `"CompareFrameStats verdicts"` — `on={avgFps=120, p1LowFps=100}, off={avgFps=100, p1LowFps=90}` → `avgDelta=20, avgPercent=20, verdict="clear"`; `on=101, off=100` → `"none"`; `on=103, off=100` → `"slight"`; `off={avgFps=0}` → `avgPercent=0, verdict="none"`.
4. `"normalizes corrupt dev settings in place"` — `settings={enabled="yes", lastReport=5, tests="x"}` → after `newDev`: `settings.enabled==false`, `settings.lastReport==""`, `type(settings.tests)=="table"`; `dev.forceCrowd==false`.
5. `"journals mode, apply and restore diffs"` — dev enabled; `deps.snapshot = {mode="normal", plates=0, applied={}, baselines={}}`; `dev:OnTick(1)`; set snapshot `{mode="crowd", plates=16, applied={particleDensity="25"}, baselines={particleDensity="100"}}`; `dev:OnTick(2)`; snapshot applied `{}` again, mode normal; `dev:OnTick(3)`. Assert journal (`dev:GetJournal()`) contains in order: `kind=="mode"` (`to=="crowd"`, `plates==16`), `kind=="apply"` (`cvar=="particleDensity"`, `value=="25"`, `baseline=="100"`), `kind=="mode"` (`to=="normal"`), `kind=="restore"` (`cvar=="particleDensity"`, `value=="100"`).
6. `"caps the journal at 2000 entries and counts drops"` — enable dev, call `dev:OnTick(i)` 2100 times with changing snapshots; `#dev:GetJournal()==2000`; `dev:GetStatus().dropped == 100` (expose `dropped` in `GetStatus`).
7. `"OnCvar tags managed writes as echo and real edits as user"` — apply via tick (snapshot applied `{a="1"}`); `dev:OnCvar("a", "1")`; tick again → journal has `kind=="cvar", tag=="echo"`; `dev:OnCvar("a", "2")`; tick → `tag=="user"`.
8. `"passive recording captures frames and stops cleanly"` — `dev:StartTest("passive")`; `deps.hook` not nil; `deps.hook()` after `stub.state.time = 2`… simpler: call `dev:OnFrame(2.0, 10)` ×10; `dev:StopTest("manual")`; `deps.hook==nil`; `dev:GetStatus().mode=="idle"`; `settings.lastReport` contains `"CrowdCalm Dev Report"` and `"comparison unavailable"`.
9. `"auto AB test flips force crowd and produces a comparison"` — `stub.state.time = 100`; `dev:SetEnabled(true)`; `dev:StartTest("auto", { phaseSeconds = 30, rounds = "AB" })`; assert `dev.forceCrowd==true`; `dev:OnFrame(100.5, 10)`–ish: 10 frames; snapshot `{mode="crowd", applied={a="1"}, ...}`; `dev:OnTick(110)` (no flip); at `stub.state.time=131`, `deps.snapshot = {mode="normal", applied={}}`; `dev:OnTick(131)` → phase B, `dev.forceCrowd==false`; 10 frames of `20` ms; `dev:OnTick(162)`; assert `dev:GetStatus().mode=="idle"`, `dev.forceCrowd==false`, `deps.hook==nil`, `dev:GetLastResult()` contains `"A"` and `"faster"` (A frames 10 ms → 100 fps vs B 20 ms → 50 fps → ON is +100%), `settings.lastReport` contains `"PHASE COMPARISON"` and `"verdict:"`, and `#settings.tests == 1`.
10. `"ABAB merges both rounds per group"` — same harness with `rounds="ABAB"`, phaseSeconds 30: ticks at 131, 162, 193 → total 4 phases then idle; journal `kind=="phase"` flips == 3; A group received frames from phases 1 and 3 (assert via final result containing `avg` computed from merged 20 frames).
11. `"auto aborts when combat blocks the flip"` — start auto AB 30s at t=100; after flip at 131 set `deps.snapshot = { mode="normal", applied={}, pendingReason="combat" }`; `dev:OnTick(133.5)` (flipCheck due 133) → `dev:GetStatus().mode=="idle"`; `dev.forceCrowd==false`; `deps.hook==nil`; `settings.lastReport` contains `"aborted"` and `"combat"`; journal has `kind=="test", state=="aborted"`.
12. `"auto aborts when the apply never takes effect"` — phase A (expected applied non-empty) but snapshot keeps `applied={}` and `pendingReason=nil`; flipCheck at start+2 → aborted, reason mentions `"apply"`.
13. `"guided recording alternates phases on demand"` — `dev:StartTest("guided")`; force true; `dev:NextPhase()` → journal phase `A stop` then `B start`, force false; `dev:NextPhase()` → force true again label A; `dev:StopTest("manual")` → idle, hook nil.
14. `"disabling dev mid-test aborts and persists"` — start passive; `dev:SetEnabled(false)` → idle, `settings.enabled==false`, `lastReport` non-empty, `deps.hook==nil`.
15. `"OnLogout mid-test aborts with a logout reason"` — start passive; `dev:OnLogout(5)` → journal test aborted reason contains `"logout"`; report persisted. Idle `dev:OnLogout(6)` → no error.
16. `"memory is sampled every 5s while recording only"` — start passive; `stub.state.gcKB = 2048`; `dev:OnTick(10)`; `dev:OnTick(12)` (no mem entry); `dev:OnTick(15)`, `dev:OnTick(20)` → journal `kind=="mem"` entries == 3 (10/15/20… first sample recorded at first tick ≥ start), each `mb==2`; stop; `dev:OnTick(30)` → no new mem entries.
17. `"report renders all sections"` — drive an AB test to completion (as test 9), condition `stub.state.gcKB`, then `local report = dev:GetReport()`; assert it contains `"== CrowdCalm Dev Report =="`, `"generated:"`, `"features:"`, `"-- PHASE COMPARISON --"`, `"-- MEMORY --"`, `"-- SWITCH TIMELINE --"`, `"-- FAILURES & NOTES --"`, `"-- SLOW FRAMES --"`, and the verdict line.
18. `"PersistReport caps the report and the tests list"` — `dev:PersistReport(string.rep("x", 70000))` → `#settings.lastReport == 60000`; call `PersistReport` 7 times with distinct summaries → `#settings.tests == 5` and `settings.tests[1].when` corresponds to the newest (assert first entry summary equals latest).
19. `"RunCommand handles on/off/status/window/usage"` — `ns.Core = { dev = dev }`; `Settings`…: `ns.Dev.RunCommand("on")` → `dev.enabled==true`, logged contains `"dev mode on"`; `"off"` → false; `"bogus"` → printed contains `"usage"`; `ns.DevWindow = { Toggle = function() toggled = toggled + 1 end }`; `RunCommand("")` with enabled → toggled==1; `RunCommand("")` with disabled → printed contains `"/ccdev on"`; `RunCommand("window")` → toggled==2. Also `_G.SlashCmdList.CROWDCALMDEV` is a function.

Constants to expose at module level if a test wants them: not required.

- [ ] **Step 2: Run the suite to watch it fail**

Run: `luajit spec/run.lua`
Expected: FAIL — `cannot load 'Dev.lua'` (spec loads the missing module). No other spec regressions.

- [ ] **Step 3: Implement `Dev.lua`**

Full engine, one coherent file. Requirements the tests pin:

- Constants (module-local): `JOURNAL_CAP=2000`, `DELTA_CAP=30000`, `MEM_INTERVAL=5`, `REPORT_CAP=60000`, `TESTS_CAP=5`, `VERDICT_CLEAR=5`, `VERDICT_SLIGHT=2`, `FLIP_GRACE=2`, `DEFAULT_PHASE_SECONDS=60`.
- `Dev.FrameStats(deltas)`: as specified in Interfaces (`capped` field defaults false; the recorder constructs a temp table copy before computing to keep it pure).
- `Dev.CompareFrameStats(on, off)`: `avgDelta=on.avgFps-off.avgFps`; `avgPercent` relative to `off.avgFps` guarded; `lowDelta=on.p1LowFps-off.p1LowFps`; verdict by `math.abs(avgPercent)` vs 5/2.
- `Dev.new(settings, deps)`: normalize settings in place (enabled `== true`, lastReport string else `""`, tests table trimmed to last 5) with metatable; state per Interfaces. Journal entries are plain tables appended to `self.entries` with `dropped` counter.
- `StartTest(mode, opts)`:
  - journal `{kind="test", mode=mode, state="started"}`;
  - `passive`: group `S` active immediately; no force change;
  - `guided`: phase index 1, label `"A"`, `SetForceCrowd(true)` via internal flip that journals `{kind="phase", name="A", event="start"}`;
  - `auto`: `phaseSeconds = opts.phaseSeconds` if in `{30,60,120}` else 60; phases from rounds (`"ABAB"` → 4 phases else 2), starting at index 1; `phaseEndsAt = now + phaseSeconds`; force per phase;
  - install hook once: `deps.setFrameHook(function() local now = deps.getTime(); local delta = (now - last) * 1000; last = now; self:OnFrame(now, delta) end)` with `last = deps.getTime()`; journal a `mem` sample immediately.
- `NextPhase()` (guided only): stop current (journal `phase <name> stop`), toggle force, next label cycles A/B, journal `phase <name> start`, reset `phaseEndsAt` unused (guided has no timer).
- `StopTest(reason)`: guard idle; journal `phase ... stop` if a phase open, then `{kind="test", state= reason=="manual" and "stopped" or "aborted", reason=reason}`; build groups result when A and B both non-empty; `deps.setFrameHook(nil)`; `self.forceCrowd=false`; `PersistReport(self:GetReport())`; clear active test keeping it as `self.lastTest` for `GetReport`/`GetLastResult`.
- `OnFrame(now, deltaMs)`: no-op unless recording; append to active group with cap (increment group `cappedFrames` when dropping); track `test.lastFrame` for report timing.
- `OnTick(now)`: return early unless `enabled`; flush pending cvar queue (tagging); snapshot diff (mode/apply/restore/journal); mem sample when recording and `now - lastMem >= MEM_INTERVAL` (first sample right after start); auto: if recording and `now >= phaseEndsAt` → advance (flip force, journal), set `flipCheckAt = now + FLIP_GRACE`; abort checks at `flipCheckAt`: `pendingReason=="combat" or "failed"` → abort reason `"combat interfered"`/`"apply failed"`; else phase-A-with-empty-applied or phase-B-with-nonempty-applied → abort `"apply did not take effect"`; if last phase finished → `StopTest("complete")` (state `"stopped"`, reason `"complete"`).
- `OnCvar(cvar, value)`: enabled only; queue `{cvar, value}`; flushed in `OnTick` AFTER snapshot diff; tag `"echo"` when value equals current applied value for cvar OR the recorded baseline/restored value for the most recent apply/restore of that cvar; else `"user"`; journal `{kind="cvar", cvar=cvar, value=value, tag=tag}`.
- `OnLogout(now)`: enabled and recording → `StopTest("logout")`; journal note otherwise (no-op if idle and disabled).
- `GetStatus()`: `{ mode = test and test.mode or (self.enabled and "idle" or "off"), phase = current label or nil, phaseEndsAt, recording = test ~= nil, forceCrowd = self.forceCrowd, result = lastResult, dropped }`.
- `GetReport()`: exact section order from the spec §6; `generated:` uses `date("%Y-%m-%d %H:%M:%S")` guarded (`type(date)=="function"`), addon version via `pcall(C_AddOns.GetAddOnMetadata, "CrowdCalm", "Version")` fallback `"?"`, character `UnitName("player")` guarded, zone `GetZoneText()` guarded, features line from the `settings` it was constructed with (all numeric/bool fields: enabled, each category, stutter.enabled). Timeline `[m:ss]` from `test.startedAt`. `SLOW FRAMES` = top 5 of captured deltas with phase label. A/B comparison only when both groups have frames, else `"comparison unavailable: <why>"` (passive → `"passive recording"`). Memory section from mem entries inside the test window (start/end/peak/delta/hour, per-phase via marks, buffers = `#journal`, `#(ns.Stutter entries if reachable via ns.Core.stutter)`, `ns.Monitor.GetSamples()` length — all guarded pcall-free `if` chains).
- `PersistReport(report)`: tail-keep to 60000; unshift `{ when = date guard or "?", summary = first line of GetLastResult() or test state }` into `settings.tests`, trim to 5.
- Commands: `Dev.RunCommand(input)` per Interfaces; logging via `print("CrowdCalm: ...")`.

- [ ] **Step 4: Run the suite to verify green**

Run: `luajit spec/run.lua`
Expected: `PASS` for every `Dev >` test; total `73 + ~19 = 92`-ish passed, 0 failed (exact count may differ slightly if tests are split).

- [ ] **Step 5: Commit**

```bash
git add Dev.lua spec/dev_spec.lua spec/run.lua
git commit -m "feat: dev engine (recorder, stats, journal, report)"
```

---

### Task 2: Core integration + `/ccdev`

**Files:**
- Modify: `Core.lua` (DEFAULTS, createFrame, init, _tick, _handleEvent)
- Modify: `spec/core_spec.lua` (load `Dev.lua`; new tests)

**Interfaces:**
- Consumes: Task 1 `ns.Dev` exactly as produced.
- Produces: `Core.dev` (Dev instance), `Core.devFrame` (hidden frame `CrowdCalmDevFrame`), effective-mode helper used by `_tick`.

- [ ] **Step 1: Write the failing tests in `spec/core_spec.lua`**

Add `stub.loadAddon("Dev.lua", ns)` between `Panel.lua` and `Core.lua` in the load list. New tests:

1. `"force crowd applies and restores the profile without any plates"` — `login()`; `plates(0)`; `ns.Core.dev:SetEnabled(true)`; `ns.Core.dev:SetForceCrowd(true)`; `ns.Core._tick(10)` → `#stub.state.callLog == 5`, `C_CVar.GetCVar("particleDensity") == "25"`; `ns.Core.dev:SetForceCrowd(false)`; `ns.Core._tick(11)` → 10 calls, cvar `"100"`. Also with force off and 0 plates nothing applies.
2. `"slash command registers and persists dev mode"` — `login()`; `_G.SlashCmdList.CROWDCALMDEV("on")` → `_G.CrowdCalmDB.settings.dev.enabled == true`; `("off")` → false; `("bogus")` → printed contains `"usage"`.
3. `"normalizes corrupt dev settings at init"` — login-style setup with `settings = { dev = { enabled = "yes", lastReport = 5, tests = "x" } }`; after `ADDON_LOADED`: `enabled == false`, `lastReport == ""`, `type(tests) == "table"`.
4. `"player path stays silent while dev mode is off"` — `login()`; `plates(16)`; tick 10, 13.1; `#ns.Core.dev:GetJournal() == 0`; `stub.state.framesByName["CrowdCalmDevFrame"]:GetScript("OnUpdate") == nil`.
5. `"dev enabled journals crowd transitions and applies"` — `login()`; `ns.Core.dev:SetEnabled(true)`; `plates(16)`; tick 10, 13.1; journal contains `kind=="mode", to=="crowd"` and `kind=="apply", cvar=="particleDensity", value=="25", baseline=="100"`. `plates(0)`; tick 20, 25.1 → `kind=="restore"` present.
6. `"full auto AB test drives the real switch"` — `login()`; `ns.Core.dev:SetEnabled(true)`; `stub.state.time = 10`; `ns.Core.dev:StartTest("auto", { phaseSeconds = 30, rounds = "AB" })`; drive frames: `local frame = stub.state.framesByName["CrowdCalmDevFrame"]`; `local hook = frame:GetScript("OnUpdate")`; for i=1..20: `stub.state.time = 10 + i*0.025; hook(frame)`; `ns.Core._tick(11)`; `stub.state.time = 41`; `ns.Core._tick(41)` → force false; more frames into phase B; `ns.Core._tick(71.5)` → test idle. Assert: callLog has 5 applies (values crowd) and 5 restores (baselines), last restore `particleDensity=="100"`; `ns.Core.dev.forceCrowd == false`; `_G.CrowdCalmDB.settings.dev.lastReport` contains `"PHASE COMPARISON"`; `#_G.CrowdCalmDB.settings.dev.tests == 1`. (Exact frame counts don't matter; assert `>= 1` frames per group via report containing `"frames /"`.)
7. `"logout mid-test aborts and persists a partial report"` — `login()`; `SetEnabled(true)`; `StartTest("passive")`; `ns.Core._handleEvent("PLAYER_LOGOUT")` → `GetStatus().recording == false`; `settings.dev.lastReport ~= ""`.
8. `"DEV frame hook is installed only while recording"` — after login + enabled: `GetScript("OnUpdate") == nil`; `StartTest("passive")` → not nil; `StopTest("manual")` → nil again.

- [ ] **Step 2: Run the suite to watch the new tests fail**

Run: `luajit spec/run.lua`
Expected: new `Core >` tests FAIL (`ns.Core.dev` nil / no `CrowdCalmDevFrame`); rest green.

- [ ] **Step 3: Implement the Core changes**

- `Core.DEFAULTS()`: add `dev = { enabled = false, lastReport = "", tests = {} }` (fillDefaults already merges tables).
- `createFrame()`: after `Core.frame`, add `Core.devFrame = CreateFrame("Frame", "CrowdCalmDevFrame", UIParent)` (never shown).
- `_tick(now)`: replace `local mode = Core.crowd:Update(now, count)` with `Core.crowd:Update(now, count)` followed by `local mode = effectiveMode()` where the helper (module-local):
  ```lua
  local function effectiveMode()
    if Core.dev and Core.dev.forceCrowd then return "crowd" end
    if Core.crowd then return Core.crowd:GetMode() end
    return "normal"
  end
  ```
  At the end of `_tick` (after `Core._persistState()`): `if Core.dev then Core.dev:OnTick(now) end`.
- `init()`: after `createFrame()` add:
  ```lua
  Core.dev = ns.Dev.new(db.settings.dev, {
    getTime = function() return GetTime() end,
    setFrameHook = function(fn)
      if Core.devFrame then Core.devFrame:SetScript("OnUpdate", fn) end
    end,
    log = function(message) Core._log(message) end,
    getSnapshot = function()
      local state = Core.switch and Core.switch:GetState()
        or { applied = {}, baselines = {}, mode = "normal", pendingReason = nil }
      return {
        mode = effectiveMode(),
        plates = Core.CountPlates(),
        applied = state.applied,
        baselines = state.baselines,
        pendingReason = state.pendingReason,
      }
    end,
  })
  ```
- `_handleEvent(...)`: add guarded pokes — `PLAYER_REGEN_ENABLED`: `if Core.dev then Core.dev:OnTick(GetTime()) end` after persist; `PLAYER_ENTERING_WORLD`: same after existing calls; `PLAYER_LOGOUT`: `if Core.dev then Core.dev:OnLogout(GetTime()) end` after persist; `CVAR_UPDATE`: `if Core.dev then Core.dev:OnCvar(cvar, value) end` after persist.

- [ ] **Step 4: Run the suite to verify green**

Run: `luajit spec/run.lua`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add Core.lua spec/core_spec.lua
git commit -m "feat: core integration for dev mode (force crowd, event hooks)"
```

---

### Task 3: Dev window (`DevWindow.lua`)

**Files:**
- Create: `DevWindow.lua`
- Create: `spec/devwindow_spec.lua`
- Modify: `spec/wow_stub.lua` (widget factories + globals)
- Modify: `spec/run.lua` (add `"devwindow_spec"` before `"dev_spec"`)

**Interfaces:**
- Consumes: `ns.Dev` (Task 1), `ns.Core.dev`/`ns.Core.RebuildSwitch`/`ns.Core._syncStutterHook` (Task 2).
- Produces: `ns.DevWindow.Toggle()`, `Create()`, `Refresh()`; frame `CrowdCalmDevPanel`; widget names: `CrowdCalmDevStatus`, `CrowdCalmDevForceCrowd`, `CrowdCalmDevAllOff`, `CrowdCalmDevAllOn`, `CrowdCalmDevMaster`, `CrowdCalmDevCategory<key>`, `CrowdCalmDevStutter`, `CrowdCalmDevModeAuto|Guided|Passive`, `CrowdCalmDevLen30|60|120`, `CrowdCalmDevRounds`, `CrowdCalmDevStart`, `CrowdCalmDevStop`, `CrowdCalmDevPhase`, `CrowdCalmDevResult`, `CrowdCalmDevCopyReport`, `CrowdCalmDevCopyTest`, `CrowdCalmDevReport`.

- [ ] **Step 1: Extend `spec/wow_stub.lua` (no test yet)**

Add to `widgetMethods` (mirroring `CreateCheckButton`):
```lua
function widgetMethods:CreateButton(name)
  local b = newWidget("Button")
  b.__name = name
  return addChild(b, name)
end

function widgetMethods:CreateEditBox(name)
  local e = newWidget("EditBox")
  e.__name = name
  e.__multiLine = false
  return addChild(e, name)
end

function widgetMethods:HighlightText()
  self.__highlighted = true
  return self
end

function widgetMethods:SetFocus()
  self.__focused = true
  return self
end

function widgetMethods:SetMaxLetters(n)
  self.__maxLetters = n
  return self
end
```
And in the `reset()` state table add `charName = "Testchar"`. In `stub.install()` add:
```lua
_G.UnitName = function()
  return stub.state.charName
end

_G.date = function()
  return "2026-10-18 12:00:00"
end

_G.C_AddOns = {
  GetAddOnMetadata = function(_, field)
    if field == "Version" then
      return stub.state.addonVersion or "0.2.0"
    end
    return nil
  end,
}
```

- [ ] **Step 2: Write the failing spec `spec/devwindow_spec.lua`**

Setup pattern:
```lua
describe("DevWindow", function()
  local ns = stub.newNs()
  stub.loadAddon("Profiles.lua", ns)
  stub.loadAddon("Dev.lua", ns)
  stub.loadAddon("DevWindow.lua", ns)

  local function fakeCore(settings, devOverrides)
    local calls = { rebuild = 0, syncStutter = 0 }
    local dev = {
      enabled = false,
      forceCrowd = false,
      startCalls = {},
      stopCalls = {},
      result = nil,
      report = "REPORT BODY",
      SetForceCrowd = function(self, on) self.forceCrowd = on end,
      StartTest = function(self, mode, opts) self.startCalls[#self.startCalls + 1] = { mode = mode, opts = opts } end,
      StopTest = function(self, reason) self.stopCalls[#self.stopCalls + 1] = reason end,
      GetStatus = function(self)
        return { mode = self.testMode or "idle", phase = self.phase, recording = self.recording == true, forceCrowd = self.forceCrowd, result = self.result }
      end,
      GetLastResult = function(self) return self.result end,
      GetReport = function(self) return self.report end,
    }
    for key, value in pairs(devOverrides or {}) do dev[key] = value end
    ns.Core = {
      sv = { settings = settings },
      dev = dev,
      RebuildSwitch = function() calls.rebuild = calls.rebuild + 1 end,
      _syncStutterHook = function() calls.syncStutter = calls.syncStutter + 1 end,
    }
    return calls
  end
  -- tests
```

Tests:
1. `"Toggle refuses while dev mode is off or Core missing"` — `fakeCore({ enabled = true })`; `ns.DevWindow.Toggle()` → printed contains `"/ccdev on"`, `stub.state.framesByName["CrowdCalmDevPanel"] == nil`; then `ns.Core.dev.enabled = true`; `Toggle()` → frame exists, `IsShown() == true`; `Toggle()` → hidden.
2. `"master and category checkboxes write settings"` — enabled dev; `settings = { enabled = true, categories = { particles = true }, stutter = { enabled = false } }`; `Create()`; click `CrowdCalmDevMaster` → `settings.enabled == false`; click `CrowdCalmDevCategoryparticles` → `settings.categories.particles == false` and `calls.rebuild == 1`; `CrowdCalmDevStutter` click → `settings.stutter.enabled == true`, `calls.syncStutter == 1`.
3. `"All OFF and All ON buttons"` — start `settings.enabled = true, categories = { particles = true, framecap = false }`; click `CrowdCalmDevAllOff` → `enabled == false`; click `CrowdCalmDevAllOn` → `enabled == true`, every category true, `calls.rebuild >= 1`.
4. `"force crowd checkbox drives the dev engine"` — click `CrowdCalmDevForceCrowd` → `ns.Core.dev.forceCrowd == true`; `Refresh()` sets the checkbox checked state from the engine (`SetChecked`/`GetChecked() == true`).
5. `"mode radios are exclusive and defaults are sane"` — after `Create()`, `CrowdCalmDevModeAuto:GetChecked() == true`; click Guided → `Guided` checked, `Auto` unchecked; `CrowdCalmDevLen60:GetText()` contains `60`.
6. `"START and STOP drive the engine with chosen options"` — click `CrowdCalmDevLen30`; `CrowdCalmDevRounds` click (→ ABAB); click `CrowdCalmDevStart` → `dev.startCalls[1].mode == "auto"`, `opts.phaseSeconds == 30`, `opts.rounds == "ABAB"`; click `CrowdCalmDevModePassive`, `Start` → `mode == "passive"`; click `CrowdCalmDevStop` → `dev.stopCalls[1] == "manual"`.
7. `"Copy report fills the edit box and highlights it"` — click `CrowdCalmDevCopyReport` → `stub.state.framesByName["CrowdCalmDevReport"]:GetText() == "REPORT BODY"`, `__highlighted == true`, printed contains `"copied"`.
8. `"Copy last test without a result prints a hint"` — `dev.result = nil`; click `CrowdCalmDevCopyTest` → printed contains `"no test"`; `dev.result = "A ... / B ..."`; click → edit box text contains `"A "`.
9. `"Refresh renders live status"` — `stub.state.fps = 77`; `stub.state.nameplates` etc. not needed; `dev.recording = true, dev.phase = "A", dev.testMode = "auto"`; `ns.DevWindow.Refresh()` → `CrowdCalmDevStatus:GetText()` contains `"77"`; `CrowdCalmDevPhase:GetText()` contains `"A"`.

- [ ] **Step 3: Run the suite to watch it fail**

Run: `luajit spec/run.lua`
Expected: FAIL — `cannot load 'DevWindow.lua'`.

- [ ] **Step 4: Implement `DevWindow.lua`**

Structure mirrors `Panel.lua` (local `frame`, `currentSettings()`, `makeCheckbox`-style helpers are re-implemented locally since Panel's are file-local). Key behaviors:

- `Toggle()`: if `not (ns.Core and ns.Core.dev and ns.Core.dev.enabled)` → `print("CrowdCalm: dev mode is off - use /ccdev on")`, return. Else `Create()`; toggle `IsShown()`; on show call `Refresh()`.
- `Create()`: idempotent; frame `CrowdCalmDevPanel` 360×580, CENTER, DIALOG, movable via drag; builds all locked widget names; module-local UI state `uiMode` ("auto"|"guided"|"passive", default "auto"), `uiLen` (default 60), `uiRounds` (default "AB"); clicking a mode radio sets `uiMode` and calls `Refresh()` (which SetChecked's all three from `uiMode`); length buttons set `uiLen` and `Refresh()` (button text gets `[` `]` markers around the active length); rounds checkbox toggles between `"AB"`/`"ABAB"` label `"ABAB (average)"`.
- Actions (all guard `currentSettings()` and `ns.Core.dev`): master/category/stutter/force-crowd checkboxes, All OFF (`s.enabled=false`), All ON (`s.enabled=true`; every category true; `Core.RebuildSwitch()`), Start (`Core.dev:StartTest(uiMode, { phaseSeconds = uiLen, rounds = uiRounds })` for auto; `StartTest("guided")`/`("passive")` otherwise), Stop (`Core.dev:StopTest("manual")`), Copy report (`local report = Core.dev:GetReport(); edit:SetText(report); edit:HighlightText(); edit:SetFocus(); print("CrowdCalm: report copied - Ctrl+C")`), Copy last test (result or `"CrowdCalm: no test result yet"`).
- `Refresh()`: status text `string.format("%s | plates %d | FPS %d | %.1f MB", mode, count, GetFramerate(), ns.Monitor.GetOwnMB())` reading `ns.Core.crowd:GetMode()` (guarded) or `forceCrowd` → `"crowd (forced)"`; phase text from `Core.dev:GetStatus()` (`"Phase A - 42s left"` when `phaseEndsAt`, else `"Recording - Xs"`, else `"idle"`); result text from `GetLastResult() or "-"`; sync all checkbox states from settings/engine.

- [ ] **Step 5: Run the suite to verify green**

Run: `luajit spec/run.lua`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add DevWindow.lua spec/devwindow_spec.lua spec/wow_stub.lua spec/run.lua
git commit -m "feat: in-game dev window (toggles, tests, report copy)"
```

---

### Task 4: Ship it (TOC, deploy, README)

**Files:**
- Modify: `CrowdCalm.toc`, `deploy.ps1`, `README.md`

**Interfaces:**
- Consumes: everything above.
- Produces: deployable 0.2.0.

- [ ] **Step 1: TOC + deploy list**

- `CrowdCalm.toc`: `## Version: 0.2.0`; add `Dev.lua` and `DevWindow.lua` after `Panel.lua`, before `Core.lua`.
- `deploy.ps1`: add `"Dev.lua"` and `"DevWindow.lua"` to `$runtimeFiles` after `"Panel.lua"`.

- [ ] **Step 2: Verify deploy picks them up**

Create a fake WoW dir (`_retail_` + `Interface`), then:
Run: `./deploy.ps1 -WowRoot <fake> -DryRun`
Expected: line `copy Dev.lua` and `copy DevWindow.lua` present; exit 0.

- [ ] **Step 3: README additions**

Add a `## Developer mode` section after `## Caveats`: enable/disable commands, window contents, the three test modes, force-crowd warning (runtime-only), where data is saved, how to hand the report over ("Copy report → paste"), and what the analyst gets. Extend the manual checklist with the six items from the design doc §11. Keep the player-facing sections untouched.

- [ ] **Step 4: Full suite + commit**

Run: `luajit spec/run.lua`
Expected: all green.

```bash
git add CrowdCalm.toc deploy.ps1 README.md
git commit -m "docs: dev mode readme, deploy list, version 0.2.0"
```

---

## Post-plan (executor notes)

- After Task 4: whole-branch review package + fresh reviewer, re-grade, one fix pass, then push to `origin crowdcalm-v1` (and report). The workspace ledger lives at `.superpowers/sdd/2026-10-18-crowdcalm-dev-mode/`.
- Manual in-game verification (README §11) runs on the user's gaming machine, not here; the deploy path is the user's retail folder.
