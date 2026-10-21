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

- Zero idle `OnUpdate` handlers. All periodic work uses `C_Timer` tickers
  acquired through `Util.AcquireTicker` (one ticker per key, refcounted).
  The one exception: the minimap button installs an `OnUpdate` for the
  duration of a drag (mouse-down to mouse-up) to orbit the button around
  the minimap rim, and removes it on release — no handler runs otherwise.
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
2. **Minimap button (owner request, pre.2; originally declined).** The
   brief kept entry points to the addon compartment and `/ccl`; for
   pre.2 the owner asked for a draggable, clickable minimap button. It is
   a plain Button (no secure/protected handlers), keeps the zero-idle-cost
   rule (`OnUpdate` only while dragging), and can be hidden in Settings.
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
7. **Custom row list has no visible scrollbar.** Widgets.RowList scrolls by
   mouse wheel only (a thin thumb indicator is future work); the client's
   own keyboard focus traversal is left alone.
8. **Pages build into a pre-sized container** passed by MainWindow
   (`def.create(container)`), so create-time `GetWidth()` math is valid —
   this differs from the brief's "lazy create a frame" phrasing but is
   required for the timeline strip and paragraph wrapping to size correctly.
9. **Glyph policy (pre.3): UI strings are Latin-1 plus the em dash.** The
   client font subset draws nothing outside that range — a `→` (U+2192)
   in the pre.2 Results card rendered as a tofu box (owner screenshot).
   G5 in `scripts/check-lua.js` walks the parsed AST, decodes Lua string
   escapes, and fails on any other code point; comments are exempt (they
   never render). Use ASCII arrows (`->`) in copy and reports.
10. **Window strata HIGH (pre.3, owner request: "always on top").** HIGH
    keeps the window above world-layer UI (action bars, minimap,
    coordinates) that overlapped it in pre.2, while staying below
    DIALOG-strata client popups so confirmations and dropdowns still
    win. `Raise()` on show handles repeated open/close; the minimap
    button (MINIMAP strata) intentionally stays above the window.
11. **Recommendation engine (pre.3): same rule for chips and panel.**
    A row is "Worth it" only when gain >= 0.5 FPS, confidence is not
    Low, and the row is neither noisy nor hitched; both the per-card
    chip and the What-to-do panel call the same classifier, so they
    can never disagree. Tested values (from -> to) are stored on each
    row at run time; rows from older saves simply lack them and the UI
    degrades to FPS-only sentences.

12. **Gauge and button art is generated, never rotated (pre.4).** The
    40-segment arc gauge used `SetRotation` on tile textures; the
    minimap bezel stacked 12 rotated segments. Both are now single
    generated textures: `gauge_dim.tga` plus baked 25/60/95% left-fill
    masks (`gauge_q/b/p.tga`) for the gauge, `ring.tga` for the bezel,
    `btn_dark/btn_gold.tga` gradients for buttons. Layers are tinted at
    runtime with palette functions, so colorblind mode swaps still
    apply; the semantic ramp (quiet = gain, busy = gold, packed = cost)
    mirrors the old segment colors.
13. **Zebra stripes painted by RowList, not by each page.** Pooled rows
    carry one BACKGROUND texture and RowList sets its alpha by index
    parity at layout time, so Stutter, Results and Settings inherit the
    look without page code (pages keep owning their content and hover
    states).

14. **Phase model reworked for stability (pre.5, owner spec).** The brief's
   single 3-window A-B-A became a plan-driven pipeline: every phase runs
   [apply/restore] -> 6 s settle -> 4 s warm-up (dropped by
   `Stats.Begin(ignoreSeconds)`) -> measured sample. Quick = A-B-A;
   Thorough = A-B-A-B-A-B-A (4 shared baselines, each test measured
   against the average of its neighbours, median + min..max spread). The
   reliability limit moved from 10% (pairwise) to 8% over every baseline
   pair including entry/exit, surfaced as "Not reliable" with the actual
   percent.
15. **Settings changes rebuild the whole window (pre.5).** Font size and
   colorblind colors are baked at build time; instead of re-skinning every
   widget in place, `UI.ScheduleRebuild()` discards and rebuilds the
   window after 0.15 s (deferred during runs, page/scale/position
   restored). Cost: a visible ~1 frame refresh; benefit: one code path
   that cannot miss a widget.
16. **Sliders commit on release (pre.5).** `Widgets.Slider.onChange` now
   fires on mouse-up (or a 0.35 s keyboard debounce), not on every value
   change -- mid-drag window scaling from the UI-scale slider moved the
   thumb under the cursor and corrupted the final value. Only Settings
   uses sliders, so no live-preview caller regressed.
