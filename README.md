# CrowdCalm

Retail World of Warcraft addon: automatically applies a crowd-friendly
graphics profile when crowds appear near you, and restores your settings
when they clear.

- Design and architecture: `docs/specs/crowdcalm-design.md`
- Implementation plan: `docs/superpowers/plans/2026-10-18-crowdcalm.md`

## How it works

CrowdCalm counts nameplates around your character once per second. When at
least `high` nameplates persist for `enterDelay` seconds, it flips a small,
curated set of graphics cvars to a lighter profile. When the count drops to
`low` or less for `exitDelay` seconds, your original values are restored.

Safety rules baked in:

- Writes never happen during combat or during the 2 s after a loading
  screen; a pending switch is applied the moment combat ends.
- Only cvars listed below are ever touched; missing or read-only cvars are
  skipped and logged.
- Any change you make yourself is treated as the new baseline — the addon
  never overwrites a value you changed while a crowd profile was active.

## Requirements

- Retail client, interface version `120105` (patch 12.1.5).
- **Friendly nameplates must be enabled** (Options > Gameplay > Names >
  "Show Friendly Nameplates"; the keybind for friendly nameplates also
  works). CrowdCalm can only count what the client displays. Friendly
  nameplates are hidden in instances, so the addon effectively stays idle
  inside dungeons and raids, and the friendly-plates hint (below) fires
  after you spend 30 s resting with zero plates.

## Install

Manual: copy this repository into
`<WoW>\retail\_retail_\Interface\AddOns\CrowdCalm` (the repository root is
the addon root; only the `.toc` and its listed `.lua` files are loaded).

Script:

```powershell
./deploy.ps1 -WowRoot "C:\World of Warcraft"     # accepts the parent or _retail_
./deploy.ps1 -WowRoot "C:\World of Warcraft" -DryRun
```

The script copies only the runtime files (never `spec/` or `docs/`).

## Commands

| Command | Effect |
| --- | --- |
| `/cc` | Toggle the settings panel |
| `/cc status` | Print mode, plate count, FPS, own addon memory |
| `/cc memory` | Print own addon memory |
| `/cc log` | Print the stutter log (if enabled) |
| `/cc on` / `/cc off` | Enable / disable the addon immediately |

## Settings

Stored per account in `CrowdCalmDB`. The panel (`/cc`) edits thresholds,
the enable toggle and per-category checkboxes; values are clamped to safe
ranges and corrections are printed to chat.

| Setting | Default | Meaning |
| --- | --- | --- |
| `enabled` | `true` | Master switch |
| `high` / `low` | `15` / `10` | Enter / exit plate counts (hysteresis) |
| `enterDelay` / `exitDelay` | `3` / `5` | Seconds the count must stay past the threshold |
| `categories.particles` | `true` | `particleDensity=25`, `particleMTDensity=30` |
| `categories.clutter` | `true` | `groundEffectDensity=16`, `groundEffectDist=70` |
| `categories.shadows` | `true` | `graphicsShadowQuality=1` |
| `categories.viewdistance` | `false` | `graphicsViewDistance=6` |
| `categories.framecap` | `false` | `maxFPS=60`, `maxFPSBk=60` |
| `categories.spelldensity` | `false` | `spellVisualDensityFilterSetting=1` |
| `categories.targetfps` | `false` | Target FPS cvar, resolved by name at runtime (experimental) |
| `framecapValue` | `60` | Frame cap value stored for the panel slider |
| `stutter.enabled` | `false` | Opt-in stutter logging |
| `stutter.thresholdMs` | `50` | Log frame deltas above this |
| `stutter.minGapMs` | `1000` | At most one log entry per gap |
| `stutter.maxEntries` | `100` | Ring buffer size |

Never touched: textures, render scale (`RenderScale`, `DynamicRenderScale`),
`gxResolution`, MSAA, `gxApi`, `uiScale`.

## Restore and crash recovery

Baselines (your pre-crowd values) and applied values are mirrored into
`CrowdCalmDB.restore` while a crowd profile is active. On login, if a
previous session was still active (crash, disconnect, Task-Kill),
CrowdCalm restores those baselines on the spot:

- value still equals what we applied → your baseline is restored;
- value was hand-edited in between → your edit is kept and becomes the
  new baseline;
- cvar no longer exists → nothing to do.

`PLAYER_LOGOUT` performs an immediate restore, ignoring the loading-screen
debounce.

## Caveats

- **Spell density** only has an effect in instanced content, and the client
  resets it after loading screens; when enabled, CrowdCalm re-applies it
  2 s after `PLAYER_ENTERING_WORLD` while a crowd is still active. If you
  manually set spell density to "4" (Full) while a crowd profile is active,
  CrowdCalm treats that value as the client's own reset (not your edit) and
  still restores your pre-crowd value later; pick 1–3 to override it.
- **Target FPS** is experimental: the cvar is found by name at runtime and
  the category is skipped with a log line when the client does not have it.
- The panel shows stored settings; cvars you change manually in the game
  options will not be reflected in the panel until `/reload`.
- Secure cvars (most graphics settings) cannot be written in combat —
  CrowdCalm queues the switch instead. Expect a one-tick delay after you
  leave combat.

## Development

- Tests: `luajit spec/run.lua` (LuaJIT; the suite is a pure-Lua harness
  with a WoW API stub, no game client needed).
- Layout: modules load in TOC order; each runtime file has a matching
  `spec/*_spec.lua` (see the plan for the task breakdown).
- Deploy for in-game testing: `./deploy.ps1 -WowRoot <path>`.

## Manual in-game verification checklist

Run on the player's machine (requires an actual retail client):

1. `/console scriptErrors 1` and enable friendly nameplates.
2. `/cc` opens the panel; sliders and checkboxes reflect stored settings.
3. Stand in a busy city: plate count climbs; after `high` plates for
   `enterDelay` seconds the profile applies (visible drop in particles /
   shadows).
4. Attack a dummy to start combat while a flip is pending: nothing applies
   until combat ends, then it applies within ~1 s.
5. Leave the crowd: originals are restored after `exitDelay`.
6. `/reload` while the crowd profile is active: settings are restored on
   load and nothing is re-applied mid-loading.
7. Task-Kill WoW (or disconnect) mid-crowd: relaunch restores your
   settings; if you hand-edited a managed cvar meanwhile, your edit wins.
8. With Spell Density enabled: load into an instance while a crowd is
   active; the filter is re-applied 2 s after the loading screen.
9. Enable stutter logging, play a bit, then `/cc log`: entries show
   timestamp, delta and context without errors.
10. Watch the chat frame for Lua errors or `tainted` messages during all
    of the above — there must be none.
