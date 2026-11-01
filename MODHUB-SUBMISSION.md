# ModHub submission sheet

Copy-paste values for the upload form on modhub.giants-software.com (GIANTS account). In the order of the form.
Checklist and rules: `Docs/PUBLISHING.md`.

## Meta Data

| Field | Value |
|---|---|
| Mod Icon (512x512) | `Docs/modhub/icon_512.png` |
| Title English | `Crop Rotation Plan` |
| Title German | `Fruchtfolgeplan` |
| Title French | `Plan de rotation des cultures` |
| Version | `1` `0` `0` `0` |
| Author | `Anders Dissing` |
| Manufacturer | `Lizard` (GIANTS: no fantasy brands, use "Lizard" where a brand is asked for) |
| Categories | First box: **Gameplay** (or the closest: Scripts / Misc). Leave the other two "Not Set". |

### Description English

```
Plan your crop rotation in the game and see on screen what to sow and harvest this month.

Menu (Esc) > Crop rotation plan:
- Plans: build a plan year by year on a year wheel (January to December). Only crops that can grow in a free gap are offered; you pick the sow month, the harvest month follows from the crop's growth time. Grass can be kept as a ley with a cut interval.
- Field groups: put your fields into groups, pick a plan and where the group is in the plan this year. It moves on by itself every year.
- Settings: display full / minimized / hidden, position top / left, grass in rotation.

Crops are read from the game (map, DLC and mod crops). Plans are saved in the savegame; a new savegame starts empty.
Multiplayer: each farm has its own plans and field groups. The farm manager edits them, or lets everyone on the farm edit them.
Alt+R: switch between full and minimized.
Console: crpLoadExample (Riverbend Springs example plan), crpReloadCrops
```

### Description German

```
Plane deine Fruchtfolge direkt im Spiel und sieh auf dem Bildschirm, was in diesem Monat gesät und geerntet werden muss.

Menü (Esc) > Fruchtfolgeplan:
- Pläne: Baue einen Plan Jahr für Jahr auf einem Jahresrad (Januar bis Dezember). Angeboten werden nur Feldfrüchte, die in einer freien Lücke wachsen können; du wählst den Saatmonat, der Erntemonat ergibt sich aus der Wachstumszeit. Gras kann als Grünland mit Schnittintervall eingeplant werden.
- Feldgruppen: Fasse deine Felder in Gruppen zusammen, wähle einen Plan und wo die Gruppe dieses Jahr im Plan steht. Das rückt jedes Jahr von selbst weiter.
- Einstellungen: Anzeige voll / minimiert / ausgeblendet, Position oben / links, Gras in der Fruchtfolge.

Die Feldfrüchte werden aus dem Spiel gelesen (Karte, DLC und Mod-Früchte). Die Pläne werden im Spielstand gespeichert; ein neuer Spielstand beginnt leer.
Mehrspieler: Jeder Hof hat eigene Pläne und Feldgruppen. Standardmäßig bearbeitet nur der Hofverwalter sie; er kann es allen auf dem Hof erlauben.
Alt+R: zwischen voll und minimiert umschalten.
Konsole: crpLoadExample (Beispielplan für Riverbend Springs), crpReloadCrops
```

### Description French

```
Planifiez votre rotation des cultures dans le jeu et voyez à l'écran ce qu'il faut semer et récolter ce mois-ci.

Menu (Échap) > Plan de rotation des cultures :
- Plans : construisez un plan année par année sur une roue annuelle (janvier à décembre). Seules les cultures qui peuvent pousser dans un créneau libre sont proposées ; vous choisissez le mois de semis, le mois de récolte découle du temps de croissance. L'herbe peut rester en prairie temporaire avec un intervalle de fauche.
- Groupes de champs : regroupez vos champs, choisissez un plan et l'année du plan où se trouve le groupe cette année. Elle avance d'elle-même chaque année.
- Paramètres : affichage complet / réduit / masqué, position en haut / à gauche, herbe dans la rotation.

Les cultures sont lues dans le jeu (carte, DLC et cultures de mods). Les plans sont enregistrés dans la sauvegarde ; une nouvelle sauvegarde commence vide.
Multijoueur : chaque ferme a ses propres plans et groupes de champs. Le gestionnaire de la ferme les modifie, ou autorise tous les membres de la ferme à les modifier.
Alt+R : basculer entre complet et réduit.
Console : crpLoadExample (plan d'exemple pour Riverbend Springs), crpReloadCrops
```

The mod's in-game texts are in English, German, Danish and French (`Build/translations`).

## Files (further down the form)

| Field | Value |
|---|---|
| Mod zip | `FS25_CropRotationPlan.zip` from the GitHub release v1.0.0.0 |
| Screenshot 1 (no text, no HUD) | `Docs/screenshots/01_fields.png` |
| Screenshot 2 | `Docs/screenshots/plans_year_rows.png` |
| Screenshot 3 | `Docs/screenshots/field_groups.png` |
| Platform | PC/Mac only (script mod, guideline 8.2) |

## Submission comment (for the testers)

```
Script mod, PC only. Adds a tab to the in-game menu (Esc > Crop rotation plan) where players build crop rotation plans on a January-December year wheel, group their fields and set where each group is in its plan. The on-screen plan shows this month's tasks (Alt+R: full/minimized).

Quick test: load any savegame (Riverbend Springs gives the right field numbers), enable the developer console and run crpLoadExample (server only). That creates two plans and six field groups for the current farm. crpReloadCrops prints the crops read from the game.

Multiplayer: plans and field groups are per farm and stored by the server in the savegame (cropRotationPlan.xml). By default only the farm manager can edit; the farm manager can allow everyone on the farm (Settings > Multiplayer). Players without the right see the plans read-only. Edits are sent to the server, which checks them (permission, plan rules, field ownership) and broadcasts the result; joining players receive the current state.

No dependencies. Languages: English, German, French, Danish.
```
