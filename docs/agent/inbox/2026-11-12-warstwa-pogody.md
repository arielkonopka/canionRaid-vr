Status: przyjęte (w kolejce po botach i wibracjach)
Od: wątek w chmurze "Zaplanuj urozmaicenia trasy i miasta"
Decyzje użytkownika (2026-11-11, ok. 23:00 UTC): "w przypadku deszczu niebo
powinno się robić ciemnoszare", "rozważmy dodanie warstwy pogody",
"działaj z agentem lokalnym w takim razie, masz moją zgodę". Projekt:
dokument "Urozmaicenia trasy: odcinek z 4 bajtów", sekcja "Warstwa pogody".
Otwarte: nic. Wartości liczbowe są startowe - do oceny z użytkownikiem
w goglach.

# Warstwa pogody: fronty, ciemne niebo, mokra jezdnia

Pogoda to osobna warstwa planu trasy (nie bajt odcinka - trwa kilometrami).
Dziś autostrada nie ma deszczu wcale (`HighwayGenerator._seg` wpisuje
zawsze `"surface": "dry"`), a niebo jest stałe w `main.tscn`.

## Co jest w PR

- `scripts/weather_plan.gd` (`WeatherPlan`) - czysta logika jak
  `HighwayPlan`, bez sceny. `WeatherPlan.new(ziarno, plan)`:
  - `weather(d)` -> `{cloud 0..1, rain 0..2, fog 0..1, wind 0..1,
    wind_sign, kind ("rain"/"snow"/"dust"/"wind"/""), freezing}`;
  - `surface(d, on_bridge := false)` -> `"dry"`, `"wet"`, `"ice"` (lód
    tylko na moście przy mrozie - most zamarza pierwszy);
  - `surface_changes(d0, d1)` -> granice stref nawierzchni do dzielenia
    odcinków (jak `HighwayPlan.limit_changes`);
  - `WeatherPlan.look(w)` (statyczna) -> kolory nieba, energia słońca,
    gęstość i kolor mgły, światło otoczenia. Pogodne = wartości z
    `main.tscn`, burza = ciemnoszare.
  - Fronty w blokach 12 km: chmurzenie 2-3 km (zapowiedź: 50-75 s przy
    140 km/h), opad 1-4 km (mżawka albo ulewa, ulewa częściej dalej),
    przejaśnienie 1,5 km, jezdnia schnie 1 km. Pierwsze 6 km bez pogody.
    Biom w środku opadu: pustynia - pył, bez opadu; góry - mgła, w połowie
    frontów mróz ("snow"); wybrzeże - wiatr i mgła.
- `tests/weather_plan_test.gd` - zgodność z Pythonem (ten sam hash),
  zapowiedź przed opadem, mokro tam gdzie pada, kolejność pytań,
  `surface_changes`, biomy, wygląd.
- `tools/weather_sim.py` - odpowiednik w Pythonie. **W chmurze nie ma
  Godota** - sprawdzony był tylko on: ziarna 777, 1, 4242, 5 OK; front
  średnio co 17-27 km, opad na 9-12% trasy, mokra jezdnia na 14-19%.

## Do zrobienia po stronie agenta lokalnego

1. Uruchom test (może mieć literówki typów - błędy w tych plikach
   poprawiaj śmiało, są odizolowane):
   ```
   godot --headless --import --xr-mode off </dev/null
   godot --headless --xr-mode off -s res://tests/weather_plan_test.gd -- 777 </dev/null
   python3 tools/weather_sim.py 777 300
   ```
   Dodaj test do zestawu.
2. **Nawierzchnia w generatorze.** Jeden `WeatherPlan` na trasę (obok
   `HighwayPlan`, to samo ziarno). `HighwayGenerator` dzieli odcinki
   w punktach `surface_changes` i wpisuje `"surface"` z
   `weather.surface(d)`. Tunel (`roof`) zawsze `"dry"`. Mokrą jezdnię
   widać już dziś po kolorze (jak strefy mokre w wąwozie) i tablica A-15
   30 m przed strefą - sprawdź, że działa też na autostradzie.
   `on_bridge` na razie `false` (mosty przyjdą z budowlami).
3. **Deszcz i niebo w scenie** (`xr_main`): w trybie Autostrada
   `_rain_target` z `weather(_last_safe_dist).rain` (pod dachem 0), zamiast
   z próbki. Co ~1,5 s: `WeatherPlan.look(w)` z pogody wygładzonej w czasie
   (stała ~3 s) i przepisanie do `ProceduralSkyMaterial` (sky_top,
   sky_horizon, ground_horizon), słońca (`light_energy`), `Environment`
   (fog_density, fog_light_color, ambient_light_color).
   **Uwaga Quest:** zmiana parametrów nieba przelicza mapę odbić
   otoczenia. Rzadkie kroki (nie co klatkę) i najlepiej
   `Sky.process_mode = PROCESS_MODE_INCREMENTAL` (rozkłada przeliczenie
   na klatki) - zmierz `Perf.add("niebo")` przed i po. Jeśli i tak drogo:
   zostaw niebo, zmieniaj tylko mgłę, słońce i światło otoczenia.
4. **Ruch w deszczu:** spokojne auta przy spawnie 0,9 prędkości, gdy
   `rain >= 0,5` (`TrafficZone._candidate`); furiaci bez zmian - deszcz
   robi ich groźniejszymi. Boty jadą po tej samej fizyce, więc same
   się ślizgają.
5. **Menu:** opcja "Pogoda: zmienna / zawsze sucho" (GameSettings,
   domyślnie zmienna). "Zawsze sucho" = `surface` zawsze "dry",
   `weather` zawsze czysta. Po zmianie menu `tests/title_test.gd`.
6. **Później (nie teraz):** wiatr jako jawna siła boczna na otwartych
   odcinkach z rękawem wiatru przy drodze; wycieraczki w kokpicie; pogoda
   w trybie wąwozu (dziś losowe strefy mokre - zostają).
7. Zrzut ekranu ciemnego nieba w ulewie dla użytkownika
   (`tests/screenshot.gd`; km z ulewą wypisz z `WeatherPlan.front` z planem biomów - Python nie zna biomów, więc jego km 99,5 dla ziarna 777 może wypaść na pustyni), potem
   jazda w goglach: czy niebo ciemnieje wyraźnie przed deszczem
   i czy mokra jezdnia jest czytelna.

Testy jak zawsze: `drive_test` (oba typy skrzyni), `highway_plan_test`,
`weather_plan_test`, `title_test` po menu. Wynik do HANDOVER.md.
