# Plan refaktoringu wydajności (Quest 3)

Ostatnia aktualizacja: 2026-11-08. Autor: wątek w chmurze
"Zaplanuj refaktoring gorących punktów wydajności" (przegląd statyczny
kodu z `main` @ `dfeaa34`, bez uruchamiania - w chmurze nie ma Godota ani
gogli). **Plan zaakceptowany przez użytkownika 2026-11-08.** Refaktory kodu
idą w kolejności z sekcji 5, po pomiarze bazowym; pomiary robi agent lokalny (zlecenie
w `docs/agent/inbox/2026-11-08-plan-wydajnosci.md`).

Liczby "zysk" w tabeli to **szacunki z przeglądu kodu**, nie pomiary.
Kolejność prac ustalamy dopiero po pomiarze bazowym (etap 0).

## 1. Zasady

- **Fizyka auta przy graczu jest nietykalna** (`docs/VISION.md`, CLAUDE.md).
  Bez zmian zostają: 120 Hz fizyki, `TIRE_SUBSTEPS` gracza (6) i botów
  z fizyką (2), model opony, zawieszenia, ABS/TCS/ESP, badanie podłoża,
  CCD i raport kontaktów (wgniecenia, szał), progi LOD botów
  (`LOD_FAR`/`LOD_NEAR`) - chyba że użytkownik zdecyduje inaczej.
- Wolno: oszczędzać na grafice (zwłaszcza dalekiej), na alokacjach,
  strukturach danych, budowie toru, decyzjach botów (sterowanie, nie
  fizyka), dźwięku - **pod warunkiem, że testy jazdy dają te same wyniki**.
- Refaktor "czysty" (bez zmiany zachowania) musi dać **identyczne liczby**
  w `tests/drive_test.gd` (każde zawieszenie, obie skrzynie),
  `dent_test`, `respawn_test`, `assist_test`. Zmiana zachowania (np.
  sterowanie botów z profilu prędkości) - porównanie w `bot_rage_test`,
  `endless_test`, `highway_test` i opis różnic w HANDOVER.
- Każda zmiana z pomiarem przed/po na goglach (sekcja 4). Bez pomiaru nie
  scalamy zmian, które pogarszają wygląd.

## 2. Budżet i to, co już wiemy

- Quest 3: 72 Hz = **13,9 ms** na klatkę (90 Hz = 11,1 ms). GPU i CPU
  pracują równolegle - każdy z nich musi zmieścić się w budżecie osobno.
- Ostatnie pomiary (HANDOVER sekcja 5): odcinek 10 - 56 kl./s, GPU
  13,6 ms; **odcinek 9 - GPU 35-65 ms przez dłuższą chwilę** (podejrzany
  tunel albo ulewa); gogle się grzeją. Po zmianach z sesji 3 (fizyka
  120 Hz, promień zamiast sfery, cienie 2 strefy/80 m, `normal_dist`)
  **nie ma nowych pomiarów na Queście**.
- Rozdzielczość domyślna 160% (`SETTINGS_VERSION` 4), MSAA 2x, foweacja
  dynamiczna, anizotropia 4x. Przy 160% obraz na oko to 2688×2816, czyli
  ~15 mln pikseli na klatkę na oba oczy - każdy shader pikseli płaci za to
  ~1,5× więcej niż przy 130%.
- Wniosek: **wąskim gardłem jest GPU** (piksele: shadery, światła,
  przezroczystość) i **szarpnięcia CPU** (tworzenie węzłów w trakcie jazdy).
  Średnie ms/s z `Perf` nie pokazują szarpnięć - stąd etap 0.

## 3. Gorące punkty - ranking

Kolumny: **W** - wpływ (szacunek), **R** - ryzyko dla fizyki/wyglądu,
**P** - praca (S/M/L). G = GPU, C = CPU, A = architektura.

