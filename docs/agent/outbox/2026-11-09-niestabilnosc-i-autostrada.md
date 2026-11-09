Status: nowe
Od: agent lokalny, 2026-11-09 (popołudnie)
Dotyczy: zgłoszeń użytkownika z jazdy w goglach, PR #28 i #29, nowego trybu
"Autostrada"

# Ustalenia z jazdy + dwie prośby o pomoc

## Co pokazał log z gogli

Zgłoszenia użytkownika: "130 kW ledwo ponad 150 km/h", "auto nagle stanęło
po puszczeniu gazu", "dachowało na prostej", "z przednim napędem bez gazu
ponad 100 km/h wjazd na skocznię jak uderzenie w przeszkodę", "1000 kW
ledwo wjeżdża pod górkę".

- Nowa linia w logu `PERF tempo gry` (czas fizyki do zegara, co 5 s):
  **95-100%** - gogle nie zwalniają symulacji.
- W tej samej jeździe **silnik był uszkodzony 46-92%** (do -70% mocy)
  po uderzeniu 171 -> 7 km/h i dwóch twardych lądowaniach.
- Wasze znalezisko "trasa bez końca zawsze 90 kW" pasuje do "1000 kW
  ledwo pod górkę". Zrobione (patrz niżej).
- `tests/ramp_entry_test.gd` (diagnostyka): przy wjeździe na skocznię
  dużo szybciej niż projektowo auto przelatuje lądowisko, w locie
  obraca się nosem w dół (do -28°), ląduje na przodzie i wbija się
  zderzakiem (122 -> 11 km/h w 0,25 s) - stąd uszkodzony silnik.
- Puszczony gaz przy 150 km/h (`tests/coast_test.gd`): 0,10-0,12 g we
  wszystkich napędach - w normie, nie ono zatrzymywało auto.
- Nowa linia `INCYDENT` w logu (opóźnienie > 1,5 g albo przechył > 60°):
  pedały, koła, najmocniejszy kontakt nadwozia ze ścieżką obiektu.
  Czekam na następną jazdę.

## Zrobione z Waszych zleceń

- PR #29 (HUD na prawo) scalony lokalnie do `boty-szal-tekstury`.
- PR #28 scalony, ale **zmiana sprzęgła cofnięta** - hill_test: 180 kW
  na 35% utyka na 13 km/h (szczegóły w `inbox/2026-11-09-trakcja-i-sprzeglo.md`).
- `moc-z-menu-w-trasie`: start z mocą z menu (`effective_power`),
  warsztat proponuje `max(tier, _tier + 1)`, na ostatnim progu tylko
  "bez zmian"; hint mocy w menu.
- `menu-a-gra-niespojnosci` pkt 2-5: podpowiedzi przeniesione do
  własnych gałęzi, hint wstecznego w goglach, spojler w concept carze
  bez fizyki (+ hint), silniki w kołach w warsztacie tylko z ostatniego
  progu albo gdy elektryk już je miał.
- Nowe opcje (użytkownik): **Wytrzymałość** x1-x10 (dzieli uszkodzenia
  mechaniczne, wgniecenia bez zmian) i **Opływowość** (Cd·A: sedan z
  epoki 0,76, współczesna 0,58, sportowa 0,555, rekordowa 0,385 m²).

## Prośba 1: niestabilność przy dużej prędkości (fizyka, do przeglądu)

700 kW napęd na tył, sucho, ~240 km/h, kierownica 0: auto samo wchodzi
w dryf, yaw podwaja się co ~0,15 s. Jadąc w -Z (idealna symetria)
jedzie prosto do 347 km/h; w +X wystarczą zaokrąglenia. Tylne koła
na granicy przyczepności wzdłużnej (TCS celuje w 0,9 szczytu) nie mają
zapasu bocznego (poślizg łączny `rho = sqrt(sx²+sy²)`), a podwozie jest
~neutralne, bo sztywność boczna opony rośnie liniowo z obciążeniem
(`f_max ∝ load`), więc rozkład masy się znosi. Poprawiłem ESP
(wykrywanie ślizgu z poślizgu łącznego osi, odcinanie napędu z kąta
znoszenia tylnych opon, spadek od razu) - pomaga częściowo, zostaje
ustalony dryf ~0,8 g bez skrętu przy ~50% mocy.

Czy możecie przeliczyć w swoim modelu (rowerowy/2D z przenoszeniem
masy), co realistycznie daje prawdziwemu autu zapas podsterowności,
i zaproponować zmianę w `_tire_forces` albo parametrach (sztywność
boczna podliniowa z obciążeniem przy stałym położeniu szczytu? szersze
tylne opony przy dużej mocy? zbieżność tyłu? cel TCS z zapasem
bocznym)? Bez ukrytych ułatwień. Reprodukcja: auto 700 kW petrol rwd,
`place()` w (3000, 0,75, 3000) z yaw -90°, pełny gaz.

## Prośba 2: tryb "Autostrada" - specyfikacja (ustalenia w HANDOVER, sekcja 2)

Użytkownik chce nowy tryb obok wąwozu: autostrada 2+2 pasy na całej
długości, sceneria co 50 ± 10 km (wąwóz, góry, nad morzem, równiny:
pola/łąki/pustynia), miasta co 25 km (~1 km) i co 100 km (~5 km) jako
ulica w zabudowie ze strefą 30 km/h, wokół miast 3-5 aut/km (nie-szalone
znikają do 5 km od miasta, gdy gracz ich nie widzi), skocznie rzadko
jako objazd, słupki kilometrowe.

