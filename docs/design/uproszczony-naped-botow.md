# Uproszczony napęd botów: propozycja do oceny

2026-11-09, wątek "Zaprojektuj nowe strategie botów road rage". Dotyczy **tylko botów**. Fizyka auta gracza zostaje bez zmian.

## Twoje warunki

- Oszukiwać wolno na **napędzie** botów.
- **Opony i bezwładność zostają** (a jeśli coś, to "nie za bardzo").
- Zawieszenie, kolizje i uszkodzenia też zostają: to widać, kiedy taranujesz bota.

## Co bot liczy dziś (pełny model gracza)

Na każdy krok fizyki (120 Hz):

1. sterowanie kół (Ackermann, ograniczenie skrętu);
2. **skrzynia biegów**: 6 biegów, decyzje o zmianie, czas zmiany, sprzęgło;
3. badanie podłoża: 4 promienie (najdroższe zapytania do silnika fizyki);
4. zawieszenie: sprężyny, tłumiki, odboje, stabilizatory;
5. **TCS** (kontrola trakcji) i **ESP** (stabilizacja toru jazdy, osobna logika dla nad- i podsterowności);
6. **silnik**: moment z krzywej przy bieżących obrotach, hamowanie silnikiem, obroty silnika jako osobny stan;
7. opony w 2 podkrokach (gracz ma 6): Magic Formula, relaksacja, dyferencjał LSD, hamulce z ABS dla każdego koła;
8. siły na nadwozie, opór powietrza, lądowanie.

## Co proponuję uprościć (tylko napęd)

| Dziś | U bota | Dlaczego można |
|---|---|---|
| 6 biegów, decyzje o zmianie, czas zmiany, sprzęgło | **przełożenie równoważne**: jak idealna skrzynia bezstopniowa, która trzyma silnik przy obrotach mocy maksymalnej, w granicach 1. i najwyższego biegu | nikt nie słyszy ani nie widzi biegów bota |
| moment z krzywej przy obrotach + osobny stan obrotów | moment = gaz × min(0,86 × P / ω silnika, T max). Współczynnik 0,86 zastępuje dziury między biegami i jest skalibrowany do pełnego modelu | jeden wzór zamiast krzywej i stanu |
| ESP | **brak** | bot nie jest człowiekiem: jego sterownik sam koryguje tor, ESP tylko się z nim kłóci |
| hamowanie silnikiem | **zostaje** (ten sam wzór, obroty z przełożenia równoważnego) | tanie, wpływa na zwalnianie przed zakrętem |
| bezwładność silnika widziana na kołach | **zostaje**: I silnika × przełożenie² | Twój warunek: bezwładność bez oszustw |
| TCS i ABS | **zostają** | próbowałem ABS raz na krok zamiast w podkrokach: hamowanie wydłużyło się o 9%, a oszczędność była znikoma |
| opony, zawieszenie, nadwozie, kolizje, uszkodzenia | **bez zmian** | Twój warunek |
| uszkodzenia silnika | mnożnik mocy, jak dziś | uszkodzony furiat dalej jeździ gorzej |

## Porównanie w symulatorze

Użyłem symulatora fizyki z repo (`tools/car_sim.py`, kopia modelu ze `stunt_car.gd`, skalibrowana do testów z gry). Uproszczony napęd to osobna klasa w `bot_drive_sim.py` (załącznik). Opony, zawieszenie i nadwozie dziedziczy bez zmian.

**Bot spokojny, 250 kW, tył, zawieszenie sport**

| manewr | pełny model bota (2 podkroki) | napęd uproszczony | różnica |
|---|---|---|---|
| 0-100 km/h [s] | 5,30 | 5,02 | -5% |
| 0-160 km/h [s] | 9,82 | 9,93 | +1% |
| prędkość po 60 s [km/h] | 272 | 260 | -4% |
| hamowanie 100-0 [m] | 37,4 | 37,8 | +1% |
| łuk R 60 m: maks. przyspieszenie boczne [g] | 0,90 | 0,90 | 0% |
| zmiana pasa przy 100 km/h: kąt znoszenia [°] | 0,52 | 0,52 | +1% |
| pełny gaz w łuku: kąt znoszenia [°] | 68 (obrót) | 17 | patrz niżej |

**Bot w szale, 350 kW**: 0-100 -8%, 0-160 -4%, hamowanie +1%, łuk 0%, zmiana pasa 0%.

Na prostej i w zakrętach różnice mieszczą się w ~5%. Jedyna wyraźna zmiana: **pełny gaz w środku łuku**. Pełny model przy 250 kW obraca tył (68°), uproszczony tylko zarzuca (17°). Powód jest taki, że prawdziwa skrzynia redukuje bieg i daje skok momentu, a "bezstopniowa" daje moc gładko. Dla bota to raczej zaleta (rzadziej sam się kręci), ale to różnica w zachowaniu, więc ją zaznaczam.

## Ile to oszczędza: uczciwie

| model | czas kroku (Python) | względem bota dziś |
|---|---|---|
| gracz (6 podkroków opon) | ~75 µs | ~175% |
| bot dziś (pełny, 2 podkroki) | ~40 µs | 100% |
| bot z uproszczonym napędem | ~35 µs | **~86-92%** |

**Sam napęd daje mało, ok. 8-14% kosztu fizyki bota.** W grze jeszcze mniej, bo dochodzą 4 promienie do podłoża, przykładanie sił i bryła w silniku fizyki, których napęd nie dotyka. Realnie to ~5-10% `bot_fiz`. Profil pokazuje, że czas idzie głównie w opony (~37%) i resztę kroku (zawieszenie, siły, całkowanie), a tych nie ruszamy.

## Co da więcej (przy Twoich warunkach)

1. **Budżet botów z pełną fizyką**, np. najwyżej 6-8 naraz. Dalsze auta jadą "na szynie" (dziś tak jest od 320 m). To największa dźwignia, bo koszt rośnie liniowo z liczbą aut.
2. **Trzy poziomy botów**:
   - blisko (< ~120 m, możliwe zderzenia): pełne opony w 2 podkrokach;
   - średnio (120-320 m): **1 podkrok opon**. W symulatorze: hamowanie 0%, łuk 0%, zmiana pasa 0%, 0-100 +11%, czas kroku **-37%**. To "trochę" oszukuje na oponach (numerycznie, nie w modelu), więc do Twojej decyzji;
   - daleko: szyna.
3. **Sterowanie botów** (`bot_ster`): szukanie po torze bywało droższe od samej fizyki. Moduł toru w tablicach (z planu wydajności) to obniża.
4. Uproszczony napęd warto dołożyć przy okazji, ale nie jako główny zysk.

## Do Twojej decyzji

- Czy napęd uproszczony wchodzi (zysk ~5-10%, prawie bez zmian w zachowaniu)?
- Czy średni poziom botów może mieć 1 podkrok opon (zysk ~35% na tych autach)?
- Budżet aut z pełną fizyką ustalimy po pomiarze na goglach (agent lokalny).

Po akceptacji: napęd jako osobny plik GDScript z testem porównawczym w Godocie, a podmianę w `stunt_car.gd` zrobi agent lokalny.
