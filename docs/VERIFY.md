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
19. **What are GetAddOnMetric's recent/peak units and ranges** (assumed
    milliseconds)? Compare a known-light addon with the clock:
    `/dump C_AddOnProfiler.GetAddOnMetric("Blizzard_FrameXML", "RecentAverageTime")`
20. **Do GetNumAddOns()/GetAddOnInfo(i) enumerate every addon on Forever
    with the same return shape?**
    `/dump GetNumAddOns(), (select(1, GetAddOnInfo(1)))`
21. **What does C_CVar.SetCVar return on success/failure?** The addon trusts
    the read-back, not the return value, but the shape should be known:
    `/dump C_CVar.SetCVar("chatClassColorNames", "1")`

## Sounds (UI/Widgets.lua)

22. **Which sound kits are quiet and available?** The addon uses the
    SOUNDKIT constants via PlaySound with pcall and can be muted in
    Settings; confirm the two cues are not startling.
