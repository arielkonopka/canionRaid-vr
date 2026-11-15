# Auto po koziołkowaniu na drugiej jezdni - pytanie o zasadę

Od: agent lokalny (2026-11-15). Zgłoszenie użytkownika z jazdy w goglach
(build z cd2288a): "czasem udaje mi się przekoziołkować na drugi pas
i nie da się z niego potem wrócić".

## Stan dziś

- Bariera w pasie rozdziału jest ciągła. Przerwy są tylko przy robotach
  (`SectionPlan.median_gap`, przejazd aut z naprzeciwka).
- Auto, które wyląduje na kołach na jezdni z naprzeciwka, nie spełnia
  żadnej reguły upadku z `xr_main._watch_track`. Jest bliżej niż hw + 15 m
  od osi, nie leży na dachu i nie jest zawieszone. Gra więc nic nie robi.
  Gracz jedzie pod prąd bez końca albo traci życie przyciskiem "nowe auto"
  (primary_click).
- Dystans liczy się dalej z rzutu na naszą oś, więc jazda pod prąd
  w przód "nabija" kilometry.

## Propozycje

A. **Druga jezdnia = poza trasą.** Gdy auto jest na jezdni z naprzeciwka
   dłużej niż ~3 s (albo stoi), zasada jak przy upadku: utrata życia,
   eksplozja, nowe auto na naszej jezdni. To prosta reguła, zgodna z "życie
   = auto, które wypadło z gry", ale surowa, bo auto jest całe.

B. **Przejazdy awaryjne w pasie rozdziału.** Na polskich autostradach są co
   kilka km, zamknięte barierą rozbieralną. W grze byłyby otwarte
   (przerwa w barierce jak `median_gap`) co ~2 km, poza budowlami i
   miastami, z widocznym znakiem lub oznakowaniem. Gracz na złej jezdni
   jedzie pod prąd albo na pasie awaryjnym do najbliższego przejazdu
   (najwyżej ~1 km) i wraca. Kraksa z autem z naprzeciwka kończy się
   naturalnie. Mniej realistycznie: otwarte przejazdy w rzeczywistości
   się nie zdarzają.

C. **Połączenie A + B:** przejazdy jak w B, a jeśli gracz po ~60 s (albo
   ~2 km) dalej jest na złej jezdni, to reguła A.

Rekomenduję **C**. Daje szansę na powrót (o to chodziło w zgłoszeniu)
i nie zostawia gracza pod prąd na zawsze. Nie ma też ukrytej pomocy:
przejazd widać, a regułę A pokazuje komunikat "ZŁA JEZDNIA" z odliczaniem.

Do czasu odpowiedzi nic w tej sprawie nie zmieniam. Robię dalej 3e
(estakada: brak nasypu nad doliną, kolizja dna doliny, dekoracje na dnie,
test `structure_drive_test -- estakada` OK).
