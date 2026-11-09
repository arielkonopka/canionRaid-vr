Status: nowe
Od: wątek w chmurze "Popraw trakcję przy przyspieszaniu"
Decyzje użytkownika (2026-11-09, karta decyzji): **"Start od mocy z menu"**
- trasa bez końca startuje z mocą wybraną w menu, warsztaty proponują
progi powyżej niej. Łatwiejsze wczesne skoki przy mocnym starcie są
akceptowane (to jawny wybór gracza).

# Moc z menu w trasie bez końca

## Problem

Użytkownik: "bardzo trudno rozpędzić do 170 km/h, choć silnik jest raczej
mocny" / "w menu wybiera się moc auta". `xr_main.gd` `restart_race()`
w trasie bez końca zawsze robi `car.apply_engine(gs.engine_type,
gs.POWER_TIERS[0])` (90 kW) - opcja "Moc maksymalna" działa tylko na
trasie pokazowej i menu tego nie mówi. Przy 90 kW 0-170 km/h to ~34 s
(symulacja), więc gracz czuje "słabe auto" mimo mocnego wyboru w menu.

## Zmiana (xr_main.gd - plik agenta lokalnego, dlatego tylko specyfikacja)

1. `restart_race()`: zamiast progu 0 - moc z menu, tak samo jak
   `GameSettings.apply_to_car` (`effective_power(engine_type,
   motor_layout == "hub", engine_power)`, łącznie z `hub_motors`).
   `_tier` = indeks tej mocy w `POWER_TIERS` (dla efektywnej mocy
   700 zamiast 1000 - indeks 700).
2. `_enter_workshop(tier)`: proponowany próg = `max(tier, _tier + 1)`
   (próg z trasy, ale nigdy nie słabszy ani równy obecnemu). Jeśli
   `_tier` jest już ostatni - tylko "bez zmian" (naprawa, tankowanie
   i +1 dźwig zostają).
3. Harmonogram skoków (`TrackGenerator.jump_schedule`) bez zmian - dalej
   strojony pod progi z numeru odcinka.
4. Hint/opis opcji "Moc maksymalna" w menu: że to moc startowa w trasie
   bez końca (warsztaty dają więcej).
5. HANDOVER: poprawić zdanie "W grze start na POWER_TIERS[0] ...
   (opcja Moc działa tylko na trasie pokazowej)" i dopisać decyzję.

## Testy

`title_test` (menu), `endless_test` (np. 180 petrol - sprawdzić, że
auto ma 180 kW od startu, a pierwszy warsztat proponuje 250),
`service_test`, `score_play_test` jeśli zależy od mocy.
