Status: nowe
Od: wątek w chmurze "Upiększ wnętrze sedana i kierownicę"
Decyzje użytkownika (2026-11-08, jego słowa): "chciałbym ładniejsze wnętrze tego sedana. kierownica jest strasznie siermięzna, czy może bardziej wyglądac jak w fiacie 125?"

# Nowe wnętrze sedana w stylu epoki (PR z gałęzi `claude/project-thread-tq9wth`)

To odpowiada też na otwarte pytanie z HANDOVER (sekcja 9 i plan, punkt 3):
**wnętrze ma być z epoki** (włoski sedan przełomu lat 60. i 70.), a nie
nowoczesne jak w SUV-ie. Proszę przenieść to do ustaleń w HANDOVER.md
i usunąć z otwartych pytań / zaktualizować punkt 3 planu.

## Co zmieniłem (tylko wygląd, fizyka nietknięta)

`scripts/stunt_car.gd`, nowa sekcja "Wnętrze sedana" (`_build_interior`,
`_build_steering_wheel`, `_build_dash_details`, `_ip_seat`, pomocnicze
`_ip_*`). W `_build_body` stare pudła wnętrza i kierownica zastąpione
jednym wywołaniem `_build_interior(...)`.

- **Kierownica**: wieniec Ø 39 cm z rurki Ø 20 mm (czarny "bakelit",
  lekki połysk), dwie szprychy z satynowego metalu lekko poniżej poziomu
  z trzema "nawierconymi" otworami, piasta cofnięta 4,5 cm ("głęboka"
  kierownica), miękka nakładka klaksonu, gładki chromowany środek
  (bez znaku), chromowany pierścień klaksonu. **Bez górnej szprychy** -
  stara kierownica w krzyż zasłaniała zegary pionową szprychą.
  Kolumna z osłoną i manetką kierunkowskazów. Obrót bez zmian:
  `_steering_wheel.rotation` w `_process` (14:1).
- **Deska**: ciemny korpus, miękki czarny wałek nad listwą pod orzech,
  cienki chrom pod listwą, osłona zestawu zegarów (daszek, boki - w układzie
  `SEDAN_CLUSTER`, tylko auto gracza), trzy małe ozdobne zegary na środku,
  okrągłe nawiewy w chromie, obrys schowka z przyciskiem, 4 przełączniki
  dźwigienkowe, stacyjka, radio z gałkami i przyciskami.
- **Fotele**: przednia kanapa zamieniona na dwa osobne fotele (z tunelem
  i dźwignią biegów między nimi), środki przeszyte w pionowe pasy
  (ciemniejsza wstawka + żeberka), wyższe boki; tylna kanapa tak samo.
- **Reszta**: boczki drzwi z chromową listwą, podłokietnikiem, klamką
  i korbką szyby; parapety okien (zakrywają szczelinę między bokiem
  karoserii a cofniętą szybą boczną); pedały; lusterko wsteczne;
  osłony przeciwsłoneczne.
- `scripts/gauges.gd`: obudowa tarcz prawie czarna zamiast brązowej
  (pasuje do osłony).
- `tests/screenshot.gd`: dwa nowe ujęcia, `wheel` i `interior`.

## Wydajność

Cała nieruchoma część wnętrza to **jedna** `MeshInstance3D` "Interior"
z 8 powierzchniami (materiał = powierzchnia), kolumna 1, kierownica 3.
Wcześniej 10 osobnych pudeł = 10 wywołań rysowania, teraz ~12. Kilka
tysięcy trójkątów. Siatka "Interior" nie rzuca cieni. Boty dostają
wersję bez drobiazgów (`detail = not is_bot`: bez zegarków, radia,
pedałów, żeberek foteli, otworów w szprychach). Nowe materiały
(`bakelite`, `alu`, `wood`) są w `_cockpit_mats`, więc prześwitują razem
z resztą kabiny. W trybie concept car "Interior" znika jak inne
`MeshInstance3D` sedana (`set_body_model`), węzeł "SteeringColumn" też.

## Prośba

W chmurze nie ma Godota - kod nie był uruchomiony. Proszę:

1. `git fetch && git merge origin/claude/project-thread-tq9wth` (albo
   przejrzyj PR) i uruchom edytor/scenę - sprawdź, czy skrypt się
   parsuje (GDScript pisany "na sucho").
2. Zrzuty: `godot --xr-mode off --resolution 960x600 -s res://tests/screenshot.gd -- /tmp/zrzuty </dev/null`
   (ujęcia `cockpit`, `gauges`, `wheel`, `interior`) i obejrzyj, czy
   nic nie przenika ani nie wisi w powietrzu (zwłaszcza osłona zegarów
   względem `Gauges`, wałek deski względem dolnej krawędzi tarcz,
   lusterko względem szyby).
3. `tests/drive_test.gd` (zmiana jest w scenie auta) i `tests/title_test.gd`
   (auto na ekranie tytułowym) - wynik do HANDOVER.md.
4. Na goglach: czy kierownica i deska wyglądają dobrze, czy coś nie
   zasłania widoku drogi, i czy klatka się trzyma. Drobne poprawki
   pozycji rób śmiało sam w tej samej gałęzi.
5. Odpisz poniżej (albo w PR) - po Twoim "OK na Queście" scalę PR.

## Odpowiedź agenta lokalnego

