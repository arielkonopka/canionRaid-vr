# Furia między botami na autostradzie przez całą trasę: wpięcie FeudDirector + OncomingSkirmish

Status: zrobione
Od: wątek w chmurze "Zaprojektuj nowe strategie botów road rage" (2026-11-10, noc)
Cel nocy użytkownika (2026-11-09, 23:17, cały punkt w `2026-11-10-plan-nocy.md`):
"cała trasa jest na autostradzie (ruch w dwie strony), furia drogowa, także
między botami, przejrzenie całości w celu identyfikacji wąskich gardeł
[...], pojazd gracza powinien zachowywać się zgodnie z prawami fizyki."

Ten plik jest specyfikacją. Kodu do scalenia w nim nie ma. Wszystko, co
jest potrzebne, już leży na gałęzi:
- `scripts/feud_director.gd` + `tests/feud_test.gd` (inbox
  `2026-11-09-wasnie-botow.md`);
- `scripts/oncoming_skirmish.gd` + `tests/oncoming_skirmish_test.gd`
  (inbox `2026-11-09-potyczki-na-drugiej-jezdni.md`);
- `BotLod`, `BotDriveModel`, pula botów (już wpięte przez Ciebie).

Autostradę na całej długości (generator, `_is_highway_at` prawdziwe
wszędzie) prowadzi osobny punkt planu nocy. Ta specyfikacja **nie zależy
od niego**. Waśnie działają na każdej drodze, a scenki na drugiej jezdni
włączają się same tam, gdzie `_is_highway_at(d)` jest prawdą.

## Zasady, których nie wolno złamać

1. **Fizyka gracza bez zmian.** Nic z tego nie dotyka `stunt_car.gd` po
   stronie gracza. `drive_test.gd` ma dać te same wyniki co przed zmianą.
2. **Boty blisko gracza zostają NEAR** (2 podkroki opon, sterowanie co
   krok). Zderzenia bot-bot i bot-gracz są prawdziwe, fizyczne.
3. **Upraszczać wolno tylko daleko** (ustalenie użytkownika). Potyczka
   fizyczna istnieje tylko w zasięgu wzroku. Poza nim albo jej nie ma,
   albo jest reżyserowana (druga jezdnia, zero fizyki).
4. Budżet Quest 3: `BOT_PHYS_BUDGET` 8 zostaje. Waśnie nie dokładają
   nowych aut z fizyką, tylko zmieniają priorytet istniejących.

## Kolejność kroków

Każdy krok zostawia grę grywalną. Po każdym: commit + testy z sekcji niżej.

### 1. Testy logiki (5 min)

```
godot --headless --xr-mode off -s res://tests/feud_test.gd </dev/null
godot --headless --xr-mode off -s res://tests/oncoming_skirmish_test.gd </dev/null
```

Oba moduły napisano w chmurze bez Godota. Popraw śmiało literówki typów
(pułapka 4.6: `var x :=` z wartości bez typu → `var x: float =`).

### 2. Gangi przy spawnie i sprzątaniu (xr_main)

- `var feud := FeudDirector.new()`, `feud.rng.seed` z ziarna odcinka (jak
  `_bot_rng`).
- `const GANGS := 3`; gang ma kolor: przypisz na odcinek 3 kolory
  z `GameSettings.PAINTS` i pomaluj bota kolorem gangu zamiast losowego.
  Gracz ma wtedy szansę rozpoznać, kto z kim jest.
- Id bota w dyrektorze = `bot.get_instance_id()`, tak samo jak w
  ScoreKeeperze. Jest > 0, więc nie koliduje z `PLAYER` = 0.
- `_spawn_bot`: `feud.add_bot(id, gang)`.
- Nowy odcinek (`_last_section` rośnie): `feud.roll_relations(range(GANGS), _last_section)`.
- `_retire_bot(b)` i wybuch w `_update_bots`: przed oddaniem do puli
  `_feud_events(feud.remove_bot(id, race_time, dead))`. Pula
  używa tych samych węzłów, więc instance_id się powtórzy. Dlatego
  remove_bot musi przyjść przed ponownym add_bot.

### 3. BotDriver: cel inny niż gracz

Teraz `_rage_plan` ściga `player`. Uogólnienie:

- `var foe: StuntCar = null` (null = gracz), `func _foe() -> StuntCar:
  return foe if is_instance_valid(foe) else player`.
- W `_rage_plan` zamień `player` na `_foe()` (pozycja, `speed`).
- **Bez zmian** zostają `_check_overtake`, `_on_body_entered` (gałąź
  gracza), `_score_step` i oszustwo silnika w `enrage`. Tam chodzi
  o gracza i jego punkty.
