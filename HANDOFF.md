# Hand-off: FS25_CropYearWheelPlanner

Status 2026-10-30. Written for the next Claude Code session and for Anders (owner).

## 1. What the mod is

A Farming Simulator 25 script mod that shows a crop rotation plan on screen and lets the player
build the plan in the game. Started for the map Riverbend Springs; must work on any map.

The owner plays on Riverbend Springs with fields grouped as 3-4-5, 6-7, 8, 23-25 (4-year plan)
and 76, 77 (2-year Canola plan). That plan is in `mod/defaultConfig.xml` today; in v2 it becomes
something the player builds in the editor (the default plan must be EMPTY, see 3.8).

Language: the owner writes Danish, the game runs in English. All UI text goes through l10n
with `en` and `da`.

## 2. Current state (v1.3.1 in `mod/`)

| Part | State |
|---|---|
| On-screen plan (full view) | Rendered in game in v1.1 (screenshot `Docs/screenshots/2026-10-30_ingame_hud_v1.1.png`, old left position). v1.3 groups by plan, one line per field group; not yet seen in game. |
| Minimized view (icon) | Built, not yet seen in game. Yellow + count = work this month, green = next month, grey = nothing, red = config error. |
| Alt+R full/minimized | Listed in the F1 help list in game; pressing it not yet reported. |
| Position top/left | Built (top default: x=0.20, topY=0.99). Not yet seen in game. |
| Plan from XML (`modSettings/FS25_CropYearWheelPlanner/cropYearWheelPlanner.xml`) | Built and unit-tested; to be replaced by savegame storage + editor in v2. |
| Own tab in Esc menu | Registered (v1.3.1, Courseplay method) and shows, BUT rows render white with unreadable text, and the tab is at the end instead of above Settings. Screenshot `Docs/screenshots/2026-10-30_ingame_tab_v1.3.1.png`. |
| Multiplayer | Not supported (`<multiplayer supported="false"/>`). |

Nothing in v1.x has been checked with GIANTS TestRunner.

## 2a. v2 status (updated 2026-10-30, local Claude Code session)

Sections 2 and 4 above describe v1.3.1. This section is the current state; where they differ, this one wins.

### Decisions by the owner
- Mod folder is `Build/` (not `mod/`). `Docs/` holds documentation (screenshots, PUBLISHING.md); `Docs/v1.1/` an old v1.1 copy for reference only. Windows ignores case: never add a separate lower-case `docs/`. Zip output goes to `dist/` (git-ignored).
- Multiplayer: by default only the farm manager may edit a farm's plans. One switch per farm ("Farm manager only" / "Everyone on the farm"), which only the farm manager can change (decided 2026-10-30, option A; per-player permissions were rejected as too complex). The Multiplayer settings section shows only in multiplayer, with a "Your rights" status row.
- No import of the old modSettings XML. The start year is gone; each field group has "Plan year now" (set on the Field groups tab).
- Rice: still open, GitHub issue #1.
- Repo: https://github.com/andersdissing/FS25-Mod_CropYearWheelPlanner (private). Releases: tag `v<modDesc version>`, see below.

