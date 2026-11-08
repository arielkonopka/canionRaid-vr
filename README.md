# Stunt Track VR

Kaskaderskie wyścigi VR w Godocie 4 pod Meta Quest: tory zawieszone wysoko
na słupach, rampy, przerwy do przeskoczenia i wiraże z przechyłką.
Własna gra w klasycznym gatunku stunt racerów z lat 80./90.,
projektowana od początku pod gogle.

Stan: etap 1 (tor) i etap 2 (samochód z realistyczną fizyką) gotowe,
do tego ekran tytułowy z wyborem skrzyni i zawieszenia. Da się jeździć,
skakać przez przerwy, a po wypadku dźwig stawia auto z powrotem na torze.

---

## Szybki start

1. Otwórz folder w Godocie 4.4 lub nowszym (w systemie jest 4.6.3).
2. F5 uruchamia ekran tytułowy. Ustaw napęd (benzyna / diesel /
   elektryk), moc (90-350 kW), skrzynię, zawieszenie, lakier oraz ABS,
   kontrolę trakcji i ESP, potem START. Wybór zapisuje się
   w `user://settings.cfg`.
3. Bez gogli gra startuje na płasko, z kamerą za autem.
4. Zaznacz węzeł **Track** i w inspektorze przestaw **Rebuild** - tor
   przebuduje się od razu w edytorze.

### Ekran tytułowy

| PC / pad | gogle | działanie |
|---|---|---|
| strzałki / d-pad / gałka | drążek | wybór wiersza i zmiana wartości |
| Enter | spust lub A | START (na innym wierszu: skok do START) |
| Esc | - | wyjście z gry |

### Sterowanie - jazda

| PC | pad | gogle | działanie |
|---|---|---|---|
| W / strzałka w górę | RT | prawy spust | gaz |
| S / strzałka w dół | LT | lewy spust | hamulec; na PC/padzie w automacie na postoju wsteczny |
| - | - | prawy grip (trzymany) | wsteczny - wchodzi dopiero po zatrzymaniu auta |
| A, D / strzałki | lewa gałka | prawy drążek ↔ | skręt (opcja "Kierownica" zamienia drążki) |
| Spacja | B | lewy grip | hamulec ręczny |
| E / Q | RB / LB | lewy drążek ↑ / ↓ | bieg w górę / w dół (manual) |
| R | Y | klik prawego drążka | nowe auto (na trasie: strata życia) |
| - | - | A | ABS wł./wył. |
| - | - | B | ESP wł./wył. |
| T | Back | X | kontrola trakcji (TCS/ASR) wł./wył. |
| - | - | Y krótko | ograniczenie skrętu z prędkością wł./wył. |
| C | - | - | kokpit / kamera z tyłu |
| F | - | klik lewego drążka | swobodny lot (podgląd toru) |
| Esc | Start | Menu | powrót do ekranu tytułowego |
| - | - | Y przytrzymany 0,8 s | wycentruj widok |

### Swobodny lot

| PC | gogle | działanie |
|---|---|---|
| strzałki | prawy drążek | ruch |
| Q / E | lewy drążek | dół / góra |
| Shift | prawy spust | przyspieszenie |
| prawy przycisk myszy + ruch | - | rozglądanie |

### Testy bez okna

```
godot --headless --xr-mode off -s res://tests/drive_test.gd -- 95 sport auto
godot --headless --xr-mode off -s res://tests/assist_test.gd -- wet
godot --headless --xr-mode off -s res://tests/engine_test.gd
godot --headless --xr-mode off -s res://tests/title_test.gd
```

`--xr-mode off` jest konieczne, bo bez runtime'u OpenXR Godot wisi
przy zamykaniu.

---

## Jak opisany jest tor

Tor to lista odcinków w `scripts/stunt_track.gd`. Każdy odcinek to słownik:

| klucz | znaczenie |
|---|---|
| `len` | długość w metrach |
| `curve` | skręt w stopniach na metr, dodatni w prawo |
| `pitch` | nachylenie w stopniach, dodatnie pod górę |
| `bank` | przechyłka w stopniach, dodatnia = prawa krawędź niżej (na zakręt w prawo) |
| `width` | szerokość jezdni w metrach |
| `gap` | `true` — dziura w torze, czyli miejsce do przeskoczenia |
| `surface` | nawierzchnia: `"dry"` (domyślna), `"wet"` (~0,7 przyczepności), `"ice"` (~0,12) |