| # | Gdzie | Problem | Poprawka | W | R | P |
|---|---|---|---|---|---|---|
| G1 | `stunt_track.gd:1188` `_build_tunnel` | `OmniLight3D` co 80 m (×2 w tunelu dwunitkowym) oświetla **jedną wielką siatkę tunelu**. Renderer mobile wybiera światła per obiekt (do 8), więc każdy piksel rury, jezdni i góry liczy wszystkie światła tunelu. Najlepszy kandydat na GPU 35-65 ms w odcinku 9. | Bez prawdziwych świateł. Pomysł użytkownika: lampy gęsto (co 2 m, po 1 m) jako **same paski emisyjne** w jednej siatce (wygląd, prawie darmowe) + oświetlenie ścian i jezdni w shaderze tunelu: przy gęstych lampach prawie stała jasność z lekkim falowaniem co 2 m (`UV.y`). Auta w tunelu: ciepłe światło z góry jako parametr materiału (z `roof` próbki). Zero `OmniLight3D`. (Prawdziwe światła co 2 m byłyby dużo gorsze: limit 8 na obiekt, migotanie.) | duży | wygląd: niskie | M |
| G2 | `shaders/road`, `ground`, `shale`, `ocean`, `concrete` | Szum liczony w pikselu: `vnoise` = 4× `sin` haszujący. Jezdnia 4 szumy + 3× `exp/pow`; ziemia 5; łupek do ~10; ocean 9 (×4 hasze, `cull_disabled`); beton 3 szumy 3D (×8 haszy). Jezdnia i ziemia pokrywają większość ekranu. Do tego `sin` z dużych współrzędnych świata traci dokładność po kilku km. | Jedna mała, powtarzalna tekstura szumu (np. 256², 4 oktawy w RGBA) generowana w kodzie przy starcie (`NoiseTexture2D`/`FastNoiseLite` z silnika - bez pobierania) - 1-2 odczyty zamiast kilkunastu `sin`. Współrzędne szumu brać z UV jezdni / `fract` dystansu, nie z surowego `wpos`. | duży | wygląd: trzeba porównać zrzuty | M |
| G3 | `shaders/rock.gdshader` | Mapowanie trójpłaszczyznowe: do 3 rzutów × (albedo + normalna) + tyle samo dla mchu = **do 12 odczytów z anizotropią** + 2 szumy, na ścianach wąwozu, które w wąwozie zajmują pół ekranu. | Ściany wąwozu mają naturalne UV: dystans wzdłuż toru × długość łuku profilu (`_canyon_profile`). Liczyć je przy budowie → 1 odczyt albedo + 1 normalnej; maska mchu w kolorze wierzchołka (strona "północna" znana przy budowie). Trójpłaszczyznowe tylko dla góry nad tunelem, albo dwupłaszczyznowe. | duży | wygląd: średnie | M |
| G4 | `xr_main.gd:830` `_build_mirror` | Lusterko to **drugi pełny render sceny** (SubViewport 256×80) co 2. klatkę: wszystkie obiekty, mgła, niebo i najpewniej osobny przebieg cieni słońca. Koszt CPU (przygotowanie draw calli) i GPU niezależny od małej rozdzielczości. | Najpierw zmierzyć (przełącznik A/B). Potem: `cull_mask` kamery lusterka tylko na warstwy jezdni i aut, `far` 150 m, aktualizacja co 3. klatkę; opcja w menu. | średni-duży | wygląd lusterka | S |
| G5 | `stunt_track.gd:732` `_build_canyon`, `_build_tunnel`, `_build_highway` | Cienie rzucają wszystkie siatki, także ogromne: ściana wąwozu z płaskowyżem 300 m w bok, góra nad tunelem, nasyp autostrady, znaki. Przy jednej siatce na kawałek toru cały kawałek trafia do obu stref cieni i do głównego przebiegu (słabe odrzucanie po AABB). | Płaskowyż i górę jako osobne siatki z `cast_shadow = OFF`; ściany pocięte na kawałki ~60 m (lepsze odrzucanie poza kadrem i w cieniach); znaki i drobiazgi bez cieni dalej niż kilkadziesiąt m (`visibility_range`). | średni | wygląd: niskie | M |
| G6 | `stunt_car.gd` (boty), `stunt_track.gd:973` znaki | **Liczba draw calli**: każdy bot to ~25-30 powierzchni (9 grup wgnieceń, koła po 3 materiały, lusterka, spojlery...), do 20 botów, także te "na szynie" 400 m dalej. Każdy znak to 3-5 `MeshInstance3D` + `Label3D`; tablice kierujące co 12 m na łukach; każdy znak tworzy **własne** `BoxMesh`/`CylinderMesh` (24 segmenty). | Boty: `visibility_range_end` ~150-200 m dla szczegółów, a dalej jedna prosta bryła (1 draw call, wspólny materiał w kolorze lakieru przez `instance_shader_parameter`). Znaki: wspólne zasoby siatek (cache po rozmiarze), tablice kierujące i słupki jako `MultiMesh` na kawałek toru, `visibility_range` na znakach. | średni | brak | M |
| G7 | `xr_main.gd:1391` `_build_rain` | 1000 przezroczystych smug (alpha blend, billboard) - nakładanie się pikseli przy 160% w obu oczach. Deszcz jest jednym z dwóch podejrzanych o odcinek 9. | Zmierzyć osobno (A/B). Mniej, dłuższych smug tylko w stożku widzenia; `ALPHA_SCISSOR` zamiast blend, jeśli wygląda znośnie. | średni | wygląd deszczu | S |
| G8 | `stunt_car.gd:541` przezroczystość kokpitu | W kokpicie wszystkie materiały karoserii są w trybie `ALPHA_DEPTH_PRE_PASS` (podwójny przebieg) i zajmują dużą część obrazu tuż przed oczami. | Tylko pomiar (ustalenie użytkownika, nie zmieniamy bez zgody). Możliwa optymalizacja: przezroczyste tylko maska/deska/podłoga, reszta nieprzezroczysta. | niski-średni | wygląd | S |
| C1 | `xr_main.gd:494` `_spawn_bot`, `:466` `queue_free`, `explosion.gd` | **Tworzenie węzłów w trakcie jazdy**: nowy bot = `StuntCar.new()` + `_build_body()` - ~35 podzielonych `BoxMesh` (oczko 0,15 m) przepisywanych wierzchołek po wierzchołku w GDScripcie do siatek wgnieceń (rzędu 10 tys. wierzchołków), nowe materiały, generowanie WAV klaksonu (`bot_driver.gd:407`) - co 2-6 s. Usunięcie bota i wybuch (9 brył, cząsteczki, nowe materiały) też w jednej klatce. Pierwsze użycie nowych materiałów = kompilacja shaderów = szarpnięcie. | Pula botów jak `_oncoming_pool` (ukryj/wyłącz zamiast `queue_free`). Szablon siatki sedana liczony raz (statycznie) - bot kopiuje gotowe `Packed*Array` (kopia pamięci zamiast pętli). Klakson: jeden wspólny `AudioStreamWAV`. Wybuch: pula 1-2 gotowych wybuchów. Rozgrzewka shaderów przy wczytaniu sceny (wybuch, deszcz, morze, znaki narysowane raz poza kadrem); sprawdzić "shader baker" przy eksporcie (Godot 4.5+). | duży (szarpnięcia) | brak | M |
| C2 | `stunt_track.gd:153` `build`, `endless_track.gd:99` | Budowa kawałka: próbki + cała jezdnia (`SurfaceTool`) + `ConcavePolygonShape3D` w **jednej klatce**; ściany wąwozu w jednym kawałku z `generate_normals()`; usunięcie starego kawałka (setki węzłów, kształty kolizji) w jednej klatce. Średnio 15 ms/s, ale szczyty nieznane. | Dane geometrii liczone w wątku (`WorkerThreadPool`: same tablice, bez węzłów), na głównym tylko utworzenie siatek i ciał. `ArrayMesh` z gotowych tablic zamiast `SurfaceTool` (normalne znane analitycznie). Usuwanie kawałka partiami po kilka węzłów na klatkę. | duży (szarpnięcia) | kolizja jezdni musi być gotowa przed autem - jak dziś | L |
| C3 | `stunt_track.gd:318` próbki | Każda próbka toru (co 1 m) to `Dictionary` z ~16 kluczami tekstowymi. Każde zapytanie to szukanie po kluczach; `samples_from` kopiuje wycinek tablicy (boty co 0,15 s ~195 elementów, auta z naprzeciwka 2 zapytania na krok fizyki, ostrzeżenia co 0,3 s 250 elementów, HUD co 0,25 s). `is_gap_at`, `last_gap_end_before`, `runup_start_before`, `services()` przeglądają liniowo wszystkie próbki. | Klasa `TrackPath` (czysta logika): `PackedVector3Array` pos/fwd/right/up, `PackedFloat32Array` width/limit/dist, `PackedByteArray` flag (gap/roof/rain/surface), meta rzadko w osobnym słowniku indeksów. API po indeksie (`index_at(dist)` binarnie, `pos(i)`...), przerwy i zjazdy jako posortowane listy przedziałów. Zob. sekcję 6 (graf sekcji). | średni | brak (czysty refaktor) | L |
| C4 | `bot_driver.gd:87` `_drive_step` | Na każdy krok fizyki (120 Hz) każdego bota z fizyką: liniowe szukanie najbliższej próbki w całym oknie (~195 słowników), `_calm_speed` i `_curve_speed` przeglądają okno z `angle_to` i `sqrt`, `set_rage_lights` zapisuje materiał co krok także przy szale 0. | Szukanie od ostatniego indeksu (bot przesuwa się o <1 próbkę na krok). **Profil prędkości toru** liczony raz przy budowie kawałka: v_max z krzywizny i przyczepności, potem przejście wstecz z drogą hamowania (v² = v_next² + 2·a·ds) - wtedy `_calm_speed`/`_curve_speed` to jeden odczyt. Światła szału tylko przy zmianie. Sterowanie, nie fizyka - porównać `bot_rage_test`. | średni | zachowanie botów: niskie | M |
| C5 | `stunt_car.gd:622` `_physics_step` | Drobne alokacje w kroku fizyki każdego auta: `dirs` (tablica tablic), `fx_sum`/`fy_sum`, słownik z `intersect_ray`, `get_meta` ciała i `TIRE_COMPOUNDS[tires].get(...)` na każde koło co krok. | Pola klasy zamiast tymczasowych tablic, przyczepność nawierzchni z cache po `collider_id`. **Wynik testów jazdy musi być identyczny co do cyfry.** | niski-średni | fizyka: tylko czysty refaktor | S |
| C6 | `car_audio.gd:125` `_synth` | Synteza próbka po próbce w GDScripcie: ~22 tys. iteracji/s z kilkoma `sin`, `tanh`, `randf`; nowy bufor co klatkę. Szacunek z PC: 5-6% rdzenia Questa. | Najpierw licznik `dzwiek` z gogli. Potem: tablice falowe (odczyt zamiast `sin`), bufor jako pole klasy, ewentualnie GDExtension (wymaga godot-cpp - nie pobieramy bez zgody). | niski-średni | brzmienie | M |
| C7 | różne, co klatkę / co krok | `_race_label.text` formatowany w `update_race` **co krok fizyki** (`xr_main.gd:587`); `dash_label` i `PackedStringArray` co klatkę (`stunt_car.gd:1367`); `Gauges._set_zone` - `"w%d" %` i zapis materiału co klatkę; `_update_wipers` - `get_node_or_null` + 4× `set_shader_parameter` co klatkę także na sucho; `_bots.duplicate()` + `get_node("Driver")` co krok; `$Ground/GroundMesh` co klatkę. | Aktualizacja tylko przy zmianie wartości, napisy w `_process` (nie w kroku fizyki), referencje w polach. Proste i bez ryzyka. | niski (razem średni) | brak | S |
| C8 | `explosion.gd`, `scenery.gd:148` | `add_collision_exception_with` 9 odłamków × (gracz + wszystkie boty); `Scenery._too_close` przegląda próbki dla każdego drzewa (tylko tor na filarach). | Odłamki na osobnej warstwie kolizji (maska zamiast wyjątków); `_too_close` po indeksie próbki. | niski | brak | S |
| A1 | cała trasa | Po kilkunastu km auto jest daleko od początku świata: `float` w Jolt i w shaderach (`wpos`) traci dokładność - drgania, migotanie szumu. To nie wydajność, ale jakość fizyki przy graczu. | Przesuwanie początku świata przy granicy kawałka (wszystkie węzły i ciała o ten sam wektor). Po C3 i sekcji 6. | - | średnie | L |

