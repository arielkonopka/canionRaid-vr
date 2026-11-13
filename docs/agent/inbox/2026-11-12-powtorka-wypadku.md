Status: zrobione (2026-11-13), do oceny w goglach
Od: wątek w chmurze "Dodaj powtórkę wypadku z kamery obserwatora"
Decyzje użytkownika (2026-11-12 19:08, dosłownie): "jeśli gracz zginął
w wypadku, to robimy powtórzone ujęcie, z tym, że gracz jest obserwatorem
podążającym za samochodem, trochę z góry...". Reszta (kiedy, jak długo,
zwolnienie, przycisk pominięcia) to propozycja chmury - do oceny
w goglach, użytkownik może zmienić.

# Powtórka wypadku z kamery obserwatora

Dotyczy HANDOVER sekcja 9 pkt 6 ("Powtórki - nie ustalono nic"): to jest
pierwsze ustalenie. Po wpięciu przenieś do odpowiednich sekcji.

## Co gracz widzi

1. Wypadek kończy się utratą życia (patrz "Kiedy" niżej).
2. Krótkie zaciemnienie 0,2 s (cięcie z kokpitu na zewnątrz), świat
   zamiera.
3. **Powtórka ostatnich ~6 s**: gracz stoi (XROrigin) za autem i trochę
   nad nim, kamera jedzie za autem. Głowa wolna - gracz może się
   rozglądać. Na auto patrzy z zewnątrz, w środku widać **całego
   manekina gracza** (z głową) z rękami i stopą tak, jak grał.
4. Wokół **kluczowej chwili** (najmocniejsze uderzenie) zwolnienie
   do 0,35×. Napis w stylu kasety wideo "● POWTÓRKA" (czerwona kropka
   miga) w dolnej części pola widzenia.
5. Powtórka kończy się dokładnie w chwili śmierci, świat rusza
   i **wybuch dzieje się na żywo** - oglądany z tego samego miejsca
   (bez obecnego odjazdu kamery `_cinematic`, kamera już jest na
   zewnątrz). Dalej jak dziś: `_after_explosion`, odrodzenie albo
   `_game_over` (powtórka także przy ostatnim życiu).
6. Spust albo B = pomiń powtórkę (od razu krok 5). Zgodnie z zasadą
   "spust zatwierdza, B wraca".

## Kiedy

Powtórka tylko przy śmierci w wypadku: `auto rozbite`, `auto na dachu`,
`upadek`. **Bez powtórki**: `nowe auto` (klik drążka, decyzja gracza),
`brak paliwa`, `utknięcie`. Opcja w menu pauzy, grupa z kamerą/rozgrywką:
"Powtórka wypadku: wł / wył" (domyślnie wł).

Uwaga: "na dachu" i "upadek" wykrywane są 1,5 s po zdarzeniu
(`_fallen_time > wait`), więc okno powtórki musi sięgać wstecz z zapasem
- stąd 6 s, a zwolnienie nie na końcu, tylko wokół kluczowej chwili.

## Kluczowa chwila i tempo

- Kluczowa chwila = próbka z największym impulsem uderzenia w oknie
  (`car.last_hit["j"]`, zapisywane do bufora przy każdej zmianie
  `last_hit`). Gdy w oknie nie ma uderzenia > ~2000 N·s (np. zjazd
  z krawędzi), to ostatnie oderwanie wszystkich kół (`wheels_on_ground`
  > 0 -> 0).
- Odtwarzanie: 1× do (kluczowa - 0,5 s), 0,35× do (kluczowa + 1,0 s),
  potem 1× do końca. Płynne przejścia tempa (~0,2 s), nie skok.
- Długość okna: stała `REPLAY_WINDOW := 6.0` s; całość trwa ~8-9 s.
  Do oceny w goglach (jeśli za długo przy częstych śmierciach - 4 s).

## Kamera obserwatora (komfort VR)

Użytkownik nie ma choroby lokomocyjnej (HANDOVER), ale ruchoma kamera
w VR i tak warto trzymać spokojną, bo auto koziołkuje:

- **Tylko pozycja i obrót w poziomie (yaw)**, horyzont zawsze poziomy,
  bez przechyłu i pochylenia (jak w `_cinematic`: pion robi głowa).
- **Kierunek z trasy, nie z nadwozia**: yaw = styczna toru w najbliższej
  próbce (`track.nearest_sample`), wygładzana (~0,5 s). Gdy auto się
  kręci albo leci bokiem, kamera nie wiruje razem z nim.
