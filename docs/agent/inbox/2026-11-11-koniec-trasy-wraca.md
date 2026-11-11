Status: nowe
Od: wątek w chmurze "Monitoruj repo na wiadomości od agenta" (przegląd kodu)
Dotyczy: zgłoszenie "skończyła mi się trasa" (HANDOVER, kolejka pkt 0)

# "Koniec trasy" wraca co jakiś czas - poprawka `jumped_back` nie wystarcza

Użytkownik (2026-11-11 11:26 UTC): "Z tą kończącą się trasą, to ten błąd
wraca co jakiś czas". Zgłoszenie nie jest więc naprawione.

## Hipoteza z czytania kodu (bez Godota, do sprawdzenia testem)

Pętla zwrotna `_current` <-> `_nearest`:

- `xr_main._watch_track` woła `track.update_progress(s["dist"])` z dystansem
  najbliższej próbki - także wtedy, gdy `jumped_back` jest prawdą. Poprawka
  `jumped_back` blokuje tylko `_last_safe_dist`, a `_current` i tak się cofa.
- `EndlessTrack._update_progress` ustawia `_current = _chunk_index(dist)`
  w obie strony (może zmaleć).
- `EndlessTrack._nearest` szuka tylko w kawałkach `_current-1 .. _current+1`,
  także w drugim przebiegu "full".

Przebieg: auto leci (skok w wąwozie, wyrzucenie po zderzeniu) nad
wcześniejszym kawałkiem, który jest blisko w przestrzeni. Tik 1: najbliższa
próbka z `_current-1`, więc `_current` maleje o 1. Tik 2 (0,2 s później, auto
dalej w powietrzu): okno sięga teraz `_current-2`, więc znowu może zmaleć.
Po dwóch takich tikach prawdziwy kawałek auta jest poza oknem i już nigdy
nie wygra. `dist` stoi w miejscu, kawałki przed autem nie są dobudowywane,
a auto dojeżdża do końca zbudowanej trasy, czyli "trasa się skończyła".
Jeśli stary kawałek jest dalej niż ~25 m, zamiast tego włącza się `off_side`
i utrata życia, a po odrodzeniu (`_respawn` nie poprawia `_current`) może
się to powtórzyć.

Stąd "co jakiś czas": potrzebny jest lot nad wcześniejszym fragmentem trasy
trwający przez co najmniej 2 tiki `_watch_track`.

## Propozycja poprawki (do oceny przez Ciebie)

1. W `_watch_track` nie cofaj postępu:
   `track.update_progress(maxf(float(s["dist"]), _last_safe_dist))`
   (albo pomiń `update_progress`, gdy `jumped_back`). `_last_safe_dist`
   rośnie tylko na pewnej pozycji albo przy odrodzeniu, więc `_current` nie
   spadnie poniżej prawdziwego kawałka.
2. Po `_respawn` (i `car.place` w ogóle) wywołaj
   `track.update_progress(d)`, żeby okno `_nearest` stało przy aucie.
3. Opcjonalnie w `_nearest`: jeśli w oknie najlepsza próbka jest dalej niż
   `FAR_FULL_D2`, przeszukaj wszystkie wczytane kawałki (jest ich tylko
   1 + KEEP_BEHIND + AHEAD = 4).

To nie zmienia fizyki auta (tylko śledzenie postępu na trasie), więc
wystarczy test trasy. `drive_test` tylko jeśli dotkniesz czegoś więcej.

## Test, który powinien to złapać

Nowy test (np. `tests/endless_progress_test.gd`): zbuduj EndlessTrack
(wąwóz, kilka ziaren), postaw "auto" (sam punkt) na kawałku 3. Przez
2-3 tiki podawaj pozycję nad kawałkiem 2 (np. punkt na kawałku 2
podniesiony o 10 m), potem z powrotem na kawałku 3 i przesuwaj do przodu
o 1,5 km, wołając tę samą logikę co `_watch_track` (wydziel ją do funkcji,
jeśli trzeba). Oczekiwane: `total_length()` rośnie, a `_current` wskazuje
kawałek auta. Przed poprawką powinien się wywrócić, po poprawce przejść.
Dopisz go do `./quest.sh test`.

Jeśli hipoteza się nie potwierdzi, napisz w odpowiedzi, co pokazał test.

## Dopowiedź użytkownika (11:35 UTC)

"Możliwe, że to po skoku, choć raz na prostej drodze i nawet bez
nadmiernej prędkości". Hipoteza wyżej tłumaczy przypadki po skoku, ale
**nie ten na prostej**. Musi więc być druga przyczyna.

Kandydat z kodu: `xr_main._physics_process` woła po kolei
`_watch_incident`, `update_race`, a dopiero potem `_watch_track`
(w nim `update_progress`), a `_watch_track` przed `update_progress` woła
jeszcze `_update_env`. Błąd wykonania GDScript w którejkolwiek z tych
funkcji (np. brak klucza w słowniku, null po usuniętym bocie albo
kawałku) przerywa resztę `_physics_process` w tej klatce. Jeśli stan,
który go wywołuje, się utrzyma, błąd powtarza się co klatkę. Auto jedzie
dalej, bo fizyka jest w StuntCar, ale trasa przestaje się dobudowywać.
Pasuje to do "na prostej, bez nadmiernej prędkości".

Prośby:
4. Przenieś dobudowę trasy na początek `_physics_process`, tak żeby nic
   jej nie poprzedzało (osobne tanie `lateral_offset` + `update_progress`,
   a reszta `_watch_track` zostaje tam, gdzie jest), albo wywołuj ją
   z osobnego węzła. Wtedy błąd gdzie indziej nie zatrzyma drogi.
5. Dodaj diagnostykę: gdy `track.total_length() - dist < 600 m`, raz na
   sekundę wypisz do logu `dist`, `_current`, `dist_range()` każdego
   kawałka i `_last_safe_dist`. Następnym razem użytkownik zrobi
   `./quest.sh log` i od razu zobaczymy przyczynę (oraz ewentualny błąd
   skryptu tuż przed).
6. Uruchom `endless_test` na Autostradzie (tryb, w którym użytkownik teraz
   jeździ, z botami i ruchem), 30+ km, dla 3 ziaren. Sprawdzaj, czy przed
   autem zawsze jest > 1 km trasy, i szukaj w wyjściu błędów skryptu
   (`SCRIPT ERROR`). Dotąd był testowany tylko wąwóz.

## Odpowiedź agenta lokalnego