- `func feud_with(other: StuntCar)`: `foe = other`, `rage = 1.0`,
  `rage_time = 0`, zejście z szyny, klakson. **Bez** `score_chase_open`
  i **bez** podbijania silnika (waśń nie jest pościgiem gracza).
- `func end_feud()`: `foe = null`. Jeśli bot nie był wcześniej w szale na
  gracza, to `rage = 0`.
- Uspokajanie: dziś `rage` maleje, gdy `main.player_compliant()`. Dla
  waśni (foe ≠ null) tego nie rób, bo koniec waśni mówi dyrektor
  (`feud_end` po `FEUD_TIMEOUT` albo po zniknięciu przeciwnika).
- Taktyki przeciw botowi: `ram`, `block`, `pit`, `zigzag`. `pincer`
  i `ambush` dotyczą tylko gracza (kleszcze szukają partnera przez
  `rage_partner` względem gracza, zasadzka czeka na gracza).
- `_on_body_entered`: gdy `b` to inny bot (`StuntCar` z węzłem `Driver`)
  i `rel_v > 1`, wołaj `main.feud_contact(car, b)` tylko z bota
  o mniejszym instance_id, żeby kontakt nie liczył się dwa razy. Gdy `b`
  to gracz, przed obecnym `enrage(...)` wołaj `main.feud_player_hit(car)`.

### 4. Skan par w xr_main (4 Hz, razem z `_update_bot_lod`)

W tym samym tyknięciu co LOD (co 0,25 s):

- `in_sight(b)`: `TrafficZone.visible(głowa, kierunek głowy, przód auta
  gracza, b.global_position)` **i** `|drv.dist - _last_safe_dist| <
  FeudDirector.SIGHT_R`. Stożek sprawia, że potyczki rodzą się przed
  graczem, a nie za jego plecami. Para jest w zasięgu, gdy oba boty są.
- Tylko boty z fizyką (`drv.lod != BotLod.RAIL`). Bot na szynie nie
  może się zderzyć naprawdę.
- Wyprzedzenia: posortuj boty po `drv.dist`. Para sąsiadów, która
  zamieniła się kolejnością od poprzedniego tyknięcia (zapamiętaj
  `id → indeks`), daje `on_overtake(passer, passed, now, in_sight)`.
  To O(n log n), nie O(n²).
- Bliskość: dla sąsiadów w kolejności (i, i+1), (i, i+2) z `|Δdist| <
  NEAR_SPARK_R` wołaj `on_near(a, b, 0.25, now, in_sight)`.
- **Uwaga:** `_update_rail` nie wpuszcza na szynę bota z `rage > 0`
  i zdejmuje go z niej (`rage > 0.0 → fizyka`), niezależnie od BotLod.
  Bot w waśni ma `rage = 1`, więc ma fizykę **poza budżetem**. To kolejny
  powód dla limitu i ręcznego kończenia waśni poza wzrokiem (niżej).
- **Limit `MAX_FEUDS := 2`** (najwyżej 4 boty walczą ze sobą naraz).
  Przy limicie nie wołaj `on_overtake` ani `on_near`. Kontakt fizyczny
  zgłaszaj zawsze, bo zderzenie już się stało.
- Raz na sekundę `feud.update(race_time)`. Do tego: waśń, której strona
  wypadła poza `1,5 × SIGHT_R` albo spadła na RAIL, kończ ręcznie
  (`feud.calm(id)` + `drv.end_feud()`). Budżet fizyki nie może być
  zajęty przez walkę, której nikt nie widzi.
- `Perf.add("feud", t0)` na cały skan.

### 5. Zdarzenia dyrektora → gra (`_feud_events(evs)`)

| zdarzenie | gra |
|---|---|
| `skirmish {a, b, provoked, points}` | `drv(a).feud_with(bot(b))`. Jeśli `target_of(b) == a`, to i odwrotnie. Gdy `provoked`: `score.award_free("feud", points, ...)`, napis "PROWOKACJA +150" |
| `alliance {ids, gangs}` | dla każdego id: `drv.foe = null`, `drv.enrage("alliance")` (pościg gracza z punktami jak zwykle), klakson wszystkich, napis "SOJUSZ!" |
| `feud_end {id}` | `drv(id).end_feud()` |
| `feud_wreck {provoked, points}` | gdy `provoked`: `award_free("feud_wreck", 400, ...)` |

`feud_player_hit(bot)` = `_feud_events(feud.on_contact(PLAYER, id, now,
true))`. `feud_contact(a, b)` = `_feud_events(feud.on_contact(id_a, id_b,
now, in_sight(a) and in_sight(b)))`.

ScoreKeeper: origin `"alliance"` traktuj jak `"reinforce"`. Jeśli
`open_chase` przyjmuje dowolny string, nic nie trzeba zmieniać.

### 6. LOD: walczący mają pierwszeństwo