- Pozycja: punkt 8 m za autem (wzdłuż stycznej) i 4 m nad jezdnią
  w tym miejscu, ale co najmniej 2,5 m nad autem (skok); sprężyna
  krytycznie tłumiona ~0,4 s, żeby nie powtarzać drgań auta.
  "Trochę z góry" = ok. 25° w dół na auto.
- Start: pierwsza klatka powtórki ustawia kamerę od razu na miejsce
  (po zaciemnieniu), bez dolatywania.
- **Tunel**: sufit - w tunelu (meta `tunnel_len` w próbce) 2,2 m nad
  jezdnią i 6 m za autem albo promień w górę od auta i zejście pod
  trafienie - jak uznasz za tańsze.
- Upadek w przepaść / do oceanu: kamera nie schodzi niżej niż
  jezdnia - 2 m; gracz patrzy w dół głową.
- Prędkość: przy 200 km/h kamera jedzie z autem jak w jeździe, to
  akceptowalne; zwolnienie i tak tnie prędkość.

## Zapis (nagrywanie)

Nowy, odizolowany `scripts/replay_recorder.gd` (`ReplayRecorder`, czysta
logika + test headless), wpięcie w `xr_main.gd`.

- **Bufor kołowy, bez alokacji w trakcie jazdy**: `PackedFloat32Array`
  przydzielony raz, indeks zapisu krąży.
- **Auto gracza, co 2 kroki fizyki (60 Hz)**: pozycja (3), kwaternion
  (4), na koło skręt / obrót / ugięcie (4×3 - to, co StuntCar ustawia
  na siatkach kół), `steering_wheel_deg` (1), gaz i hamulec (2, stopa
  manekina), kontrolery lewy/prawy w układzie auta (2×7, ręce manekina
  przez IK), obroty silnika i gaz do dźwięku (2), impuls uderzenia (1).
  ~45 liczb × 360 próbek = ~65 KB.
- **Boty i auta z naprzeciwka, 30 Hz**: do 8 najbliższych w 120 m,
  pozycja + kwaternion + skręt (8 liczb), identyfikator instancji na
  slot. Koła botów w powtórce kręcą się z prędkości (z różnicy pozycji),
  bez zapisu.
- **Przesunięcie świata (`WorldOrigin.apply`)**: bufor ma pozycje
  float32 w bieżącym układzie, więc przy przesunięciu odejmij `shift`
  od wszystkich zapisanych pozycji (jednorazowo, ~1000 wektorów).
  Bez tego powtórka po przesunięciu pokaże auto setki metrów obok.
- Koszt mierz `Perf.add("replay_rec", ...)` w linii PERF+. Oczekiwanie:
  rząd 10-30 µs na próbkę na Queście.
- Nagrywanie tylko w `Race.RACING` w trybie DRIVE; reset bufora przy
  `_restart_section` i odrodzeniu (powtórka nie może sięgać sprzed
  odrodzenia).

## Odtwarzanie

- Nowy stan `Race.REPLAY` przed `Race.EXPLODING`. W REPLAY `xr_main`
  nie liczy logiki jazdy: spawn botów, szał, paliwo, punkty, wykrywanie
  upadku, `ensure_ahead` - wszystko stoi.
- Auto gracza: `freeze = true`, transformacja i siatki kół z bufora
  (interpolacja liniowa pozycji, `slerp` kwaternionów - przy 0,35×
  i 60 Hz wystarczy). Auto **widoczne** (dziś `lose_life` od razu je
  chowa - chowanie przenieść do wybuchu).
- Boty i auta z naprzeciwka: zapamiętać stan żywy (transformacja,
  prędkości), wyłączyć z fizyki (`PROCESS_MODE_DISABLED`, jak w puli)
  i ustawiać transformacje z bufora. Bot nieobecny w danej próbce
  (np. wrócił do puli) - ukryty w tym czasie. Na końcu powtórki stan
  końcowy = chwila śmierci, więc wystarczy przywrócić prędkości
  i włączyć fizykę. Wybuchy botów i części karoserii w oknie pomijamy.
- Manekin gracza: cele IK rąk z zapisanych kontrolerów (w układzie
  auta), stopa z gazu/hamulca, **głowa i tułów widoczne** (dziś głowa
  schowana skalą kości w widoku z fotela), po powtórce z powrotem.
- Na czas powtórki: wyłączyć lusterko (`_mirror_vp` - oszczędność),
  ukryć HUD trasy, zegary zostają w aucie (to część deski).
- Dźwięk (etap 2, jeśli tanio): silnik z zapisanych obrotów i gazu,
  ton obniżony w zwolnieniu (w zwolnieniu brzmi "filmowo"), stuk
  `thud` w chwilach uderzeń z bufora. Radio gra dalej.

