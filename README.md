# Canion Raid VR

Kaskaderska jazda VR w Godocie 4 pod Meta Quest 3: niekończący się wąwóz
z łupkowymi ścianami, generowany odcinkami, z trudnością rosnącą
z dystansem. Skocznie, garby, tunele (także dwunitkowe), rozwidlenia,
mokra i oblodzona jezdnia, deszcz, okna na morze. Na drodze jeżdżą
puste, zdalnie sterowane auta, które po stłuczce wpadają w szał drogowy.
Własna gra w gatunku stunt racerów, projektowana od początku pod gogle.

Zasady w skrócie:

- jedziesz bez końca, odcinek po odcinku; życia to auta - tracisz je
  przy dachowaniu, rozbiciu, wypadnięciu z trasy albo pustym baku;
- co 5 odcinków zjazd na stację paliw (przejeżdża się powoli pasem
  dystrybutorów), co 10 - zjazd do warsztatu z mocniejszym silnikiem;
- uderzenie w bota zabiera 20 s z czasu, ale bot się mści (taktyk szału
  jest kilka, konfigurowane w menu); uspokaja go tylko jazda zgodna
  z przepisami;
- fizyka auta jest realistyczna (opony Pacejki, silnik z krzywą momentu,
  skrzynia, dyferencjały, ABS/TCS/ESP), pomoce są jawne i wyłączalne.

Pełny stan projektu i decyzje: `HANDOVER.md`.

---

## Szybki start

1. Otwórz folder w Godocie 4.4 lub nowszym (rozwijane na 4.6.3).
2. F5 uruchamia ekran tytułowy. W podmenu: trasa (życia), samochód
   (napęd benzyna/diesel/elektryk, moc 90-700 kW - 1000 kW tylko dla
   elektryka z silnikiem w każdym kole, skrzynia, tył/4x4), nadwozie
   i opony (masa, spojler, opony, zawieszenie), systemy wspomagania,
   sterowanie, wygląd i widok, szał drogowy botów. Wybór zapisuje się
   w `user://settings.cfg`.
3. Bez gogli gra startuje na płasko, z kamerą za autem.
4. Na Questa: `./quest.sh` (testy, build, wgranie, start).

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

## Jak powstaje trasa

Trasę bez końca składa `scripts/track_generator.gd` z modułów (prosta,
łuk z przechyłką, szykana, garb, podjazd, skocznia, tunel, rozwidlenie,
zjazd na stację / do warsztatu). Każdy odcinek trasy (sekcja) to lista
segmentów, z których `scripts/stunt_track.gd` liczy próbki i buduje
geometrię; `scripts/endless_track.gd` dobudowuje sekcje przed autem
i usuwa za nim. Skocznie są liczone z balistyki pod prędkość, jaką auto
danego progu mocy osiąga na rozbiegu (pomiar `tests/runup_test.gd`).

Segment to słownik:

| klucz | znaczenie |
|---|---|
| `len` | długość w metrach |
| `curve` | skręt w stopniach na metr, dodatni w prawo |
| `pitch` | nachylenie w stopniach, dodatnie pod górę |
| `bank` | przechyłka w stopniach, dodatnia = prawa krawędź niżej (na zakręt w prawo) |
| `width` | szerokość jezdni w metrach (na starcie 14,8 m - trzy pasy na dwa auta) |
| `gap` | `true` — dziura w jezdni (tylko na trasie pokazowej) |
| `surface` | `"dry"`, `"wet"` (~0,7 przyczepności), `"ice"` (~0,12); `""` = według strefy |
| `limit` | ograniczenie prędkości od tego miejsca [km/h] |
| `meta` | znaki, tunele, wyspy, zjazdy - patrz generator |

`pitch`, `bank` i `width` są płynnie interpolowane od wartości
poprzedniego segmentu. Kierunek liczony jest z kątów yaw i pitch, nie
z ramy Freneta (na prostej rama Freneta jest nieokreślona) - dlatego
na razie nie ma pętli ani jazdy do góry nogami.

### Tekstury

Skały (ściany wąwozu, góry nad tunelami, mech) używają tekstur z
[freepbr.com](https://freepbr.com/) w katalogu `textures/`. Licencja nie
pozwala ich rozpowszechniać, więc **nie ma ich w repozytorium** - bez
nich gra używa proceduralnego łupku (`shaders/shale.gdshader`). Żeby
zbudować wersję z teksturami, pobierz z freepbr.com: Cavern Walls,
Ocean Rock (wersje "-bl") i Mossy Rock Model do `textures/`; wycinek
mchu (`textures/derived/moss_*.png`) robi `python3 tools/make_moss.py`
z atlasu Mossy Rock Model.

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

Canion Raid VR, Copyright (C) 2026 Ariel Konopka.

GPL-3.0-or-later - pełny tekst w pliku `LICENSE`. Program jest wolnym
oprogramowaniem: możesz go rozpowszechniać i modyfikować na warunkach
GNU General Public License w wersji 3 albo (do wyboru) późniejszej.
Rozpowszechniany jest BEZ JAKIEJKOLWIEK GWARANCJI.

Model "Car Concept" (`models/concept_car/`) - Darmstadt Graphics Group
GmbH i Eric Chadwick (konwersja glTF, Khronos glTF Sample Assets),
oryginał "Free Concept Car 004" - Unity Fan; licencja
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Zmiany:
uproszczona siatka i mniejsze tekstury pod Questa, usunięte logotypy
Khronos, wersja dla botów bez wnętrza (`tools/prepare_concept_car.sh`).

Wtyczka `addons/godotopenxrvendors` ma własną licencję (MIT, plik
`addons/godotopenxrvendors/LICENSE`).
