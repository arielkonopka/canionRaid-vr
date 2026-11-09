# Modele aut z epoki - parametry z symulacji

Wygenerowane przez `python3 tools/car_styles_tune.py` (symulator `tools/car_sim.py`, odwzorowanie fizyki z `stunt_car.gd` na płaskiej suchej jezdni, opony całoroczne). Nie edytuj ręcznie - zmień założenia w `STYLES` i uruchom skrypt ponownie.

## Nastawy

| Model | Masa [kg] | Rozstaw osi / kół [m] | Promień koła [m] | Środek masy nad jezdnią [m] | Przód [%] | Bezwładność przechył/pochylenie/odchylenie | Cd·A [m²] | Napęd | Moc fabryczna | Zawieszenie | final_mult | Sprężyny (×) | Stabilizatory P/T (×) | Hamulce P/T [Nm] |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Sedan z lat 70. | 1150 | 2,57 / 1,64 | 0,33 | 0,58 | 50 | 480.0 / 1750.0 / 1950.0 | 0,76 | rwd, petrol | 90 kW | sport | 1,00 | 1,00 | 1,00 / 1,00 | 1900 / 1050 |
| Kombi | 1230 | 2,57 / 1,64 | 0,33 | 0,60 | 47 | 531 / 1931 / 2134 | 0,82 | rwd, petrol | 90 kW | soft | 0,95 | 1,15 | 0,92 / 0,93 | 2140 / 810 |
| Hatchback z lat 80. | 860 | 2,35 / 1,40 | 0,29 | 0,53 | 60 | 319 / 898 / 993 | 0,70 | fwd, petrol | 90 kW | sport | 1,05 | 1,25 | 0,64 / 1,11 | 2180 / 410 |
| Klin z lat 80. | 1120 | 2,45 / 1,48 | 0,31 | 0,48 | 50 | 412 / 1502 / 1700 | 0,59 | rwd, petrol | 130 kW | stiff | 0,90 | 1,00 | 0,42 / 0,49 | 1980 / 790 |
| Kabriolet | 1180 | 2,50 / 1,45 | 0,32 | 0,52 | 50 | 449 / 1663 / 1864 | 0,74 | rwd, petrol | 90 kW | sport | 0,90 | 1,05 | 1,04 / 1,06 | 2080 / 790 |
| Muscle z lat 70. | 1550 | 2,80 / 1,56 | 0,34 | 0,54 | 52 | 669 / 2622 / 2968 | 0,86 | rwd, petrol | 180 kW | soft | 0,95 | 1,25 | 0,80 / 0,75 | 2220 / 810 |
| Terenówka 4x4 | 1680 | 2,40 / 1,45 | 0,38 | 0,68 | 50 | 896 / 2613 / 2722 | 1,30 | awd, diesel | 90 kW | soft | 1,00 | 1,00 | 1,36 / 1,56 | 2700 / 700 |
| Furgon | 1480 | 2,60 / 1,56 | 0,33 | 0,72 | 50 | 867 / 2440 / 2508 | 1,34 | rwd, diesel | 90 kW | soft | 1,00 | 1,25 | 0,76 / 1,08 | 2320 / 630 |

## Wyniki manewrów (moc fabryczna, ABS/TCS/ESP włączone, chyba że napisano inaczej)

| Model | 0-100 [s] | 0-160 [s] | V po 60 s [km/h] | 100-0 [m] | Skidpad R60 [g] | Podsterowność [deg/g] | Przechył [deg/g] | SSF | Częst. przód/tył [Hz] | Prześwit / po upadku z 1,5 m [m] |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Sedan z lat 70. | 10,7 | 28,5 | 185 | 37,4 | 0,90 | 0,31 | 2,1 | 1,41 | 1,78 / 1,78 | 0,30 / 0,00 |
| Kombi | 11,6 | 32,1 | 182 | 37,5 | 0,90 | 0,29 | 3,5 | 1,37 | 1,53 / 1,46 | 0,30 / -0,04 (dobicie) |
| Hatchback z lat 80. | 8,9 | 21,5 | 196 | 38,0 | 0,91 | 0,44 | 2,5 | 1,33 | 1,82 / 2,22 | 0,26 / -0,12 (dobicie) |
| Klin z lat 80. | 7,5 | 16,8 | 230 | 37,5 | 0,93 | 0,25 | 1,6 | 1,54 | 2,40 / 2,39 | 0,24 / 0,01 |
| Kabriolet | 11,5 | 29,9 | 187 | 37,5 | 0,91 | 0,28 | 2,3 | 1,39 | 1,83 / 1,82 | 0,27 / -0,02 (dobicie) |
| Muscle z lat 70. | 7,0 | 16,2 | 228 | 37,6 | 0,92 | 0,24 | 3,5 | 1,44 | 1,53 / 1,59 | 0,28 / -0,05 (dobicie) |
| Terenówka 4x4 | 12,7 | - | 155 | 37,8 | 0,87 | 0,39 | 4,5 | 1,07 | 1,39 / 1,39 | 0,36 / -0,00 (dobicie) |
| Furgon | 11,5 | - | 156 | 37,7 | 0,88 | 0,31 | 4,5 | 1,08 | 1,56 / 1,55 | 0,20 / -0,13 (dobicie) |

