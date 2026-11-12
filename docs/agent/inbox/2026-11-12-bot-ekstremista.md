Status: przyjęte (kolejka: po sprzęgle/TCS/ESP)
Od: wątek w chmurze "Dodaj bota ekstremistę"
Do: agent lokalny
Decyzje użytkownika: pomysł użytkownika 2026-11-12 (cytat niżej). Otwarte:
zachowanie na łukach (karta decyzji w wątku; domyślnie "lift").

# Bot "ekstremista"

Użytkownik (2026-11-12): *"nowy typ bota, nazwijmy go ekstremista, to taki,
co jedzie maksymalną możliwą prędkością i trąbi na wszystkich i mruga
długimi światłami, ale nie zwalnia..."*

## Gotowe w chmurze (do uruchomienia)

- `scripts/extremist_brain.gd` (`ExtremistBrain`, czysta logika jak
  FeudDirector): wybór pasa, gaz/hamulec, wzorce klaksonu i długich,
  `v_safe_from_profile`, moc oszukanego napędu, punkty za przepuszczenie,
  szansa pojawienia się na km.
- `tests/extremist_test.gd` - w chmurze nieuruchamiany (brak Godota):
  `godot --headless --xr-mode off -s res://tests/extremist_test.gd </dev/null`

## Zachowanie (ustalone z wizji + wiadomości użytkownika)

1. **Cel to droga, nie gracz.** Nie ma taktyk szału, nie goni gracza,
   klakson gracza ani zderzenie go nie "wkurzają" - już jest na maksimum.
   `enrage()` na nim nic nie robi (poza punktacją kontaktu, niżej).
2. **Maksymalna możliwa prędkość:** pełny gaz, ograniczenia prędkości go
   nie obchodzą. Oszustwo tylko w napędzie (dozwolone przez użytkownika):
   `apply_engine("petrol", ExtremistBrain.engine_kw(player.engine_power_kw))`
   - co najmniej 450 kW i 1,3 x gracz, więc zawsze dogoni. Opony,
   masa, bezwładność - bez zmian.
3. **Nie zwalnia przed autami - nigdy.** Trąbi i mruga, zjeżdża na pas
   z największym czasem do zderzenia (TTC), w ostateczności poboczem
   (pas awaryjny `SHOULDER_R` autostrady), a jak nie ma gdzie - taranuje.
   Ulubiony pas: lewy. Histereza `LANE_HOLD`, auto obok (gap < 5,5 m)
   blokuje pas.
4. **Łuki** (`curve_mode`, karta decyzji użytkownika - wpisz wynik tutaj):
   `"lift"` (domyślnie) tylko odpuszcza gaz przy 0,85 g, nigdy nie hamuje;
   `"never"` dosłownie pełny gaz; `"curves"` hamuje przed łukami (nie
   przed autami). Fizyka sama zdecyduje, kiedy wyleci.
5. **Klakson:** seria (2 x 0,3 s, okres 1,4 s) na każde auto, do którego
   się zbliża bliżej niż 160 m na dowolnym pasie; ciągły, gdy TTC na jego
   pasie < 2 s. **Długie:** dwa mrugnięcia na sekundę na każde auto
   bliżej 260 m. Gracz pierwszy go **usłyszy** z tyłu i zobaczy błyski
   w lusterku.

## Integracja (agent lokalny)

### BotDriver (`scripts/bot_driver.gd`)
- `var persona := ""` ("extremist"); `var brain: ExtremistBrain`.
- W `_drive_step`, po wyznaczeniu `best/offset`, gałąź dla ekstremisty
  zamiast `_calm_speed`/`_rage_plan`:
  - `lanes`: dla każdego pasu naszej jezdni najbliższe auto przed nim
    (gracz + boty z `main._bots`, ~10 Hz wystarczy, wynik trzymać między
    krokami): `gap` wzdłuż drogi (`dot(best.fwd)`), przypisanie do pasu po
    offsetcie w poprzek (`hwy_lane_off`), `v` = prędkość wzdłuż drogi.
    Auto z `|ahead| < 5,5 m` na danym pasie => `gap = 0` (zajęty).
  - `shoulder`: na autostradzie pas awaryjny (oś `lane_center(0) +
    (LANE_W + SHOULDER_R) / 2`), w wąwozie `{}`.
  - `v_safe = ExtremistBrain.v_safe_from_profile(_prof, dist,
    ExtremistBrain.decel_for(brain.curve_mode))`.
  - Wynik: `target_off` z pasu (`SHOULDER` = oś pobocza), `throttle`,
    `brake`; w miejscu `LAT_RATE`/`LAT_GRIP` stałe z `ExtremistBrain`
    (0,7 μg to brawura kierowcy, nie opony). Utknięcie/cofanie i "w
    powietrzu bez gazu" zostają wspólne.
  - Uwaga: obecny kod w `_drive_step` ogranicza gaz w `_aggr < 1` i
    hamuje przy `kmh > target_kmh` - ekstremisty to nie może dotyczyć.
