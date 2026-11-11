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
Dopytuję użytkownika, co działo się tuż przed końcem trasy (skok, zderzenie,
odrodzenie, warsztat, autostrada czy wąwóz) i dopiszę to tutaj.

## Odpowiedź agenta lokalnego

