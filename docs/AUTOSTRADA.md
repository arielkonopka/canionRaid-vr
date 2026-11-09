# Tryb "Autostrada" - specyfikacja

Ostatnia aktualizacja: 2026-11-09. Autor: wątek w chmurze "Zaprojektuj tryb
Autostrada", na prośbę agenta lokalnego
(`docs/agent/outbox/2026-11-09-niestabilnosc-i-autostrada.md`, prośby 2 i 3).
Ustalenia użytkownika: `HANDOVER.md`, sekcja 2 ("TRYB AUTOSTRADA"). To jest
propozycja projektowa - decyzje należą do użytkownika, a agent lokalny może
się nie zgodzić (wydajność na Queście, fizyka).

## 1. Co gracz dostaje

- W menu wybór trasy: **Wąwóz** (jak dziś) albo **Autostrada**.
- Autostrada **2+2 pasy na całej długości**, dwie jezdnie za barierą, na
  drugiej ruch z naprzeciwka. Płasko, szerokie łuki (R 900-2500 m), limit
  140 km/h.
- **Sceneria co 50 ± 10 km**: łąka (start), pola, pustynia, góry, nad morzem,
  wąwóz; przejście przez 2 km (teren i obiekty mieszają się).
- **Miasta**: co 25 km małe (~1 km zabudowy), co 100 km duże (~5 km). Ta sama
  droga przechodzi w ulicę: chodniki z krawężnikiem, latarnie, domy po obu
  stronach (w dużym mieście dwa rzędy, wyżej w centrum), strefa **30 km/h**
  ze stopniowaniem przed miastem (70 na 850 m, 50 na 250 m przed zabudową).
- **Ruch wokół miast**: 3-5 aut/km na każdej jezdni do 5 km od zabudowy.
- **Słupki**: hektometrowe co 100 m, kilometrowe co 1 km z numerem (obie
  jezdnie). Ekrany akustyczne 1,5 km przed i za miastem.
- **Objazdy ze skocznią**: rzadko (~1 na 30 km), nigdy przy mieście; za
  przerwą w barierze równoległy pas po prawej z rampą - można ominąć.
- Furiaci (szał, zasadzki, punkty) jak w wąwozie - to nie jest "ruch".

## 2. Moduły w tym PR (odizolowane, nic ich jeszcze nie używa)

| Plik | Co robi |
|---|---|
| `scripts/highway_plan.gd` (`HighwayPlan`) | Plan trasy: biom, miasta, ograniczenia, gęstość ruchu, objazdy, słupki - z dystansu `d` (float 64-bit), deterministycznie z ziarna, leniwie (setki km bez tablic). |
| `scripts/highway_generator.gd` (`HighwayGenerator`) | Odcinki jezdni w formacie StuntTrack, kawałkami ~1-1,6 km, **każdy kawałek we własnym układzie** (`localize`). Zmiany ograniczeń dokładnie na granicach odcinków. Meta: `autostrada` (biom), `city_start`/`city_end`, `detour`, `arc`. |
| `scripts/highway_scenery.gd` (`HighwayScenery`) | MultiMesh: budynki (proceduralne okna), latarnie, słupki, ekrany, obiekty biomów (drzewa, krzewy, kaktusy, palmy, turbiny, głazy), chodniki z kolizją, kolizja pierwszego rzędu budynków (pudła), numery km (Label3D). |
| `shaders/facade.gdshader` | Elewacja z oknami liczonymi w metrach budynku (nie zależy od położenia w świecie). |
| `scripts/traffic_zone.gd` (`TrafficZone`) | Decyzje ruchu: które auta usunąć, gdzie dodać nowe; test widoczności (głowa + lusterka). |
| `scripts/world_origin.gd` (`WorldOrigin`) | Przesuwanie początku świata, offset 64-bit, parametr globalny shaderów. |
| `shaders/world_wrap.gdshaderinc` | Szum okresowy dla shaderów liczonych z pozycji w świecie. |
| `tests/highway_plan_test.gd` | Plan + symulacja ruchu (gęstość, nie znika widoczne ani w furii). |
| `tests/highway_gen_test.gd` | Generator "na płasko" przez 300 km + sprawdzenie zabudowy + błąd float32. |
| `tests/world_origin_test.gd` | Przesunięcie na prawdziwym RigidBody (Jolt) + 300 km jazdy. |

