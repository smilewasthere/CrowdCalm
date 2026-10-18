# CrowdCalm — Design Specification

Status: v1 scope, approved 2026-10-18.
Authority: this document. The implementation plan
(`docs/superpowers/plans/2026-10-18-crowdcalm.md`) argues from this spec;
conflicts inside the plan resolve against this document.

## 1. Purpose

CrowdCalm watches how many player nameplates are near you. When the count
indicates a crowd (city hub, world event), it automatically applies a
curated, crowd-friendly graphics profile after a short sustained-crowd
delay. When the crowd clears, it restores your exact previous settings
after a short sustained-quiet delay. Everything is conservative:
out-of-combat only, a curated cvar set, no texture/resolution/render-scale
changes, and a crash-safe restore model.

## 2. Target client

- Retail World of Warcraft, live patch 12.1.5 → TOC `## Interface: 120105`.
  (12.1.0 = 120100, PTR 120107.) Midnight blocks out-of-date addons from
  loading, so the Interface number is bumped every patch cycle.
- Retail only. The Forever client (16xxx) is out of scope.
- Lua 5.1 dialect (WoW uses 5.1; tests run on LuaJIT 2.1, itself 5.1).

## 3. Feature set (v1)

### 3.1 Crowd detection

- Source: `C_NamePlate.GetNamePlates()`; each plate token tested with
  `UnitIsPlayer` when "count only players" is enabled (default on).
- Hysteresis state machine: enter crowd mode when count ≥ `high` (default
  15) sustained for `enterDelay` (default 3 s); exit when count ≤ `low`
  (default 10) sustained for `exitDelay` (default 5 s). Between the two
  thresholds nothing changes — this prevents flapping at the boundary.
- Evaluated once per second by a single ticker (no per-frame work).
- Friendly nameplates must be enabled by the player for city counting to
  see anything; the addon prints a one-time hint when it has been enabled
  and resting for 30 s with zero player plates detected. Friendly plates
  are forbidden by Blizzard in instances, so the trigger is effectively
  open-world/hub — this is a documented limitation, not a bug.

### 3.2 Profile switching

- Curated categories (order fixed, all optional, defaults in parentheses):
  - `particles` (ON): `particleDensity="25"`, `particleMTDensity="30"`
  - `clutter` (ON): `groundEffectDensity="16"`, `groundEffectDist="70"`
  - `shadows` (ON): `graphicsShadowQuality="1"`
  - `viewdistance` (OFF): `graphicsViewDistance="6"`
  - `framecap` (OFF): `maxFPS="60"`, `maxFPSBk="60"`
  - `spelldensity` (OFF): `spellVisualDensityFilterSetting="1"`
  - `targetfps` (OFF): discovered at runtime (see §6.3)
- Never touched, by construction (guard test enforces the pattern list):
  textures, render scale (`RenderScale`, `DynamicRenderScale`),
  resolution (`gxResolution`), MSAA, `gxApi`, `uiScale`.
- `projectedTextures` is deliberately excluded: it can remove boss
  mechanic visuals (e.g. defile-style ground effects).
- The player's own visuals and NPC visuals are never affected by these
  cvars; spell density only reduces *other party/raid members'* spell
  visuals — the player's own casts and all NPC mechanics remain visible.
- Any cvar missing on the client, read-only, or discoverable-but-absent is
  skipped with a log line; the rest of the profile still applies.

### 3.3 Restore model (crash-safe)

Three layers:

1. **Normal restore** — crowd clears → restore every managed cvar to its
   pre-crowd value (baseline captured on first apply).
2. **Orderly logout** (`PLAYER_LOGOUT`) — restore immediately, mark
   session inactive, persist.
3. **Crash / kill** — `CrowdCalmDB.restore` persists `sessionActive` plus
   `baselines` (pre-crowd values) and `applied` (crowd values). At next
   login, for every managed cvar compare the current value:
   - current == applied → restore baseline (the addon left it engaged);
   - current == baseline → nothing to do;
   - anything else → the user changed it by hand while the addon was
     active or dead; **adopt it as the new baseline**, never overwrite.
   Values for cvars that no longer exist are dropped.
4. **User edits during crowd mode** — observed via `CVAR_UPDATE`; a change
   that is not our own write is adopted as the new baseline.

### 3.4 Optional monitoring (slim)

- Status panel (`/cc`): mode, crowd count, FPS, own addon memory
  (`collectgarbage("count")`), last switch time. 12-sample memory ring.
- Opt-in stutter log: when enabled, a single `OnUpdate` records frame
  deltas above a threshold (default 50 ms) at most once per second, with
  context (zone, mode, seconds since last switch), capped at 100 entries.
- No per-addon CPU profiling and no leak baseline in v1 (deferred, §8).

### 3.5 Configuration

- `/cc` opens the panel: enable toggle, category checkboxes, sliders for
  `high`/`low`/`enterDelay`/`exitDelay`, frame-cap value, stutter toggle.
- Slash commands: `/cc status`, `/cc log`, `/cc memory`, `/cc on|off`.
- `Panel.ValidateSettings` clamps consistent, safe values (low < high,
  delays 0–60 s, thresholds 1–40, frame cap 0–400) and reports corrections.

## 4. Hard constraints

