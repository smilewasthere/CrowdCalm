# CrowdCalm Lab

CrowdCalm Lab is an in-game World of Warcraft addon: a measurement laboratory
for crowded places such as capital cities and hubs. It answers three questions
with numbers measured on **your** PC:

1. Which graphics settings give the most FPS in crowds for the least visual
   loss? (A-B-A lab tests, one setting at a time)
2. Which addons cost the most CPU and memory? (read-only reporting)
3. When do stutters happen, and what was going on around them? (zone, crowd
   size, active test)

Version 1 never changes your settings by itself. You press **Run**, the lab
steps a setting down and back up (A-B-A, so a crowd moving through cannot fool
the result), and your original values are always one button away.

Works on:

- Retail Midnight — interface `120105` (and `120107` on the PTR)
- WoW: Forever beta — interface `16001`

## Install

1. Download this repository (Code → Download ZIP) or copy the folder.
2. Copy the **inner** `CrowdCalmLab` folder (the one that contains
   `CrowdCalmLab.toc`) into
   `<World of Warcraft>\_retail_\Interface\AddOns\`.
   Copy the folder itself, not the repository root.
3. Keep the folder name exactly `CrowdCalmLab` — the client only loads a
   folder whose name matches the `.toc` file.
4. Restart the client (or `/reload`), then run `/ccl`.

Forever (beta) users: the same inner folder goes into
`_classic_beta_\Interface\AddOns\` (the folder may change at launch).

Repo tooling (optional, for development):

```powershell
# static gate: needs Node.js + `npm install luaparse` (point CCL_TOOLS at that folder)
node scripts\check-lua.js

# regenerate the committed textures (needs Python + Pillow)
python scripts\make-textures.py

# manual deploy to your own client (you supply the path; nothing is assumed)
.\scripts\deploy.ps1 -WowRoot "C:\World of Warcraft" -DryRun
```

## Screenshots

_Placeholder — screenshots will be added after the first in-game run._

## Safety promise

- Version 1 applies **no** automatic changes. Ever.
- If you later run a lab test, settings are changed only outside combat, only
  one verified value at a time, and they are restored on finish, cancel,
  combat start, logout and reload.
- A "Restore my settings" button is always visible in the footer.
- If a crash or Alt-F4 left a test value behind, the addon detects the
  mismatch at login and offers to restore — it never overwrites silently.
- The addon never reads combat data (names, health, auras, cooldowns) and
  never touches other addons' code.

## Known limits

- The addon is untested in game until `docs/FIRST-RUN-CHECKLIST.md` has been
  run once; `docs/VERIFY.md` lists every assumption that needs checking.
- Friendly nameplates are off by default, so the crowd count may read low
  (and may be capped around 40 players — unverified).
- The profiler cannot query Blizzard addons and does not cover mouse-click
  handlers.
- "Scan memory" is a blocking call and may hitch; it never runs automatically
  and never during combat.
- Instance crowds are not tested: Blizzard keeps a separate raid/battleground
  profile there.

## Project layout

- `CrowdCalmLab/` — the addon itself (this is what you copy into AddOns)
- `docs/` — `VERIFY.md` (in-game checks), `FIRST-RUN-CHECKLIST.md`, `DESIGN.md`
- `scripts/` — `deploy.ps1`, `make-textures.py`, `check-lua.js`

## License

MIT — see [LICENSE](LICENSE).
