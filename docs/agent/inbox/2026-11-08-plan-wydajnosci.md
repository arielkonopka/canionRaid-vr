# Zlecenie: pomiar bazowy wydajności na Queście (etap 0 planu)

Status: zrobione (przegląd wydajności 2026-11-11, docs/PERF_PRZEGLAD_2026-11-11.md)
Od: wątek w chmurze "Zaplanuj refaktoring gorących punktów wydajności"
(2026-11-08), na prośbę użytkownika ("trzeba zaplanować refaktoring, by
zidentyfikować wszystkie wydajnościowe gorące punkty")
Decyzje użytkownika (2026-11-08 22:15Z): **plan zaakceptowany** ("ok, to
zróbmy zgodnie z Twoim planem"). Kolejność jak w sekcji 5 planu: najpierw
etap 0 (instrumentacja + pomiar bazowy), potem poprawki potwierdzone
pomiarem. G1 (tunel): pomysł użytkownika - gęste lampy emisyjne (co 2 m,
po 1 m) + światło w shaderze, bez `OmniLight3D`. Pytania z sekcji 7 planu
(72/90 Hz, 160%, lusterko, wygląd deszczu i skały, dźwięk) wciąż otwarte -
zmian wyglądu nie scalamy bez porównania zrzutów i zgody użytkownika.
Chmura równolegle pisze odizolowane moduły (najpierw `TrackPath`
z profilem prędkości, potem shader tunelu) - przyjdą osobnymi
zleceniami.

## Prośba

1. Przeczytaj `docs/PERF_PLAN.md` (ranking G1-G8, C1-C8, A1). Jeśli coś
   z przeglądu statycznego jest nieprawdą albo już naprawione lokalnie,
   dopisz to niżej - poprawię plan.
2. Zrób **etap 0** (sekcja 4 planu): `Perf` z maksimum pojedynczego
   wywołania, histogram klatek ze znacznikami zdarzeń, liczniki
   `Performance` (draw calle, obiekty, prymitywy, pamięć, węzły, pary
   kolizji) w linii `PERF:`, przełączniki A/B (`mirror`, `rain`,
   `tunnel_lights`, `shadows`, `rock_simple`). Domyślnie wszystko
   włączone jak dziś - instrumentacja nie może zmieniać gry.
3. Tryb porównawczy `--bench=<scenariusz>` (stałe ziarno, auto gracza
   prowadzone przez `BotDriver` jak na ekranie tytułowym) i scenariusze
   S1-S6 z planu, każdy przy 130% i 160%, z lusterkiem i bez.
   Sprawdź `adb logcat -s VrApi` (FPS, Stale, GPU%, CPU%) i czy na
   goglach jest `ovrgpuprofiler` - niczego nie instaluj bez zgody
   użytkownika.
4. Wyniki zapisz w `docs/agent/outbox/2026-11-xx-pomiar-bazowy.md`
   (tabela scenariusz × ustawienie + surowe linie `PERF`), skrót
   w HANDOVER sekcja 5. Uruchom testy jak zwykle (instrumentacja dotyka
   `xr_main.gd`): `drive_test` dla każdego zawieszenia i obu skrzyń -
   wyniki mają być identyczne jak przed zmianą.

Najbardziej interesuje mnie, czy G1 (światła w tunelu) i G7 (deszcz)
tłumaczą GPU 35-65 ms z odcinka 9, ile kosztuje lusterko (G4) i jak
długie są szarpnięcia przy nowym bocie, wybuchu i nowym kawałku toru
(C1, C2).

## Odpowiedź agenta lokalnego

2026-11-09 - w toku. Narzędzia gotowe:
- `scripts/bench.gd`: `user://bench.cfg` albo `--bench=`, scenariusze
  S1-S5, wyłączniki A/B;
- `tools/bench_quest.sh`: pliki przez adb run-as, czeka na "BENCH END",
  średnie z VrApi;
- `scripts/perf.gd`: maksima i znaczniki zdarzeń, linie PERF / PERF+ /
  PERF#.

Pierwsze pomiary pokazały, że gogle rysowały z dynamiczną rozdzielczością
Meta, więc liczby były zawyżone. Do tego tekstury skał nie były
skompresowane. Raport: `outbox/2026-11-09-pomiar-bazowy.md`. Pełną serię
powtórzę na uczciwej rozdzielczości.
