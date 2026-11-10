# Modele aut z epoki - parametry z symulacji

Wygenerowane przez `python3 tools/car_styles_tune.py` (symulator `tools/car_sim.py`, odwzorowanie fizyki z `stunt_car.gd` na płaskiej suchej jezdni, opony całoroczne). Nie edytuj ręcznie - zmień założenia w `STYLES` i uruchom skrypt ponownie.

## Nastawy

| Model | Masa [kg] | Rozstaw osi / kół [m] | Promień koła [m] | Środek masy nad jezdnią [m] | Przód [%] | Bezwładność przechył/pochylenie/odchylenie | Cd·A [m²] | Napęd | Moc fabryczna | Zawieszenie | final_mult | Sprężyny (×) | Stabilizatory P/T (×) | Hamulce P/T [Nm] |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Sedan z lat 70. | 1150 | 2,57 / 1,64 | 0,33 | 0,58 | 50 | 480.0 / 1750.0 / 1950.0 | 0,76 | rwd, petrol | 90 kW | sport | 1,00 | 1,00 | 1,00 / 1,00 | 1900 / 1050 |
| Kombi | 1230 | 2,75 / 1,50 | 0,34 | 0,60 | 48 | 602 / 1978 / 2146 | 0,82 | rwd, petrol | 90 kW | soft | 0,95 | 1,25 | 1,28 / 1,30 | 2190 / 890 |
| Hatchback z lat 80. | 860 | 2,37 / 1,29 | 0,30 | 0,53 | 60 | 316 / 903 / 985 | 0,70 | fwd, petrol | 90 kW | sport | 1,05 | 1,25 | 0,97 / 1,68 | 2290 / 440 |
| Klin z lat 80. | 1120 | 2,75 / 1,59 | 0,31 | 0,48 | 50 | 490 / 1517 / 1752 | 0,59 | rwd, petrol | 130 kW | stiff | 0,90 | 1,10 | 0,28 / 0,33 | 1910 / 840 |
| Kabriolet | 1180 | 2,71 / 1,59 | 0,29 | 0,52 | 50 | 444 / 1602 / 1924 | 0,74 | rwd, petrol | 90 kW | sport | 1,10 | 1,25 | 0,42 / 0,42 | 1830 / 750 |
| Muscle z lat 70. | 1550 | 2,68 / 1,37 | 0,33 | 0,54 | 52 | 597 / 2630 / 2897 | 0,86 | rwd, petrol | 180 kW | soft | 0,95 | 1,25 | 1,55 / 1,44 | 2210 / 770 |
| Terenówka 4x4 | 1680 | 2,71 / 1,62 | 0,35 | 0,68 | 50 | 908 / 2521 / 2830 | 1,30 | awd, diesel | 90 kW | soft | 1,00 | 1,25 | 0,53 / 0,61 | 2360 / 730 |
| Furgon | 1480 | 3,04 / 1,75 | 0,38 | 0,72 | 50 | 1035 / 2441 / 2652 | 1,34 | rwd, diesel | 90 kW | soft | 1,00 | 1,10 | 0,48 / 0,68 | 2540 / 850 |

## Wyniki manewrów (moc fabryczna, ABS/TCS/ESP włączone, chyba że napisano inaczej)

