# Przegląd wydajności - 2026-11-11 (noc)

Zlecenie użytkownika: przejrzeć cały kod, znaleźć wąskie gardła wydajności,
zaproponować rozsądne rozwiązania i zrobić refaktoring w duchu DRY.

Założenia od użytkownika:
- **Auto gracza zawsze zgodnie z fizyką.**
- **Boty mogą "oszukiwać"**, gdy gracz ich nie widzi, albo gdy odstępstwo
  od fizyki (np. prędkość) mieści się w **7%**.
- **Wyjątek: bot uderzony przez auto gracza zawsze zachowuje bezwładność
  i reakcję na zderzenie zgodną z fizyką** ("chodzi o odczucie gry").

## Pomiar na Queście 3 (bench S4 - autostrada, 75 s, rozdzielczość 130%)

Bench: `tools/bench_quest.sh WYNIK.txt "S4:130:"`. Gogle muszą mieć
wstrzymanego Guardiana (`adb shell setprop debug.oculus.guardian_pause 1`),
inaczej start gry blokuje okno granic strefy (pułapka w HANDOVER).

| | Przed (b7869af) | Po (pule aut, 060d7d6) | Po, 110% |
| --- | --- | --- | --- |
| kl./s (śr., VrApi) | 59,7 | 59,7 | **71,9** |
| GPU (gra) | 15,0 ms | 15,6 ms | 11,9 ms |
| najdłuższa klatka | 92 ms | 54 ms | 55 ms |
| `hud` śr. / maks | 27,5 / 8,9 ms | 9,0 / 3,0 ms | |
| `bot_ster` śr. | 41,8 | 24,2 | |
| `trasa` śr. / maks | 16,6 / 5,0 ms | 2,0 / 0,9 ms | |
| `boty_mgr` śr. / maks | 38,8 / 181 ms | 24,3 / 23 ms | |
| `auto_fiz` śr. | 48,8 | 59,9 | |

Średnie w ms na sekundę, bez dwóch pierwszych pomiarów (rozruch).
Lusterko wyłączone (A/B): +1 kl./s - nie ono ogranicza GPU.
`auto_fiz` +11 ms/s: odzysk koło po kole i przenoszenie na przód
(ustawienia użytkownika: elektryk w kołach) - do zbadania przy
porządkach fizyki gracza (propozycja 3).

Rozkład procesora przed (ms na sekundę, suma / najdłuższy pojedynczy):
`auto_fiz 48/1,7`, `bot_ster 41/1,7`, `hud 28/8,5`, `boty_mgr 22/7,1`,
`bot_wyg 19/4,8`, `trasa 17/4,6`, `dzwiek 15/1,1`, `auto_wyg 7/0,8`.

**Wniosek**: przy 130% gogle są ograniczone głównie przez **GPU**
(16 ms przy budżecie 13,9 ms na 72 kl./s). Poprawki procesora zmniejszają
skoki (krótkie przycięcia), ale do stałych 72 kl./s przy 130% trzeba też
odciążyć GPU (lusterko, cienie) albo zejść z rozdzielczością.

## Zrobione tej nocy (bez zmiany zachowania)

1. **Mapka trasy (`hud`, skoki do 20 ms w jeździe użytkownika)**:
   `samples_from(dist, length, stride)` w `StuntTrack` i `EndlessTrack`
   zwraca co `stride`-tą próbkę plus wszystkie ze znacznikami (`_meta_idx`,
   liczone raz na kawałek). Mapka: ~1500 kopii słowników 4 razy na sekundę
   -> ~200. Ostrzeżenia (`_update_warning`): krok 4 m.
2. **Usługi na trasie (`trasa`)**: `StuntTrack.services()` co 0,2 s
   przechodziło po wszystkich próbkach wczytanej trasy - teraz tylko po
   próbkach ze znacznikami (ten sam `_meta_idx` - DRY) i wynik
   zapamiętany na kawałek.
3. **Boty (`bot_ster`)**:
   - profil prędkości okna (`_prof`) liczony raz przy odświeżeniu okna
     (co 0,15 s); `_calm_speed` i `_curve_speed` - dwie prawie identyczne
     pętle po słownikach co krok - czytają wspólny profil (DRY);
   - najbliższa próbka szukana lokalnie od poprzedniej (było przeszukanie
     ~195 próbek co krok);
   - światła szału zapisywane tylko w szale albo przy wygaszaniu (było:
     2 materiały co krok każdego bota).
4. **Wygląd botów (`bot_wyg`)**: wycieraczki i krople na szybie tylko
   u gracza (u botów co klatkę 4 parametry shadera + szukanie węzła);
   światło stopu zapisywane tylko przy zmianie.
5. **Zegar jazdy**: napis co 0,1 s (dziesiąte sekundy) zamiast co krok
   fizyki z setnymi - Label3D przebudowywał siatkę tekstu co klatkę.
   Zmiana stanu wyścigu odświeża od razu.
6. **Biom (paleta ziemi, horyzont, morze)**: 5 razy na sekundę
   (`_watch_track`) zamiast co klatkę; nad morzem co klatkę było
   szukanie najbliższej próbki.
7. **Klakson**: jeden dźwięk na grę (`BotDriver._make_horn` - był
   generowany w GDScript dla każdego nowego bota, 8820 próbek).
