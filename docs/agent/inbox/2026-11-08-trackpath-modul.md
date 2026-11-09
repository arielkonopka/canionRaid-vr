# Moduł TrackPath (plan wydajności C3 + C4) - do sprawdzenia testem

Status: przyjęte
Od: wątek w chmurze "Zaplanuj refaktoring gorących punktów wydajności"
(2026-11-08)
Decyzje użytkownika: plan `docs/PERF_PLAN.md` zaakceptowany 2026-11-08
("ok, to zróbmy zgodnie z Twoim planem"). Wpięcie w gorące pliki - Twoja
strona, po pomiarze bazowym (zlecenie `2026-11-08-plan-wydajnosci.md`).

## Co jest

- `scripts/track_path.gd` (`TrackPath`, nowy, nic go jeszcze nie używa):
  próbki jednego kawałka trasy w tablicach `Packed*` zamiast słowników,
  zapytania po indeksie (`index_at`, `index_from`, `nearest_index`
  z podpowiedzią, `track_index` - marsz od poprzedniego indeksu dla botów),
  przerwy jako przedziały (`is_gap_at`, `last_gap_end_before` bez
  przeglądania wszystkich próbek), `transform_at_distance` (lokalnie,
  bez `global_transform` kawałka).
- **Profil prędkości** (`speed_profile`, `speed_at`, `apply_braking`):
  to, co `BotDriver._calm_speed` i `_curve_speed` liczą pętlą po oknie
  co krok fizyki, liczone raz na kawałek przejściem wstecz z drogą
  hamowania (min po j >= i z sqrt(c_j² + 2·a·Δd) - ten sam wzór).
  Spokój: `speed_profile(0.6, 5.0, true, 200/3.6)`, szał:
  `speed_profile(0.8, 6.0, false, 400/3.6)`.
- `tests/track_path_test.gd`: na kawałkach wąwozu i toru na filarach
  (z przerwami) porównuje każde zapytanie z dzisiejszym `StuntTrack`
  i profil z pętlą BotDriver przepisaną 1:1; wypisuje czasy obu.

## Prośba

1. Uruchom (po `--import`):
   `godot --headless --xr-mode off -s res://tests/track_path_test.gd -- 12345 </dev/null`
   i z 2-3 innymi ziarnami. Oczekiwane `TRACK_PATH: OK`. Kod pisany bez
   Godota - literówki/błędy typów popraw od ręki i dopisz niżej, co było.
2. Wklej niżej linie "profil: ..." (różnice km/h i czasy) - z nich widać,
   ile da C4 i czy profil jest dość wierny. Profil bywa wolniejszy
   (widzi całą ścieżkę, nie 180 m) i minimalnie szybszy tuż za łukiem
   (pętla bierze próbki do 2 m za botem) - test przepuszcza do 8 km/h.
3. Wpięcie (po pomiarze bazowym, proponowana kolejność, każdy krok
   z testami jazdy):
   a) `StuntTrack` trzyma `path := TrackPath.from_samples(_samples)` po
      `_sample_path()`; `is_gap_at`, `last_gap_end_before`,
      `transform_at_distance`, `_sample_near` delegują do `path` (wyniki
      identyczne - test to sprawdza);
   b) `BotDriver`: indeks bota przez `track_index` zamiast pętli po
      `_window`, `_calm_speed`/`_curve_speed` z profili kawałka
      (`EndlessTrack` przy dobudowie: `apply_braking` na końcu poprzedniego
      profilu z `v[0]` nowego) - porównać `bot_rage_test`, `endless_test`;
   c) dopiero potem reszta kodu na indeksy i usunięcie słowników próbek.
   Z PR #18 (wysokość trasy w generatorze) nie powinno być konfliktu -
   `TrackPath` czyta tylko gotowe próbki.

## Odpowiedź agenta lokalnego

2026-11-08 - `tests/track_path_test.gd` uruchomiony (Godot 4.6.3, po
`--import`), **bez poprawek**: `TRACK_PATH: OK` dla ziaren 12345, 777, 42.
Kompiluje się bez ostrzeżeń.

Linie profilu (fragment - kawałki toru na filarach, z przerwą):

```
12345 filary Section8: 556 próbek, przerw 1 - profil: 257 zapytań, szybszy o 0.0, wolniejszy o 207.2 km/h; pętla 10842 us, profil 233 us
12345 filary Section9: 550 próbek, przerw 1 - profil: 252 zapytań, szybszy o 0.0, wolniejszy o 2.0 km/h; pętla 11335 us, profil 330 us
777   filary Section8: 545 próbek, przerw 1 - wolniejszy o 208.8 km/h; pętla 9910 us, profil 228 us
42    filary Section9: 518 próbek, przerw 1 - wolniejszy o 328.7 km/h; pętla 10097 us, profil 221 us
```

Wniosek: koszt ~45× mniejszy (≈11 ms → ≈0,23 ms na kawałek). Różnice
"wolniejszy o ~200-330 km/h" są tylko na kawałkach z przerwą (tor na
filarach) - profil widzi całą ścieżkę z przerwą, pętla BotDriver widzi
180 m; w wąwozie (jedyny tryb gry) przerw nie ma. Warto w profilu
traktować przerwę jak skok (v_req ze znaku), jeśli kiedyś wróci tor na
filarach.

Wpięcie (a, b, c) po pomiarze bazowym, zgodnie z planem.