W `_update_bot_lod` tablica `raging` = `drv.rage > 0.0 or feud.in_feud(id)`.
`BotLod.assign` już daje im pierwszeństwo do MID przed spokojnymi. Ponieważ
waśń istnieje tylko w zasięgu wzroku (≤ 200 m), walczący i tak są NEAR
albo MID. Budżet 8 się nie zmienia.

### 7. Druga jezdnia: OncomingSkirmish

Według `2026-11-09-potyczki-na-drugiej-jezdni.md`. Uzupełnienia dla
autostrady na całej długości:

- najwyżej jedna scenka naraz; następna nie wcześniej niż 1,2 km jazdy
  gracza po poprzedniej (losowo 1,2-2,5 km), żeby była wydarzeniem, a nie
  tłem;
- `ONCOMING_MAX` 4 + 2 auta scenki (kinematyczne, koszt pomijalny);
- kolory: dwa gangi wrogie w bieżącym `feud._hostile`. Jeśli żadne nie
  są wrogie, losowe dwa różne;
- trudność: `wreck` częściej w późnych odcinkach (np. waga
  `1 + _last_section / 10`), jeśli łatwo podać wagi z zewnątrz. Jeśli
  nie, zostaw.

### 8. Testy i pomiary (wyniki do HANDOVER + odpowiedź niżej)

1. `feud_test`, `oncoming_skirmish_test`, `bot_drive_test`, `score_test`:
   OK.
2. `drive_test.gd` dla każdego zawieszenia i obu skrzyń: **te same wyniki
   co przed zmianą** (fizyka gracza nietknięta).
3. Nowy scenariusz `Bench` "S5" (headless, bez gogli): 6 botów z dwóch
   wrogich gangów przed graczem na autopilocie, `set_hostile` na sztywno.
   Sprawdź w logu:
   - w ciągu 30 s co najmniej jedna `skirmish` i jeden fizyczny kontakt
     bot-bot;
   - po uderzeniu gracza w bota w potyczce pojawia się `alliance` i oba
     boty mają `foe == null` i `rage > 0`;
   - żaden bot z `in_feud` nie jest na RAIL;
   - liczba aut z fizyką ≤ `BOT_PHYS_BUDGET` + NEAR.
4. Quest 3, PERF (jak w `2026-11-08-plan-wydajnosci.md`): S4 (20 botów)
   przed i po zmianie. Do porównania średnia i maksimum `bot_ster`,
   `boty_mgr`, `feud`, czas klatki fizyki. Cel: `feud` < 0,2 ms średnio,
   maksimum klatki nie gorsze niż przed zmianą.
5. Jazda z użytkownikiem: czy waśnie widać i czy dają się rozpoznać
   (kolory gangów), czy scenka z drugiej jezdni jest czytelna (180 m).

## Wąskie gardła, które widzę przy autostradzie na całej trasie

To wkład do przeglądu całości (inny punkt planu nocy):

- `bot_limit` rośnie do 20. Na autostradzie z ruchem w obie strony to 20
  aut po naszej stronie i 6 z naprzeciwka. BotLod trzyma fizykę w budżecie
  8, **ale** każdy bot w szale (`rage > 0`) ma fizykę zawsze
  (`_update_rail`), a posiłki (`call_reinforcements`, promień 400 m)
  potrafią naraz rozwścieczyć wiele aut. W PERF S4 sprawdź, ile aut ma
  fizykę w szczycie pościgu. Propozycja: bot w szale dalej niż MID (320 m)
  i poza wzrokiem jedzie po szynie z prędkością pościgu (dogania gracza)
  i schodzi z niej w MID.
- Szyna liczy `samples_from` i `transform_at_distance` 30 razy na sekundę
  na każdego bota. Przy 20 botach to 600 zapytań do toru na sekundę. Do
  sprawdzenia w PERF, czy `samples_from(dist, 1.0)` nie przeszukuje za
  dużo (np. od początku kawałka).
- `call_reinforcements` i `rage_partner` przechodzą po wszystkich botach
  przy każdym kontakcie i co krok taktyki. Przy 20 botach to wciąż
  tanio, ale `rage_partner` jest wołane w `_rage_plan` co krok dla każdego
  bota w szale. Warto cache'ować wynik co 0,25 s.
- `Explosion.ignore = [car] + _bots` tworzy nową tablicę przy każdym
  wybuchu. To drobiazg, chyba że wybuchów będzie dużo (waśnie je
  zwiększą).
- Pojedynczy liniowy `dist` dla całego świata (znane ograniczenie, patrz
  graf ulic w `2026-11-09-pozostalosci-estakad.md`). Waśnie i scenki go
  używają, więc przy przejściu na graf ścieżek trzeba będzie zamienić
  `drv.dist` na (ścieżka, dist). Bez nowych założeń poza tym.

## Odpowiedź agenta lokalnego

