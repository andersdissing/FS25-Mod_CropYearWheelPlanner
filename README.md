# Crop Rotation Plan (FS25_CropRotationPlan)

A Farming Simulator 25 mod that lets you build crop rotation plans **inside the game** and shows on screen,
every month, what to sow and harvest on which fields.

<!-- screenshot: Docs/screenshots/02_plan_on_screen.png -->

- Build plans year by year on a **year wheel** (January to December).
- Only crops that can actually **grow in a free gap** are offered; you pick the sow month and the harvest month follows from the crop's growth time.
- **Grass as a ley**: choose how long it stays (3 months to 3 years) and how often it is cut.
- **Field groups**: put your own fields into groups, pick a plan and where the group is in the plan this year. It moves on by itself every year.
- Crops are **read from the game**: base game, DLC and mod crops on the map you play.
- **Multiplayer**: every farm has its own plans; the farm manager decides who may edit them.
- Everything is stored in the **savegame**. A new savegame starts empty.
- English, German, French and Danish.

---

## Contents

1. [Installation](#installation)
2. [The on-screen plan](#the-on-screen-plan)
3. [The menu: Esc > Crop rotation plan](#the-menu-esc--crop-rotation-plan)
   - [Settings](#settings)
   - [Plans](#plans)
   - [The plan editor](#the-plan-editor)
   - [Field groups](#field-groups)
4. [Multiplayer](#multiplayer)
5. [Crops](#crops)
6. [Console commands](#console-commands)
7. [Known limitations](#known-limitations)
8. [Development](#development)

---

## Installation

1. Download `FS25_CropRotationPlan.zip` from the [releases](../../releases).
2. Put the zip (do not unzip it) in `Documents\My Games\FarmingSimulator2025\mods`.
3. Start the game and activate **Crop Rotation Plan** when you load or create a savegame.

## The on-screen plan

The plan is drawn on top of the game, at the top of the screen or on the left side.


- **Full** shows one line per field group under the plan's name: the plan year (e.g. *Year 2/4*), the crops
  this year, and either **Now:** (yellow, work this month) or **Next:** with the month.
- **Minimized** shows a single icon:
  - yellow with a number: work this month (number of fields),
  - green: work next month,
  - grey: nothing to do this month or next.
- **Alt + R** switches between full and minimized (change the key in Settings > Controls).

## The menu: Esc > Crop rotation plan

The mod adds its own tab to the in-game menu, directly above the game's Settings tab.
It has three sub-tabs: **Settings**, **Plans** and **Field groups**.

### Settings


| Setting | What it does |
|---|---|
| Display | Full, Minimized or Hidden. Your own setting, saved on your PC. |
| Position | Top or Left. Your own setting, saved on your PC. |
| Show / minimize key | Shows the key (Alt + R by default). |
| Grass in rotation | On: grass can be added to plans as a ley. Applies to your farm. |
| Who can edit the plan | Multiplayer only, see [Multiplayer](#multiplayer). |
| Your rights | Multiplayer only: whether you can edit. |

### Plans


- The list on the left shows your plans with their number of years and field groups.
  **+ New plan** asks for a name; **Edit plan** opens the editor; **Delete plan** needs a second click.
- Click the plan name to rename it. **Years in cycle** sets how many years the rotation has
  (a year can only be removed when nothing is sown in it).
- **Columns** shows one column per plan year with a card per crop ("Sow Oct", "Harvested in year 2").
- **Year rows** shows one row per year from January to December, with a bar from sowing to harvest.
  A bar that crosses the new year continues in the next row.

![Plans, Year rows view](Docs/screenshots/plans_year_rows.png)

### The plan editor

<!-- screenshot: Docs/screenshots/03_plan_editor.png -->

1. Click a **dashed gap** (free months) on the year wheel.
2. The side panel lists the crops that **fit** the gap. Crops that do not fit are greyed out;
   hover over one to see why (wrong season, too long, a tree, needs a rice paddy, ...).
3. Pick a crop, then the **sow month**. The harvest month is worked out from the crop's growth time.
   Sowing may happen in the month the crop before is harvested, and a harvest may fall in the month the
   next crop is sown.
4. Below the result you see which crops can be sown after the harvest.
5. **Add seed to plan**. Click a bar to see it or remove it.
6. **Save plan** stores the plan; **Cancel** throws the changes away.


**Grass** is kept as a ley: choose how long it stays (3 or 6 months, 1, 2 or 3 years; only what fits the gap)
and when it is cut: **Ready to harvest** (every 2 growing months) or **Fully grown** (every 3).
The editor shows about how many cuts that gives; grass does not grow from November to February.

### Field groups

<!-- screenshot: Docs/screenshots/field_groups.png (retake: field numbers 23/25/76/77 were shortened, fixed in the next build) -->

- **+ New field group**, then click your fields in **Your fields** on the right to add them.
  Your fields are read from the game (the farmland your farm owns); grey ones are not in a group yet.
- Click a field in a group to take it out. **+** next to a group's fields turns "add fields" on and off.
- Pick the group's **plan** and **Plan year now**: where the group is in its plan this year.
  It moves on by itself every new year.
- Groups in the same plan at different plan years spread the crops, so the mills get every crop every year.

## Multiplayer


- Every farm has its **own** plans, field groups and Grass in rotation setting.
- By default **only the farm manager** can edit them. The farm manager can switch
  **Who can edit the plan** to **Everyone on the farm**. Only the farm manager can change that switch.
- **Your rights** shows whether you can edit. Without the right, the Plans and Field groups pages are view only.
- The server checks every change (no overlapping crops, the field must belong to the farm) and shares it
  with all players. Players who join get the current plans.
- Display and Position are each player's own.

## Crops

Crops are read from the game the same way the game's own crop calendar does, so base game, DLC and mod crops
on your map are all there, with their own icons and sowing and harvest months.

Not offered in a rotation: trees and orchards (poplar, grapes, olives), sugarcane (regrows every year),
permanent meadow, cover crops (e.g. oilseed radish) and crops harvested all year. Rice needs a paddy field and is
shown as not available for now.

## Console commands

Open the developer console (enable it with `<controls>true</controls>` under `<development>` in
`Documents\My Games\FarmingSimulator2025\game.xml`, then press `~`).

| Command | What it does |
|---|---|
| `crpLoadExample` | Replaces your farm's plans and field groups with an example (Riverbend Springs, fields 3-4-5, 6-7, 8, 23-25, 76, 77). Server only. |
| `crpReloadCrops` | Reads the crops from the game again and prints them. |

## Known limitations

- The Plans, plan editor and Field groups pages are used with the **mouse**; gamepad navigation is not there yet.
- Quitting a savegame can write one harmless `TabbedMenu.lua:285` error to the log (issue #2).
- Rice and paddy fields (issue #1).
- PC only: script mods are not allowed on consoles.

---

## Development

```
Build/          the mod as it ships (zip the contents, not the folder)
  scripts/CropRotationPlan.lua        main: settings, on-screen plan, input, load/save hooks
  scripts/CropRotationPlanLogic.lua   pure plan rules (gaps, sow months, ley, plan year, tasks)
  scripts/CropRotationPlanCrops.lua   crops read from the game (fruit types, growth time, icons)
  scripts/CropRotationPlanData.lua    plans and field groups per farm, savegame file, local settings
  scripts/CropRotationPlanSync.lua    multiplayer: edit requests, server checks, state events
  scripts/CropRotationPlanUI.lua      drawing toolkit for the custom menu pages
  scripts/CropRotationPlanPages.lua   Plans, plan editor and Field groups pages
  scripts/CropRotationPlanFrame.lua   the Esc menu tab
  gui/CropRotationPlanFrame.xml       tab layout (header, sub-tabs, Settings rows)
  translations/l10n_en.xml, _de.xml, _da.xml, _fr.xml   all texts, one file per language
Docs/           screenshots (see image-task.md), PUBLISHING.md (ModHub checklist), v1.1/ (old v1.1 copy, reference only)
tests/          check_static.py, test_logic.py, smoke_test.py
tools/          deploy.ps1 (local test), release.ps1 (GitHub release)
HANDOFF.md      design decisions, verified facts and pitfalls, status
```

### Translations

All texts are in `Build/translations/l10n_<language>.xml` (English, German, Danish today).
To add a language, copy `l10n_en.xml` to `l10n_<code>.xml` with the game's language code (e.g. `fr`, `nl`, `pl`)
and translate the `text=` values; keep the `name=` keys and every `%d` / `%s` in the same order.
The mod's title and description are in `Build/modDesc.xml` (one `<code>` element per language);
a translated description must not be a copy of the English one (ModHub rule).
`python tests/check_static.py Build` checks that every language has every key with the same placeholders.

### Checks and tests

```
pip install luaparser lupa
python tests/check_static.py Build   # XML, Lua 5.1 syntax, l10n keys and placeholders
python tests/test_logic.py           # plan rules in a real Lua runtime
python tests/smoke_test.py           # the whole mod against a stubbed FS25: single player, multiplayer, random clicking
```

### Test in the game

`pwsh -File tools\deploy.ps1` builds the zip, closes FS25, keeps the last log in `dist\logs`,
copies the zip to the mods folder and starts the game (`-NoStart` to skip starting).

### Release

`pwsh -File tools\release.ps1 2.2.0.0` sets the version in `Build/modDesc.xml`, tags `v2.2.0.0` and pushes.
The GitHub workflow runs the checks and tests and publishes the release with `FS25_CropRotationPlan.zip`.
Publishing on the in-game ModHub: see [Docs/PUBLISHING.md](Docs/PUBLISHING.md).
