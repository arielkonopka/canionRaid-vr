Status: zrobione (mapka na prawo od kierownicy, PR #29)
Od: wątek w chmurze "Przenieś HUD z mapką na prawo"
Decyzje użytkownika (2026-11-09, jego słowa): "HUD z mapką i informacjami powinien być po prawej stronie od kierownicy, bo inaczej zasłania zegary."

# HUD na prawo od kierownicy: PR #29 do przetestowania

PR #29 (`claude/project-thread-j5uoey` -> `boty-szal-tekstury`) zmienia
tylko `scripts/xr_main.gd`. Wszystkie elementy HUD (mapka `TrackHud`,
kolumna postępu `_race_label`, znaki ostrzegawczy i ograniczenia,
popupy, BENCH, napis radia w concept carze) są teraz dziećmi jednego
węzła `HudPanel` w `car.seat.position + HUD_FROM_EYES`, obróconego twarzą
do oczu. `HUD_FROM_EYES = (0,27; -0,11; -0,62)`, czyli mapka 17-29°
w prawo, kolumna do ok. 37°, 4-16° pod linią wzroku. Osłona zegarów
kończy się ok. 17° w prawo. Liczone od fotela, więc działa też
w concept carze (fotel na środku).

Ponieważ `xr_main.gd` to Twój plik: jeśli PR koliduje z Twoją pracą,
przenieś zmianę u siebie (diff jest mały) i daj znać tutaj.

Proszę:
1. `tests/drive_test.gd` (zawieszenia i skrzynie jak zwykle) i
   `tests/title_test.gd`.
2. Zrzuty z gogli przez adb, sedan i concept car: widok na wprost
   (oba zegary w całości odsłonięte), mapka z kolumną postępu, znak
   ostrzegawczy/ograniczenia, popup punktów. Wrzuć do `docs/agent/outbox/`
   albo podaj ścieżkę.
3. Jeśli kolumna przy 37° jest za daleko w bok albo coś zasłania drogę,
   popraw `HUD_FROM_EYES` (np. x 0,24) i opisz, co wybrałeś.
4. Wpis do HANDOVER.md (ustalenie: HUD na prawo od kierownicy).

Po Twoim potwierdzeniu scalę PR #29 do `boty-szal-tekstury`.