- Klakson: `brain` zwraca `horn` per krok; zbocza -> `_horn.play()` /
  `stop()`. Do ciągłego sygnału osobny strumień z pętlą (ten sam
  dwuton, `loop_mode = LOOP_FORWARD` na pełnych okresach 420/498 Hz) albo
  odtwarzanie od nowa co 0,4 s. Proponuję `doppler_tracking =
  PHYSICS_STEP` na jego klaksonie (i kamerze gracza, jeśli tanie) -
  przelot 250 km/h z efektem Dopplera to cały urok.
- Szyna (LOD): ekstremista na szynie jedzie `_rail_v` ~ jego prędkości
  maksymalnej (np. 70 m/s), nie limitem; przez auta na szynie po prostu
  przenika (poza wzrokiem). Przejście szyna -> fizyka przy 250 km/h
  sprawdzić (`linear_velocity` i obroty kół jak dziś).
- Żeton fizyki: ekstremista w zasięgu NEAR zawsze z fizyką (jak bot
  z żetonem); najwyżej **jeden** ekstremista naraz.

### StuntCar (`scripts/stunt_car.gd`)
- `set_high_beam(t)`: jak `set_rage_lights`, ale biały, `emission_energy`
  do ~6. Za dnia sama emisja słabo widać - proponuję 2 małe quady
  billboard z addytywną "gwiazdką" (unshaded, bez cieni; tanie na
  Queście), widoczne też w lusterku. Bez prawdziwych `SpotLight3D`.
- Kolejność zapisu materiału: ekstremista nie używa czerwonych świateł
  szału, więc `set_rage_lights` go nie dotyczy.

### xr_main (`scripts/xr_main.gd`)
- Pojawianie: co km trasy losowanie z `spawn_chance_per_km(km)` (0 przez
  pierwsze 3 km, potem 0,15 rosnące do 0,6 - trudność rośnie z czasem).
  Spawn **za graczem**, 350-500 m, poza wzrokiem (TrafficZone.visible),
  na lewym pasie, z prędkością ~200 km/h. Znika, gdy > 800 m przed
  graczem i poza wzrokiem albo po wraku.
- Wygląd: zwykły styl z puli, bez koloru gangu (nie należy do gangów,
  `feud.add_bot` go pomija). Manekin za kierownicą jak u innych.
- Ostrzeżenie HUD "EKSTREMISTA Z TYŁU" to pomoc dla gracza - tylko
  jawna i wyłączalna (CLAUDE.md), więc ewentualnie jako opcja menu,
  domyślnie wyłączona; podstawą jest dźwięk i lusterko.

### Boty a ekstremista (szał bot-bot)
- Kontakt z nim idzie zwykłą drogą `feud_contact` (FeudDirector) - on
  sam się nie rewanżuje (nie ma celu), ale potrącony bot może wpaść
  w szał na niego (`feud_with`) - gonitwa i tak zgaśnie po
  `FEUD_TIMEOUT`, bo go nie dogoni.
- Propozycja (do potwierdzenia przez użytkownika w HANDOVER / otwartych
  pytaniach): bot, na którego trąbi z bliska (< 60 m), z szansą 0,15
  wpada w szał na niego, tylko w zasięgu wzroku gracza.

### Punkty (ScoreKeeper)
- **Ucieczka/przepuszczenie:** gdy wyprzedzi gracza bez kontaktu -
  `award_free("extremist_pass", ExtremistBrain.pass_points(min_gap))`
  (200 / 120 / 60 pkt za odstęp boków < 1 / 2,5 / 4 m).
- **Rozbity ekstremista:** wrak w ciągu 10 s od kontaktu z graczem albo
  od uniku gracza bliżej 4 m -> 500 pkt; wybuch -> zwykła premia za
  wybuch.
- Kontakt z graczem: zwykłe `score_damage` za obrażenia zadane.

## Sprawdzić / testy

1. `tests/extremist_test.gd` (czysta logika).
2. Po wpięciu: `tests/drive_test.gd` i `tests/bot_rage_test.gd` (zmiany
   w BotDriver), najlepiej scena z jednym ekstremistą za graczem na
   autostradzie i w wąwozie; czy kolizja przy różnicy ~150 km/h nie
   tuneluje (CCD, przegląd `2026-11-12-ccd-impact-przeglad.md`).
3. Quest: czas kroku z ekstremistą w NEAR (2 podkroki opon przy 70 m/s),
   czy błyski są widoczne w lusterku (lusterko odświeżane co kilka
   klatek - mrugnięcia 0,15 s mogą wypadać; wtedy wydłużyć `BEAM_ON`).

Wyniki proszę do HANDOVER.md i krótko tutaj.

## Odpowiedź agenta lokalnego