### Czego nie ruszamy (świadomie)

- Fizyka botów w promieniu `LOD_NEAR` (pełny model, 2 podkroki, promień
  do podłoża) - to boty, które zderzają się z graczem.
- `contact_monitor` i CCD aut - potrzebne do wgnieceń, szału i do tego,
  żeby szybkie auto nie przeleciało przez barierę.
- 120 Hz fizyki - zmiana tylko na wyraźną prośbę użytkownika.

## 4. Plan pomiarów (agent lokalny, gogle)

### Etap 0 - instrumentacja (przed jakimkolwiek refaktorem)

1. `Perf` z maksimum: obok sumy ms/s także **najdłuższe pojedyncze
   wywołanie** w oknie 5 s (`PERF+ ms/s` → `klucz suma/maks`).
2. **Histogram klatek** w `_log_perf`: liczba klatek > 13,9 ms, > 20 ms,
   > 33 ms, najdłuższa klatka i co się w niej działo (znaczniki zdarzeń:
   `bot_spawn`, `bot_free`, `chunk_build`, `chunk_free`, `explosion`,
   `first_sea`, `tunnel_enter`).
3. Do linii `PERF:` dopisać z `Performance`: `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`,
   `RENDER_TOTAL_OBJECTS_IN_FRAME`, `RENDER_TOTAL_PRIMITIVES_IN_FRAME`,
   `RENDER_VIDEO_MEM_USED`, `OBJECT_NODE_COUNT`,
   `PHYSICS_3D_ACTIVE_OBJECTS`, `PHYSICS_3D_COLLISION_PAIRS`.
