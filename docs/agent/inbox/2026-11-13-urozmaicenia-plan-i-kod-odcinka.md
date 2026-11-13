Status: zrobione - etap 1 (2026-11-13), bench na Queście czeka na gogle
Od: wątek w chmurze "Zaplanuj urozmaicenia trasy i miasta" (odpowiedź na
outbox/2026-11-13-plan-urozmaicen.md)
Decyzje użytkownika: 2026-11-11 - kod odcinka ukryty przed graczem (tylko
testy, logi, odtwarzanie z ziarna); pułapka "znak kłamie" zostaje, ale
rzadko (najwyżej raz na kilkadziesiąt km, dopiero dalej na trasie).
2026-11-13 do agenta: "zapytaj chmurę o ten plan".
Decyzja użytkownika 2026-11-13 21:42 UTC (karta w wątku w chmurze):
kolejność "Przekroje, potem budowle" - etapy 1 zdarzenia, 2 przekroje,
3 budowle, 4 pułapki, 5 krajobraz i miasto, jak w tabeli niżej.
Otwarte: nic.
Projekt: dokument "Urozmaicenia trasy: odcinek z 4 bajtów".

# Urozmaicenia trasy: plan etapów i pierwsze zlecenie (kod odcinka + zdarzenia)

## Część A: plan i kolejność

Trasa dzielona jest na odcinki po 1,2 km (~30 s przy 140 km/h). Każdy
odcinek opisują 4 bajty: budowla (b0), przekrój (b1), pułapka z katalogu
złej inżynierii ruchu (b2) i zdarzenie z botami (b3) z akcentem
krajobrazu. Nad surowym hashem działa reżyser napięcia: grupy 3-5
odcinków build -> peak -> (fade) -> rest, kalendarz pierwszych wystąpień
po km, gramatyka sąsiedztwa i budżet kosztu na Queście. To wszystko jest
już w `SegmentCode` (część B) - geometria i boty mają tylko wykonać to,
co kod mówi.

| Etap | Co | Dlaczego w tym miejscu | Koszt Quest |
|---|---|---|---|
| 1 | `SegmentCode` w trasie + **bajt zdarzeń** (b3): korek, pod prąd, zasadzka, pościg od tyłu, blokada, waśń, wolna ciężarówka | "za mało w gracza" nie jest rozwiązane (proporcja 1 : 6 przy 140 km/h, strojenie ruchu nie da więcej). Boty, gangi, ekstremista i `OncomingSkirmish` już są - to głównie scenariusze z gotowych klocków, bez nowej geometrii. Daje od razu rytm napięcia, który potem "ubierają" budowle | tylko boty, limit jak dziś (koszt zdarzeń w budżecie) |
| 2 | **przekroje** (b1): zwężenie do 1 pasa, 1+1, roboty z przejazdem na drugą jezdnię, rozjazd L/P (`_split`), 2+1, pas dla wolnych | zmienia sposób jazdy przy minimalnym koszcie (to ta sama jezdnia, inne pasy i pachołki); zdarzenia z etapu 1 nabierają sensu (blokada na zwężeniu, ciężarówka na 1+1, pod prąd na robotach) | pachołki/bariery jako MultiMesh |
| 3 | **budowle** (b0): tunel (jest już w generatorze), podjazd górski kilometrami, wiadukt kolejowy z pociągiem, most nad rzeką, estakada, serpentyny | największa różnorodność za oknem, ale najdroższa w pracy (modele, LOD, oświetlenie tunelu bez OmniLight) | największy - bench przed/po każdej budowli |
| 4 | **pułapki** (b2) po kalendarzu: zakręt zaciskający się, zwężenie za tunelem, niski wiadukt, boczny wiatr, przejazd kolejowy... | pułapka potrzebuje budowli/przekroju (zwężenie za tunelem = tunel + zwężenie), więc po 2 i 3. Każda z jawną zapowiedzią >= 4 s przed nią | mały |
| 5 | akcenty krajobrazu (wrak, wiatraki, zamek, billboard...), miasto liniowe (b0 = 7) | dekoracja, gdy reszta działa | średni |

Każdy etap: `drive_test` (oba typy skrzyni), testy logiki, bench na
Queście przed i po (Perf), rendery dla użytkownika.

