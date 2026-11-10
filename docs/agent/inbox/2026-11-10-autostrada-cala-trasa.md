Status: nowe
Od: wątek w chmurze "Zaprojektuj tryb Autostrada" (noc 2026-11-09/10)
Decyzje użytkownika (2026-11-09, przed snem): "cała trasa jest na
autostradzie (ruch w dwie strony), furia drogowa, także między botami".
Ustalenia z pytań spec. pkt 11 są już w HANDOVER sekcja 2 (ruch między
miastami 0,5-1/km, 140→70→50→30, stacje co ~20 km, warsztat w mieście,
nasyp 1 m) - **nic tu nie zmieniam, to są odpowiedzi użytkownika**.
Plan nocy: `inbox/2026-11-10-plan-nocy.md` (prowadzi inny wątek).

# Autostrada na całej trasie + etap 3 (ruch w obie strony)

## W tym PR-ze (moduły odizolowane, testy do uruchomienia)

- `HighwayPlan.traffic_density`: między miastami **0,5 → 1 auta/km**
  (rośnie przez pierwsze 200 km - filar 11), przy mieście 3-5/km;
  nowe `base_traffic(d)`, `in_city_zone(d)` (`in_traffic_zone` zostaje
  jako alias).
- `TrafficZone.step`: znikanie bez reguły "poza strefą miasta = zawsze";
  zamiast tego **nadmiar** - gdy w oknie jest więcej niż `wanted + 1`
  spokojnych aut (wyjazd ze strefy miasta), znikają najdalsze
  niewidoczne. Auta w furii i widoczne nigdy.
- `HighwayGenerator.lane_center(lane, oncoming)`: środki pasów
  autostrady względem osi naszej jezdni: nasza 0 (prawy) **+0,75**,
  1 (lewy) **-3,0**; druga jezdnia 0 **-15,0**, 1 **-11,25** (przy
  WIDTH 11,25 i HIGHWAY_MEDIAN 3).
- `tests/highway_plan_test.gd`: ruch między miastami (średnio > 0,3,
  bez nadmiaru), gęstości, `lane_center`.

```
godot --headless --xr-mode off -s res://tests/highway_plan_test.gd </dev/null
godot --headless --xr-mode off -s res://tests/highway_gen_test.gd -- 4242 300 </dev/null
```

## Do zrobienia po stronie agenta (gorące pliki)

### A. Autostrada domyślną trasą

1. `GameSettings.track_mode` domyślnie `"autostrada"`; `SETTINGS_VERSION`
   9 z migracją **jednorazową** zapisanego `"canyon"` → `"autostrada"`
   (pułapka z HANDOVER: zapisany wybór wygrywa z nowym domyślnym; gracz
   nigdy świadomie nie wybierał wąwozu - był domyślny). Wąwóz zostaje
   w menu jako druga trasa; `title_test` po zmianie.
2. Opis w menu: Autostrada pierwsza na liście.
3. Wąwóz jako sceneria autostrady to biom `canyon` (etap 2 spec.) - nie
   odcinki starego generatora.
4. Zgodność z wątkiem "Usuń pozostałości dróg na estakadach" (inbox
   `2026-11-09-pozostalosci-estakad.md`, etap 1 "jeden tryb trasy"):
   tam `track_mode` = "canyon" + przyszła autostrada; tu domyślna
   staje się autostrada - bez sprzeczności, tylko inna wartość domyślna.

### B. Pasy (błąd do poprawki niezależnie od reszty)

Dziś `_spawn_bot`, `BotDriver` (`lane_w := (w - 1) / 3`, cel spokojnej
jazdy `target_off = lane_w`), `_oncoming_xf` i pozycja startu liczą
**trzy pasy po (w - 1) / 3**. Na autostradzie (11,25 m: 2 pasy + pas
awaryjny 3 m + opaska 0,75 m) to daje "prawy pas" +3,4 m - **na pasie
awaryjnym**, a środkowy 0 m - okrakiem przy linii. Z naprzeciwka
-17,7 m (pas awaryjny tamtej jezdni) i -10,8 m.
Propozycja: `EndlessTrack.lane_offset(dist, lane, oncoming := false)` -
w trybie Autostrada `HighwayGenerator.lane_center(...)`, w wąwozie dzisiejszy
wzór (pasy -1/0/+1 × (w-1)/3). Używać w `_spawn_bot`, `BotDriver`
(spokojna jazda: prawy pas, wyprzedzanie: lewy; szał: `lane_w` = odstęp
pasów 3,75), `_oncoming_xf` (pasy 0/1 zamiast -1..1). Druga jezdnia ma
dziś tę samą siatkę co nasza, więc jej pas awaryjny jest od strony pasa
rozdziału - siatkę drugiej jezdni odbić (UV.x z minusem w `_build_mesh`
dla drugiej jezdni), żeby linie zgadzały się z ruchem.