Przykład:

```gdscript
{"len": 25.0, "pitch": 14.0},      # rampa w górę
{"len": 18.0, "gap": true},        # przerwa — tu się skacze
{"len": 30.0, "pitch": -8.0},      # lądowanie na zjeździe
```

`pitch`, `bank` i `width` są płynnie interpolowane od wartości
poprzedniego odcinka, więc nie trzeba pisać osobnych odcinków
przejściowych — wejście w przechyłkę robi się samo.

Domyślną trasę możesz podmienić bez ruszania kodu: wypełnij pole
`Segments` w inspektorze węzła **Track**. Pusta lista = `DEFAULT_TRACK`
ze skryptu.

### Dwie decyzje projektowe warte uwagi

**Kierunek liczony jest z kątów yaw i pitch, nie z ramy Freneta.**
Na prostym odcinku krzywizna wynosi zero, więc normalna krzywej jest
nieokreślona i tor zaczyna się obracać wokół własnej osi. Dwa kąty
nie mają tego problemu.

**Tor nie zamyka się w pętlę.** Domknięcie obwodu wymaga dobrania
końcowych odcinków tak, by wrócić dokładnie do punktu startu. To osobny
problem i sensowniej go rozwiązać, gdy już wiadomo, jak tor ma jeździć.

---

## Co dalej

- **Etap 2** — samochód: **zrobione**, `scripts/stunt_car.gd`.
  Realistyczny model: opony Pacejki z relaksacją, silnik z krzywą momentu,
  6 biegów, LSD, ABS, stabilizatory. Celowo bez `VehicleBody3D`.
- **Etap 3** — samochód na torze. Przydadzą się `nearest_sample()`
  i `lateral_offset()` na dole `stunt_track.gd`. Szukają liniowo,
  czyli wolno; przy dłuższych torach trzeba będzie siatki przestrzennej
  albo wyszukiwania od ostatniej znanej próbki.
- **Etap 4** — lot i lądowanie. Gdy wszystkie koła tracą kontakt,
  zostaje czysta balistyka. Model uszkodzeń to licznik sumujący energię
  twardych lądowań.
- **Etap 5** — przeciwnik i struktura wyścigu.

---

## Eksport na Questa

Wszystko jednym poleceniem: `./quest.sh` (build, wgranie, start), `./quest.sh help` pokazuje resztę.
Poniższe kroki ręczne są potrzebne tylko na nowym komputerze.

1. **Szablony eksportu**: Editor → Manage Export Templates → Download.
2. **Godot OpenXR Vendors**: wtyczka z AssetLib (szukaj „Godot OpenXR
   Vendors”). Bez niej Quest nie dostanie loadera Meta.
3. **Android SDK**: Editor → Editor Settings → Export → Android, wskaż
   ścieżkę do SDK i debug keystore.
4. W presecie eksportu Android włącz w sekcji XR tryb OpenXR i
   zaznacz Meta jako dostawcę.
5. Tryb developerski na goglach, `adb devices` powinno je widzieć,
   potem eksport APK albo „one-click deploy”.

Od Godota 4.4 APK pakuje się prosto z edytora, bez zewnętrznych narzędzi.

### Ustawienia, które już są w `project.godot`

- `physics_ticks_per_second = 240` — sztywne sprężyny i lądowania
  z dużej wysokości rozsypują się przy 60 Hz.
- `physics_interpolation = true` — fizyka szybsza niż klatki, więc
  ruch musi być interpolowany.
- `renderer/rendering_method = "mobile"` — wymagane na Queście.
- `msaa_3d = 2` (4x) — na płaskich, nieteksturowanych wielokątach
  robi największą różnicę w czytelności krawędzi.

W Godocie 4.6 Jolt jest domyślnym silnikiem fizyki. We wcześniejszych
wersjach włącz go ręcznie: Project Settings → Physics → 3D → Physics Engine.

---

## Licencja

GPL-3.0-or-later. Plik `LICENSE` zawiera tylko notę — pełny tekst
licencji pobierz z <https://www.gnu.org/licenses/gpl-3.0.txt>
i zapisz w jego miejscu.