**Testy nie były uruchomione** (w chmurze nie ma Godota) - proszę uruchomić:

```
godot --headless --import --xr-mode off </dev/null
godot --headless --xr-mode off -s res://tests/highway_plan_test.gd </dev/null
godot --headless --xr-mode off -s res://tests/highway_gen_test.gd -- 4242 300 </dev/null
godot --headless --xr-mode off -s res://tests/world_origin_test.gd </dev/null
```

## 3. Precyzja float32 przy setkach km (najważniejsza pułapka)

Godot z Debiana ma pojedynczą precyzję. Trasa nie zawraca (`MAX_YAW`), więc
współrzędne rosną liniowo: krok float32 to 0,12 mm przy 1-2 km, ~1 mm przy
10 km, ~8 mm przy 100 km, ~31 mm przy 300 km. Objawy bez poprawki: drżenie
obrazu w goglach (od kilkunastu km), "schodki" wierzchołków jezdni i kół,
wzory w shaderach z `wpos` rozsypane w szum (`sin(duża liczba)`).

Trzy warstwy rozwiązania:

1. **Kawałki we własnym układzie** (`HighwayGenerator.localize`): kawałek
   zaczyna się w (0, y, 0), węzeł `StuntTrack` stoi w (x, 0, z) końca
   poprzedniego (`end_state()` już zwraca pozycję przez `to_global`).
   Wierzchołki, próbki i kolizja mają współrzędne < ~2 km. Dystans i kurs
   są w słownikach jako float 64-bit - nie psują się.
2. **Przesuwanie świata** (`WorldOrigin`): gdy auto jest dalej niż 2048 m
   od zera w poziomie, wszystkie węzły z grupy `origin_shift` przesuwają
   się o wielokrotność 1024 m. Przy 140 km/h raz na ~50 s, przy 350 km/h
   raz na ~20 s. Koszt: kilkadziesiąt przypisań pozycji w jednym kroku.
3. **Wzory w shaderach**: `wpos + world_origin_wrap` i szum okresowy
   (`world_wrap.gdshaderinc`, okres 6000 m). Jezdnia: UV.y = dystans (float32
   w wierzchołku!) - zamienić na `dist - d_start + fposmod(d_start, P)`
   w kawałku, z P = wielokrotność okresu kresek i tekstury (np. 6000 m).

### Gdzie wpiąć przesuwanie (gorące pliki - agent lokalny)

W `xr_main._physics_process`, **na początku kroku**, przed sterowaniem
i botami:

```gdscript
var s := _origin.check(car.global_position)
if s != Vector3.ZERO:
    _origin.apply(s, get_tree().get_nodes_in_group(WorldOrigin.GROUP))
    _on_origin_shift(s)   # poprawki pamiętanych pozycji, lista niżej
```

Do grupy `origin_shift` (najwyższe węzły; dzieci jadą z nimi): kawałki
trasy (`StuntTrack` w `EndlessTrack`), auto gracza, boty, auta
z naprzeciwka (także w puli), wraki, wybuchy (`explosion.gd`), deszcz
(GPUParticles - w układzie świata cząstki przeskoczą; najprościej
`restart()` po przesunięciu), `XROrigin3D`, jeśli nie jest dzieckiem auta.
Teren (`Ground/GroundMesh`) i horyzont już idą za autem (`_process`) - nie
muszą być w grupie; wzór terenu zostaje ciągły dzięki `world_origin_wrap`
(punkt 3).

Do sprawdzenia w kodzie (`_on_origin_shift`, odjąć `s`): każda zapamiętana
**pozycja w świecie** (`Vector3`), np. `StuntCar.last_hit` (punkt
kontaktu), stan wgnieceń z punktami w świecie, cele botów i punkty taktyk
(`BotDriver`, jeśli trzymają `Vector3`, a nie dystans), pozycje do
liczenia prędkości z różnicy położeń, ślady opon/kół, HUD-owa mapka
(jeśli rysuje z pozycji). Wszystko, co trzyma **dystans** (`dist`,
`_last_safe_dist`, szyna botów, auta z naprzeciwka), jest odporne.

Interpolacja fizyki (`physics_interpolation=true` w project.godot): `apply`
woła `reset_physics_interpolation()` na każdym przesuniętym węźle - bez tego
przez jedną klatkę obraz "leci" przez 2 km.

