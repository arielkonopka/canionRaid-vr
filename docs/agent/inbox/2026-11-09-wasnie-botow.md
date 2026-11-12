# Waśnie między botami: gangi, potyczki w zasięgu wzroku, sojusz po ataku gracza

Status: zrobione (FeudDirector)
Od: wątek w chmurze "Zaprojektuj nowe strategie botów road rage" (2026-11-09)
Decyzje użytkownika (2026-11-09):
- "Więcej botów, które tworzą grupy, które potrafią wzajemnie być w stanie
  furii drogowej. Boty, które się wyprzedzą, mogą wpaść w furię w stosunku
  do siebie."
- "Boty mogą wzajemnie się nie lubić, i gdy są w zasięgu wzroku gracza,
  mogą prowadzić potyczki między sobą. Zaatakowanie takiego bota od razu
  sprawia, że wrogowie łączą się ze sobą w sojusz."
- Optymalizacja botów: wszystko, co się da, byle zderzenia i skoki blisko
  gracza były realistyczne (inbox `2026-11-09-boty-naped-i-poziomy.md`).

## W tym PR-ze (odizolowane, czysta logika + test)

- `scripts/feud_director.gd` (`FeudDirector`): gangi (`add_bot(id, gang)`),
  wrogość między gangami losowana na odcinek (`roll_relations`, szansa
  25% → 70% z odcinkiem), potyczki **tylko w zasięgu wzroku** (`in_sight`,
  `SIGHT_R` 200 m): wyprzedzenie wroga (50%), zderzenie (wróg zawsze,
  neutralny 30% i od tej chwili wrogowie), wrogowie obok siebie (< 40 m,
  ~8%/s). Cel bota w potyczce: `target_of(id)`.
  **Uderzenie przez gracza bota w potyczce → sojusz**: obie strony (i ci
  z ich gangów, którzy walczą) biorą na cel gracza, gangi są sojusznikami
  45 s. Zdarzenie `"alliance"` → napis "SOJUSZ!" i klaksony.
  **Prowokacja**: wepchnięcie bota we wroga (kontakt gracza ≤ 3 s przed
  potyczką) daje 150 pkt, wrak z takiej potyczki 400 pkt (`points`
  w zdarzeniach → `ScoreKeeper.award_free`). Potyczki niesprowokowane
  nie dają punktów (chaos na drodze jest nagrodą sam w sobie).
- `tests/feud_test.gd` - **nieuruchomiony** w chmurze.

## Prośba

1. Uruchom `tests/feud_test.gd`, popraw literówki.
2. **Uogólnij cel w `BotDriver`**: dziś `_rage_plan` zna tylko `player`
   (~12 miejsc). Potrzebny `target: StuntCar` - gracz albo inny bot -
   taktyki (pit, ram, block, ambush, zigzag) zadziałają wtedy między botami.
   Cel: z `FeudDirector.target_of(id)` gdy ≠ NONE, inaczej jak dziś.
3. Gangi przy spawnie: grupy 2-4 aut z jednym kolorem (i numerem na
   przyszłych manekinach), różne charaktery prędkości (np. szybcy +15 km/h
   ponad limit, wolni -15), żeby wyprzedzanie zdarzało się samo.
4. `xr_main` (~10 Hz, **tylko boty NEAR/MID z BotLod** - szyna nic nie
   liczy): sortowanie botów po dystansie na torze, wyprzedzenia sąsiadów →
   `on_overtake`; pary wrogów < 40 m → `on_near`; `body_entered` bot-bot
   i bot-gracz → `on_contact`; wybuch/zniknięcie → `remove_bot`; ~1 Hz
   `update`.
5. Żetony ataku na gracza (opcjonalnie, później): przy sojuszu wielu aut
   naraz atakują 2-3 najbliższe, reszta jedzie obok - czytelność i Quest.
6. Na goglach z użytkownikiem: czy potyczki widać i czy są czytelne, czy
   sojusz po ataku jest wyraźny (napis, klaksony), PERF+ przy kilku
   walczących autach.

## Odpowiedź agenta lokalnego

(puste)
