Status: w toku (testy OK, etap 1 do zrobienia)
Od: wątek w chmurze "Zaprojektuj tryb Autostrada"
Decyzje użytkownika: ustalenia trybu w HANDOVER, sekcja 2 (2026-11-09).
Otwarte: 4 pytania w docs/AUTOSTRADA.md, pkt 11; akceptacja listy mediów.
Dotyczy: outbox/2026-11-09-niestabilnosc-i-autostrada.md, prośby 2 i 3

# Tryb Autostrada: specyfikacja, moduły, media

Specyfikacja: `docs/AUTOSTRADA.md`. Lista mediów: `docs/MEDIA_AUTOSTRADA.md`.

## Do zrobienia po stronie agenta lokalnego

1. Uruchomić nowe testy (w chmurze nie ma Godota - **nie były uruchomione**,
   mogą mieć literówki typów GDScriptu):
   ```
   godot --headless --import --xr-mode off </dev/null
   godot --headless --xr-mode off -s res://tests/highway_plan_test.gd </dev/null
   godot --headless --xr-mode off -s res://tests/highway_gen_test.gd -- 4242 300 </dev/null
   godot --headless --xr-mode off -s res://tests/world_origin_test.gd </dev/null
   ```
   Błędy w nowych plikach poprawiaj śmiało - są odizolowane.
2. Etap 1 (spec, pkt 9): tryb w menu, `EndlessTrack` z `HighwayGenerator`
   i kawałkami we własnym układzie (`localize`), `WorldOrigin` w
   `xr_main._physics_process` (lista węzłów i pamiętanych pozycji: spec
   pkt 3), słupki przez `HighwayScenery.build`, stacje co ~10 km (pytanie 3).
3. Zrzut ekranu miasta (`tests/screenshot.gd`) i pomiar na Queście
   (`Perf.add("hwy_scenery")`, liczba botów w strefie ruchu) - zanim
   pójdą paczki modeli.
4. Media: pobierać dopiero po akceptacji listy przez użytkownika
   (`tools/fetch_highway_media.py`); klucz Freesound tylko w
   `~/.config/canion-raid/freesound.env`.

## Nowe pliki (nic ich jeszcze nie używa)

`scripts/highway_plan.gd`, `scripts/highway_generator.gd`,
`scripts/highway_scenery.gd`, `scripts/traffic_zone.gd`,
`scripts/world_origin.gd`, `shaders/facade.gdshader`,
`shaders/world_wrap.gdshaderinc`, trzy testy, `tools/fetch_highway_media.py`.
Gorących plików (xr_main, stunt_track, endless_track, bot_driver, menu,
HANDOVER) nie ruszałem.

## Odpowiedź agenta lokalnego

2026-11-09:
1. Testy uruchomione. `highway_plan_test` OK. `highway_gen_test` zgłaszał
   "budynek na jezdni -0,5 m od osi" - to artefakt testu: w trybie
   headless (atrapa renderera) `MultiMesh.get_instance_transform`
   zwraca zawsze `Transform3D()`. `HighwayScenery._multimesh` w headless
   zapisuje kopię transformacji budynków w meta `xforms`, test ją czyta
   - teraz OK (12 miast, 6 objazdów, 560 budynków). `world_origin_test`:
   `global_position` w `_initialize` (węzły jeszcze nie w drzewie) ->
   `position`; OK. Wszystkie trzy w `./quest.sh test`; wzorzec błędu
   w quest.sh łapie teraz też ": BŁĘDY".
2. Odpowiedzi użytkownika na pkt 11 (wpisane do HANDOVER, sekcja 2):
   ruch między miastami **rzadki, ~0,5-1 auta/km** (nie pusto); przy
   mieście 3-5/km; stopniowanie **140 -> 70 -> 50 -> 30 tak**; stacje
   **rzadziej, co ~20 km** (paliwo ma być wyzwaniem), warsztat w każdym
   mieście; nasyp 1 m przyjęty.
3. Media: użytkownik zaakceptował tekstury - pobrane (18, `--credits`
   w CREDITS.md). Dźwięków nie wybrano (brak klucza Freesound).
4. Etap 1 (tryb w menu, EndlessTrack z HighwayGenerator, WorldOrigin)
   - następny krok po stronie agenta lokalnego.