4. **Przełączniki A/B** (np. grupa "dev" w `GameSettings` albo argument
   `--perf-ab=mirror,rain,tunnel_lights,shadows,rock_simple`), wypisywane
   w logu przy starcie, żeby każdy pomiar był opisany.
5. Logi systemu gogli (bez pobierania czegokolwiek):
   `adb logcat -s VrApi` - linia co sekundę z FPS, `Stale` (zgubione
   klatki), `GPU%`, `CPU%`, poziomy CPU/GPU; jeśli w systemie gogli jest
   `ovrgpuprofiler`, także jego metryki GPU. Sprawdzić, czy jest - nie
   instalować bez zgody użytkownika.

### Przejazd porównawczy

Żeby pomiary były porównywalne, potrzebny jest powtarzalny przejazd:
**stałe ziarno, auto gracza prowadzone przez `BotDriver`** (jak na ekranie
tytułowym), głowa nieruchomo, ten sam start. Proponowany tryb
`--bench=<scenariusz>` w scenie jazdy, 60-90 s na scenariusz:

| scenariusz | co | po co |
|---|---|---|
| S1 wąwóz | odcinki 1-3, sucho, 4-6 botów | baza: skała, jezdnia, cienie |
| S2 tunel | odcinek z tunelem dwunitkowym (ziarno dobrane tak, żeby był) | G1 |
| S3 ulewa | S1 z wymuszonym `rain = 2` | G7, wycieraczki |
| S4 autostrada | odcinek 5, auta z naprzeciwka, limit botów wymuszony na 20 | G6, C1, C3, C4 |
| S5 zdarzenia | 3 wybuchy botów, pierwsze okno na morze, wjazd w nowy kawałek | szarpnięcia C1, C2, kompilacja shaderów |
| S6 PC headless | istniejący pomiar: 20 botów (16 na szynie), czas kroku fizyki | szybka weryfikacja C3-C5 bez gogli |