Gęstość z symulatora (ziarna 777 i 1): zdarzenie w ~40% odcinków
(4,5-5 na 10 km), wrogie (pod prąd, zasadzka, pościg, blokada, waśń)
~2-3 na 10 km, czyli co 1,5-2 min przy 140 km/h; pierwsze 3 odcinki
spokojne; odpoczynek co 3-5 odcinków (rest bez zdarzeń i pułapek).

## Część B: pierwsze zlecenie

### Co jest w PR

- `scripts/segment_code.gd` (`SegmentCode`) - czysta logika jak
  `WeatherPlan`. `SegmentCode.new(ziarno, weather := null)`:
  - `segment(k)` / `at(d)` -> słownik: `k, phase ("build"/"peak"/"fade"/
    "rest"), structure, s_len, s_param, section, change_at, variant,
    trap, trap_at, trap_level, event, ev_level, accent, cost, code`;
  - `index_at(d)`, `phase(k)`, `pack(s)` / `unpack(code)` (statyczne),
    `describe(k)` - jedna linia do logu, nazwy wartości w `STRUCTURES`,
    `SECTIONS`, `TRAPS`, `EVENTS`;
  - liczone leniwie po kolei (gramatyka i koszt patrzą wstecz), kolejność
    pytań niczego nie zmienia; z `WeatherPlan` ulewa podnosi koszt
    odcinka (mniej budowli i zdarzeń w ulewie).
- `tests/segment_code_test.gd` - kody z Pythona (ziarno 777, odcinki
  0-11), niezmienniki reżysera z pogodą i bez, kolejność pytań,
  pack/unpack.
- `tools/segment_code_sim.py` - odpowiednik w Pythonie. **W chmurze nie
  ma Godota** - sprawdzony był tylko on: ziarna 777, 1, 4242, 5 na 300 km
  OK, 176-189 różnych układów (budowla, przekrój, pułapka, zdarzenie).

### Do zrobienia po stronie agenta lokalnego

1. Testy (literówki typów w nowych plikach poprawiaj śmiało):
   ```
   godot --headless --import --xr-mode off </dev/null
   godot --headless --xr-mode off -s res://tests/segment_code_test.gd -- 777 </dev/null
   python3 tools/segment_code_sim.py 777 300
   ```
   Dodaj do zestawu.
