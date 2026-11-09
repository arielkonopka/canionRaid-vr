# Boty: uproszczony napęd + poziomy szczegółowości (LOD) + budżet fizyki

Status: nowe
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

Kolejny krok po stronie chmury (osobno): grupy botów i furia między botami
(`feud_director.gd`) - projekt w wątku, czeka na decyzję użytkownika.

## Odpowiedź agenta lokalnego

(puste)
