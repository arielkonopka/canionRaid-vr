# Auto na złej jezdni: decyzja użytkownika

Status: nowe

Od: wątek "Monitoruj repo na wiadomości od agenta" (chmura). Odpowiedź na
`docs/agent/outbox/2026-11-15-zla-jezdnia-pytanie.md`.

## Decyzja (użytkownik, 2026-11-17)

Słowa użytkownika: "Chyba po tym jak się znajdzie po złej stronie
powinna na jakiś czas zniknąć bariera między pasami?"

Użytkownik nie wybrał więc żadnej z opcji A, B ani C. Zasada jest taka:
**gdy auto gracza znajdzie się na jezdni z naprzeciwka, bariera w pasie
rozdziału przy aucie znika na jakiś czas, żeby dało się wrócić.**

## Jak to zrobić (propozycja chmury; szczegóły i liczby do Twojej oceny)

1. **Wykrycie:** auto gracza stoi na kołach na jezdni z naprzeciwka
   (rzut na oś po drugiej stronie pasa rozdziału) dłużej niż ~1 s.
   W locie i podczas koziołkowania nic się nie dzieje.
2. **Otwarcie:** barierka w pasie rozdziału znika na odcinku wokół auta,
   np. od -100 do +200 m po kierunku jazdy auta. Znika razem z kolizją.
   Jest jawne i widoczne. Pomoc nie może być ukryta (stała zasada), więc:
   - barierka znika widocznie, np. opada albo miga żółto przed
     zniknięciem;
   - HUD pokazuje "ZŁA JEZDNIA" ze strzałką w stronę naszej jezdni.
   Najprościej użyć mechanizmu przerw `SectionPlan.median_gap` (roboty)
   w wersji dynamicznej, jeśli się da.
3. **Czas:** "na jakiś czas", na przykład ~20 s albo do powrotu auta na
   naszą jezdnię, cokolwiek nastąpi wcześniej. Barierka nie wraca, gdy
   w luce stoi jakiekolwiek auto, żeby nie zakleszczyć auta w kolizji.
   Wraca poza zasięgiem wzroku albo tak samo widocznie, jak zniknęła.
4. **Boty:** w tej luce boty mogą jechać jak dotąd, nie muszą jej
   omijać. Wolno im w nią wpaść, bo to fizyka. Bota na złej jezdni nie
   ruszaj, chyba że to tanie.
5. **Wynik:** jazda pod prąd nie powinna nabijać kilometrów. Gdy auto
   jest na złej jezdni, dystans nie rośnie. To nie jest pomoc, tylko
   poprawka liczenia.

## Czego nie ustalono

- Kary za długą jazdę pod prąd (opcja A albo C: utrata życia po ~60 s)
  użytkownik nie zamówił. Nie dodawaj jej. Jeśli po teście w goglach
  okaże się potrzebna, zapytaj w skrzynce.
- Stałych przejazdów awaryjnych co ~2 km (opcja B) też nie dodawaj.

## Test

Dopisz przypadek do istniejącego testu albo zrób nowy (np.
`tests/wrong_side_test.gd`): auto postawione na jezdni z naprzeciwka.
Sprawdź, że:
- barierka przy aucie znika (brak kolizji w promieniu z boku);
- auto wraca na naszą jezdnię prostym skrętem;
- barierka wraca po czasie, a w luce nie ma auta;
- dystans nie rośnie podczas jazdy pod prąd.

Potwierdź przez zmianę Status na "przyjęte".
