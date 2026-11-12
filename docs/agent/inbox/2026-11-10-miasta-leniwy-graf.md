Status: zrobione (CityGraph)
Od: wątek w chmurze "Usuń pozostałości dróg na estakadach" (na prośbę
wątku z planem nocy, `2026-11-10-plan-nocy.md`)
Decyzje użytkownika: miasta, po których da się jeździć, generowane
"leniwie" (2026-11-09, 22:58 i 23:00; nocny cel 23:17). Szczegóły
pomysłu: `2026-11-09-pozostalosci-estakad.md`, dopisek pkt 2.

# Miasta: leniwy graf ulic - moduł do wpięcia

## Co jest w PR

- `scripts/city_graph.gd` (`CityGraph`) - czysta logika, bez sceny:
  - **graf niejawny**: węzły na siatce 80 m z przesunięciem z hasha,
    aleje (14 m) co 4 kolumny/wiersze + obwodnica na brzegu `bounds`,
    ulice (9 m) między alejami całymi odcinkami - **bez ślepych
    zaułków** (każdy węzeł ma >= 2 wyloty) i spójne miasto; łuk ulicy
    z hasha pary węzłów (ta sama ulica z obu stron i po powrocie);
    nic nie jest zapisywane;
  - **leniwa budowa**: `start(a, b)`, potem `update(pos)` kilka razy na
    sekundę z położeniem auta (układ miasta 2D: x, z świata). Zbudowane:
    bieżąca ulica w całości, 2 przejechane, przy obu jej końcach
    wszystkie wyloty jako zalążki 25 m. Wjazd w zalążek = skręt: ta ulica
    staje się bieżącą i buduje się w całości, przy jej końcu pojawiają się
    nowe zalążki, stare znikają. `update` zwraca różnicę
    `{"add": [{key, a, b, len}], "remove": [key], "switched"}` (len -1 =
    cała ulica, > 0 = zalążek); geometrię robi wywołujący. Naraz zbudowanych
    najwyżej 11 krawędzi. `odometer` = przejechana droga.
- `tests/city_graph_test.gd` - determinizm, symetria, brak ślepych
  zaułków, spójność, łuk z obu stron, 200 skrzyżowań jazdy losowej
  z zawrotkami (bieżąca zawsze zbudowana, skręt przełącza, powrót = ta
  sama geometria).
- `tools/city_graph_sim.py` - wierny odpowiednik w Pythonie (ten sam
  hash, te same liczby). **W chmurze nie ma Godota** - sprawdzony był
  tylko ten skrypt (ziarna 4242, 1, 777, 5: OK, ~19 km jazdy,
  maks. 8 krawędzi naraz, 28-101 powrotów na ulice już widziane).

## Do zrobienia po stronie agenta lokalnego

0. **Porównaj z własnymi zmianami o miastach** (użytkownik mówi, że masz
   niewypchnięte zmiany z miastami). Jeśli masz już swoje miasta, wybierz
   z użytkownikiem: wymienić ich układ ulic na `CityGraph` czy tylko
   wziąć z niego leniwy graf jako "skręty w boczne ulice". Napisz
   w odpowiedzi tutaj, co wybraliście.
1. Uruchomić test (może mieć literówki typów - błędy w tych plikach
   poprawiaj śmiało, są odizolowane):
   ```
   godot --headless --import --xr-mode off </dev/null
   godot --headless --xr-mode off -s res://tests/city_graph_test.gd -- 4242 200 </dev/null
   python3 tools/city_graph_sim.py 4242 4000     # powinno dać te same liczby węzłów i stopni
   ```
2. **Budowa geometrii z różnicy** (nowy węzeł, np. `CityStreets`): na
   "add" - wstęga jezdni po `edge_points` (ten sam `road.gdshader`,
   UV.y = dystans wzdłuż ulicy), chodniki z krawężnikiem i zabudowa jak
   w `HighwayScenery` (MultiMesh, bez kolizji dalej niż chodnik), na
   "remove" - `queue_free`. Skrzyżowanie: wielokąt jezdni wokół węzła
   (promień ~połowa najszerszej ulicy + 2 m), żeby końce wstęg się nie
   przenikały. Zalążek kończy się zabudową zasłaniającą dalszą część
   ulicy (albo mgłą) - nie może wyglądać jak urwana droga. Budowa
   rozłożona na klatki jak `StuntTrack.slice_build` (ulica 80 m to
   niedużo, ale 4 zalążki naraz przy skręcie).
3. **Wjazd i wyjazd** (tryb Autostrada: miasta co 25 / 100 km):
   autostrada wchodzi do miasta aleją na brzegu `bounds` (`start(a, b)`
   z pierwszą krawędzią tej alei), a wyjazd to dowolna aleja dotykająca
   obwodnicy po przeciwnej stronie - dalej znów `HighwayGenerator`
   z `start_state` z końca tej krawędzi (pozycja, kierunek). Na razie
   prościej: jedna aleja wyjazdowa oznaczona znakiem, reszta obwodnicy
   zamknięta zabudową. Rozmiar `bounds` z planu (małe miasto ~1 km =
   13×13 komórek, duże ~5 km).
4. **Postęp gracza w mieście nie jest `dist`**: odcinki, trudność,
   punkty i spawn botów liczyć z `odometer`; odrodzenie po stracie auta
   na ostatnim skrzyżowaniu (`current_a`). Boty w mieście jeżdżą po tym
   samym grafie (losowy wylot na skrzyżowaniu jak w teście) i znikają,
   gdy ich ulica zostanie usunięta (spokojne) albo jadą za graczem
   (w szale) - to wymaga, żeby ulica bota w szale też była w zestawie
   (do dodania: `pin(key)`, jeśli okaże się potrzebne).
5. `ground_y` w mieście (etap 2 z `2026-11-09-pozostalosci-estakad.md`):
   miasto płaskie na wysokości jezdni przy wjeździe, ulice bez garbów.
6. Zrzut ekranu (`tests/screenshot.gd`) i pomiar na Queście
   (`Perf.add("city")`) przed pierwszą jazdą z użytkownikiem.

## Poprawka (chmura, 2026-11-10, po zgłoszeniu w outbox/2026-11-10-noc-agent-lokalny.md)

Zawrócenie na tej samej ulicy nie odwracało `current_a`/`current_b`
(30 błędów w `city_graph_test`). Przyczyna: przełączenie brało tylko
**inną** najbliższą krawędź, a przy zawrotce auto zostaje na tej samej.
Python tego nie złapał, bo porównywał tylko klucz krawędzi bez kierunku -
po dodaniu sprawdzenia kierunku symulator pokazuje te same 30 błędów.
Teraz `update` śledzi dystans wzdłuż bieżącej krawędzi i po `TURN_BACK`
(3 m) jazdy wstecz odwraca kierunek (`switched = true`). Symulator po
poprawce: 4 ziarna OK. Proszę o ponowne uruchomienie `city_graph_test`.
