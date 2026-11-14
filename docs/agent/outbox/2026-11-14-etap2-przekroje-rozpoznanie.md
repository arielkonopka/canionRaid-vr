# Etap 2 (przekroje): co umie dziś generator, prośba o zlecenie

Od: agent lokalny (2026-11-14, w nocy). Etap 1 (zdarzenia) jest wpięty
i scalony (PR #90, #92). Etap 2 to decyzje projektowe, więc najpierw do
Was. Niżej rozpoznanie kodu, żeby zlecenie mogło być konkretne.

## Stan dziś

- **Jezdnia autostrady** = `HighwayGenerator._seg(len, curve, bank,
  width, limit)`. Przekrój opisuje tylko `width` (stała 11,25 m: 2 pasy
  po 3,75, pas awaryjny 3,0, opaska 0,75). Zmienną szerokość już się
  używa: stacja paliw (`WIDTH + SERVICE_EXTRA_W`) z przejściem w
  `StuntTrack` między próbkami.
- **Oznakowanie** jest w shaderze `road.gdshader` (layout 1/2 =
  autostrada). Linie są **na sztywno**: lewa krawędź 0,6-0,75 m, prawa
  `w - 3`, przerywana w 4,5 m, koleiny dla 2 pasów. Zwężenie do 1 pasa,
  2+1 czy pas dla wolnych wymagają nowego parametru przekroju
  w wierzchołkach (np. UV2 albo COLOR: liczba pasów, przesunięcie,
  ciągła/przerywana) i rozgałęzienia w shaderze. Koszt GPU pomijalny.
- **Pasy botów i auta z naprzeciwka**: `HighwayGenerator.lane_center(lane,
  oncoming, width)` liczy oś od lewej krawędzi ze stałych LANES i
  LANE_W. Przekrój z inną liczbą pasów musi tu dać inną oś, a boty
  (`BotDriver.lane`, `hwy_lane_off`) i `TrafficZone` (pas 0/1) muszą
  znać pasy w danym miejscu (`sample["lanes"]`?).
- **Druga jezdnia** jest lustrem pierwszej (`_oncoming_pose`, kolizja,
  barierka na pasie rozdziału). Roboty z przejazdem na drugą jezdnię
  (1+1 na jednej nitce) to: przerwa w barierce, dwie łagodne esowe
  zmiany pasa, ruch z naprzeciwka na NASZEJ jezdni (jest już
  `OncomingCar.wrong_way` z etapu 1 - kinematyczne auto na naszym
  pasie). To największa pozycja etapu 2.
- **Rozjazd L/P (`_split`)**: w generatorze autostrady nie ma
  rozgałęzień. W wąwozie (`TrackGenerator`) jest objazd równoległym
  pasem przy skoczni. Rozjazd z wyborem drogi to drugi tor
  (EndlessTrack zna jeden ciąg kawałków) - proponuję poza etapem 2
  albo jako "pozorny" rozjazd: dwie nitki obok siebie przez
  200-400 m, potem znów jedna.
- **Pachołki / bariery robót**: nie ma modeli. MultiMesh z prymitywów
  (stożek, blok) wg Waszej propozycji. Kolizja: CCD działa na
  StaticBody - pachołek jako lekkie RigidBody dałby fizykę, ale to
  koszt. Proponuję statyczne bez kolizji (przejechanie = przewrócenie
  wizualne?) albo kolizję tylko dla barier betonowych.

## Pytania / prośba

1. Zlecenie etapu 2 w trybie jak dotąd: Wy - czysta logika przekroju
   (np. `SectionPlan`/funkcja `section_at(d)` -> {pasy, przesunięcie,
   linie, pachołki, limit}) z testem; ja - geometria, shader, boty,
   rendery, bench.
2. Kolejność wewnątrz etapu: proponuję **zwężenie do 1 pasa** (sam
   shader + lane_center + boty), potem **2+1 / pas dla wolnych**,
   potem **roboty z przejazdem na drugą jezdnię** (największe), rozjazd
   "pozorny" na końcu albo wcale.
3. Pachołki: z kolizją czy bez?

Gogle odłączone - bench etapu 1 i rendery zdarzeń przy następnym
podłączeniu.
