# VERIFY — assumptions that need one in-game check

Every line here is something the addon treats defensively (feature detection,
pcall, fallback) but has **not** been confirmed in game, because nothing in
this repository has run inside WoW yet. Run each `/dump` in the chat box and
note the result in this file (or tell the addon author).

## Client and loading

1. **Where does GetBuildInfo() return the interface number?**
   Compat.lua prefers the 4th return and falls back to scanning.
   `/dump GetBuildInfo()`
2. **Is the addon namespace table really shared between every file of one
   addon?** (Core/Init.lua sets `ns.version`, other files read it.)
   `/dump ns.version` — after loading, this should print `1.0.0`, not nil.
3. **Does PLAYER_LOGOUT fire before a reload?** (Brief section 4.3 requires
   this for the crash-recovery baseline.) `/reload` after arming the log, and
   check whether the SavedVariables file changed.
4. **Do GetZoneText(), GetSubZoneText(), IsResting(), GetNumGroupMembers(),
   GetInstanceInfo() exist on WoW: Forever (16001) with the same shapes?**
   `/dump GetZoneText(), GetSubZoneText(), IsResting(), GetNumGroupMembers(), (select(2, GetInstanceInfo()))`

## Profiler (Engine/Meter.lua, Engine/StutterLog.lua)

5. **Does one profiler tick equal one frame?** The addon assumes
   GetApplicationMetric deltas accumulate per rendered frame.
   Run `/console gxframerate` tests or compare a 10 s window:
   `/dump C_AddOnProfiler.GetApplicationMetric("CountTimeOver50Ms")`
   (run it twice a few seconds apart; the rise should roughly match visible
   long frames.)
6. **Do CountTimeOver* counters reset on /reload?** (The addon skips negative
   deltas, so a reset is safe, but the behavior should be known.)
   `/dump C_AddOnProfiler.GetApplicationMetric("CountTimeOver100Ms")` before
   and after a `/reload`.
7. **Are GetApplicationMetric / GetAddOnMetric / GetOverallMetric present on
   both clients?** The addon logs `profiler=yes/no` at login — check the chat
   line after `/ccl` load on each client.

## Nameplates and crowd context (Engine/Context.lua)

8. **Does C_NamePlate.GetNamePlates() count anything useful in a capital
   city with friendly nameplates enabled?** Stand in Stormwind/Ogrimmar with
   "Show Friendly Nameplates" on and run:
   `/dump #C_NamePlate.GetNamePlates()`
   Also note the highest count you ever see (a historical cap of ~40 is
   unverified).
9. **Are friendly nameplates protected inside instances?** The addon already
   treats in-instance counts as unreliable; confirm the count reads 0 or
   frozen inside a dungeon.

## CVars (Engine/CVarGuard.lua, Data/Settings.lua)

10. **Which candidate CVars are secure, which hitch, which need a graphics
    restart, and what are their valid ranges on each client?**
    For each candidate (view distance, environment detail, ground clutter,
    shadow quality, liquid detail, particle density, SSAO, depth effects,
    compute effects, outline mode, spell density, bodyQuota,
    projectedTextures, graphicsTextureResolution):
    `/dump C_CVar.GetCVarInfo("graphicsShadowQuality")`
    Record: value, defaultValue, flags (isSecure), and the documented range
    from the game's own options UI (the slider positions).
11. **What do Spell Density values mean?** Changelog says 0 to 5 with 5 =
    Everything, but the UI shows three choices.
    `/dump C_CVar.GetCVar("graphicsSpellDensity")` while toggling the option.
12. **Is the raid/battleground twin CVar set separate as documented**
    (`RAIDgraphics...` names on the wiki)? The addon refuses to test inside
    instances, so this is informational only.

## Templates, atlases, frames (UI/Skin.lua, UI/Widgets.lua)

13. **Which Blizzard templates exist on each client?**
    `/dump CreateFrame("Button", nil, nil, "UIPanelButtonTemplate")`
    `/dump CreateFrame("CheckButton", nil, nil, "UICheckButtonTemplate")`
    `/dump CreateFrame("Slider", nil, nil, "OptionsSliderTemplate")`
    `/dump CreateFrame("Frame", nil, nil, "UIDropDownMenuTemplate")`
    (Each should return a frame userdata, not nil/error.)
14. **Does SetTextureSliceMargins exist on both clients?**
    `/dump CreateFrame("Frame"):SetTextureSliceMargins ~= nil` — the addon
    feature-detects this and falls back to plain textures.
15. **Does the cooldown swipe texture exist for the progress ring?**
    The addon falls back to a linear bar automatically; confirm which path
    is used (check the chat debug log).

## Addon cost (Engine/AddonCost.lua)

16. **Does C_AddOns.DisableAddOn exist on both clients?** The "Disable on
    next reload" row stays hidden unless this probe passes.
    `/dump C_AddOns and C_AddOns.DisableAddOn ~= nil`
17. **Which memory API shape is present** (namespaced C_AddOns.* or the old
    globals)? The addon probes both:
    `/dump C_AddOns and C_AddOns.GetAddOnMemoryUsage ~= nil, GetAddOnMemoryUsage ~= nil`
18. **What are GetAddOnMetric's recent/peak units and ranges** (assumed
    milliseconds)? Compare a known-light addon with the clock:
    `/dump C_AddOnProfiler.GetAddOnMetric("Blizzard_FrameXML", "RecentAverageTime")`
