# Wąskie gardła - kandydaci do przeprojektowania (2026-11-10)

Od: wątek w chmurze "Doprowadź grę do pełnej trasy autostradowej".
Przegląd kodu z gałęzi `boty-szal-tekstury` (po PR #46-#49), bez Godota
i bez gogli - **liczby to szacunki, nie pomiary**. Uzupełnia
`docs/PERF_PLAN.md` (ranking G1-G8, C1-C8, A1 - tam szczegóły); tutaj
patrzę na to, co zmienia się, gdy autostrada idzie przez całą trasę
z ruchem w obie strony, furią między botami i miastami z leniwym grafem.
Zasada bez zmian: **fizyka auta gracza i botów przy graczu jest
nietykalna** (VISION, CLAUDE.md); upraszczamy tylko to, czego gracz nie
dotyka.

## Ranking

| # | Obszar | Dlaczego teraz | Kierunek przeprojektowania | Wpływ | Praca |
|---|---|---|---|---|---|
| W1 | Pozycja na trasie = jedna liczba `dist` | ~76 odwołań do `["dist"]`; boty, HUD, warsztaty, odrodzenie, LOD zakładają jedną linię. Prawdziwe rozwidlenia, miasta (graf ulic, PR #49) i dwie jezdnie jako osobne drogi nie mieszczą się w tym modelu. | Pozycja `(path_id, s)` i graf odcinków (PERF_PLAN sekcja 6). `TrackPath` już istnieje (`scripts/track_path.gd`), ale **nikt go nie używa**. Najpierw adapter: `EndlessTrack` wystawia `TrackPath` obok słowników, nowe moduły (ruch, miasta) piszą tylko na `TrackPath`. | architektura - odblokowuje miasta i rozwidlenia | L |
| W2 | Próbki toru jako `Dictionary` | Autostrada na całej trasie = stale ~12 botów + ~12 aut z naprzeciwka; każde pyta o próbki (`samples_from`, `nearest_sample` - 22 wywołania w kodzie) przez słowniki z ~16 kluczami tekstowymi. Koszt rośnie liniowo z ruchem. | PERF_PLAN C3: tablice `Packed*Array` w `TrackPath`, wyszukiwanie od ostatniego indeksu, profil prędkości liczony raz przy budowie (C4). | CPU, średni-duży | L |
| W3 | Budżet aut z fizyką a szał | Bot w szale ma zawsze fizykę i omija budżet `BotLod` (8). Posiłki w 400 m i waśnie gangów mogą wściec wiele aut naraz - wtedy fizyka (GDScript, 2 podkroki opon, 120 Hz) rośnie bez sufitu. | **Żetony pościgu**: najwyżej K (np. 4) goniących z fizyką; kolejni czekają na szynie poza wzrokiem gracza i dostają żeton, gdy ktoś odpadnie. Waśnie dalej niż `LOD_NEAR` rozgrywane skryptem (jak `OncomingSkirmish`: klatki kluczowe, bez fizyki, ten sam wynik - wrak, punkty dla nikogo). Fizyka tylko tam, gdzie gracz może dotknąć. | CPU, duży; stabilność klatki przy furii | M |
| W4 | Trzy poziomy ruchu | Ruch w obie strony na całej długości: dużo aut w kadrze daleko. Dziś każde auto to ~25-30 draw calli (PERF_PLAN G6). | Fizyka (blisko, budżet) / szyna kinematyczna (środek) / **daleko: jeden `MultiMesh` na jezdnię** (prosta bryła w kolorze lakieru przez `instance_shader_parameter`, 1 draw call). Przejście z szyny na MultiMesh poza 200 m. | GPU+CPU, duży | M |
| W5 | Wgniecenia liczone w GDScripcie | `_dent_rebuild` przepisuje tablice wierzchołków w GDScripcie (siatki rzędu 10 tys. wierzchołków). Przy furii między botami zderzeń jest wielokrotnie więcej - szarpnięcia. | Globalny budżet: najwyżej 1 przebudowa siatki na klatkę (kolejka), boty dalej niż ~40 m bez wgnieceń wizualnych (uszkodzenia w liczbach zostają - wpływ na jazdę bez zmian). Docelowo: deformacja w shaderze wierzchołków z małej tekstury wgnieceń. | szarpnięcia, średni | S-M |
| W6 | `xr_main.gd` jako "bóg" | 2227 linii, 83 funkcje: wyścig, życia, boty, pula, LOD, auta z naprzeciwka, stacje, warsztat, HUD, deszcz, lusterko, sterowanie, pauza, przesuwanie świata. Każda nowa funkcja (sklep, menu stacji, klakson, waśnie) dokłada się tu, a wątki w chmurze nie mogą tu pisać bez konfliktów. | Rozbicie na węzły-systemy z jasnym API: `TrafficDirector` (boty, pula, LOD, waśnie, z naprzeciwka, żetony z W3), `ServiceStops` (stacje, warsztat, sklep), `DriverInput` (mapowanie kontrolerów - jedno miejsce na spust/B/klakson), `RaceDirector` (stan, życia, odcinki), `HudPresenter`. Robić przy okazji, kawałek po kawałku - zaczynając od tego, co i tak się zmienia (sklep, sterowanie). | utrzymanie, praca równoległa | L (stopniowo) |
| W7 | Trzy osobne menu | Tytuł, pauza i warsztat mają osobną obsługę przycisków i osobne listy opcji. Prośby z tej nocy (pauza = pełne ustawienia, spust zatwierdza wszędzie, pytanie o restart) to dziś trzy razy ta sama robota. | Jeden `MenuController` ze stosem ekranów (zatwierdź / wstecz / zbocze spustu) i jedno drzewo opcji (`settings_menu.gd`) używane przez tytuł i pauzę. Warsztat i stacja jako ekrany tego samego sterownika z listą ofert z `WorkshopShop`. | utrzymanie, spójność | M |
| W8 | Budowa kawałka w jednej klatce | Autostrada dokłada zabudowę miast (MultiMesh + kolizja pierwszego rzędu), nasypy, słupki; miasta z grafem dołożą ulice budowane w biegu. | PERF_PLAN C2: geometria w `WorkerThreadPool` (same tablice), na głównym wątku tylko utworzenie siatek/ciał; usuwanie partiami. Graf miast (PR #49) już daje różnicę add/remove - budować ulice po jednej na klatkę. | szarpnięcia, duży | L |
| W9 | `float32` w UV jezdni | `UV.y` jezdni = dystans wzdłuż toru [m] (`shaders/road.gdshader`). Przesuwanie świata (`WorldOrigin`) nie pomaga, bo dystans rośnie bez końca: po ~100 km krok float32 to ~1 cm, po kilkuset km pasy i szum zaczną "pływać". Na autostradzie przez całą trasę to realne. | Zawijać `UV.y` przy budowie kawałka (np. `fmod(dist, 4096)` z okresem będącym wielokrotnością okresu pasów i szumu) albo trzymać dystans od początku kawałka. Tani, bez ryzyka. | jakość obrazu po długiej jeździe | S |
| W10 | Światła w tunelach | `OmniLight3D` co 80 m na rurę dalej są w kodzie (za przełącznikiem `tunnel_lights`). | PERF_PLAN G1 (paski emisyjne + jasność w shaderze). Na autostradzie tuneli mniej, więc niższy priorytet niż przed tygodniem. | GPU w tunelach | M |
| W11 | Fizyka w GDScripcie | Auto gracza: 6 podkroków opon x 120 Hz; boty 2 podkroki. To ogranicza, ile aut może naprawdę walczyć fizycznie (W3). | Model opon i kół w GDExtension (C++) dałby kilka razy więcej aut z fizyką bez zmiany wyników. **Wymaga pobrania godot-cpp - tylko za zgodą użytkownika.** Warunek: wyniki testów jazdy identyczne co do cyfry. | CPU, bardzo duży | L |
| W12 | Synteza dźwięku, napisy co krok | PERF_PLAN C6 i C7 - bez zmian od planu; nadal tanie do zrobienia. | Jak w PERF_PLAN. | niski-średni | S |

## Fizyka gracza - co jeszcze odstaje od "zgodnie z prawami fizyki"

Nie wydajność, ale ten sam przegląd (cel 4 użytkownika):

1. **Sprzęgło** - ruszanie: obroty spadały skokiem z `launch_rpm` do 1300.
   Poprawka w PR #35 (czeka na testy agenta): dynamika obrotów silnika,
   sprzęgło z ograniczonym momentem; przyczyna utykania pod górę z PR #28
   to cykl graniczny TCS (`TCS_GAIN` 2,0 -> 0,5).
2. **Niestabilność przy dużej prędkości** (HANDOVER sekcja 8, pkt 00):
   700 kW tył, ~240 km/h, kierownica 0 - auto samo wchodzi w dryf.
   Fizycznie możliwe (tylne opony na granicy przyczepności wzdłużnej
   nie mają zapasu bocznego), ale prawdziwe auta tej mocy mają szersze
   tylne opony i zbieżność tyłu. Kandydat: szerokość tylnych opon jako
   funkcja mocy (jawna, w opisie auta), zbieżność tyłu w geometrii -
   bez ukrytego "stabilizatora".
3. **Odbicie bezwładności silnika** jest liczone tylko przy zamkniętym
   sprzęgle (`reflected` w `_physics_step`) - przy ślizgającym się
   sprzęgle koła nie czują silnika, co jest poprawne; po PR #35 warto
   sprawdzić, czy przejście ślizganie -> zamknięte nie daje skoku
   prędkości kół (test: `launch_test` z zapisem omega co krok).
4. **Lądowanie przy nadmiarze prędkości** (pkt 00): auto obraca się nosem
   w dół i wbija zderzakiem - to fizyka, nie błąd. Decyzja projektowa
   (dłuższe lądowiska) zostaje u użytkownika.

## Co proponuję zrobić najpierw

1. W9 (zawijanie `UV.y`) - minuty pracy, chroni długą jazdę po autostradzie.
2. W3 (żetony pościgu) razem z wpięciem waśni - bez tego furia między
   botami może zabić klatkę na Queście.
3. W5 (budżet wgnieceń) - tanie, a zderzeń będzie dużo więcej.
4. W7 przy okazji próśb o menu z tej nocy (pauza, spust/B) - jeden
   sterownik zamiast trzech poprawek.
5. Potem W2 -> W1 (TrackPath i graf) - przed wpięciem miast na dobre.

Pomiar przed i po każdej zmianie: `tools/bench_quest.sh` (PERF_PLAN
sekcja 4), na uczciwej rozdzielczości (bez dynamicznej rozdzielczości
Meta).
