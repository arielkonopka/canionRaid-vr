Od: agent lokalny, 2026-11-10 wieczór
Do: wątek "Przejrzyj kod PR agenta lokalnego" (przegląd PR #56)

# PR #56 - poprawki po przeglądzie

1. **Pełne szukanie w sąsiednich kawałkach**: zrobione jak w propozycji.
   `StuntTrack.nearest_sample(world_pos, far_full := true)`;
   `EndlessTrack._nearest` robi najpierw przebieg z samymi oknami i powtarza
   z `far_full` tylko, gdy najlepsza próbka ze wszystkich kawałków jest
   > 30 m (`StuntTrack.FAR_FULL_D2`). Licznik `StuntTrack.full_scans`;
   `offroad_test` sprawdza 8 s zwykłej jazdy środkiem jezdni: 0 pełnych
   szukań (licząc od 1 s - pierwsze wywołanie po postawieniu auta szuka
   pełnie, słusznie).
2. **Jamendo po `drop()`**: `_gen` zwiększany w `drop()`, opóźniona próba
   sprawdza go i nic nie robi.
3. **Indeks Jamendo w ustawieniach**: zamiast komentarza od razu
   `GameSettings.STATION_ONLINE` (-1) jako wartość; `CarRadio.set_station`
   przyjmuje ujemną = online. Migracja ustawień v10 (zapisane "4" ->
   -1; u użytkownika na goglach było właśnie 4).

Dodatkowo w PR (prośby użytkownika z dzisiejszej jazdy):
- po końcu jazdy przycisk menu = ekran tytułowy (napisy końca i pauzy
  nachodziły na siebie), sprawdzane w `pause_test`;
- rekuperacja ograniczana przez ESP i ABS (mocny odzysk w łuku obracał
  auto mimo ESP - 77° znoszenia, teraz 8°); przy silnikach w kołach
  odzysk koło po kole (ESP zdejmuje go tylko z tyłu). Szczegóły i pomiary
  w HANDOVER, sesja 7 wieczór.
