Status: zrobione (2026-11-14)
Od: wątek w chmurze "Zaplanuj urozmaicenia trasy i miasta"
Decyzja użytkownika: 2026-11-14 09:43 UTC, karta "Czy ekstremista ma
omijać zamknięte pasy na zwężeniach?", odpowiedź **"Tak, zna otwarte
pasy"** (dotyczy pytania z odpowiedzi do 2026-11-14-etap2-przekroje.md).
Otwarte: nic.

# Ekstremista zna przekroje

Na zwężeniu wpycha się na otwarty pas jak furiat: nie hamuje przed
autami, ale nie jedzie zamkniętym pasem przez pachołki.

Propozycja najtańsza, bez zmian w `ExtremistBrain`. Jego logika TTC
już ucieka z pasa, na którym coś stoi:

1. `BotDriver` (budowa `_x_ctx`, ~bot_driver.gd:738): dla każdego pasa
   0/1 sprawdź `track.sections.lanes_at(d)` na odcinku `dist ..
   dist + 400` (co ~20 m, raz na 0,1 s jak dziś). Jeśli pas wypada
   z `fwd` (albo jest `closing`), ustaw w jego wpisie `gap` = odległość
   do tego miejsca i `v = 0`. Dla mózgu to stojąca przeszkoda, więc
   zjedzie na otwarty pas we właściwym czasie, a gdy ten jest zajęty,
   wepchnie się (TTC, klakson, długie, jak dziś).
2. Pobocze (`shoulder`) w strefie zostaje, jeśli jest otwarte. Przy
   zamkniętym prawym pasie odcina je linia pachołków, więc wtedy
   `shoulder = {}`.
3. Pas "lewy/prawy" w mózgu to indeks z `fwd` (przy 3+3 i 2+1 lista
   pasów ma inną długość). `_entry` już przycina indeks.
4. Test: w `section_drive_test` ekstremista przejeżdża zwężenie,
   0 przewróconych pachołków przez niego i 0 próbek na zamkniętym pasie
   za początkiem skosu. Dodatkowo `extremist_play_test` bez zmian.

## Odpowiedź agenta lokalnego

Zrobione (2026-11-14), wg propozycji, bez zmian w `ExtremistBrain`:

1. `BotDriver._extremist_step` (budowa `_x_ctx`, co 0,1 s) sprawdza
   `lanes_at(dist + k)` dla k = 0..400 m co 20 m. Pas 2+2, którego oś nie
   ma odpowiednika w `fwd` (±1,3 m) albo jest `closing`, dostaje
   `gap` = k i `v` = 0.
2. Zamknięty prawy pas zeruje pobocze (`shoulder = {}`).
3. Oś pasa ekstremisty: `hwy_lane_at(ln, dist + 0,5 s)`, czyli indeks
   przycięty do otwartych.

Test `section_drive_test -- zwezenie`: ekstremista jest wypuszczany za
graczem, gdy ten jest w strefie. Test czeka (najwyżej 60 s), aż
ekstremista minie strefę. Wynik:
- na zamkniętym pasie 0 z 3920 próbek;
- przewrócone pachołki: 0.

Mózg zachowuje się zgodnie z charakterem. Jedzie otwartym pasem, a gdy
ten jest zajęty, ucieka na pobocze (przy zamkniętym lewym pasie jest
dozwolone). W ostateczności taranuje auto przed sobą (w jednym
przebiegu przy 163 km/h).

Pachołki liczę tylko wtedy, gdy ekstremista jedzie prosto (kurs < 20°
od drogi). Po taranie auto się obraca i pachołki lecą od zderzenia, to
już fizyka.

`xr_main.x_cones_hit` liczy pachołki ekstremisty. Pachołki lecą też od
botów w szale z fizyką (`_knock_cones`), bo plan szału nie zna
przekrojów.

`extremist_play_test`, pełny zestaw i `drive_test`: wynik w HANDOVER.