17. **Caps and movement probes are strictly read-only (pre.5).**
   `maxfps` / `renderFrameRateCap` / `gxVSync` are read via pcall before
   each run and never written; `GetUnitSpeed` / `GetPlayerFacing` are
   probed once at load and degrade to warn-only FPS sampling when absent.
   Verified by inspection: LabRunner contains no `SetCVar` for those keys.
18. **One accent gradient serves both orientations (pre.6).** The tile
   selection accent is a top strip, identical in orientation to the hero
   card accents, so a single horizontal `accent.tga` covers both. A left
   edge strip would have needed a rotated twin (SetTexCoord permutation)
   for no visual gain.
19. **Top-3 rows are page-local, not a widget (pre.6).** The
   label | bar | value row exists only on Overview, so the layout lives
   in Overview.lua; Widgets only gained the sparkline's gradient bars
   and grid lines (also single-consumer, but they replace existing
   widget behavior rather than adding an API).
20. **Overlay countdown reuses the Ring clock (pre.6).** `Widgets.Ring`
    already stores `duration`/`startedAt` for its fallback bar; the
    centered countdown reads those fields at the 1 Hz refresh instead of
    owning a second timer, so the number and the ring can never disagree.
21. **Recommendation thresholds tightened (pre.7, owner ruling).**
    Amends #11: a row is only "Worth it" when the gain is also >= 5% of
    its baseline and larger than the baseline gap (max-min of that test's
    baselines). Below that the chip reads "No clear gain"; a negative
    gain bigger than the gap reads "Slower" (new classifier state, red).
    Chips, the What-to-do panel and the Best medal still call one
    classifier, so they cannot disagree; older saved rows simply lack
    the baseline stats and degrade to the pre.7-less path.
22. **Stutter rule counts episodes, not every long frame (pre.7, owner
    spec).** A tick records only a freeze (frame >= 100 ms), a micro
    burst (3+ frames >= 50 ms in one tick) or a low-FPS streak (2
    consecutive ticks under the floor); isolated 50-99 ms frames are
    noise, not events. The first 5 s after load/zone change are
    suppressed and saved entries without wall-clock time are dropped, so
    counts stay truthful across sessions. The meter sparkline was aligned
    to the same micro-burst rule so the two views never contradict.
23. **Run plan gained a pre-roll, a shuffle and an opt-in big step
    (pre.7, owner spec).** Jobs start after a 15 s pre-warm phase (its
    own ring, counted in the estimate) and run in a shuffled order with
    the combine job pinned last; the optional "Big step" checkbox makes
    every job test its setting at the lowest allowed value (Body Quota
    ~ half the current value) instead of one step down, labeled
    "Big step: A -> B -> A" with the "shows the setting matters" note.
    Values are re-read after every apply (mismatch = "Not testable"),
    after every restore phase (mismatch = row "Not testable" + banner)
    and after the final restore (mismatch = restore-failed banner +
    report warning) instead of trusting SetCVar.
24. **Addons page lists enabled addons only (pre.7, owner request).**
    The brief's cost panel showed every addon; disabled rows cluttered it,
    so the list filters to enabled ones (Blizzard included, marked "not
    queryable") with the hidden count in the sort tooltip, and gained a
    one-click "Disable & Reload" (confirm -> done sound -> `ReloadUI`
    after 1 s, pcall'd with an error fallback). Enable state comes from
    `Compat.IsAddOnEnabled`'s probe chain, which fails open (enabled) so
    an unknown API never empties the list; the real return semantics are
    a VERIFY item.
25. **G4 locale check is a hard failure (pre.7).** The gate previously
    only warned about `L("missing")` literals; it now fails the build and
    also matches `Lfmt("key", ...)` calls (the old regex required `)`
    immediately after the key, so every format call was unchecked). Both
    gaps were proven with RED runs before going green.

## Testing philosophy

Nothing in this repository has run inside WoW yet, by design (the owner
installs the addon personally). Every unverified API assumption is listed
in `docs/VERIFY.md` with a copyable `/dump` line, and every call site uses
feature detection + `pcall` with a visible fallback. The static gates
(G1 parse/TOC/IconTexture, G2 PowerShell parse, G3 media manifest,
G4 locale callability/keys, G5 glyph safety) prove the repo is
well-formed; the in-game behavior proof is
`docs/FIRST-RUN-CHECKLIST.md`.