2. **Kod w trasie.** Jeden `SegmentCode` na trasę Autostrady (obok
   `HighwayPlan` i `WeatherPlan`, to samo ziarno, z pogodą gdy "Pogoda:
   zmienna"). Odcinki liczone od początku trasy (`d` jak w planie).
   Przy wjeździe gracza w nowy odcinek: `print("ODCINEK ", describe(k))`
   (bez HUD - kod ukryty przed graczem). Bajty b0-b2 na razie tylko
   w logu; geometria przyjdzie w etapach 2-3.
3. **Zdarzenia (b3)** - wyzwalane raz na odcinek, gdy gracz jest
   ~300 m przed jego początkiem (scenariusz musi zdążyć się ustawić poza
   wzrokiem; spawn zawsze przez `_can_vanish` / `visible` jak dziś).
   `ev_level` 0-3 = ile aut / jak bardzo w szale. Z gotowych klocków:
   - 1 **korek**: na tym odcinku spokojne auta w naszą stronę gęściej
     (np. x2) i wolniej (0,5-0,7 limitu). Nie wrogie - oddech z napięciem.
   - 2 **kierowca pod prąd**: jedno auto na **naszej** jezdni jadące na
     gracza, lewym pasem (szybkim), start 900-1200 m przed graczem poza
     stożkiem. Zapowiedź >= 4 s (~155 m przy 140 km/h): spokojne auta
     przed nim włączają awaryjne i zjeżdżają na prawy pas, on miga
     długimi i trąbi. Punkty za minięcie bez kontaktu (jak przepuszczenie
     ekstremisty, za odstęp).
   - 3 **zasadzka**: dopóki nie ma wjazdów (etap 2), furiat(-ci) stoją na
     pasie awaryjnym / w zatoce 300-500 m przed graczem i ruszają, gdy
     gracz jest ~60 m od nich (VISION: "uciekanie przed furiatami,
     zwłaszcza z zasadzek" - premia za ucieczkę).
   - 4 **pościg od tyłu**: 1 + `ev_level` furiatów 350-500 m za graczem,
     jak spawn ekstremisty (lewy pas, szybciej niż limit). W lusterku
     rosną światła.
   - 5 **blokada**: dwa boty obok siebie przed graczem, zajmują oba pasy
     i jadą ~0,6 limitu; reagują na próbę wyprzedzenia (zajeżdżanie).
     Na zwężeniach (etap 2) jeszcze groźniejsze.
   - 6 **waśń gangów**: dwa gangi wrogie (`FeudDirector.roll_relations`
     wymuszone na wrogość) i po 1 + `ev_level` aut przed graczem
     w zasięgu wzroku - potyczka na naszej jezdni.
   - 7 **wolna ciężarówka**: auto 0,5 limitu na prawym pasie (wygląd
     ciężarówki, jeśli jest w `CarStyles`), za nią 1-2 zwykłe auta
     wyprzedzające "na trzeciego" (na 1+1 będzie to wyprzedzanie pod
     prąd).
   Wartości startowe - do oceny z użytkownikiem w goglach.
4. **Rytm a obecne losowania.** W odcinkach `rest` nic wrogiego się nie
   pojawia (ani ekstremista, ani nowa potyczka). Losowanie ekstremisty
   co km zostaje, ale tylko w `build`/`peak`. Limit botów jak dziś -
   zdarzenie, które się nie mieści, przepada (nie odkładamy).
5. **Test sceny** (np. `tests/segment_event_test.gd`, autopilot jak
   w `drive_test`, ~40 km): każde odblokowane zdarzenie pojawia się
   w swoim odcinku, nic wrogiego w `rest`, liczba botów <= limit, żadne
   auto nie znika w polu widzenia. Zmierz też spotkania w naszą stronę
   na km z zdarzeniami (wcześniej 1 : 6 przy 140 km/h).
6. **Quest:** bench przed i po w odcinku `peak` z pościgiem
   i z waśnią (najwięcej aut naraz). Jeśli drogo - obniż `ev_level`
   albo `COST_EVENT` w `SegmentCode` (koszt jest po to).

Testy jak zawsze: `drive_test` (oba typy skrzyni), `highway_plan_test`,
`weather_plan_test`, `segment_code_test`, nowy test sceny. Wynik do
HANDOVER.md.

## Odpowiedź agenta lokalnego

Etap 1 wpięty (2026-11-13). Bench na Queście jeszcze niezrobiony:
użytkownik odłączył gogle.

**SegmentCode w Godocie.** Były 3 poprawki, w GDScript i w symulatorze:
- wcięcie w `describe`;
- budowla bez kosztu (podjazd) nie jest wycinana przy przekroczeniu
  budżetu. Wcześniej zostawał pas dla wolnych bez podjazdu (ziarno 5
  z pogodą);
- niezmiennik kosztu w teście dopuszcza przekroczenie tylko wtedy, gdy
  nie ma już czego ciąć (ulewa po ulewie).

Ziarna 777, 1, 4242, 5, 33, 11 i 2026 są OK w obu implementacjach.
`segment_code_test 777` jest w `quest.sh test`.

**Kod w trasie.** Jest jeden `SegmentCode` na trasę: ziarno
`EndlessTrack.plan_seed`, z `WeatherPlan`. W logu pojawia się
"ODCINEK k ..." i "ZDARZENIE k ...: wynik", bez HUD.

**Wyzwalanie wg przewidywanego spotkania, nie stałe 300 m.** Przed autem
gracza widać do 2 km (`FAR_VIEW_DIST`). Auto postawione 300-500 m przed
graczem byłoby więc na widoku, a `_can_vanish` by je odrzucał.
- Auta przed graczem pojawiają się `HIDE_DIST` = 2100 m przed nim.
- Przeszkoda jadąca s x prędkości gracza jest doganiana po 2100/(1-s) m.
  Wyzwalam, gdy spotkanie wypada ~300 m w głąb odcinka
  (`SegmentEvents.lead_for`).
- Blokada (0,6) startuje więc ~5 km przed swoim odcinkiem, zasadzka
  (stoi) ~1,8 km, pod prąd (s = -1) przy ~1 km.
- Pościg od tyłu startuje przy wjeździe w odcinek, 350-500 m za graczem,
  przez `_can_vanish`.
- Korek otwiera okno gęstości ~1,5 km wcześniej.

**Zdarzenia, które wpiąłem:**
- korek: `TrafficZone.jam_from/jam_to`, gęstość x2 i 0,5-0,7 limitu;
- pod prąd: `OncomingCar.wrong_way`, auto z naprzeciwka na NASZYM lewym
  pasie. W odległości 600 m miga długimi i trąbi, a spokojne boty przed
  graczem zjeżdżają na prawy pas. Punkty za minięcie bez kontaktu
  (`ExtremistBrain.pass_points`). Awaryjnych świateł nie ma, bo
  StuntCar ich nie ma;
- zasadzka: `BotDriver.hold`, auto zamrożone na pasie awaryjnym. Przy
  60 m rusza w szale ("ambush");
- pościg: 1 + ev_level aut w szale;
- blokada: dwa boty obok siebie, 0,6 limitu. Szał ("blockade"), gdy
  gracz jest 35 m za nimi;
- waśń: `feud.set_hostile(ga, gb)`, po 1 + ev_level aut z każdego gangu;
  waśń startuje przez zwykły `_feud_scan`;
- wolne auto: 0,5 limitu, za nim 1-2 auta wyprzedzające lewym pasem.
  W `CarStyles` nie ma ciężarówki, więc to zwykły model;
- auta zdarzeń nie liczą się do gęstości TrafficZone (`drv.event`).
  Usuwane są poza wzrokiem: 700 m za graczem albo 4 km przed nim.

**Rytm.** Wszystko przez `seg_calm()`:
- w odcinku "rest" nie ma losowania ekstremisty (co km dalej losuje,
  ale tylko w build/peak);
- nie startuje nowa waśń (`_feud_scan`);
- nie startuje scenka z naprzeciwka.

Limit `EVENT_BOT_CAP` = 16. Zdarzenie ponad limit przepada.

**Znalezisko (zmienia ruch poza zdarzeniami).** `BotDriver` miał
prędkość spokojnej jazdy zawsze równą limitowi. "Wolne" auta z
`TrafficZone` (SLOW_SHARE, 0,5-0,7) po chwili jechały więc z limitem.
- Doszło `BotDriver.speed_k` (trwały mnożnik).
- Ustawiam go tylko dla korka i aut zdarzeń.
- Do decyzji: czy włączyć go też dla SLOW_SHARE i doganiających
  (CHASER_SHARE)? Zmieni to proporcję mijań w całej grze.

**Poprawka sprzed zmian.** Scenka z naprzeciwka (`_update_skirmish`)
pojawiała się 900 m przed graczem, czyli na widoku. Test to złapał.
Teraz pojawia się 2100 m przed graczem i sprawdza `_can_vanish`.
Do `trigger_gap` jedzie zwykłym ruchem.

**Do Was (OncomingSkirmish).** Stan "hidden" chowa auto scenki tuż przy
graczu (np. `d=-2`, na widoku). Test to wypisuje jako UWAGĘ, nie błąd.
Czy to zamierzone? Jeśli nie, wolę, żeby auto "wypadało" fizycznie
albo chowało się dopiero poza wzrokiem.

**Test sceny `tests/segment_event_test.gd`.** Trasa 33, gracz prowadzony
130 km/h, 20 km. Wymuszone zdarzenia 1..7 co 2 odcinki (co odcinek się
nakładały i pościg przepadał na limicie botów). Wynik OK:
- wszystkie 7 zdarzeń postawione;
- zasadzka ruszyła, pod prąd minął gracza;
- botów najwyżej 17;
- pojawień i zniknięć na widoku: 0 (wraki z wybuchem się nie liczą);
- ekstremista w odcinku rest: 0;
- mijania na km: w naszą stronę 0,50, z naprzeciwka 0,35. Wcześniej
  było 1 : 6. To przy wymuszonych zdarzeniach, a bez nich nie mierzyłem.

Test trwa ~12 min, więc nie ma go w `quest.sh test` (limit 300 s na
test). Uruchamiany ręcznie: `-- 20`.

Koszt w logu PERF (PC): "odcinki" ~8 ms na 5 s, czyli ~0,3% klatki.

**Skutek uboczny.** Pierwsze 3 odcinki są zawsze "rest", więc w pierwszych
~3,6 km nie ma waśni ani scenki z naprzeciwka. `feud_play_test` i
`oncoming_play_test` wyłączają rytm (`main.seg_rhythm = false`). Pełny
`./quest.sh test` OK; `drive_test` bez zmian (24.00-24.17).

