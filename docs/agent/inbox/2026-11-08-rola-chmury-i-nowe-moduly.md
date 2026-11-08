# Wiadomość: rola wątku w chmurze + dwa nowe moduły do wpięcia

Status: nowe
Od: wątek w chmurze "Zaprojektuj nowe strategie botów road rage" (2026-11-08),
na prośbę użytkownika ("przekaż wiadomość")
Decyzje użytkownika (2026-11-08):
- Wątek w chmurze **pomaga w projektowaniu i w pull requestach** (pisze
  odizolowane moduły, przegląda i scala PR-y). **Nie pobiera Godota** -
  testy uruchamiasz Ty.
- Farmienie punktów jest w porządku (bez ochrony).

## Prośba

1. Uruchom testy logiki (nowe pliki, po `godot --headless --import
   --xr-mode off </dev/null`):
   - `tests/score_test.gd` (ScoreKeeper, z PR #5)
   - `tests/stunt_shop_test.gd` (StuntTracker + WorkshopShop, ten PR)
   Kod jest pisany bez uruchomienia - mogą być literówki albo błędy typów.
   Popraw je od ręki i dopisz tu, co było nie tak (żebym wiedział na
   przyszłość), albo odpisz, jeśli coś w logice jest źle.
2. Wpięcie (Twoja strona, gorące pliki) - szczegóły w
   `2026-11-08-plan-gry-podzial-pracy.md`:
   - `ScoreKeeper` w `xr_main` + zdarzenia z `BotDriver`, usunięcie `HIT_BONUS`;
   - `WorkshopShop.offers(car.damage, keeper.points, owned)` w menu
     warsztatu obok wyboru napędu; `buy(id, car.damage, keeper)`;
     przy "repaired_full" zawołaj `car.repair()` (wgniecenia);
   - `StuntTracker.step(delta, car.global_basis, car.angular_velocity,
     car.wheels_on_ground, car.speed, normalna_jezdni)` raz na krok fizyki
     gracza, wynik do `keeper.award_free(e.kind, e.points, now, e.text)`.
     Na zwykłym torze normalna = `Vector3.UP` wystarczy; na przyszłej
     pętli podawaj normalną jezdni.
3. Gdy otworzysz PR z wpięciem (do `main` albo do swojej gałęzi), mogę
   go przejrzeć i scalić - użytkownik na to pozwolił. Wpisz w opisie, które
   testy przeszły.

## Przyjęte w modułach założenia do sprawdzenia na goglach

- Ceny: pościg ~500-800 pkt, pełna naprawa wraku 3150 pkt, zapasowe auto
  2500. Strój po kilku przejazdach (linie `SCORE:` w logu).
- Sztuczki: skok liczy się od 0,35 s w powietrzu; obrót z tolerancją 60°
  (300° = salto); czyste lądowanie = 4 koła w 0,3 s i auto równo z
  jezdnią; pętla/beczka na kołach = 330° obrotu, licznik zeruje się po
  1,5 s jazdy prosto.

## Odpowiedź agenta lokalnego

(puste)
