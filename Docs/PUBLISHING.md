# Publishing on the ModHub (in-game "Mods" / ModHub browser)

Written 2026-10-30. Source: GIANTS ModHub Guidelines v5.9.1 (the latest public version, linked from
https://farming-simulator.com/modhub-guidelines; written for FS22, still the one GIANTS links). Before uploading,
download the current version from the **Data** section of the upload page: rules such as `descVersion` change
with game patches.

## What publishing gives you

- Mods on the official ModHub can be downloaded **inside FS25** (main menu > Downloadable Content / ModHub) and from
  farming-simulator.com. That is the only way to appear in the in-game mod browser; there is no other channel.
- **PC/Mac only.** Script mods are not allowed on consoles (Sony/Microsoft rule, guideline 8.2). Crop Rotation Plan
  is a script mod, so it will never be on PlayStation/Xbox.
- Free only. Mods behind paywalls (Patreon etc.) are rejected. Other websites may only link to the ModHub page.

## The process

```
You: self-test with TestRunner  ->  Upload (New)  ->  Pending  ->  Data check (GIANTS runs TestRunner)
     ->  In-game test (single player + 30 min multiplayer)  ->  PC release
     A fail at any step sends the mod back to you with the reason.
```

1. **GIANTS account**: register/log in at farming-simulator.com.
2. **TestRunner**: download the public test tool from the GIANTS forum
   (https://forum.giants-software.com/viewtopic.php?t=187502), run it on the **unzipped** mod folder (`Build/`)
   and fix everything it reports.
3. **Upload**: on farming-simulator.com, log in, go to the ModHub's mod upload page. Fill in title, category
   (script mods: "Gameplay"/"Scripts"), the zip, the screenshots and a **submission comment** (anything the
   testers need to know, e.g. how to load the example plan with `crpLoadExample`).
4. **Review**: GIANTS testers go through the stages above. They do not publish a fixed time; plan for
   **weeks**, not days. The better prepared the mod is, the faster it goes.
5. **Updates** later: only for real fixes; smaller updates must wait at least **two weeks** after the last one.
   Upload an update as a new mod with `_update` in the zip name (`FS25_CropRotationPlan_update.zip`), with a
   **changelog in the description**. Never upload an update just to change the version number.

## Checklist for this mod

| Rule (guideline item) | Status | To do |
|---|---|---|
| Zip name starts with `FS25_`, English, no version (5.2) | OK: `FS25_CropRotationPlan.zip` | |
| `descVersion` is the latest for the current game patch (5.4) | Done (v2.3) | 115, from the log of game 1.25.0.0 ("ModDesc Version: 115"). Check again after game patches. |
| Title with capital initials, description in CDATA, version with 4 digits (5.5) | OK | |
| Detailed description, hotkeys explained (5.5, 10.4) | OK | Alt+R and console commands are described. |
| `<multiplayer supported="true"/>` only if MP works (5.5, 7.6) | **Not tested** | Play at least **30 minutes in multiplayer** (host + 1 client, two farms) without errors. |
| **EN and DE texts** for every UI text (8.2) and a DE description that is not a copy of EN (5.1, 7.2) | Done (v2.3) | EN, DE and DA for all texts, title and description; `tests/check_static.py` fails if one is missing. A German speaker should proofread. |
| Mod icon `icon_*.dds`, **256x256, BC1, no mipmaps, GIANTS template background**, in the zip root (5.1) | Done (2026-11-01) | Artwork on the GIANTS template `Docs/ModHub Icon Template FS25/FS25_ModHub_BG512.png`: `Build/icon_CropRotationPlan.dds` 256x256 BC1 without mipmaps, `Docs/modhub/icon_512.png` for the form (upload it again: it changed). |
| No logos, watermarks, links, credits in icon, screenshots, description (5.1) | OK | Only contributors at the end of the description are allowed. |
| At least 3 screenshots, first without text and HUD, English text (5.1) | To do | See `image-task.md` (shots 1, 2, 3). |
| Log file free of errors and warnings (7.1) | Fix to verify (v2.3) | Issue #2: the uninstall now removes the page from every menu list and logs `[CropRotationPlan] Menu tab removed (...)`. Quit a savegame from the menu and check the log. |
| Zip contains only needed files (7.5) | OK | `.lua`, `.xml`, `.dds` and a README (allowed). |
| Custom UI works at 4:3, 16:9, 16:10, 21:9 (8.2) | **Not tested** | `pwsh -File tools\screen-shape.ps1 4:3` (also `16:10`, `21:9`, `32:9`) sets a game window of that shape; `-Restore` puts your setting back. |
| No paywall; link only to the ModHub page (1) | OK | |
| GitHub link in the description (10.4) | Optional | Allowed for script mods only if viewable without login: the repo is private now. Either make it public or leave the link out. |

## Work list before submitting

1. Check that issue #2 is gone (quit a savegame from the menu, read the log).
2. Mod icon on the GIANTS template background.
3. 30 minutes multiplayer test; fix what it finds.
4. Test the UI at 4:3, 16:10 and 21:9 (`tools/screen-shape.ps1`).
5. Proofread the German texts.
6. Check `descVersion` again after the next game patch.
7. Run TestRunner on `Build/` until it is clean. Done 2026-11-01: TestRunner 0.9.23 PASS, 0 errors, 0 warnings (`Docs/testrunner/`). It required: icon 512x512 (not 256), no pcall/xpcall in Lua, every word of every title capitalised.
8. Screenshots (image-task.md, 6 shots).
9. Release on GitHub (`tools/release.ps1`), then upload that zip to the ModHub.
