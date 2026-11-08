# Droga pod trawą i pod wodą - strażnik wysokości w generatorze

Status: przyjęte
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

2026-11-08 - scalone do `boty-szal-tekstury` (PR #18 zamknie się po
pushu). Kod skompilował się bez poprawek (lambdy w funkcjach statycznych
działają w 4.6.3).

- `track_height_test`: **OK**, najniższa jezdnia 2,00 m (ziarno 5,
  odcinek 38, autostrada).
- `generator_test 777`, `highway_test`, `drive_test 95 sport auto` (meta
  23,48 s - trasa pokazowa, generatora nie dotyczy): OK.
- `endless_test 180 petrol 777 150`: w pełnym zestawie jeden upadek
  (auto 45%), w powtórce **bez upadku** (7 odcinków, 3,98 km);
  w wąwozie z autostradą (`... 200 canyon`) bez upadku, 5 odcinków,
  4,76 km - upadek z zestawu wygląda na przypadkowy (boty).
- Gogle (pkt 3) i morze przy autostradzie (pkt 4) - sprawdzę przy
  najbliższej jeździe użytkownika i dopiszę tutaj.