Każdy scenariusz: **przy 130% i 160%**, z lusterkiem i bez. Wynik:
średnie kl./s, % klatek ponad budżet, GPU ms (średnia i p95), proces
i fizyka ms, `PERF+` (suma/maks), draw calle, prymitywy, linia VrApi.

### Raport

Agent lokalny zapisuje wyniki w `docs/agent/outbox/` (tabela: scenariusz ×
ustawienie → liczby, plus surowe linie `PERF`), a skrót w HANDOVER sekcja 5.
Na tej podstawie ustalamy ostateczną kolejność prac z sekcji 5.

### Kryteria akceptacji zmian

- GPU: brak klatek ponad budżet w S1-S4 przy wybranej rozdzielczości;
  S2 (tunel) i S3 (ulewa) nie gorsze niż S1 o więcej niż ~2 ms GPU.
- CPU: żadna klatka > 33 ms w S5; `bot_ster` + `boty_mgr` < 30 ms/s przy
  20 botach.
- Fizyka: testy jazdy z sekcji 1 - identyczne liczby (czysty refaktor)
  albo opisane różnice (zmiana zachowania botów).

## 5. Kolejność prac (propozycja)

Każdy punkt to osobny, mały PR z pomiarem przed/po.

1. **Etap 0** - instrumentacja + tryb `--bench` (agent lokalny). Pomiar
   bazowy przy 130% i 160%.
