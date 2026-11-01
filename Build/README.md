# FS25_CropRotationPlan

Planlæg sædskiftet i spillet og se på skærmen, hvad der skal sås og høstes i denne måned.

## Installation
Læg `FS25_CropRotationPlan.zip` (uudpakket) i mods-mappen:
`Documents\My Games\FarmingSimulator2025\mods`
Aktivér moddet når du indlæser savegamet.

## Menuen (Esc) > Sædskifteplan

### Indstillinger
- Visning: Fuld, Minimeret eller Skjult.
- Placering: Top eller Venstre.
- Tast: Alt+R skifter mellem fuld og minimeret (ændres under Indstillinger > Styring).
- Græs i sædskiftet: Til / Fra.

### Planer
Listen over planer, + Ny plan, Rediger plan og Slet plan. En plan kan vises som kolonner (et år pr. kolonne)
eller årsrækker (januar til december, en bjælke pr. afgrøde fra såning til høst).

Planeditoren (Rediger plan) viser et årshjul med en række pr. år:
- Klik på et stiplet hul (ledige måneder). Kun afgrøder der kan gro i hullet kan vælges; de andre er grå,
  og grunden står når musen holdes over dem.
- Vælg såmåneden. Høstmåneden regnes ud fra afgrødens vækstid. Høst må falde i næste afgrødes såmåned.
- Græs lægges som græsmark: vælg hvor længe (3 eller 6 mdr., 1, 2 eller 3 år) og hvornår der slås
  ("Klar til høst" hver 2. vækstmåned eller "Fuldt udvokset" hver 3.). Ingen vækst november til februar.
- Klik på en bjælke for at se eller fjerne afgrøden.
- Intet gemmes før du trykker Gem plan.

### Markgrupper
En række pr. gruppe: marker, plan, "Planår nu" og årets afgrøder.
- + Ny markgruppe, klik derefter på dine marker i panelet til højre for at tilføje dem.
- Klik på en mark i gruppen for at tage den ud.
- "Planår nu" er hvor gruppen er i sin plan i år. Det rykker selv videre hvert år.

## På skærmen
Fuld visning: en linje pr. markgruppe under planens navn med planår, årets afgrøder og
"Nu: Høst Hvede" (gult) eller "Næste: Så Raps (aug)".
Minimeret: ét ikon. Gult med tal = opgaver denne måned (antal marker), grønt = opgaver næste måned, gråt = intet.

## Gemt i savegamet
Planer og markgrupper gemmes af serveren i `cropRotationPlan.xml` i savegame-mappen. Et nyt savegame starter tomt.

## Afgrøder
Afgrøderne læses fra spillet (kort, DLC og mod-afgrøder) med så- og høstmåneder fra spillets egen
afgrødekalender. Træer, plantager, sukkerrør og efterafgrøder kan ikke indgå. Ris kræver en rismark.

## Konsol (udviklerkonsol)
- `crpLoadExample`: erstatter planer og markgrupper med eksemplet for Riverbend Springs.
- `crpReloadCrops`: læser afgrøderne igen og skriver dem i konsollen.

## Multiplayer
Hver gård har sine egne planer, markgrupper og indstillingen Græs i sædskiftet. Som standard kan kun gårdens leder redigere dem.
Gårdens leder kan under Indstillinger > Multiplayer skifte "Hvem kan redigere planen" til "Alle på gården".
"Dine rettigheder" viser om du selv kan redigere. Afsnittet Multiplayer vises kun i multiplayer.
Serveren tjekker hver ændring (ingen overlap, marken skal tilhøre gården) og deler den med alle spillere.
Tilskuere (ingen gård) kan ikke redigere. Visning og placering er hver spillers egne og gemmes på spillerens pc
(`modSettings\FS25_CropRotationPlan\settings.xml`). `crpLoadExample` virker kun på serveren og fylder serverspillerens gård.
