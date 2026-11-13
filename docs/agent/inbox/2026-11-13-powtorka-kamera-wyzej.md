Status: nowe
Od: wątek w chmurze "Dodaj powtórkę wypadku z kamery obserwatora"
Decyzje użytkownika (2026-11-13 19:43 UTC, dosłownie): "powtorka wyszla
nieźle, kamera może być nieco wyżej, ale poza tym świetnie".

# Powtórka wypadku: kamera nieco wyżej

Dotyczy `2026-11-12-powtorka-wypadku` (zrobione). Użytkownik ocenił
powtórkę w goglach: dobrze, zmiana tylko wysokości kamery. Odległość,
długość okna, zwolnienie i napis zostają (zaakceptowane - przenieś
z "do oceny" do ustaleń w HANDOVER).

## Zmiana

"Nieco" = mały krok, nie podwójnie. Propozycja w `xr_main.gd`:

- `REPLAY_UP` 4,0 -> **5,5 m** nad jezdnią (przy 8 m za autem kąt
  patrzenia w dół rośnie z ~27° do ~35°);
- `REPLAY_ABOVE_CAR` 2,5 -> **3,5 m** (ta sama proporcja przy skokach);
- tunel bez zmian (i tak rządzi strop: `REPLAY_CEIL_GAP`); sprawdź tylko,
  czy promień w górę `REPLAY_UP + 3.0` dalej sięga stropu najwyższego
  tunelu, skoro `REPLAY_UP` rośnie (powinien - jest dłuższy);
- na PC `REPLAY_PITCH` 25° -> 32°, żeby auto zostało w środku kadru.

Po zmianie `replay_play_test`, zrzuty `tests/replay_shot.gd` i krótka
notka w HANDOVER (stałe + ustalenie użytkownika). Jeśli w zrzutach auto
wychodzi za małe albo za nisko w kadrze - wybierz 5,0 m i napisz tu.

## Odpowiedź agenta lokalnego

(tu)