8. **`get_node("Driver")` ~25 razy w xr_main** (także w komparatorach
   sortowania) -> `StuntCar.driver` + `XrMain._drv(b)` (DRY).
9. **Zasada fizyki przy zderzeniu**: auta z naprzeciwka jeżdżą po szynie
   jako ciała kinematyczne - dla gracza były ścianą o nieskończonej masie.
   Teraz bliżej niż 5,5 m od gracza przechodzą na pełną fizykę z tą samą
   prędkością (`_loosen_oncoming`; scenka na drugiej jezdni się kończy),
   do puli po 30 s albo 400 m. Test `oncoming_loose_test`.
   Boty na naszej jezdni już spełniały zasadę: w pobliżu gracza (LOD NEAR,
   120 m) i w szale z żetonem jadą fizycznie.

10. **Pule aut przy wczytywaniu**: nowe auto (bot, z naprzeciwka) to
    ~170 ms jednej klatki na Queście (na PC 6-8 ms) - skoki co 30-40 s.
    `BOT_POOL_WARM` 14 (było 6), nowa pula aut z naprzeciwka
    (`ONCOMING_POOL_WARM` 8, `_new_oncoming_car` - jeden sposób
    tworzenia, DRY), odrodzenie oddaje auta do puli zamiast je niszczyć.
11. **Porządki DRY**: `StuntTrack.lane_width` (6 kopii wzoru),
    `XrMain._explode` (3 kopie), `BotDriver.horn_on` (3 kopie; przy okazji
    wyciek - każdy nowy kierowca bota dokładał autu z puli kolejny
    odtwarzacz klaksonu), usunięty nieużywany `Gauges.set_limit`.

## Propozycje (nie zrobione - do decyzji albo na następne sesje)

Kolejność: zysk / ryzyko.

1. **Lusterko wsteczne (GPU)**: SubViewport renderuje całą scenę co drugą
   klatkę, z cieniami słońca. Zmierzyć A/B (`"S4:130:mirror"`), potem:
   `far` 150 m, maska warstw bez scenerii, co 3.-4. klatkę, bez cieni.
2. **Dźwięk (`dzwiek` 15-21 ms/s)**: synteza w GDScript próbka po próbce
   (22050 Hz, kilka `sin`/`fmod`/`tanh` na próbkę). Tablica sinusa
   i szumu albo 11025 Hz - połowa kosztu, bez zmiany charakteru;
   docelowo zapętlone próbki z `pitch_scale`.
3. **Fizyka auta gracza (`auto_fiz` ~0,4 ms na krok, 120 Hz)**: bez
   zmiany fizyki - mniej alokacji na krok (`dirs`, `fx_sum`), stałe
   (`tan(peak_slip_angle)`) liczone przy zmianie parametrów, flagi napędu
   zamiast porównań napisów w pętli kół. Zysk ~10-20%, ryzyko małe.
4. **Budowa kawałka trasy co ~1 km**: kroki `_build_mesh`,
   `_build_road_collision`, `_build_highway` po `await` nie są mierzone
   (Perf) - najpierw pomiar, potem dzielenie albo WorkerThreadPool.
5. ~~Auta z naprzeciwka: `_oncoming_xf` po szerokość~~ - **odrzucone**:
   szerokość naszej jezdni zmienia się przy zjazdach i w miastach, a od
   niej zależy położenie drugiej jezdni; koszt to 2 kopie próbek na auto.
6. **Ruch (TrafficZone, co 0,5 s)**: `wanted()` 2x po 18 punktów, każdy
   `nearest_city` alokuje słowniki - zapamiętać `city(n)`.
7. **Boty na szynie poza wzrokiem w 7%**: obecny podział LOD
   (NEAR 120 m fizyka / MID 30 Hz / RAIL) mieści się w zasadzie
   użytkownika. Można dalej: bot MID poza stożkiem widzenia też na szynę,
   prędkość szyny ograniczona do ±7% prędkości, jaką miałby fizycznie.
8. **Krok fizyki 120 Hz przy 72 Hz obrazu**: 1-2 kroki na klatkę; 90 Hz
   zmniejszyłoby koszt fizyki o 25%, ale zmienia prowadzenie - tylko po
   rozmowie z użytkownikiem (realistyczna fizyka).

## Powielenia (DRY) - zostały

- 5 implementacji "najbliższej próbki" (StuntTrack, EndlessTrack, okno
  BotDriver, TrackPath, bezpośrednie wywołania w xr_main) - docelowo
  `TrackPath` (gotowy, nieużywany).
- Pas ruchu `(width - 1.0) / 3.0` w 6 miejscach; trzy wzory pasów
  autostrady (`HighwayGenerator.lane_center`, `hwy_lane_off`,
  `OncomingSkirmish.hwy_from_median`).
- Cykl życia bota i auta z naprzeciwka: dwie pule, dwa `spawn`, dwa
  `park` (różne: bot ma kierowcę i fizykę, auto z naprzeciwka jedzie po
  szynie) - wspólna mogłaby być klasa puli.
- Sygnały dźwiękowe generowane trzema funkcjami (`_make_chirp`,
  `_make_beep`, `_make_horn`) - różne kształty, wspólny byłby tylko zapis
  WAV.