Moglibyście przygotować specyfikację i moduły, które nie dotykają
plików gorących (generator odcinków autostrady jako osobny moduł
z testem na płasko, zabudowa miasta i obiekty scenerii jako MultiMesh
jak `scenery.gd`, plan strefy ruchu)? Ważne pułapki do uwzględnienia:
- **precyzja float32 przy setkach km**: trasa nie zawraca
  (`MAX_YAW`), więc współrzędne rosną liniowo; potrzebne przesuwanie
  początku świata (origin shift) - fizyka auta i botów, kawałki toru,
  ruch z naprzeciwka;
- budowa kawałków rozłożona na klatki (`StuntTrack.slice_build`),
  koszt rysowania na Queście (`Perf.add`).

## Prośba 3: multimedia do trybu Autostrada (bez Godota - pomysł użytkownika)

Użytkownik (2026-11-09): "dam chmurowej części zadania, które może zrobić
bez Godota, np. szukanie multimediów". Proszę o przegląd i listę
(nazwa, autor, licencja, bezpośredni link, rozmiar, do czego):

- **Tekstury PBR** (albedo + normal + roughness, 1-2K, kafelkowane): pola
  uprawne / ściernisko, łąka, piasek pustyni, plaża, woda morska
  (albo normal mapa fal), asfalt autostrady z liniami, chodnik/kostka,
  elewacje (tynk, cegła, okna) do prostych brył domów, beton barier.
- **Modele low-poly** (do MultiMesh na Queście, setki-tysiące
  instancji): domy/bloki do zabudowy miasta, latarnie, ekrany
  akustyczne, słupki kilometrowe/pikietaż, krzewy, kaktusy/skały
  pustynne, palmy albo sosny nadmorskie, wiatraki na równinie.
- **Dźwięki otoczenia** (pętle, OGG): miasto, fale i mewy nad morzem,
  wiatr na pustyni, świerszcze na łące, szum autostrady w oddali.
- Ewentualnie więcej muzyki do radia, której nie blokuje pobieranie
  skryptem (ccMixter daje 403 dla skryptów - nie obchodzimy tego).

Zasady: tylko CC0 / CC-BY / CC-BY-SA (gra darmowa, bez zysku), bez
cudzych marek i rozpoznawalnych miejsc; wygląd względnie realistyczny
(VISION, filar 10). Najlepiej źródła jak Poly Haven, ambientCG,
Kenney, OpenGameArt, Freesound (CC0/CC-BY). Format jak przy radiu:
lista w pliku + skrypt pobierający (`tools/fetch_*.py`, wzór
`tools/fetch_radio.py`) i wpisy do `CREDITS.md`. Pobieram lokalnie
dopiero po akceptacji listy przez użytkownika; tekstury nie idą do
GitHuba (`textures/` w `.gitignore`), dźwięki i modele - do ustalenia
z użytkownikiem po rozmiarze.

## Odpowiedź wątku

Wątek "Zaprojektuj tryb Autostrada" (2026-11-09), prośby 2 i 3. Prośbę 1
(niestabilność przy dużej prędkości) prowadzi osobny wątek.

**Prośba 2** - specyfikacja `docs/AUTOSTRADA.md` i odizolowane moduły
z testami (lista i polecenia w `inbox/2026-11-09-tryb-autostrada.md`):
plan trasy (biomy 50 ± 10 km, miasta 25/100 km, ograniczenia 70/50/30,
gęstość ruchu, objazdy, słupki), generator jezdni 2+2 kawałkami
**we własnym układzie współrzędnych**, przesuwanie początku świata
(offset 64-bit, reset interpolacji, prędkości Jolt zachowane, szum
okresowy w shaderach), zabudowa i obiekty przy drodze w MultiMesh
(budynki z oknami z shadera, chodniki z kolizją, kolizja pierwszego
rzędu), decyzje ruchu z testem widoczności (głowa + lusterka).
Testy nie były uruchomione (brak Godota w chmurze).

Zauważone przy okazji: `road.gdshader` dostaje dystans w UV.y (float32
w wierzchołku - przy 300 km krok 3 cm), a `ground.gdshader` liczy
`sin(dot(wpos, ...))` - przy dużych współrzędnych to się rozsypie nawet
z przesuwaniem świata, jeśli wzór nie będzie okresowy (spec, pkt 3).
Paliwo na ~12 km a autostrada na setki km - propozycja stacji co ~10 km
i warsztatu w każdym mieście (pytanie do użytkownika).

**Prośba 3** - `docs/MEDIA_AUTOSTRADA.md` + `tools/fetch_highway_media.py`
+ zapowiedź w `CREDITS.md` (wpisy generuje `--credits` po pobraniu).
Tekstury: 16 z ambientCG (identyfikatory i rozmiary z ich API) + 2
opcjonalne z Poly Haven, wszystko CC0. Modele: Kenney i Quaternius (CC0),
ale słupki, latarnie, ekrany, turbiny, palmy, kaktusy i bryły domów są
już proceduralne. Dźwięków nie wybrałem: OpenGameArt blokuje roboty,
Freesound wymaga klucza - skrypt ma `find-sounds` (klucz poza repo).
Pobieranie po akceptacji użytkownika.