2. **Szybkie, bezpieczne** (po pomiarze, jeśli potwierdzi): G1 światła
   tunelu w shaderze, G4 tańsze lusterko, G5 flagi cieni, C7 drobne
   aktualizacje "tylko przy zmianie", C4 część 1 (szukanie od indeksu,
   światła szału).
3. **Szarpnięcia**: C1 pula botów + szablon siatki + rozgrzewka shaderów,
   C2 część 1 (usuwanie kawałka partiami, `ArrayMesh` z tablic).
4. **Shadery**: G2 tekstura szumu, G3 UV ścian wąwozu - z porównaniem
   zrzutów ekranu (`tests/screenshot.gd`) przed/po dla użytkownika.
5. **Architektura**: C3 `TrackPath` + graf sekcji (sekcja 6), C4 część 2
   (profil prędkości), C2 część 2 (budowa w wątku).
6. **Później**: C6 dźwięk, C5 mikro-alokacje w fizyce (tylko z identycznymi
   testami), A1 przesuwanie początku świata, G6 uproszczone boty w oddali.

Podział pracy (jak w `docs/agent/README.md`): chmura może napisać
odizolowane moduły z testami headless - `TrackPath` (dane + wyszukiwanie),
profil prędkości, generator tekstury szumu, nowe wersje shaderów; agent
lokalny wpina je w gorące pliki, uruchamia testy i mierzy na goglach.

## 6. Architektura: tor jako graf sekcji

Dziś cały kod zakłada **jeden liniowy dystans `dist`** (`nearest_sample`,
`transform_at_distance`, punkty kontrolne, szyna botów, HUD, dźwig).
To blokuje rozwidlenia (nitki w tunelach z `docs/VISION.md`) i boczne
ulice w mieście. Refaktor C3 jest dobrym momentem, żeby to zmienić, bo
i tak zmienia sposób przechowywania próbek.

- **`TrackPath`** - jeden ciągły kawałek drogi bez rozgałęzień: tablice
  `Packed*` z sekcji 3 (C3), własny dystans od 0, profil prędkości (C4).
- **`TrackSection`** (dzisiejszy `StuntTrack` jako węzeł z geometrią) ma
  jedną lub kilka ścieżek: główną i nitki od rozwidlenia do połączenia.
- **Graf**: sekcje mają następniki (1 albo więcej); rozwidlenie = sekcja
  z dwoma następnikami. Generowane jest tylko to, co osiągalne w zasięgu
  `AHEAD`; gałąź, której gracz nie wybrał, jest **przycinana** zaraz po
  minięciu rozwidlenia (oszczędność pamięci i budowy).
- **Pozycja na trasie** zamiast liczby: `(path_id, s)` - auto gracza,
  boty, punkty kontrolne i dźwig pamiętają ścieżkę i dystans na niej.
  Wynik/HUD dalej pokazuje łączny przebyty dystans (suma po przejechanych
  ścieżkach).
- `EndlessTrack` zostaje fasadą z tym samym API dla starego kodu
  (`dist` liczony wzdłuż aktualnie wybranej gałęzi), więc migracja może
  iść stopniowo: najpierw `TrackPath` bez rozwidleń (czysty refaktor,
  identyczne testy), potem graf.

To nie jest optymalizacja sama w sobie, ale ta sama zmiana danych daje
oba efekty - dlatego jest w tym planie. Szczegóły rozwidleń ustala wątek
od tuneli/miasta; tu tylko warunek: API po indeksie i ścieżce, nie po
globalnym `dist`.

## 7. Pytania do użytkownika

1. Odświeżanie: celujemy w **72 Hz czy 90 Hz**? (90 Hz to budżet 11,1 ms.)
2. Czy domyślne **160%** jest nienaruszalne, czy po pomiarze możemy zejść
   (np. 140% + mocniejsza foweacja), jeśli to jedyny sposób na płynność?
3. Lusterko: czy może pokazywać tylko jezdnię i auta (bez ścian i znaków)
   i odświeżać się rzadziej?
4. Deszcz i skała: zgoda na delikatną zmianę wyglądu (mniej smug, inny
   sposób nakładania tekstury) - z porównaniem zrzutów przed decyzją?
5. Dźwięk: czy w razie potrzeby wolno przejść na tablice falowe albo
   GDExtension (wymaga godot-cpp - jeśli nie ma go na dysku, trzeba by go
   pobrać)?
