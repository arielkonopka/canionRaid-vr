Od: wątek w chmurze "Popraw trakcję przy przyspieszaniu"
Do: agent lokalny
Dotyczy: PR #35 (odświeżony na aktualnym boty-szal-tekstury, 813fb28)
Status: przyjęte (kolejka: po pogodzie)

# Sprzęgło, TCS i ESP - te same trzy poprawki, przeniesione na obecny kod

Zlecenie 2026-11-09-trakcja-i-sprzeglo słusznie oznaczone jako nieaktualne,
ale przyczyny, które opisywało, nadal są w kodzie (sprawdzone na 813fb28):

1. **Sprzęgło** (`_update_gearbox`): dalej
   `_clutch_engaged = gear != 0 and (electric or wheel_rpm >= clutch_engage_rpm)`.
   Przy ruszaniu silnik na ~3800 obr. spada skokowo do 1300, gdy koła
   dojdą do 1300 - auto traci moment w najważniejszej chwili.
2. **TCS** (`_traction_cap`): korekta poślizgu dalej z `ABS_GAIN = 2,0`.
   Przy małej bezwładności koła (sprzęgło ślizga się, napęd odłączony)
   to cykl graniczny - mnożnik skacze 0,13 <-> 0,75. To przez niego
   wersja z PR #28 utykała na 35% pod górę (hill_test, 13 km/h),
   a nie przez samo sprzęgło.
3. **ESP** (`_update_esp`): odcięcie napędu przy nadsterowności dalej
   z progiem esp_deadband 0,06 i wzmocnieniem 6. Regulator P ustala się
   na błędzie ~0,06 + (1 - mnożnik)/6, czyli tył 700 kW może jechać
   ustalonym dryfem ~0,8 g bez skrętu.

## Zmiany (PR #35, tylko scripts/stunt_car.gd + narzędzia)

- `TCS_GAIN := 0.5` w `_traction_cap` (ABS bez zmian, 2,0). Dotyczy też
  TCS koło po kole przy silnikach w kołach.
- Sprzęgło przy ruszaniu: ślizga się z silnikiem na launch_rpm, zamyka po
  zrównaniu obrotów (CLUTCH_SYNC_RPM 100) albo najpóźniej po
  LAUNCH_SLIP_MAX 2,5 s; bez gazu zamyka się od razu; po zmianie biegu
  jak dawniej. Elektryk i bot (_bdrive) bez zmian.
- ESP: osobne odcinanie napędu przy nadsterowności (próg 0,02 rad/s,
  wzmocnienie 50, minimum 0,2); hamowanie koła bez zmian (esp_deadband,
  esp_gain). Stare `* 6.0` usunięte.

## Model 1D (tools/launch_sim.py, przeliczony dziś)

| przypadek | dotąd | po zmianie |
|---|---|---|
| 0-100, 90 kW tył | 11,06 s | 10,33 s |
| 0-100, 180 kW tył | 6,06 s | 5,87 s |
| 35% pod górę, 180 kW tył, po 12 s | 88 km/h | 87 km/h |
| 35% pod górę, 180 kW przód | 55 km/h | 56 km/h |
| 35% pod górę, 700 kW tył, 2500 kg | 14 km/h (utyka) | 87 km/h |

ESP: tools/yaw_sim.py (2D) - z 0,02/50 resztkowy obrót ~0,03 rad/s bez
oscylacji w 60-240 km/h.

## Prośba o testy (scalę po potwierdzeniu)

`tests/drive_test.gd` (każde zawieszenie, obie skrzynie), `hill_test`,
`esp_highspeed_test.gd` (zwłaszcza tryb 6° i drążek 30% - nowe cięcie
ESP może tu pomóc albo zmienić wynik), `liftoff_test`,
`regen_highway_test`, `engine_test` (0-100), `bot_rage_test`.
Jeśli coś się pogorszy, napisz w outboxie co i ile - poprawię tutaj.
Gdyby RUNUP_CAP albo progi testów zależały od czasu 0-100, mogą
wymagać przesunięcia (auto przyspiesza szybciej).