## Znane uproszczenia (świadomie)

- Wgniecenia i szyba: w powtórce auto ma **końcowe** uszkodzenia od
  początku okna (cofanie siatki wymagałoby kopii wierzchołków co
  chwilę). Jeśli użytkownik zauważy - etap 2: lista wywołań `dent`
  z czasem i jedna kopia siatki z początku okna.
- Iskry, dym, ślady opon nie są powtarzane.

## Testy (agent lokalny)

- `tests/replay_recorder_test.gd` (headless): bufor kołowy (zawinięcie,
  brak alokacji - stały rozmiar), interpolacja, przesunięcie świata,
  wybór kluczowej chwili (uderzenie / oderwanie kół), mapa tempa
  (czas powtórki -> czas zapisu, ciągła i monotoniczna).
- Test sceny: wymuszony `lose_life("auto rozbite")` po kilku sekundach
  jazdy z botami -> REPLAY -> EXPLODING -> RACING bez błędów, auto
  widoczne w REPLAY, pozycja w ostatniej klatce = pozycja śmierci;
  `lose_life("nowe auto")` - bez powtórki; pominięcie spustem.
- Zrzut z kamery obserwatora (jak `player_dummy_shot.gd`) - do oceny.
- Po wpięciu `tests/drive_test.gd` (zmiana w scenie jazdy), wynik do
  HANDOVER.

## Do oceny przez użytkownika w goglach

Odległość i wysokość kamery (8 m / 4 m), długość okna (6 s), siła
i miejsce zwolnienia, czy napis "● POWTÓRKA" nie przeszkadza.

## Odpowiedź agenta lokalnego

Zrobione (2026-11-13), wg specyfikacji, z tymi uwagami:

- `scripts/replay_recorder.gd` (`ReplayRecorder`): bufory przydzielone
  raz, gracz 40 liczb na klatkę (bez osobnego "gazu do dźwięku" -
  to ten sam gaz), do 8 aut po 8 liczb. Tempo: `speed_at` / `advance`
  (0,35x od klucza -0,5 s do +1,0 s, rampy 0,2 s). Kluczowa chwila:
  najmocniejszy impuls > 2000 N·s, potem ostatnie oderwanie wszystkich
  kół, a bez obu - sekunda przed końcem.
- **Pułapka**: zapis co 1/60 s w czasie gry wypada co drugi krok fizyki,
  więc pojedynczy krok z uderzeniem przepadał i klucz spadał na zapasowy.
  `xr_main._rec_hit` zbiera maksimum impulsu między klatkami zapisu.
  `StuntCar.hit_j` to najmocniejszy impuls bieżącego kroku (także z CCD).
  Przy tempie gry 110% okno ma ~6,6 s (362 klatki po 1/60 s czasu gry).
- Kamera: sprężyna 0,4 s **z prędkością celu**. Sama sprężyna wisiała
  2v/ω ≈ 22 m za autem przy 100 km/h (pierwszy zrzut: auto daleko
  w kadrze). Tunel: promień w górę od auta, kamera 0,6 m pod
  trafieniem i 6 m za autem. Na PC pochylenie 25°, w goglach sam yaw.
- Auto i boty ustawiane w kroku fizyki (`_replay_physics`), kamera
  w `_process`; ściemnienie 0,2 s to czarny quad przed kamerą. Boty
  nieobecne w danej chwili zapisu są ukryte, a na końcu wraca ich
  widoczność, tryb procesu i prędkości.
- Manekin: `PlayerDummy.set_replay(on)` pokazuje głowę i dłonie tułowia,
  ręce idą z zapisanych kontrolerów (`replay_hands`).
- Opcja "Powtórka wypadku" w grupie Trasa (wł./wył., na żywo).
- Nie zrobione (etap 2): dźwięk w powtórce (silnik stoi na wolnych
  obrotach; obroty są w zapisie) i obracanie kół botów z prędkości.
- Testy: `replay_recorder_test` 11/11, `replay_play_test` 12/12
  (REPLAY 9,1 s -> EXPLODING -> RACING, boty wyłączone i z powrotem,
  wybuch w miejscu śmierci, "nowe auto" bez powtórki, spust pomija po
  0,61 s). Oba w `quest.sh test`; pełny zestaw OK. `drive_test` dla
  wszystkich zawieszeń i skrzyń bez zmian (24.00-24.17).
- Zrzuty: `tests/replay_shot.gd` -> `renders/2026-11-13-powtorka/`
  (przed, uderzenie w zwolnieniu, po, wybuch; OPIS.md).
