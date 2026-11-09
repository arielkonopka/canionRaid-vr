Status: nowe
Od: wątek w chmurze "Usuń pozostałości dróg na estakadach"
Decyzje użytkownika (2026-11-09): zrobić **wszystkie 4 etapy** (0-3);
spadnięcie z estakady = **jazda dalej po dnie wąwozu** (z uszkodzeniami),
nie utrata auta; tekstury CC0 **do repo** ("dodać tekstury do repo, jeśli
są kompatybilne w sensie licencji" - CC0 jest zgodne z GPL).
Raport z audytem (19 miejsc z plikami i liniami): Claude Doc
"Pozostałości estakad - audyt i plan refaktoryzacji"
(https://claude.ai/artifact/SBNMcwPrizsBxvDnX7EZAb).

# Pozostałości toru na słupach: refaktoryzacja w 4 etapach

## Diagnoza w jednym akapicie

Główną pozostałością nie są filary, tylko założenie, że **świat to płaska
trawa na y = 0** (`main.tscn` Ground + `WorldBoundaryShape3D`), a jezdnia
to płyta wisząca nad nią. Wąwóz nie ma dna (ściany zaczynają się na
krawędzi jezdni), morze leży na stałym `SEA_Y` 0,3, nasyp autostrady
i wiadukt schodzą do zera, a `TrackGenerator._guarded` wstawia podjazdy,
żeby droga nie zeszła poniżej 2 m (błąd "droga pod trawą", PR #18). Na
tym samym założeniu stoi nowy kod Autostrady (`highway_generator.gd`
`ROAD_Y`, `highway_scenery.gd` stawia domy na y = 0). Kierunek:
**teren liczony od drogi, nie droga od terenu**. Estakady zostają, ale
jako typ odcinka (VISION, filar 2), nie jako tryb gry.

Każdy etap osobnym commitem/PR-em, gra po każdym działa. Po każdym
etapie testy z CLAUDE.md: `drive_test` dla każdego zawieszenia i obu
skrzyń, `endless_test` (wąwóz), `title_test`, `highway_test`, wynik do
HANDOVER.md.

## Etap 0 - szybkie porządki (bez zmiany rozgrywki)

1. `xr_main.gd:875` napis warsztatu "+ naprawa karoserii, + 1 dźwig"
   → "+ 1 auto" (gracz widzi słowo "dźwig", a dźwigów nie ma).
2. `stunt_track.gd` `_build_mesh`, filary: `if canyon: return` →
   `if canyon or highway: return`. Kawałek autostrady ma `canyon = false`,
   więc dziś co 14 m powstaje filar schowany w nasypie (jezdnia 4 m,
   `cap_top` ~3,7 > 2).
3. Tamże: spód i boki płyty (`deck`, "widać je przy spadaniu z toru") tylko
   gdy `not canyon and not highway`. Uwaga: `_build_highway` woła
   `_build_mesh` dla drugiej jezdni - ta sama flaga ją obejmie.
4. Usunąć martwe przekazywanie `road_material` (StuntTrack go nie używa,
   jezdnia ma `road.gdshader`), `pillar_material`, `start_height` przez
   `EndlessTrack` / `xr_main.gd:218-219` / `title.gd:75-76`;
   `Material_road` i `Material_pillar` z `main.tscn` (sprawdzić, czy
   `title.tscn` ich nie potrzebuje).
5. `quest.sh:105`: `endless_test "180 petrol 777 150 canyon"` - dziś bez
   5. argumentu test jedzie po estakadach.
6. HANDOVER sekcja 1 ("tory zawieszone wysoko na słupach") i opis
   `icon.svg` w sekcji 4 - poprawić na obecną grę (nową ikonę można
   zrobić później).

## Etap 1 - jeden tryb trasy

1. **`drive_test` na stałej trasie wąwozu z metą**: `DEFAULT_TRACK` bez
   przerwy (rozbieg, skocznia ze stołem jak z generatora, łuk z
   przechyłką mokry, lód, meta), `canyon = true`. Ma zostać porównywalny
   między zawieszeniami i skrzyniami (CLAUDE.md). Stare wyniki w HANDOVER
   oznaczyć jako z poprzedniej trasy.
2. `GameSettings.track_mode`: tylko "canyon" (i przyszły "highway" z trybu
   Autostrada). `SETTINGS_VERSION` 3 + migracja w `load_settings()`
   ("endless"/"demo" → "canyon"). Klucz `cranes` → `lives` też z migracją
   (pułapka z HANDOVER: zapisany wybór wygrywa z nowym domyślnym).
3. `TrackGenerator`: bez gałęzi estakad - `MIN_HEIGHT`/`MAX_HEIGHT`,
   `gap: not canyon`, napis "SKOK", parametr `canyon` w `generate_section`.
   `generator_test`, `track_path_test` przestawić na wąwóz.
4. `xr_main`: jedna ścieżka utraty auta. Wyrzucić gałęzie dla estakad
   w `_use_crane` / `_respawn` / `fall_depth` / `respawn_back` /
   `_canyon` (zostaje `_right_car`, `lose_life`, `_restart_section`).
   Nazwy "crane" w kodzie → "life"/"respawn" (kosmetyka, ale myli).
5. `StuntTrack`: usunąć `pillar_spacing`, `pillar_size` (nieużywany),
   `start_height`, `scenery` (drzewa tylko dla estakad - patrz etap 2.9).
   **API przerw** (`is_gap_at`, `last_gap_end_before`,
   `runup_start_before`, `gap` w próbkach, `TrackPath.FLAG_GAP`) zostaje -
   wraca w etapie 3. Można je przyspieszyć (`_dists.bsearch` jak
   w `transform_at_distance`), bo `is_gap_at` jest liniowe i woła je
   `_spawn_bot` i `_safe_pose`.

## Etap 2 - teren liczony od drogi (główna zmiana)

1. **`ground_y(d, lateral)` w kawałku** (`StuntTrack`, statyczna część
   najlepiej w `TrackPath`): wysokość gruntu względem próbki jezdni.
   Wąwóz: dno = jezdnia (żwir 1,8 m już jest w profilu), autostrada:
   jezdnia - wysokość nasypu, otwarcie wąwozu i okno na morze: poziom
   liczony od jezdni na styku, nie od zera. Funkcja gładka w `d`, żeby
   kawałki zgadzały się na styku bez wymiany danych (jak `sea_factor`).
2. **Dno wąwozu** - siatka + kolizja między podstawami ścian (dziś jest
   tylko pobocze 1,8 m i pustka pod jezdnią). Na razie na poziomie
   jezdni, więc nic się nie zmienia wizualnie; od etapu 3 dno może być
   niżej niż jezdnia. Kolizja dna: osobne ciało z `surface`
   "gravel"/grip ~0,6 (do ustalenia), żeby uszkodzenia przy lądowaniu
   liczyły się jak dziś.
3. **Daleki teren**: `Ground/GroundMesh` dalej jedzie za autem, ale na
   wysokości z wygładzonego profilu drogi (np. średnia jezdni w promieniu
   ~300 m minus 2 m, zmiana płynna) zamiast y = 0. **Usunąć
   `WorldBoundaryShape3D`** - kolizja gruntu tylko z kawałków (pobocza,
   dno, nasyp, płaskowyż do zasięgu `CANYON_COLLIDE_K` - to, do czego auto
   realnie doleci). To samo `title.gd:179`.
4. **Morze** (`SEA_Y`, `_build_sea`): poziom = jezdnia na środku okna
   minus stała (dziś efektywnie 2-25 m niżej, zależnie od wysokości
   drogi - wybrać np. 8 m), płaszczyzna jak dziś.
5. **`_open_factor`**: płaskowyż przy autostradzie schodzi do `ground_y`
   autostrady, nie do y = -0,5 (znany błąd "półki płaskowyżu" przy
   wyjeździe z autostrady, HANDOVER sekcja 5).
6. **Autostrada** (`_build_highway`, `_build_overpass`): nasyp `er1`/`el1`
   i stopy wiaduktu do `ground_y`, nie do zera.
7. **Strażnik wysokości** (`_guarded`, `lowest_edge`, `_rise`): przestaje
   pilnować trawy. Zostaje tylko pas wysokości bezwzględnej (np. ±150 m
   od startu - float32, mgła, `WorldOrigin` przesuwa tylko XZ?) -
   sprawdzić z `world_origin.gd`, czy przesuwa też Y. Generator może
   wtedy schodzić dolinami zamiast wspinać się podjazdami 7°.
   `track_height_test` → "jezdnia nigdzie pod `ground_y`, dno nigdzie
   ponad jezdnią, wszystko w pasie wysokości".
8. **Upadek** (`xr_main._watch_track`, boty `y < -50`): względem
   `ground_y` kawałka (np. 50 m pod gruntem = utrata), nie bezwzględne -50.
9. **Tryb Autostrada (PR #36)**: `highway_generator.gd` `ROAD_Y` i
   `highway_scenery.gd` (linie 148, 226, 305 - domy, krawężniki, chodniki
   na y = 0) na `ground_y`. Lepiej teraz, zanim powstanie więcej kodu na
   zerze. `Scenery.scatter` (drzewa) można wtedy użyć przy autostradzie
   z `ground_y` zamiast `y = 0` (uwaga PERF_PLAN C8: `_too_close` po
   indeksie próbki).

## Etap 3 - estakady jako typ odcinka

1. Moduł `_viaduct` w generatorze wąwozu: **dno opada 15-30 m** pod
   jezdnią (wąwóz się pogłębia: ściany rosną w dół, `ground_y` niżej),
   jezdnia biegnie dalej na filarach. Kod filarów zostaje - stopa na
   `ground_y` zamiast na zerze (`base := Vector3(pos.x, 0.0, pos.z)`).
2. **Przerwy w jezdni tylko tu** (ustalenie użytkownika: "przerwy tylko
   na konstrukcjach nad ziemią: na palach, w pętlach, beczkach"). Wraca
   API przerw i balistyka `_jump_geometry`, która już jest.
3. **Spadnięcie = jazda dalej po dnie** (decyzja użytkownika
   2026-11-09): lądowanie na dnie z uszkodzeniami (jak twarde lądowanie
   dziś), dno to **druga ścieżka trasy** (próbki, `lateral_offset`,
   `nearest_sample` wybierają ścieżkę, na której jest auto), która
   rampami wraca do jezdni za estakadą. To ten sam mechanizm co
   rozwidlenia na dwie nitki (HANDOVER sekcja 5, ścieżki A/B) - zrobić
   wspólnie. Boty i `_last_safe_dist` muszą znać ścieżkę.
4. Częstość: rzadko (1 na 3-4 odcinki), najpierw estakada bez przerw,
   od dalszych odcinków z przerwą. Znak ostrzegawczy przed przerwą jak
   dziś przed skocznią (prędkość). HUD/mapka: dno jako druga linia.
5. Test: `endless_test` z ziarnem, które trafia na estakadę z przerwą -
   autopilot raz przeskakuje, raz (za wolno) spada i dojeżdża dnem.

## T. Tekstury - pobrać i dodać do repo (zgoda użytkownika)

Chmura nie może ich pobrać (proxy blokuje ambientCG i Poly Haven), więc:

1. `python3 tools/fetch_highway_media.py textures` - wszystkie 30 pozycji
   z `TEXTURES` (16 z listy Autostrady + 12 nowych + 2 opcje aerial) do
   `textures/cc0/<nazwa>/{albedo,normal,roughness}.jpg` + `SOURCE.txt`.
2. `.gitignore` ma już wyjątek `!/textures/cc0/` (reszta `textures/`,
   czyli freepbr, dalej poza repo). Commit razem z plikami `.import`
   Godota. Sprawdzić rozmiar (~45 MB); jeśli za dużo dla repo, zapytać
   użytkownika o Git LFS.
3. `python3 tools/fetch_highway_media.py --credits` → wkleić do
   `CREDITS.md` (zastępuje sekcję "Tryb Autostrada (planowane)").
4. Podmiana w grze: `StuntTrack.ROCK_TEXTURES` i `MOSS_TEX` na
   `textures/cc0/canyon_rock`, `mountain_rock`, `moss` (pliki `.jpg`,
   inne nazwy map: `albedo`, `normal` w konwencji GL, `roughness`).
   Skala `rock_scale` dobrać na zrzucie ekranu; łupek ma mieć poziome
   warstwy - `cliff_side` ma warstwy w osi V tekstury, sprawdzić
   orientację w `rock.gdshader` (triplanar). Wtedy APK z repo wygląda tak
   samo jak lokalny, bez freepbr. Pomiar na Queście przed/po
   (`rock_simple`).
5. Reszta (dachy, blacha, żwir, beton tunelu, pola, śnieg) - przy
   etapach 2-3 i w trybie Autostrada, gdzie są potrzebne.

Braki: czerwona cegła (przyciemnić `Bricks105` w shaderze), elewacja
mieszkalna z oknami (okna w `facade.gdshader`), deski płotów/stodół.

## Dopisek (użytkownik, 2026-11-09 wieczorem)

1. **Twoje lokalne zmiany mają pierwszeństwo.** Użytkownik mówi, że
   "agent lokalny już coś nazmieniał" (m.in. są miasta) - w repo tego
   jeszcze nie widać (ostatni commit agenta na `boty-szal-tekstury` to
   PR #27). Zanim zaczniesz etapy: scal to zlecenie ze swoim stanem
   i przelicz numery linii z raportu. Jeśli miasta stoją już na y = 0
   (jak `highway_scenery.gd`), etap 2.9 obejmuje też je: domy, chodniki,
   krawężniki na `ground_y`.
2. **Miasta jako grafy ulic (przyszła faza, nie teraz).** Użytkownik:
   "miasta chciałbym kiedyś mieć jako grafy, po których można jeździć".
   Nie robić w tych etapach, ale nie zamykać drogi:
   - etap 3 i tak wprowadza **więcej niż jedną ścieżkę** (dno pod
     estakadą, rozwidlenia). Zrób to jako ogólny zbiór ścieżek
     połączonych węzłami (ścieżka = `TrackPath`, węzeł = punkt
     rozgałęzienia / złączenia z dystansem na każdej ścieżce), nie jako
     sztywne "A i B". Miasto to potem po prostu gęsty graf takich
     ścieżek (ulice, skrzyżowania);
   - zapytania `nearest_sample` / `lateral_offset` / postęp gracza
     (`_last_safe_dist`, odcinki, boty na "szynie") mają brać ścieżkę,
     na której jest auto, a dystans liczyć wzdłuż niej - nie zakładać
     jednego liniowego `dist` dla całego świata;
   - `ground_y` w mieście liczyć z najbliższej ulicy (nie z jednej osi).
   Zapisz to w HANDOVER, sekcja 8, jako pomysł użytkownika na później.
3. **Zamienniki tekstur** (użytkownik: "tam, gdzie nie udało się pobrać,
   bierz zamienniki"): skrypt ma `FALLBACKS` - pozycja, która się nie
   pobierze (zmieniony ID, 404), sama przechodzi na zastępczą (CC0),
   a `--credits` podpisuje to, co faktycznie leży w `SOURCE.txt`. Braki
   z ambientCG (czerwona cegła, deski, tynk domu) są uzupełnione z Poly
   Haven: `brick_red`, `wood_planks`, `plaster_house`. Elewacji z oknami
   nie ma nigdzie - okna w `facade.gdshader`.
