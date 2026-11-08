# Plan gry: furia drogowa bez końca + tryb kaskaderski. Podział pracy

Status: nowe
Od: wątek w chmurze "Zaprojektuj nowe strategie botów road rage" (2026-11-08)
Decyzje użytkownika (2026-11-08, cytaty w skrócie):
- "Nie przeszkadza mi farmienie punktów." - bez ochrony przed farmieniem
  (malejąca nagroda w `ScoreKeeper` domyślnie wyłączona, `diminish_k = 0`).
  Mandat za uderzenie spokojnego bota zostaje (decyzja wcześniejsza).
- Gracz **uczestniczy w furii drogowej**: albo jej **unika**, albo w niej
  **walczy**, a punkty idą na **naprawę auta w warsztacie**.
- Forma: **nieskończona gra zręcznościowa w stylu lat 80.**, ale
  "w kompletnie nowym odkryciu" (VR, realistyczna fizyka).
- Obok trybu ciągłego **tryb kaskaderski**: sztuczki, np. **wyjazd
  z beczki**, **zjazd z góry, żeby zrobić pętlę**. "Generalnie ma to być
  gra zręcznościowa."
- Wątek w chmurze **może pisać kod** (podział pracy z agentem lokalnym),
  **przeglądać i scalać PR-y**.

## Pętla gry (tryb ciągły "Furia")

1. Jedziesz wąwozem / autostradą, ruch, przepisy.
2. Furia: posiłki albo furia po wyprzedzeniu (pościgi płatne) albo
   Twoje uderzenie (mandat, pościg bez punktów).
3. Wybierasz: **uciekasz** (unik, zgubienie, przepisowe uspokojenie, skok)
   albo **walczysz** (rozbicie, obrót, przebicie formacji). Seria mnoży.
4. Warsztat co 10 odcinków: punkty → naprawa strefami, potem ulepszenia.
   Paliwo ~12 km - stacje co 5 odcinków (osobny zasób).
5. Życia = auta. Wynik końcowy: odcinek, km, `total_earned`.

Styl lat 80.: wynik zawsze widoczny, krótkie krzykliwe napisy ("+150 UNIK
x2"), dźwięki 8-bit przy zdarzeniach (jest już 8-bitowa tablica odcinka),
trudność rośnie z odcinkiem bez końca. Realizm fizyki bez zmian.

## Tryb kaskaderski (propozycja, do rozwinięcia)

- Osobny wybór w menu, trasa z modułów-sztuczek: zjazd z góry → pętla,
  beczka (korkociąg), skocznia z lądowaniem na stole, ściana z przechyłką.
- Punkty: czas w powietrzu, obroty (całkowanie prędkości kątowej
  w układzie auta: przewrót/beczka/obrót), czyste lądowanie (wszystkie
  koła, mało uszkodzeń), ukończona pętla, bliskość ściany.
- Wymaga **ramy toru obracanej** (rotation-minimizing frame /
  kwaternion na próbce) - HANDOVER już to notuje; pętla: v² ≥ g·R
  z zapasem na przyczepność, zjazd z góry daje prędkość.
- Ten sam `ScoreKeeper` (nowe rodzaje zdarzeń) - jeden portfel i jeden
  styl napisów.

## Podział pracy

Zasada: chmura pisze **nowe, odizolowane pliki** (czysta logika + testy
headless), agent lokalny **wpina je w gorące pliki** (`xr_main.gd`,
`bot_driver.gd`, `stunt_track.gd`, menu) i sprawdza na Queście. Mniej
konfliktów, a chmura nie ma gogli.

| Część | Kto | Stan |
|---|---|---|
| `scripts/score_keeper.gd` - punkty, seria, mandat, portfel | chmura | **w tym PR-ze** |
| `tests/score_test.gd` - test logiki | chmura | **w tym PR-ze**, nieuruchomiony (brak Godota w chmurze) |
| Uruchomić `score_test`, poprawić ewentualne błędy składni | agent | do zrobienia |
| Wpięcie: karta pościgu w `BotDriver` (koniec fazy ataku, min. odstęp, kontakt), `xr_main` (zgubienie/wybuch/uspokojenie), usunięcie `HIT_BONUS` | agent | do zrobienia |
| Napisy punktów (pula Label3D przy desce), wynik na desce, dźwięki zdarzeń | agent | do zrobienia |
| Warsztat: cennik napraw strefami + zakupy | chmura: `workshop_shop.gd` (gotowe); agent: menu | logika gotowa, test `stunt_shop_test` |
| Detektor sztuczek (`stunt_tracker.gd`: powietrze, obroty, lądowanie, pętla, beczka) | chmura | gotowe, test `stunt_shop_test` |
| Rama toru obracana, moduły pętla/beczka, tryb w menu | agent | później |
| Wybór taktyki botów (utility AI zamiast losowania w "mixed"), czysta funkcja ocen | chmura | później |
| Przegląd PR-ów agenta | chmura | na bieżąco |

## API `ScoreKeeper` (skrót, szczegóły w komentarzu pliku)

`open_chase(id, origin, now)`, `note_contact(id, now)`,
`end_attack(id, hit, min_gap, kmh, now)`, `close_chase(id, reason, now, kmh)`
("lost"/"calmed"/"wreck"), `award(kind, id, now, kmh)` (pit, outmaneuver,
jump_escape, formation), `new_section()`, `spend(n)`, `log_line(p)`.
Każda zwraca listę wypłat `{kind, points, combo, text}`. `id` =
`get_instance_id()` bota, `now` = czas jazdy. Klasa jest `RefCounted` -
po dodaniu pliku `godot --headless --import --xr-mode off </dev/null`.

Pytania do agenta: czy API pasuje do miejsc w kodzie (np. czy łatwo
wykryć koniec fazy ataku w `_rage_plan`)? Jeśli nie - zmień je i napisz tu.

## Odpowiedź agenta lokalnego

(puste)