### C. Ruch w obie strony (etap 3 spec.)

1. **Nasza jezdnia**: w trybie Autostrada liczbę spokojnych botów
   wyznacza `TrafficZone` (co ~0,5 s `step`), nie `bot_limit`. Lista aut
   dla `step`: `{"id": instance_id, "dist": drv.dist, "lane", "oncoming":
   false, "raging": drv.rage > 0.05, "visible": TrafficZone.visible(head,
   head_fwd, car_fwd, pos)}` (`head` = kamera XR). Kandydatów do dodania
   sprawdzić `visible` i dopiero wtedy `_spawn_bot(dist, lane)` z
   `speed_kmh`. Usuwanie: `_retire_bot` (pula, bez szarpnięcia).
   Furiaci i waśnie bez zmian (`BotDriver`, `FeudDirector` - inbox
   `wasnie-botow`): każde auto ruchu może wpaść w szał (wyprzedzenie 25%,
   kontakt, posiłki, waśnie między botami w zasięgu wzroku).
2. Szczyt w strefie miasta: ~9 aut w oknie -300…+1500 m + furiaci.
   `BotLod` z budżetem 8 aut z fizyką wystarcza (dalsze na szynie).
   Pula botów (dziś 6 na starcie) - zwiększyć do ~12, budowa rozłożona
   na klatki jak dziś. Pomiar: `Perf` "boty" w strefie dużego miasta.
3. **Druga jezdnia**: `_update_oncoming` w trybie Autostrada z
   `TrafficZone` (wpisy `"oncoming": true`) zamiast losowego zegara;
   `ONCOMING_MAX` 4 → ~12 (kinematyczne, tanie; pula). Pasy 0/1 z
   `lane_center(lane, true)`, prędkość `speed_kmh` z planu (w mieście 30).
   Widoczność z naprzeciwka: zwykle widoczne z daleka - znikają dopiero
   za graczem (`dist` < gracz - 300 m), co `step` już robi.
4. **Potyczki na drugiej jezdni** (`OncomingSkirmish`, PR #46):
   `fits(width)` wymaga ≥ 13 m, a jezdnia autostrady ma 11,25 m -
   w trybie Autostrada **nie odpaliłyby nigdy**. Scenki potrzebują dwóch
   pasów obok siebie: sprawdzać szerokość dwóch pasów + pasa awaryjnego
   (≥ 10,5 m) albo podawać `fits` szerokość bez opaski.
5. Test: `endless_test -- 180 petrol 777 400 autostrada` przez strefę
   pierwszego miasta (25 km) - liczba aut w oknie w logu, bez auta na
   pasie awaryjnym (|offset - lane_center| < 1 m dla spokojnych botów).

### D. Rozwidlenia

Oznakowanie wysepki (czoło z żółto-czarną tablicą, niebieski znak nakazu
obu stron, trójkąt ostrzegawczy 120 m wcześniej) robi inny wątek
w `stunt_track`. W trybie Autostrada rozwidleń jezdni nie ma - wybór
drogi dają miasta (niżej).

### E. Miasta, po których da się jeździć (życzenie użytkownika, później)

Użytkownik: "chciałbym miasta, po których da się jeździć, ale generowane
w sposób leniwy". Wątek "Oceń pomysł przejazdów przez miasto" i skrzynka
(PR #44/#45: graf ulic niejawny - funkcja ziarna i siatki) już to
opisują. Dla Autostrady: miasto z `HighwayPlan.city(n)` = siatka ulic
wokół drogi przelotowej (ta sama `dist`), przecznice w miejscach przerw
zabudowy `HighwayScenery` (`STREET_EVERY`, dziś bez jezdni). Wymaga
grafu dróg zamiast jednej linii `dist` - **etap 5**, po etapach 2-4.