| Model | 0-100 [s] | 0-160 [s] | V po 60 s [km/h] | 100-0 [m] | Skidpad R60 [g] | Podsterowność [deg/g] | Przechył [deg/g] | SSF | Częst. przód/tył [Hz] | Prześwit / po upadku z 1,5 m [m] |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Sedan z lat 70. | 10,7 | 28,5 | 185 | 37,4 | 0,90 | 0,31 | 2,1 | 1,41 | 1,78 / 1,78 | 0,30 / 0,00 |
| Kombi | 11,6 | 32,0 | 182 | 37,3 | 0,89 | 0,26 | 3,5 | 1,25 | 1,60 / 1,52 | 0,25 / -0,09 (dobicie) |
| Hatchback z lat 80. | 8,9 | 21,3 | 196 | 37,9 | 0,91 | 0,41 | 2,5 | 1,22 | 1,82 / 2,22 | 0,23 / -0,15 (dobicie) |
| Klin z lat 80. | 7,5 | 16,9 | 230 | 37,4 | 0,94 | 0,23 | 1,4 | 1,65 | 2,52 / 2,50 | 0,19 / -0,02 (dobicie) |
| Kabriolet | 10,9 | 28,4 | 187 | 37,2 | 0,93 | 0,26 | 2,3 | 1,53 | 2,00 / 1,99 | 0,20 / -0,07 (dobicie) |
| Muscle z lat 70. | 7,0 | 16,2 | 228 | 37,7 | 0,90 | 0,26 | 3,5 | 1,27 | 1,53 / 1,59 | 0,25 / -0,08 (dobicie) |
| Terenówka 4x4 | 12,7 | - | 155 | 37,5 | 0,89 | 0,34 | 4,5 | 1,19 | 1,56 / 1,55 | 0,27 / -0,06 (dobicie) |
| Furgon | 11,4 | - | 156 | 37,2 | 0,90 | 0,26 | 4,5 | 1,22 | 1,47 / 1,45 | 0,32 / -0,03 (dobicie) |

## Stabilność i dachowanie

Sinus z przerwą (test ESC, 80 km/h): obrót 1 s i 1,75 s po skręcie względem szczytu (norma ≤ 0,35 / ≤ 0,20). Hak (fishhook, 80 km/h): największy przechył i czy dwa koła jednej strony oderwały się od jezdni. Gaz w łuku: pełny gaz przy 60% przyczepności na R40.

| Model | Sinus ESP | Sinus bez ESP | Sinus 120 km/h ESP | Hak ESP: przechył / 2 koła w górze | Hak bez ESP | Gaz w łuku ESP+TCS: znoszenie | Gaz w łuku bez pomocy | Bot 250 kW: gaz w łuku / sinus | Bot 350 kW: 0-100 / Vmax |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Sedan z lat 70. | 0,00 / 0,00 OK | 0,00 / 0,00 OK | 0,02 / 0,00 OK | 2,0° / nie | 2,0° / nie | 2,0° | 2,0° | 8,6° / 0,00 / 0,00 OK | 5,2 s / 281 |
| Kombi | 0,00 / 0,00 OK | 0,00 / 0,00 OK | 0,06 / 0,00 OK | 3,8° / nie | 3,8° / nie | 2,1° | 2,3° | 8,1° / 0,00 / 0,00 OK | 5,0 s / 295 |
| Hatchback z lat 80. | 0,00 / 0,00 OK | 0,00 / 0,00 OK | 0,44 / 0,43 NIE obrót | 2,6° / nie | 2,6° / nie | 1,3° | 1,8° | 2,0° / 0,00 / 0,00 OK | 7,1 s / 267 |
| Klin z lat 80. | 0,00 / 0,00 OK | 0,00 / 0,00 OK | 0,04 / 0,00 OK | 1,4° / nie | 1,4° / nie | 4,3° | 89,7° obrót | 7,0° / 0,00 / 0,00 OK | 5,2 s / 312 |
| Kabriolet | 0,00 / 0,00 OK | 0,00 / 0,00 OK | 0,02 / 0,00 OK | 2,2° / nie | 2,2° / nie | 2,8° | 3,9° | 7,8° / 0,00 / 0,00 OK | 5,5 s / 257 |
| Muscle z lat 70. | 0,00 / 0,00 OK | 0,00 / 0,00 OK | 0,07 / 0,00 OK | 3,5° / nie | 3,5° / nie | 6,3° | 89,7° obrót | 7,7° / 0,00 / 0,00 OK | 5,3 s / 289 |
| Terenówka 4x4 | 0,00 / 0,00 OK | 0,00 / 0,00 OK | 0,30 / 0,17 OK | 4,9° / nie | 4,9° / nie | 1,8° | 1,8° | 3,9° / 0,00 / 0,00 OK | 3,9 s / 245 |
| Furgon | 0,00 / 0,00 OK | 0,00 / 0,00 OK | 0,10 / 0,00 OK | 5,2° / nie | 5,2° / nie | 2,6° | 2,9° | 8,1° / 0,00 / 0,00 OK | 5,1 s / 243 |

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
