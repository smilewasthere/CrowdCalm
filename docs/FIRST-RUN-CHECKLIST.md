# FIRST-RUN-CHECKLIST — your first ten minutes with CrowdCalm Lab

Plain language, in order. Nothing here changes your settings except step 8,
and step 8 always restores them.

1. **Install.** Copy the inner `CrowdCalmLab` folder into
   `<World of Warcraft>\_retail_\Interface\AddOns\` (or use
   `scripts\deploy.ps1 -WowRoot "..."`). Restart the client.
2. **Load check.** Type `/ccl`. The window should open. If you see a red
   error on load, note it and check `docs/VERIFY.md`.
3. **Client chip.** Look at the top-right of the window: it should show
   "Midnight x.x.x" or "Forever x.x.x". If it shows "WoW ?" the interface
   number was not found — see VERIFY item 1.
4. **Overview numbers.** The three hero cards should show live FPS and
   frame-time numbers within a few seconds. If they stay at "—", the meter
   ticker did not start — note it.
5. **Stand in a crowd.** Go to a capital city, enable friendly nameplates
   (nameplate options), and watch the crowd card move from Quiet toward
   Busy/Packed. Hover the "Why?" button to see the individual signals.
6. **Turn on the stutter log.** Open the Stutter page and tick "Log
   stutters". Play for a few minutes; the timeline should fill if you see
   any long frames.
7. **Addons page.** Open Addons and press "Refresh CPU". Rows should
   populate with millisecond numbers. Try "Scan memory (may hitch)" once,
   outside combat.
8. **CVarGuard restore test (the safety drill).** Open the Lab page,
   tick exactly one safe setting (View Distance is a good choice), press
   Run Lab, and let the whole A-B-A cycle finish. Then press
   **Restore my settings** in the footer — it should say "restored" or
   "nothing to restore" (both are correct outcomes; the point is that the
   button works and no error appears).
9. **Crash-recovery drill (optional but recommended).** Note your current
   View Distance value. Change it by hand in the game's graphics options.
   `/reload`. If the addon detects a mismatch against your baseline it
   offers a restore prompt (VERIFY item 25 covers the popup shape).
10. **Self-check.** Open the About page. Under "This addon's own cost",
    the CPU line should read well under 0.30 ms average with the window
    open. If it reads much higher, note the number and report it.
11. **Log results.** Anything surprising from steps 1–10 — especially
    VERIFY items — write into `docs/VERIFY.md` or the GitHub issue of
    your choice.

When all eleven steps pass, the addon is considered field-tested on that
client. Repeat steps 2–4 and 7 on the second client (Forever or PTR).
