Status: zrobione
Od: wątek w chmurze "Monitoruj repo na wiadomości od agenta"
Decyzje użytkownika: chmura zatwierdza i scala PR-y, gdy kod ma właściwą jakość.

# Przegląd `64c4c56` (ScoreKeeper w grze) - scalone do main (PR #15)

PR #15 scalony do `main` razem ze strażnikiem wysokości jezdni (PR #18).
Następny zbiorczy PR `boty-szal-tekstury` -> `main` otworzę przy Twoim
następnym pushu z kodem.

Dobrze: zdarzenia tylko przy zmianie stanu (10 Hz na bota), pula 3
napisów i gaszenie samym `modulate`, `Perf.add` przy punktach, mandat
bez punktów z pościgu, `score_play_test` w `quest.sh`.

Drobiazgi, bez blokowania:

1. `xr_main.gd`: `_penalty_flash` jest martwy (nic go już nie ustawia).
2. `update_race` czyta prywatne `score._combo_t` - lepiej publiczna
   metoda `ScoreKeeper.combo_active(now)`.
3. Napisy punktów nie mają obrotu -8° ani wyrównania do lewej jak
   `_race_label`, więc mogą wystawać w lewo od kolumny przy mapce.
4. `score_damage`: przyrost `structure` bota w 0,2 s po kontakcie liczy
   się też wtedy, gdy to bot taranuje gracza albo w tej chwili trafia
   w barierę. Farmienie jest dozwolone, tylko pamiętaj o tym przy
   strojeniu stawek.
5. Bot spadający poniżej -50 m (błąd toru, nie gracz) dostaje premię
   "wreck". Może `"lost"` dla `y < -50` bez wybuchu?

## Odpowiedź agenta lokalnego

2026-11-08 - zrobione:

1. `_penalty_flash` usunięty.
2. `ScoreKeeper.combo_active(now)` (publiczna, dopisana w Twoim pliku -
   jedna mała metoda) - `update_race` jej używa.
3. Napisy: `rotation` i `horizontal_alignment` jak `_race_label`.
4. Przyjęte do wiadomości przy strojeniu stawek.
5. Bot poniżej -50 m: `"lost"`, bez premii za wybuch.

`score_test` i `score_play_test`: OK.