1. **Combat** — Blizzard blocks `SetCVar` for secure cvars in combat
   (many graphics cvars are secure). All writes happen only when not
   `InCombatLockdown()`; otherwise the desired mode is queued and flushed
   on `PLAYER_REGEN_ENABLED`.
2. **Loading screens** — cvar values and addon state are unreliable during
   loading; a 2 s debounce after `PLAYER_ENTERING_WORLD` blocks all writes.
   `PLAYER_LOGOUT` restore ignores the debounce (it must complete before
   exit).
3. **Performance** — one 1 s ticker; no `OnUpdate` except the opt-in
   stutter monitor.
4. **Blizzard rules** — no automation of gameplay; this addon only changes
   client display settings the player could change manually.
5. **No libraries, no external dependencies.** enUS strings inline.

## 5. SavedVariables

```lua
CrowdCalmDB = {
  schemaVersion = 1,
  settings = {
    enabled = true,
    countOnlyPlayers = true,
    high = 15, low = 10, enterDelay = 3, exitDelay = 5,
    categories = { particles = true, clutter = true, shadows = true,
                   viewdistance = false, framecap = false,
                   spelldensity = false, targetfps = false },
    framecapValue = 60,
    stutter = { enabled = false, thresholdMs = 50, minGapMs = 1000,
                maxEntries = 100 },
    hintShown = false,
  },
  restore = {
    sessionActive = false,
    baselines = {},  -- cvar -> pre-crowd value (strings, as GetCVar returns)
    applied   = {},  -- cvar -> crowd value we set
  },
}
```

Migration: unknown `schemaVersion` → reset settings to defaults and clear
`restore` (never guess at a future schema).

## 6. Research facts this design depends on

### 6.1 Spell density (12.x)

- Cvar: `spellVisualDensityFilterSetting`. Values: 1 = Essential,
  2 = Reduced, 4 = Everything (0 is dev-only).
- Only affects *other party/raid players'* spell visuals; effectively
  instanced content.
- Known client issue: the value silently resets to 4 after loading
  screens (acknowledged Aug 2025, still reported Jan 2026). Workaround
  used by the "Spell Density" addon: re-apply on login/zone change. We do
  the same, only while crowd mode has it engaged.

### 6.2 Frame cap / Target FPS

- `maxFPS` / `maxFPSBk` are the reliable frame caps (default 0 = uncapped
  soft cap ~200). Used for the `framecap` category.
- The new "Target FPS" graphics option is NOT a frame limiter: it only
  affects GPU-bound dynamic settings and is unreliable. Its companion
  `DynamicRenderScale` is BETA, causes hitching, and dynamically changes
  render scale — forbidden by §4. The `targetfps` category is offered
  off-by-default with these caveats in the UI.

### 6.3 Runtime cvar validation

- Never guess cvar names. `C_Console.GetAllCommands()` enumerates the
  client's real cvars; `Profiles.Select` receives an environment whose
  `isKnown`/`isSecure`/`isReadOnly` answers come from it (via
  `C_CVar.GetCVarInfo`). The Target-FPS cvar name is NOT yet confirmed
  (to be verified in-game); it is discovered by scanning for an exact
  case-insensitive name match and simply skipped ("not-found") if absent.
- User changes are detected with the `CVAR_UPDATE` event.

### 6.4 Nameplates in Midnight

- Nameplate cvars are character-scoped. Friendly nameplates must be
  enabled manually; the API surface (`C_NamePlate.GetNamePlates`,
  `UnitIsPlayer`) is unchanged for our purposes.

## 7. Module map

| File | Role | Tested by |
|---|---|---|
| `Crowd.lua` | hysteresis state machine (pure) | `spec/crowd_spec.lua` |
| `Profiles.lua` | category definitions + `Select` filter (pure) | `spec/profiles_spec.lua` |
| `Restore.lua` | crash-recovery decision planner (pure) | `spec/restore_spec.lua` |
| `Switch.lua` | apply/restore orchestrator, combat+loading gating | `spec/switch_spec.lua` |
| `Stutter.lua` | stutter log buffer (pure) | `spec/stutter_spec.lua` |
| `Monitor.lua` | memory/FPS sampling (thin) | `spec/monitor_spec.lua` |
| `Panel.lua` | config/status UI + validation (thin) | `spec/panel_spec.lua` |
| `Core.lua` | events, ticker, SavedVariables glue | `spec/core_spec.lua` |

All modules attach to the addon-owned namespace table passed as the
second arg of the file chunk (no `_G` pollution). Pure modules take
injected deps (time, cvar accessors) so they run under the stub.

## 8. Deferred (v2 candidates)

- Per-addon CPU rankings via `C_AddOnProfiler` and memory-leak baseline.
- Raid/dungeon event-aware profiles (Blizzard's built-in `RAID*` /
  `raidGraphics*` profile already covers instances).
- Forever client support (TOC 16001) if persistence semantics confirmed.
- Auto-detect Target-FPS availability with a warning when the client
  renames the cvar.

## 9. Open items (verified at in-game manual testing, Task 9)

- Exact Target-FPS cvar name (discovery path handles absence gracefully).
- Whether spell-density reset after loading still occurs on 12.1.5.
- Taint check (`/console scriptErrors 1`) with all features engaged.
- Crash-recovery behavior after a real Task-Kill mid-crowd.
