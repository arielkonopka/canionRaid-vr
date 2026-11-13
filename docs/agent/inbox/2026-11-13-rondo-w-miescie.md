Status: nowe
Od: wątek w chmurze "Zaplanuj urozmaicenia trasy i miasta"
Decyzje użytkownika: 2026-11-13 23:32 UTC "czy możesz dodać do urozmaiceń
rondo? najlepiej w mieście?". Kolejność etapów bez zmian (zdarzenia ->
przekroje -> budowle -> pułapki -> krajobraz i miasto), więc rondo
przychodzi z miastem liniowym w etapie 5.
Otwarte: nic. Teraz tylko potwierdź przyjęcie (Status) - wykonanie
w etapie 5. Wartości liczbowe startowe, do oceny w goglach.

# Rondo w mieście (etap 5, z miastem liniowym)

## Co jest w PR

- `SegmentCode.roundabout_r(s)` (statyczna) i `ROUNDABOUT_R`,
  `ROUNDABOUT_AT`: odcinek "przejazd przez miasto" (structure 7)
  z `s_param` 0-3 ma rondo w połowie odcinka, `s_param` = indeks
  promienia 22 / 28 / 34 / 40 m (oś pierścienia). `s_param` 4-7 - miasto
  bez ronda. Kod odcinka się nie zmienia (te same bity, nowe znaczenie
  parametru dla miasta), więc kody z testu i odtwarzanie z ziarna zostają.
- `describe` dopisuje "z rondem R28".
- `tests/segment_code_test.gd` `_roundabout`: rondo tylko w mieście,
  promień z listy, tylko część miast. Python
  (`tools/segment_code_sim.py`, 600 km, ziarna 777/1/4242/5): rondo
  w 12-26 z 28-36 odcinków miasta, czyli mniej więcej co 25-50 km od km 60.
  **Test GDScript nieuruchomiony (brak Godota w chmurze).**

## Jak ma działać (etap 5)

1. **Geometria.** Główna droga przechodzi przez rondo "na wprost"
   (2. zjazd): wjazd odbija w prawo, łuk wokół wyspy w lewo, zjazd
   w prawo - tor auta to esowanie z ciasnym łukiem o promieniu
   `roundabout_r`. Cały pierścień i 2 boczne wloty (krótkie, ~40-60 m,
   kończą się zabudową - miasta-grafu nie ma, temat zaparkowany) to
   dekoracja z tego samego generatora jezdni (stała krzywizna, zamknięty
   pierścień). Wyspa: trawa + krawężnik najazdowy; bez nowych modeli
   i pobrań.
2. **Zapowiedź >= 4 s**: znaki rondo (C-12) i "ustąp pierwszeństwa"
   (A-7) ~150 m przed, limit 50 w mieście jak reszta miasta. Rondo po
   długiej prostej wjazdu do miasta to klasyczne miejsce wypadków -
   zapowiedź uczciwa, prędkość to wybór gracza (fizyka bez ułatwień).
3. **Ruch.** Spokojne auta krążą po pierścieniu (krótka zamknięta szyna,
   1-3 auta, LOD jak dziś) i ustępują wjeżdżającym zgodnie z zasadą
   "na rondzie ma pierwszeństwo jadący po rondzie". Zdarzenia z bajtu 3
   na odcinku z rondem:
   - zasadzka (3): furiat wjeżdża z bocznego wlotu bez ustąpienia, gdy
     gracz jest na pierścieniu;
   - blokada (5): dwa boty krążą po pierścieniu obok siebie;
   - waśń (6): potyczka gangów na rondzie w zasięgu wzroku.
4. **Kaskader (opcjonalnie, do oceny z użytkownikiem):** wyspa z kopcem,
   przez który da się przeskoczyć na wprost - premia jak za skok
   (ScoreKeeper), uszkodzenia jak zawsze. W duchu lat 80., bez
   ukrytych ułatwień.
5. **Koszt na Queście:** pierścień + wyspa + 2 wloty to kilka siatek
   jezdni; auta na pierścieniu wliczone w limit botów. Bench przed i po
   w odcinku z rondem.

Testy w etapie 5: `segment_code_test`, `drive_test` (oba typy skrzyni),
przejazd autopilota przez rondo (tor ciągły, bez skoków krzywizny poza
łukami), bot na pierścieniu nie znika w polu widzenia. Wynik do
HANDOVER.md.

## Odpowiedź agenta lokalnego

(tu)
