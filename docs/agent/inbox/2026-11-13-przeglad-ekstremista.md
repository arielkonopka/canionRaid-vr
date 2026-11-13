# Przegląd b2fead7 (bot ekstremista) - pula botów

Status: nowe
Od: wątek "Monitoruj repo na wiadomości od agenta"

Całość czyta się dobrze: mózg osobno, PathSteer wydzielony i używany
przez autopilota testów, premie z oknem 15 m, szyna 70 m/s. Jedna
rzecz do poprawy przed scaleniem do main:

## Ekstremista wraca do puli z silnikiem i długimi

`_spawn_extremist` robi `b.apply_engine("petrol",
ExtremistBrain.engine_kw(...))` i `set_high_beam(...)` na aucie z puli.
`_retire_bot` / `_park_bot` / `_take_bot` tego nie cofają:
- następny zwykły bot z tego węzła jedzie z mocą ekstremisty zamiast
  250 kW (`_new_bot_car` ustawia 250 kW tylko przy tworzeniu);
- `_beam_stars` zostają widoczne, a lampy przednie mają emisję z
  ostatniego `set_high_beam`, jeśli ekstremista zniknął w trakcie
  mrugania (np. `s > 800` przy `_can_vanish`, albo restart odcinka).
  `_style_head` tworzy się raz, więc zmiana stylu tego nie czyści.

Propozycja: w `_take_bot` (albo w `_retire_bot`) przywrócić
`apply_engine("petrol", 250)`, jeśli `engine_power_kw != 250`, oraz
`set_high_beam(0.0)`. Przy okazji `set_high_beam(0)` mogłoby wracać do
koloru z `_make_head_mat` (1, 0.92, 0.75), a nie białego, żeby po
mruganiu lampy wyglądały jak przed nim. Test: w extremist_play_test
po zniknięciu ekstremisty wziąć auto z puli i sprawdzić moc i
`_beam_stars[*].visible`.

Drobne, bez pilności:
- `set_high_beam` i `set_rage_lights` piszą ten sam materiał. Dziś
  ekstremista nie wchodzi w szał (rage 0), więc się nie biją. Gdyby
  kiedyś dostał rage, obie funkcje będą nadpisywać się co klatkę.

Po poprawce scalę #83. Potwierdź zmianą Status.
