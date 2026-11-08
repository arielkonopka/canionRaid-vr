# Droga pod trawą i pod wodą - strażnik wysokości w generatorze

Status: nowe
Od: wątek w chmurze "Napraw drogę pod wodą i łąką" (2026-11-08)
Decyzje użytkownika: błąd zgłoszony przez użytkownika ("czasem droga jest
pod wodą lub pod łąką, bo jest zielona"); użytkownik prosił o przejrzenie
i refaktor. Poprawka czeka na Twoje testy i sprawdzenie na goglach.

## Co się działo

Teren to wciąż jedna płaska trawa na y = 0 (`main.tscn` Ground +
`WorldBoundaryShape3D`, z czasów toru na palach), morze z okna na
`StuntTrack.SEA_Y` 0,3. Wąwóz nie ma własnego dna. Generator sprawdzał
wysokość tylko **przed** modułem, a skocznia (stół + zeskok -12°) schodzi
o 5-10 m w jego trakcie:

- autostrada: jezdnia na 4 m, skocznia schodzi do ~-2 m → pod trawą;
- wąwóz: skocznia od ~6 m (hmin 2 + 4) w dół → pod morzem / trawą.

Port wysokości generatora do Pythona (300 ziaren × 40 odcinków): 8%
odcinków miało jezdnię < 0,3 m, ponad połowa na autostradzie; po poprawce
0 przypadków, minimum 2,0 m.

## Zmiany (gałąź `claude/project-thread-v2w7vc`, PR do `boty-szal-tekstury`)

- `scripts/track_generator.gd`: `_guarded` - każdy moduł najpierw na próbę
  (kopia stanu, ten sam `rng.state`), jeśli najniższy punkt jezdni (z niższą
  krawędzią na przechyłce, `lowest_edge`) < `d.hmin`, przed modułem
  podjazd (`_rise` = kolejne `_climb`; na autostradzie `_highway_level`)
  i próba od nowa. `_module` przepisany na wybór `Callable` + strażnik
  (bez pętli `for _once in [0]`).
- `tests/track_height_test.gd` (nowy, sam generator, bez sceny) + wpis
  w `quest.sh test`.
- `HANDOVER.md`: sekcja 5 (Trasa bez końca), sekcja 6, historia.

## Prośba

1. Kod pisany **bez Godota** - najpierw `--check-only` / import. Ryzyko:
   lambdy w funkcjach statycznych (powinny działać w 4.6).
2. `track_height_test`, `generator_test 777`, `endless_test 180 petrol 777 150`,
   `highway_test` i `drive_test` (zawieszenia × skrzynie). Trasa dla ziarna
   777 będzie trochę inna (dodatkowe podjazdy) - wyniki endless_test mogą
   się przesunąć. Wyniki wpisz do HANDOVER.
3. Na goglach: przejechać autostradę (3. odcinek) i kilka skoczni w wąwozie -
   czy nigdzie nie widać trawy ani wody na jezdni.
4. Do sprawdzenia przy okazji (nie poprawione): płaszczyzna morza ma 9 km
   i istnieje razem z kawałkiem toru, więc gdy okno na morze wypada blisko
   autostrady, woda może przykryć trawę i podstawę nasypu obok niej.
   Jeśli to widać na goglach, dopisz tu - zaproponuję ograniczenie morza.

## Odpowiedź agenta lokalnego
