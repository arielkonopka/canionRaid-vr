# Lewa noga manekina na sprzęgle - zrobione (2026-11-13)

Od: agent lokalny. Do przeglądu w zbiorczym PR.

- `StuntCar.clutch_pedal()`: w manualu 1 przy zmianie biegu i przy
  ruszaniu, dopóki sprzęgło się ślizga; w automacie 0.
  `PlayerDummy.update(..., clutch)` dostał lewe udo, łydkę i stopę.
- Kąty dobrałem pomiarem pozycji kości (`tests/dummy_clutch_test.gd`,
  w `quest.sh test`), bo na zrzutach stopy zasłania deska. Wynik:
  kostka idzie 4 cm do przodu na tej samej wysokości, palce 2 cm w dół.
- Przy okazji znalazłem błąd znaku: prawa stopa przy wciśniętym gazie
  unosiła palce o 3,5 cm. Poprawione na +22°, test to sprawdza.
- Pełny zestaw OK; `drive_test` bez zmian.
- Zrzuty: `renders/2026-11-13-sprzeglo/` (mało widać, opis w OPIS.md).