Jolt: przypisanie `global_position` ciału sztywnemu to teleport; prędkości
są przywracane. Kontakty z poprzedniego kroku przepadają (jedna klatka bez
"warm start") - na prostej autostradzie niewidoczne; jeśli w logu
`INCYDENT` pojawi się coś w chwili przesunięcia, opóźnić przesunięcie do
chwili, gdy auto ma 4 koła na ziemi.

## 4. Jezdnia (HighwayGenerator)

- Szerokość naszej jezdni `WIDTH` = 2 × 3,75 + pas awaryjny 3 + opaska
  0,75 = **11,25 m**. Druga jezdnia jak dziś (`_build_highway`: przesunięcie
  o szerokość + `HIGHWAY_MEDIAN`). `road.gdshader` dziś liczy linie z
  szerokości dla 3 pasów - dla autostrady 2 pasy + linia krawędziowa pasa
  awaryjnego (np. `UV2.y` = liczba pasów albo osobny parametr materiału).
- Wysokość `ROAD_Y` 1 m nad terenem (niski nasyp; wąwozowa autostrada ma 4 m).
  Dziś teren to płaszczyzna y = 0, więc jezdnia jest płaska. Garby i podjazdy
  w górach dopiero z prawdziwym terenem (wtedy strażnik wysokości jak
  `TrackGenerator._guarded`).
- Łuki: wejście i wyjście z połową krzywizny (StuntTrack nie ma klotoid),
  przechyłka 2,5°; w mieście R 250-600 bez przechyłki. Bez tablic U-3/A-1
  (meta `arc` zamiast `curve_len`/`curve_sign`).
- Kawałek kończy się na granicy modułu po przekroczeniu 1 km (1,0-1,6 km).
  `EndlessTrack`: `AHEAD` 2 kawałki wystarczy (2-3 km przed autem; przy
  350 km/h ~25 s na budowę).

### Wpięcie w EndlessTrack (propozycja)

Nowy tryb jako `EndlessTrack.mode = "autostrada"` (albo osobna klasa
`HighwayTrack` z tym samym API). Różnice w `_add_section`:

```gdscript
var loc := HighwayGenerator.localize(start)      # start = end_state() poprzedniego
chunk.position = loc["origin"]
chunk.start_state = loc["state"]
chunk.segments.assign(_hgen.next_chunk(loc["state"]))
chunk.highway = true
chunk.canyon = false
chunk.scenery = false          # zamiast Scenery.scatter - HighwayScenery
```

i w `StuntTrack.build` (po `_build_highway`), dla kawałka autostrady:
`for n in HighwayScenery.build(_samples, plan, rng, HighwayScenery.edges_for(width)): _adopt(n)`
z `await _slice()` między budynkami a resztą. Numer odcinka (`section_at`)
w tym trybie to numer kilometra albo miasta - HUD pokazuje "km 123".

Znaki z meta: `city_start` → tablica z nazwą miejscowości (jak `_town_sign`,
nazwa z `name_seed` - generator nazw, bez prawdziwych miejscowości),
`city_end` → przekreślona; `limit` → B-33/B-34 już działa; `detour` →
budowa objazdu (niżej).

W mieście: zamiast barier energochłonnych na zewnętrznej krawędzi -
krawężnik i chodnik (`HighwayScenery._sidewalks`, z kolizją); bariera
w pasie rozdziału zostaje; bez nasypu (chodnik wypełnia do budynków).

## 5. Sceneria (biomy)

`HighwayPlan.biome_blend(d)` → `{a, b, t}`. Teren to jedna płaszczyzna za
autem - wystarczy, że `ground.gdshader` dostanie kolory/tekstury biomu
`a` i `b` i współczynnik `t` (uniformy ustawiane co klatkę z dystansu
auta) - przejście 2 km jest płynne. Horyzont (`Scenery.horizon`) na biom:
góry - wyższe i bliższe (z śniegiem), pustynia - płaskie mesy w kolorze
piasku, nad morzem - bez gór od strony morza, pola/łąka - niskie wzgórza.
Morze: dziś `sea_factor` co 5 km w wąwozie; w trybie Autostrada lustro
wody po lewej stronie przez cały biom "seaside" (obiekty biomu wtedy tylko
po prawej - do poprawki w `_biome_props`, dziś obie strony).

Obiekty biomów (`HighwayScenery.BIOME_PROPS`): rodzaj, gęstość, odległość
od krawędzi. ~150-350 instancji/km, jedno wywołanie rysowania na rodzaj
w kawałku, `visibility_range_end` 450-3000 m.