## Stabilność i dachowanie

Sinus z przerwą (test ESC, 80 km/h): obrót 1 s i 1,75 s po skręcie względem szczytu (norma ≤ 0,35 / ≤ 0,20). Hak (fishhook, 80 km/h): największy przechył i czy dwa koła jednej strony oderwały się od jezdni. Gaz w łuku: pełny gaz przy 60% przyczepności na R40.

| Model | Sinus ESP | Sinus bez ESP | Sinus 120 km/h ESP | Hak ESP: przechył / 2 koła w górze | Hak bez ESP | Gaz w łuku ESP+TCS: znoszenie | Gaz w łuku bez pomocy | Bot 250 kW: gaz w łuku / sinus | Bot 350 kW: 0-100 / Vmax |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Sedan z lat 70. | 0,00 / 0,00 OK | 0,00 / 0,00 OK | 0,02 / 0,00 OK | 2,0° / nie | 2,0° / nie | 2,0° | 2,0° | 8,6° / 0,00 / 0,00 OK | 5,2 s / 281 |
| Kombi | 0,00 / 0,00 OK | 0,01 / 0,00 OK | 0,07 / 0,00 OK | 3,5° / nie | 3,5° / nie | 2,2° | 2,4° | 7,9° / 0,00 / 0,00 OK | 5,0 s / 295 |
| Hatchback z lat 80. | 0,00 / 0,00 OK | 0,00 / 0,00 OK | 0,33 / 0,25 NIE | 2,4° / nie | 2,4° / nie | 1,3° | 1,8° | 2,0° / 0,00 / 0,00 OK | 7,2 s / 267 |
| Klin z lat 80. | 0,00 / 0,00 OK | 0,51 / 0,00 NIE | 0,07 / 0,00 OK | 1,5° / nie | 1,5° / nie | 4,5° | 89,7° obrót | 7,6° / 0,00 / 0,00 OK | 5,1 s / 312 |
| Kabriolet | 0,00 / 0,00 OK | 0,00 / 0,00 OK | 0,05 / 0,00 OK | 2,2° / nie | 2,2° / nie | 2,5° | 2,6° | 9,0° / 0,00 / 0,00 OK | 5,0 s / 305 |
| Muscle z lat 70. | 0,00 / 0,00 OK | 0,00 / 0,00 OK | 0,08 / 0,00 OK | 3,6° / nie | 3,6° / nie | 5,7° | 89,7° obrót | 6,7° / 0,00 / 0,00 OK | 5,4 s / 289 |
| Terenówka 4x4 | 0,00 / 0,00 OK | 0,00 / 0,00 OK | 0,26 / 0,12 OK | 5,1° / nie | 5,1° / nie | 2,0° | 2,0° | 5,4° / 0,00 / 0,00 OK | 4,0 s / 245 |
| Furgon | 0,00 / 0,00 OK | 0,52 / 0,03 NIE | 0,10 / 0,04 OK | 5,0° / nie | 5,0° / nie | 2,9° | 3,2° | 9,0° / 0,00 / 0,00 OK | 4,9 s / 243 |

## Rozkład botów (wagi %)

| Model | Wąwóz i tunel | Autostrada |
| --- | --- | --- |
| Sedan z lat 70. | 25 | 25 |
| Kombi | 15 | 20 |
| Hatchback z lat 80. | 20 | 15 |
| Klin z lat 80. | 10 | 10 |
| Kabriolet | 5 | 5 |
| Muscle z lat 70. | 10 | 10 |
| Terenówka 4x4 | 10 | 5 |
| Furgon | 5 | 10 |