### What v2 is (versions 2.0.0.0 to 2.2.0.0)
| Part | State |
|---|---|
| Esc tab above Settings, dark rows, header icon, sub-tab backgrounds | Seen in game (v1.3.2 to v2.0, owner's screenshot and test). |
| Settings: Display, Position, key row, Grass in rotation, Who can edit | Base-game option rows from the XML. |
| Plans (list, new/rename/delete, Columns and Year rows views) | Seen in game in v2.0: owner made 3 plans incl. grass leys. |
| Plan editor (year wheel, gaps, crops that fit, sow month, ley + cut interval, follow-ups, Save/Cancel) | As above. |
| Field groups (fields from farmland ownership, plan, plan year now, crops this year) | As above: 3 groups saved. |
| Crops from the game | Worked in game: "25 crops read from the game" on Riverbend. |
| Storage in `<savegame>/cropYearWheelPlanner.xml`, new savegame empty | Worked in game (v2.0 file seen). v2.1 writes version 3 (per farm) and reads v2.0 files as farm 1. |
| On-screen plan from the new data | Built; not reported. |
| Multiplayer (v2.1) and edit permission (v2.2) | Built and tested only in the smoke test (server + clients, manager / non-manager / spectator), NOT in a real MP game yet. |
| Known error | `TabbedMenu.lua:285 'iconFilename'` once when quitting a savegame (also in v1.3.1). Harmless so far. GitHub issue #2. |

### Files (Build/scripts)
- `CropYearWheelPlanner.lua` main: local settings, current farm, on-screen plan, input, load/save hooks, console `cywpLoadExample` (server only) and `cywpReloadCrops`.
- `CropYearWheelPlannerLogic.lua` pure plan rules ported from `Editor_Crop.dc.html`: absolute months (t = 0 is Jan of plan year 1), gaps, sow choices, ley durations and cuts, overlaps, year rows, plan year from (planYear, anchorYear), tasks and group status. Calendar year = game year + 1 in Jan/Feb (game years run Mar to Feb, plans Jan to Dec).
- `CropYearWheelPlannerCrops.lua` crops read like the game's crop calendar: `getFruitTypes()` filtered to `shownOnMap`, `getIsPlantableInPeriod/getIsHarvestableInPeriod(missionInfo.growthMode, period)` in pcall, title and `hudOverlayFilename` from the fill type. Growth time = first plantable period of the window to the first harvestable period after it. Built-in calendar as fallback (non-seasonal growth). Blocked: trees, sugarcane, meadow, catch crops, crops harvested all year, rice (paddy).
- `CropYearWheelPlannerData.lua` data per farm `{ grassInRotation, plans, groups, nextPlanId, nextGroupId }`, savegame XML v3, local settings `modSettings/FS25_CropYearWheelPlanner/settings.xml` (display, position), network stream read/write, edit helpers, example plan.
- `CropYearWheelPlannerSync.lua` multiplayer: `CropYearWheelPlannerSync.request(op)` is the only way the UI changes data. Server/single player applies at once; a client sends `CropYearWheelPlannerEditEvent`. The server takes user and farm from the connection (`userManager:getUserIdByConnection`, `g_farmManager:getFarmByUserId`), checks the edit right (`farm.editPermission`, `g_farmManager:getFarmById(id):isUserFarmManager(userId)`; local player: `g_currentMission.playerUserId`; multiplayer: `missionDynamicInfo.isMultiplayer`), validates (spectator, plan limits and overlaps, field owned by the farm), saves and broadcasts `CropYearWheelPlannerStateEvent` for that farm. Rejected edit: warning in the log, sender gets the state back. Joining players get all farms via `FSBaseMission.sendInitialClientState`.
- `CropYearWheelPlannerUI.lua` small immediate-mode toolkit (rects, text, buttons, steppers, crop icons, tooltips, clickable boxes).
- `CropYearWheelPlannerPages.lua` the Plans, plan editor and Field groups pages.
- `translations/l10n_en.xml`, `_de.xml`, `_da.xml` all UI texts (modDesc `<l10n filenamePrefix="translations/l10n"/>`, FS25 format `<l10n><texts><text name text/>`); title and description stay in modDesc. EN + DE are ModHub requirements; the German was written by Claude and needs a native proofread.
- `CropYearWheelPlannerFrame.lua` + `gui/CropYearWheelPlannerFrame.xml` the tab. Plans and Field groups containers are empty in the XML; the frame's `draw` draws the pages in the container's area and `mouseEvent` matches clicks against the boxes drawn.

### Verified facts and pitfalls learned in v1.3.2 to v2.1
- Settings rows (`fs25_multiTextOptionContainer`) are white by default; colour them with `InGameMenuSettingsFrame.COLOR_ALTERNATING[isEven]`, restarting after each `name="sectionHeader"` (as AutoDrive and AdvancedDamageSystem do). This fixed the white rows.
- Page position: move the frame before `g_inGameMenu.pageSettings` in `pagingElement.elements`, `pagingElement.pages` and `pageFrames`, then `rebuildTabList()`.
- Sub-tab buttons grow with their text but their `background` ThreePartBitmap does not: `background:setSize(tab.size[1], tab.size[2])` after `setText`.
- `fs25_menuHeaderIcon` points at an atlas slice; with your own file call `setImageUVs(nil, unpack(GuiUtils.getUVs({0,0,w,h},{w,h})))` or it renders as a solid block.
- `TextInputDialog.show(callback, target, default, title, prompt, maxChars, okText)`: always pass a target, otherwise the game calls `callback(text, clickOk)` without it.
- Custom pages are drawn in Lua (not cloned base-game elements, unlike 3.1) to avoid guessing GUI profile names. Mouse only; no gamepad/keyboard navigation on those pages yet.
- The game's GUI XML and icon atlas are inside `dataS.gar`; slice ids for check/cross icons were not found.
- Owner's documents folder is redirected to OneDrive: `[Environment]::GetFolderPath('MyDocuments')`, not `%USERPROFILE%\Documents`. FS25 is installed under Steam (app id 2300320).

### Testing and tools
- `tests/check_static.py` XML, Lua 5.1 syntax (no goto, //, table.unpack), l10n keys, en/da placeholders.
- `tests/test_logic.py` plan rules in a real Lua runtime (`pip install lupa`).
- `tests/smoke_test.py` the whole mod against a stubbed FS25: single-player play-through, savegame round trip, v2.0 file migration, 3000 random clicks; then multiplayer with one server and two clients in separate Lua runtimes, events written and read through a stream, bad edits rejected, 1500 random client clicks. Catches nil errors and wrong `string.format` arguments (real l10n texts), not layout problems.
- `tools/deploy.ps1` builds the zip, kills FS25, keeps the last `log.txt` in `dist/logs/`, copies to the mods folder, starts the game via Steam (`-NoStart` to skip).
- `tools/release.ps1 <version>` sets `<version>` in modDesc, tags `v<version>`, pushes; `.github/workflows/release.yml` fails if tag and modDesc differ, runs the checks and tests, publishes the release with `FS25_CropYearWheelPlanner.zip` (file name never carries the version: the game takes the mod name from it).

### Next steps
1. Test v2.1 in game: single player (plans from v2.0 must still be there as farm 1), then a real multiplayer session (host + one client, two farms).
2. Issue #2 (quit error): try keeping the page installed on `deleteMap` like AdvancedDamageSystem.
3. Gamepad/keyboard navigation on the custom pages.
4. Rice / paddy (issue #1).
5. TestRunner, German texts, screenshots if it goes to ModHub.

## 3. Target v2.0 (agreed with the owner through the mockups)

Mockups: `docs/mockups/*.dc.html` and the live canvas
https://claude.ai/artifact/SYuc3GY6Ye25LLeRJUDdUX (interactive; the logic in the
`<script>` blocks is the reference for the editor rules).

### 3.1 Menu tab
- Own tab in the Esc menu, placed directly ABOVE the base game Settings tab (not last).
- Header "Crop Year Wheel Planner" and three sub-tabs: Settings, Plans, Field groups.
- Look and feel must be the base game's. Build rows by cloning base-game elements (see 5.3), not from hand-written profiles.

### 3.2 Settings sub-tab (mockup 1)
- Display: Full / Minimized / Hidden.
- Position: Top / Left.
- Show/minimize key: info row "Alt + R (change in Settings › Controls)".
- Crops › Grass in rotation: On / Off (default On).
- Multiplayer › Who can edit the plan: "Farm manager only" (OPEN QUESTION, see 7).
- NO global start year. It was removed as redundant (see 3.4).

### 3.3 Plans sub-tab (mockup 2)
- List of plans (+ New plan), name, years in cycle.
- Two views of a plan: Columns (one column per year, crop cards) and Year rows (one row per year, months Jan to Dec, a bar per crop from sowing to harvest, like the owner's PowerPoint).
- Click a crop opens the plan editor.

### 3.4 Field groups sub-tab (mockup 3)
- One row per group: fields (chips, + add), plan, "Plan year now", and the crops this game year.
- "Plan year now" replaces the old start year. Store it as (planYear, gameYear set) and derive the plan year for any game year; it moves on by itself on `MessageType.YEAR_CHANGED`.
- "Your fields" panel lists the fields the farm OWNS, read from the game (farmland ownership), grey when not in a group.

### 3.5 Plan editor (mockup 4, the most important screen)
- Plan name, Years in cycle stepper (a year can only be removed if nothing is sown in it).
- Year wheel: one row per year, months Jan to Dec, bars from sowing to harvest, continuing into the next row across new year. Bars that share a month (harvest then sowing) go in separate lanes.
- Dashed gaps = free months. Click a gap: side panel "Add seed":
  - only crops that can GROW in that gap are buttons; the others are greyed icons with the reason on hover;
  - the player chooses only the SOW month; harvest = sow + growth time (computed, never typed);
  - sow months offered = months in the crop's sowing window where it is harvested before the next crop is sown;
  - harvest month may equal the next crop's sowing month, and sowing may equal the previous crop's harvest month;
  - under the result: icons of the crops that can be sown in the harvest month (follow-up crops);
  - button "Add seed to plan".
- Click a bar: details and "Remove seed from plan".
- Footer: Cancel and "Save plan". Nothing is stored before Save; in multiplayer Save sends the plan to everyone.

### 3.6 Crops
- Read from the game, not hard-coded: `g_fruitTypeManager:getFruitTypes()` gives map + DLC + mod crops actually loaded.
- Per fruit type: `allowsSeeding`, `regrows`, `getIsPlantableInPeriod(growthMode, period)`, `getIsHarvestableInPeriod(growthMode, period)`. Growth time = first harvestable period after a plantable period (period 1 = March).
- Icon: the game's own icon via the fruit's fill type (`g_fruitTypeManager:getFillTypeByFruitTypeIndex(i)`, then its HUD overlay filename). The mockup uses drawn placeholders only.
- Excluded from rotation: trees and orchards (Poplar, Grapes, Olives), crops that regrow by themselves (Sugarcane).
- Rice / Long Grain Rice need a paddy field. Find how the game marks this (not found yet in LUADOC).
- Future option (owner liked it, not required now): filter by "crops my machines can sow and harvest", from the farm's vehicles' sowing machines and cutters.

### 3.7 Grass (important to the owner)
- Allowed in rotation when the setting is On.
- Placed as a ley: player picks how long it stays (3 or 6 months, 1, 2 or 3 years, only what fits the gap).
- Cut interval, two buttons: "Ready to harvest" (every 2 growing months) and "Fully grown" (every 3). Show about how many cuts, counting growing months only (no growth Nov to Feb).
- Background: in FS22 waiting for the 3rd stage gave +50 %. Players report that FS25 gives the same yield at 2 and 3 months (possibly a bug). Keep both options.

### 3.8 Storage
- In the SAVEGAME (per savegame), not in modSettings. The owner must never copy an XML file by hand.
- New savegame = empty plan, no field groups. The Riverbend plan in today's `defaultConfig.xml` is only an example/test fixture.
- Optional: one-time import of an existing `modSettings/.../cropYearWheelPlanner.xml` (v1.1 to v1.3 users).

### 3.9 Multiplayer
- Server is authoritative: plans, field groups and settings that matter to all (grass on/off) live on the server and are saved with the savegame.
- Clients send edit requests as events; the server validates (permission + plan rules) and broadcasts.
- New clients get the full state on join (`writeStream` / `readStream` on join).
- Display and position are per player (local), not synced.

### 3.10 On-screen plan
- Keep full / minimized / hidden, Alt+R, top/left.
- Full view groups by plan, one line per field group: plan year, crops this year, "Now:" (yellow) or "Next:".
- Grass shows as a ley with its cut interval.

## 4. Repo map

```
mod/                    The mod as it ships (zip the contents, not the folder)
  modDesc.xml           descVersion 105, l10n inline (en, da), action CYWP_TOGGLE_SIZE (Alt+R)
  scripts/CropYearWheelPlanner.lua        main: settings, HUD drawing, input, loadMap/deleteMap
  scripts/CropYearWheelPlannerLogic.lua   pure functions: period/month, cycle year, field status
  scripts/CropYearWheelPlannerConfig.lua  XML plan read/compile/validate (v1.x storage)
  scripts/CropYearWheelPlannerFrame.lua   Esc menu tab (v1.3.1)
  gui/CropYearWheelPlannerFrame.xml       tab layout (renders badly, replace)
  defaultConfig.xml     the owner's Riverbend plan, used as test fixture
tests/
  check_static.py       XML, Lua block balance, l10n keys
  check_config.py       Python mirror of the config compiler, checks defaultConfig.xml gives the original plan
tools/build.sh          runs the checks and builds dist/FS25_CropYearWheelPlanner.zip
docs/mockups/           the agreed UI mockups (.dc.html, open in the canvas link above)
Docs/screenshots/       in-game screenshots and the log of the v1.3.0 menu freeze
```

## 5. Verified facts and pitfalls

### 5.1 Engine and modDesc
- FS25 accepts modDesc `descVersion` 90 to 111 (we use 105). Below 90 the mod silently does not load.
- Lua 5.1: no `goto`, no `os.*` (use `g_currentMission.time`, `environment.currentYear`, `currentPeriod`). Period 1 = March.
- `MessageType.YEAR_CHANGED` and `PERIOD_CHANGED` exist (period = month, not season).
- Inputs: `PlayerInputComponent.registerGlobalPlayerActionEvents` appended; it is called for on-foot and vehicle contexts.
- Text/overlay: `renderText`, `setTextColor`, `setTextBold`, `setTextAlignment(RenderText.ALIGN_*)`, `drawFilledRect`, `getTextWidth`, `Overlay.new/setPosition/setDimension/setColor/render/delete`.

### 5.2 Menu tab
- `TabbedMenu:addPage` registers the frame's ROOT element as the page; the menu then cannot find the frame. Result (v1.3.0): `PagingElement.lua:249 'disabled'`, `TabbedMenu.lua:285 'iconFilename'`, `SmoothListElement.lua:873` every frame, menu frozen. See `Docs/screenshots/2026-10-30_log_v1.3.0_menu_freeze.txt`.
- Working method (v1.3.1, from Courseplay `CpGuiUtil.fixInGameMenuPage`): `menu.pagingElement:addElement(frame)`, `updateAbsolutePosition`, `updatePageMapping`, `menu:registerPage(frame, position)`, `menu:addPageTab(frame, file, GuiUtils.getUVs({x,y,w,h},{texW,texH}))`. Courseplay also reorders `pagingElement.elements`, `pagingElement.pages` and `pageFrames` to put the page at a given position: needed for "above Settings" (find the index of `g_inGameMenu.pageSettings`).
- `GuiUtils.getUVs` defaults to a 1024x1024 texture; pass the real size.
- Clean up on `deleteMap`: `menu:unregisterPage(Class)`, `pagingElement:removeElement(frame)`, `updatePageMapping`, `frame:delete()`, `g_gui.frames[name] = nil`.
- Tooltip `Text` inside a `MultiTextOption` needs `name="tooltip"` or the log warns.
- v1.3.1 rows are white with invisible text: the hand-written profile combination in `gui/CropYearWheelPlannerFrame.xml` does not get the base game's settings styling. The v1.2 approach (clone `InGameMenuSettingsFrame.multiTimeScale.parent`, and the section header element) showed up in the General settings page in game (the owner found it); how it looked was not reported. Clone base-game elements into the tab, or copy the base game's settings frame structure (Courseplay's `GlobalSettingsFrame.xml` is a working FS25 reference).

### 5.3 Reference code
- LUADOC (community): https://github.com/umbraprior/FS25-Community-LUADOC
- Base game Lua (partial): https://github.com/Dukefarming/FS25-lua-scripting, https://github.com/MyGameSteamOfficial/fs25-lua-api
- Patterns and verified facts: https://github.com/TheCodingDad-TisonK/fs25-claude-skill
- Courseplay FS25 (menu pages, settings frames): https://github.com/Courseplay/Courseplay_FS25
- Settings injection examples: FS25_OuttaMyWay (`scripts/gui/ConfigurationSettingsExtension.lua`), FS25_CabCinematic

### 5.4 Testing
- No FS25 and no Lua interpreter in the cloud sandbox. Logic is tested through Python mirrors (`tests/`). Compiling Lua from source was blocked there.
- In game: copy `dist/FS25_CropYearWheelPlanner.zip` to `Documents\My Games\FarmingSimulator2025\mods`. After a session, `Documents\My Games\FarmingSimulator2025\log.txt`; search `CropYearWheelPlanner` and `Error`. Copy the log right after closing the game (a new start overwrites it).
- Before ModHub: GIANTS TestRunner on the unzipped mod folder.

## 6. Suggested order of work

1. Fix the tab: base-game look, position above Settings, sub-tabs (Settings, Plans, Field groups). Test in game early: GUI is the riskiest part.
2. Data model in the savegame (plans with seeds as absolute sow month + crop + grass duration/cut; field groups with fields, plan, plan year anchor) + empty default. Unit-test the plan rules outside the game (port the editor logic from `docs/mockups/Editor_Crop.dc.html`).
3. Crops from the game (fruit types, growth time, icons).
4. Plan editor and field group editor.
5. On-screen plan reading the new model.
6. Multiplayer events and permission.
7. TestRunner, English/German texts and screenshots if it goes to ModHub (see ModHub guidelines; scripts mean PC only).

## 7. Open questions for the owner
- Multiplayer: who may edit the plan, only the farm manager or everyone on the farm?
- Rice: show as "needs paddy" or hide on maps without paddies?
- Import of the existing modSettings XML into the savegame: wanted?
- Coffee and Bananas (Beans & Alpacas DLC) have no calendar on the wiki; handled automatically if the growth data is read from the game.