## 6. Miasta i ruch

- Zabudowa: pudła 1×1×1 skalowane w instancji (front 9-34 m, głębokość
  9-18, wysokość 5,5-12 m / w dużym 9-45 m), przerwy-przecznice co 90-160 m
  (bez jezdni - na razie; boczne drogi to osobny temat, wątek "Oceń pomysł
  przejazdów przez miasto"). Kolizja tylko pierwszego rzędu.
- Koszt (szacunek): małe miasto ~120 budynków, duże ~1200 w 4-5 kawałkach;
  1 wywołanie rysowania na kawałek. Do zmierzenia `Perf.add("hwy_scenery")`
  i linii PERF+ na Queście.
- Ruch (`TrafficZone.step`, co ~0,5 s): okno -300…+1500 m od gracza,
  gęstość z planu na obie jezdnie, nowe auta 700-1500 m przed graczem,
  najwyżej 1 nowe na jezdnię na wywołanie. Auto bez furii znika, gdy jest
  niewidoczne i (poza oknem albo poza strefą 5 km). Widoczność zgrubna:
  stożek 140° od głowy do 900 m + lusterka (stożek 50° do tyłu, 200 m) -
  lepiej nie usunąć niż usunąć na oczach.
- Auta ruchu: na naszej jezdni BotDriver w trybie spokojnym (szyna daleko
  od gracza jak dziś - `LOD_FAR`), z naprzeciwka - kinematyczne jak
  `_update_oncoming`. W strefie miasta może być ~2 × 9 aut + furiaci -
  pomiar kosztu botów na Queście (dziś 20 botów = 4,15 ms/krok na PC).
- Modele aut: z wątku "Dodaj nowe modele aut z epoki" (paczki CC0 czekają
  na akceptację użytkownika) - tu bez duplikowania.

## 7. Objazd ze skocznią

`meta.detour = {start, end, side}`; jezdnia główna prosta przez 450 m.
Budowa jak zjazd do stacji (`_build_service`): przerwa w barierze po
prawej, równoległy pas 5 m za pasem awaryjnym (dystans ten sam - jedna
linia `dist`, `lateral_offset` działa), w środku rampa ze stołem
(`TrackGenerator._jump_geometry` - balistyka) zaprojektowana na
**100-120 km/h z długim lądowiskiem** (pomiar `ramp_entry_test`: przy
nadmiarze prędkości auto przelatuje lądowisko i wbija się nosem), powrót
przez drugą przerwę. Punkty za skok - jak dziś (`StuntTracker`).

## 8. Paliwo, stacje, warsztat (propozycja do decyzji)

Zasięg paliwa ~12 km (ustalenie z punktacji), autostrada ma setki km.
Propozycja: **MOP ze stacją co ~10 km** (zjazd jak dziś), **warsztat
w każdym mieście** (co 25 km). Bez tego gracz stanie po 12 km.

## 9. Etapy (jak w HANDOVER, sekcja 8, pkt 000)

1. Menu "Autostrada" + `HighwayGenerator` + kawałki lokalne + `WorldOrigin`
   + słupki (`HighwayScenery` bez miast) + stacje co 10 km. Test:
   `drive_test` / `endless_test` przez 20+ km, `world_origin_test`.
2. Biomy: teren (shader), horyzont, obiekty; `world_wrap` w shaderach.
3. Miasta (zabudowa, chodniki, limit 30) + `TrafficZone` + auta z epoki.
4. Objazdy ze skocznią.

## 10. Media

Lista i skrypt: `docs/MEDIA_AUTOSTRADA.md`, `tools/fetch_highway_media.py`.
Pobieranie dopiero po akceptacji listy przez użytkownika.

## 11. Otwarte pytania do użytkownika

1. Ruch: rozumiem "nie-szalone znikają do 5 km od miasta" jako: w promieniu
   5 km gęstość jest utrzymywana, dalej auta bez furii rozpływają się, gdy
   ich nie widać - między miastami pusta autostrada (sami furiaci). Dobrze?
2. Stopniowanie ograniczeń przed miastem (140 → 70 → 50 → 30)?
3. Stacja co ~10 km i warsztat w każdym mieście (paliwo na ~12 km)?
4. Jezdnia na niskim nasypie 1 m (dziś na autostradzie w wąwozie 4 m)?