19. **Do GetNumAddOns()/GetAddOnInfo(i) enumerate every addon on Forever
    with the same return shape?**
    `/dump GetNumAddOns(), (select(1, GetAddOnInfo(1)))`
20. **What does C_CVar.SetCVar return on success/failure?** The addon trusts
    the read-back, not the return value, but the shape should be known:
    `/dump C_CVar.SetCVar("chatClassColorNames", "1")`

## Window, input, and misc UI (UI/MainWindow.lua, UI/Widgets.lua, UI/Compartment.lua)

21. **Which sound kits are quiet and available?** The addon uses the
    SOUNDKIT constants via PlaySound with pcall and can be muted in
    Settings; confirm the two cues are not startling.
22. **Does OnKeyDown deliver digits 1–7 while the window has keyboard
    enabled, and does ESC still close it via UISpecialFrames?**
    Open the window, press `3` (should switch to Results) and `Esc`
    (should hide the window without typing into chat).
23. **Does the addon compartment callback fire with the expected
    signature?** Click the compartment icon; the window should toggle.
    `/dump CrowdCalmLab_OnAddonCompartmentClick ~= nil`
24. **Does SetGradient exist on Texture objects on both clients, and in
    which argument shape** (color-table or numeric)? The addon applies the
    gradient to a BACKGROUND texture (not the frame) and pcalls both
    shapes; visually confirm the header gradient is not a flat block.
25. **Does StaticPopupDialogs accept the "%s" text pattern with a long
    multi-line string** (the restore prompt lists up to six settings)?
    Trigger it by changing a graphics setting manually after a clean
    logout baseline, then relogging.
26. **Does GetFramerate() exist on Forever with the same units (FPS)?**
    `/dump GetFramerate()`

27. **Does the minimap button show, toggle, drag, and persist?** At login
    a 32px CrowdCalm Lab logo button should sit on the minimap ring
    (top-right by default). Left-click toggles the window; dragging
    orbits it and the angle survives `/reload`; Settings -> "Show
    minimap button" hides and shows it immediately.
    `/dump CrowdCalmLabMinimapButton ~= nil`

## pre.3 owner-feedback items

28. **Do the header and footer of the window drag it?** Grab the empty
    area of the title bar (left of the chip) and of the footer (left of
    the Restore button) and move the mouse; the window should follow,
    the position should survive `/reload`, and hovering should show the
    "Drag here..." tooltip.
29. **Does the window now sit above game UI?** With action bars /
    minimap / coordinates visible, open the window over them: the bars
    must draw *under* the window. Also open and close it a few times —
    it should come back on top each time (`Raise` on show).
30. **Does the Lab running cover block the page?** Start a run: the tile
    grid must disappear behind a near-opaque cover immediately (not
    after a second), clicks on the covered area must do nothing, and
    Cancel (wide, bottom-center) must hide the cover instantly. The
    "Lab running" banner at the top must remain visible above the cover.
31. **Do Quick / Thorough / Run Lab no longer overlap?** On the Lab page
    the four controls form one row at the bottom-right; none of their
    borders may intersect. Combine checkbox sits above them, left.
32. **Does Results explain what to change?** After a run, the top panel
    must name the best change with its tested values ("set X to Y (it
    is Z now)"); each card must show a colored chip (Worth it / No gain /
    Re-test / Can't test / Hitch), a "Change 4 to 3 ..." line, and a
    Confidence tooltip explaining Low / Medium / High. Copy report must
    start with `RECOMMEND:` lines. Rows from pre.3-era runs simply omit
    the change line (older saves have no stored values).
33. **Does the Addons page fill itself?** Open it fresh (not in combat):
    the list should populate within a second without clicking anything,
    and the top-right label should read "N addons ... sorted by CPU".
    If opened during combat, it must fill itself automatically when
    combat ends. The "No addons found." icon must sit in the middle of
    the page, not over the caveat text.

## pre.4 visual-refresh items

34. **Does the crowd gauge read as a clean semicircle?** On Overview,
    the "Crowd right now" card must show a smooth arc band (no visible
    square tile segments), with a Quiet label to the left of the dome,
    a Packed label to the right, and the zone line above the band --
    never on it. The fill must be green (Quiet), gold (Busy) or orange
    (Packed); with colorblind mode on it must swap to that palette.
35. **Do buttons show gradient faces and outlines?** Every button in
    the window now has a generated dark gradient face and a 1px
    outline; Run Lab / Start / Restore wear the gold face with a dark
    label and keep the hover glow.
36. **Is Quick / Thorough a segmented control?** The active mode wears
    the gold face immediately on click (no need to wait a tick), the
    inactive one stays dark, and the choice survives `/reload`.
37. **Are the Addons sort headers ghost style?** The three column
    headers are text-only (no button face) and the active sort column
    is gold; clicking another header moves the gold.
38. **Does the minimap button look refreshed?** The logo is a smaller
    uncropped square centered on the disc, the bezel is one thin ring
    (no 12 visible blocks), and after changing UI scale or reload the
    button still sits on the minimap rim (it re-anchors on resize).
39. **Do lists show zebra stripes?** Stutter, Results and Settings row
    lists must alternate subtle darker/even rows.
