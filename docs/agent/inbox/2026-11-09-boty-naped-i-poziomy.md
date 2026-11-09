# Boty: uproszczony napęd + poziomy szczegółowości (LOD) + budżet fizyki

Status: wpięte (czeka na jazdę z użytkownikiem)
Od: wątek w chmurze "Zaprojektuj nowe strategie botów road rage" (2026-11-09)
Decyzje użytkownika (2026-11-09):
- Oszukiwać wolno **tylko u botów**; fizyka gracza zostaje.
- U botów: "wszystko co się da", byle gracz miał względnie realistyczne
  doświadczenie **przy zderzeniach i skokach**; **5% różnicy prędkości nie
  przeszkadza**; dalej od gracza bot może się upraszczać ("i tak go nie
  widać"). Na oponach i bezwładności nie oszukiwać "za bardzo".
- Opis z liczbami pokazany użytkownikowi: `tools/bot_drive_sim.py`
  (porównanie w symulatorze `tools/car_sim.py`).

## Co jest w tym PR-ze (odizolowane, czysta logika + test)

- `scripts/bot_drive_model.gd` (`BotDriveModel`): napęd bota bez skrzyni,
  sprzęgła i obrotów jako stanu - przełożenie równoważne (jak idealna
  bezstopniowa) i moment `gaz × min(0,86·P/ω, T_max)`. Hamowanie silnikiem
  tym samym wzorem. Bezwładność silnika na kołach zostaje (I_e·r_eq²
  przez `_total_ratio`). W symulatorze vs pełny model bota: 0-100 -5%,
  0-160 +1%, hamowanie +1%, łuk i zmiana pasa 0%; pełny gaz w środku łuku
  zarzuca mniej (pełny model redukuje bieg i dostaje skok momentu).
  Zysk sam w sobie mały: ~8-14% kroku w Pythonie, w grze pewnie 5-10%
  `bot_fiz`.
- `scripts/bot_lod.gd` (`BotLod.assign`): poziomy NEAR (< 120 m, opony
  2 podkroki, sterowanie co krok) / MID (< 320 m, **opony 1 podkrok**,
  sterowanie 30 Hz) / RAIL (szyna jak dziś), histereza 20 m, **budżet aut
  z fizyką** (NEAR zawsze ma fizykę; budżet obcina MID od najdalszych,
  boty w szale pierwsze). 1 podkrok w symulatorze: hamowanie, łuk, zmiana
  pasa bez zmian, 0-100 +11%, krok -37%.
- `tests/bot_drive_test.gd` - test obu modułów. **Nieuruchomiony** (brak
  Godota w chmurze).

## Prośba

1. Uruchom `tests/bot_drive_test.gd` (po `--import`), popraw literówki.
2. Wpięcie w `stunt_car.gd` (opis w nagłówku `bot_drive_model.gd`):
   flaga `simple_drive` dla botów; `_update_gearbox` bez zmian biegów
   (gear 1, sprzęgło zamknięte; logika wstecznego do wychodzenia
   z utknięcia zostaje); `_total_ratio(1)` → `drive.ratio(...)`;
   `_engine_torque_at_clutch` → `drive.engine_torque(...)`;
   `_update_engine_rpm` → `drive.rpm(...)`; ESP pominięte.
3. Wpięcie `BotLod` w `xr_main._update_bots` (~4 Hz): poziom → 
   `TIRE_SUBSTEPS` (2/1), takt `BotDriver` (co krok / co 4. krok,
   wejścia trzymane), RAIL → obecna szyna. Budżet na start 8, potem
   zmierz na Queście (PERF+ `bot_fiz`, `bot_ster`) przy 4/6/8/10 autach
   z fizyką i wpisz wynik do `outbox/`.
4. Sprawdź, że `bot_rage_test` i `score_play_test` dalej przechodzą (boty
   w szale muszą dogonić gracza - przy 350 kW 0-100 wychodzi szybciej niż
   dziś, więc raczej łatwiej).

5. **Test na goglach z użytkownikiem** (prośba użytkownika: "chętnie
   pościgam się z samochodami"): po wpięciu zbuduj na Questa i poproś
   użytkownika o jazdę z botami w szale - zderzenia, taranowanie, pit,
   skoki z botami blisko. Pytania do niego: czy boty przy zderzeniach
   i skokach zachowują się tak samo jak przed zmianą, czy coś "skacze"
   na granicy 120 m / 320 m (przełączanie poziomów), czy boty nadążają.
   Pomiary PERF+ i jego wrażenia do `outbox/`.

Pełny opis projektu z liczbami (to, co widział użytkownik):
`docs/design/uproszczony-naped-botow.md`.

Kolejny krok po stronie chmury (osobno): grupy botów i furia między botami
(`feud_director.gd`) - projekt w wątku, czeka na decyzję użytkownika.

## Odpowiedź agenta lokalnego

2026-11-09 (wieczór):
1. `bot_drive_test` - dwa błędy parsowania (`var mid_w :=` / `var p_mid :=`
   z wartości bez typu - Godot 4.6 nie wnioskuje; poprawione na `: float`),
   potem OK. W zestawie `./quest.sh test`.
2. Wpięte w `stunt_car.gd`: `simple_drive` (boty z `_spawn_bot`), model
   tworzony leniwie w kroku (po `apply_engine` zerowany), `_total_ratio(1)`,
   `_engine_torque_at_clutch`, `_update_engine_rpm`, `_update_gearbox`
   (gear 1, sprzęgło zamknięte; **wsteczny automatu "hamulec na postoju"
   zostawiony** - bez tego bot nie wychodził z utknięcia). **ESP NIE
   pominięte**: bez niego bot w szale (250-350 kW, tył) obracał się sam
   przy pełnym gazie (bot_rage_test: -136° przy 124 km/h).
3. `BotLod` w `xr_main._update_bot_lod` (4 Hz, budżet 8): NEAR 2 podkroki,
   MID 1 podkrok + `BotDriver` co 4. krok (delta sumowana), RAIL przez
   `BotDriver.lod` (szyna z `lod == RAIL`; bez BotLod - stare progi).
4. Z mocniejszym przyspieszaniem bot w szale dochodził do limit+50 km/h
   i wypadał w łuku - `_curve_speed` liczy teraz 0,7 g zamiast 0,8 g.
   bot_rage_test: bot trzyma się gracza 6-28 m i taranuje (przed zmianą
   0,8: odpadał na 70-160 m). score_play_test, endless_test OK.
5. Zauważone w logu z Questa (przed tą zmianą): **pojawienie się bota =
   ~170 ms jednej klatki** (`boty_mgr` maks 171 ms) - budowa StuntCar
   z siatką sedana w `_spawn_bot`. Plan: pula botów (ukrywanie zamiast
   `queue_free`). Pomiary PERF+ przy 4/6/8/10 autach z fizyką - po jeździe
   z użytkownikiem.
