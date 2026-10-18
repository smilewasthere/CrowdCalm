# DESIGN — CrowdCalm Lab architecture

How the addon is put together, what each layer may do, and every deviation
from the original brief (section 12 asked for these to be listed, not hidden).

## Layers and load order

The `.toc` loads in this exact order; each file registers itself into the
shared `ns` table (`local ADDON_NAME, ns = ...`):

| Layer | Files | May depend on |
|---|---|---|
| Core | `Core/Init.lua` (first — defines `ns.addInit` / `ns.onLogin`), `Events.lua`, `Locale.lua`, `Util.lua`, `Compat.lua` | nothing below |
| Data | `Data/Palette.lua`, `Data/Settings.lua` | Core |
| Engine | `Stats`, `Meter`, `Context`, `StutterLog`, `CVarGuard`, `LabRunner`, `AddonCost`, `SelfCheck` | Core, Data |
| UI | `Skin`, `Widgets`, `MainWindow`, `Compartment`, `Pages/*` | everything above |

`MainWindow.lua` must load after `Widgets.lua` and before `Pages/*` (pages
call `ns.ui.RegisterPage` at file scope). `Compartment.lua` loads last so
`ns.ui` exists when the slash/compartment globals are wired.

## The `ns` contract

Every file receives the addon namespace table as its second vararg and
assigns exactly one module key (`ns.util`, `ns.meter`, `ns.ui`, …). The only
intentional globals are:

- `CrowdCalmLabDB` (SavedVariables)
- `CrowdCalmLab_OnAddonCompartmentClick` (required by `## AddonCompartmentFunc`)
- `_G.SLASH_CCL1` / `_G.SLASH_CCL2` + `SlashCmdList["CCL"]` (the client's
  documented slash-registration mechanism)

`.luacheckrc` whitelists exactly these.

## Safety design (CVarGuard)

- Every write goes through `Guard.Apply`, which snapshots the current value
  first and refuses to run in combat.
- Read-back verification after every write; a mismatch aborts the job.
- `CVAR_UPDATE` ownership: while a test holds a CVar, an external change to
  that same CVar aborts the test and restores (foreign-change protection).
- Restore paths: finish, cancel, combat start, foreign change, logout
  (`PLAYER_LOGOUT`), and the login-time baseline comparison (offers, never
  overwrites).
- Scope badges come from `GetCVarInfo` flags: "server" for account/character-
  stored CVars, "local" otherwise, "unknown" when flags cannot be interpreted.
  The secure-by-default rule: when the flag bits are ambiguous, treat the
  CVar as server-scoped and refuse to test it.

## Performance budget

- Zero `OnUpdate` handlers. All periodic work uses `C_Timer` tickers
  acquired through `Util.AcquireTicker` (one ticker per key, refcounted).
- The meter runs at 4 Hz only while refcounted (`Acquire`/`Release`:
  window open, a lab test, or the stutter log).
- The stutter log runs a 1 Hz ticker only while enabled.
- Pooled frames for repeated rows (`Util.CreateFramePool`); preallocated
  rings for samples (`Util.NewRing`) and stutter entries (500-slot pool).
- Target: well under 0.3 ms average with the window open (checked live on
  the About page via `SelfCheck`).

## Palette and typography

- All colors live in `Data/Palette.lua`; the colorblind toggle swaps the
  gain/cost pair (`gainColor()` / `costColor()` functions).
- Fonts prefer Blizzard font objects (`GameFontNormal`, `NumberFontNormal*`)
  with a `CreateFont` fallback using `STANDARD_TEXT_FONT`. The font-size
  setting overrides the height per FontString only — it never mutates the
  shared Blizzard font objects.
- 8 px spacing rhythm; 24 px minimum control height; status is never
  conveyed by color alone (every badge carries a word).

## Disclosed deviations from the brief

1. **Custom row list instead of ScrollBox.** ScrollBox's template and
   mixin surface differs between the two target clients; a ~70-line pooled
   wheel-scroll list (Widgets.RowList) is testable by eye and has no
   template drift. (Brief section 7.6 allowed fallbacks; this is the
   fallback path, chosen up front.)
2. **No minimap button.** Entry points are the addon compartment (where
   the client has one) and `/ccl`. A minimap button would add another
   protected-frame interaction surface for zero measurement value.
3. **Letter-tile emblem/icons instead of atlas artwork.** Atlas names and
   their texture coordinates were not verifiable from the repo;
   `scripts/make-textures.py` generates committed TGAs (gold letter tiles),
   so the visual identity does not depend on an unverified atlas.
4. **Added `.gitattributes`** for consistent line endings between the
   Windows and Linux toolchains used in development.
5. **Added `scripts/check-lua.js` + `scripts/fixtures/broken.lua`** as the
   always-available static gate (luaparse), because luacheck is not
   installed on every machine. `.luacheckrc` is kept in sync for people
   who do have luacheck.
6. **UI page title overlay omitted.** The rail highlight and banner carry
   the current-page context; a separate per-page title row was cut to keep
   content area maximal on the 920×600 frame.

## Testing philosophy

Nothing in this repository has run inside WoW yet, by design (the owner
installs the addon personally). Every unverified API assumption is listed
in `docs/VERIFY.md` with a copyable `/dump` line, and every call site uses
feature detection + `pcall` with a visible fallback. The static gates
(G1 parse/TOC/IconTexture, G2 PowerShell parse, G3 media manifest) prove
the repo is well-formed; the in-game behavior proof is
`docs/FIRST-RUN-CHECKLIST.md`.
