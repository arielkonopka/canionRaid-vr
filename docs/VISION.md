# Canion Raid VR - założenia projektu (wizja)

Ostatnia aktualizacja: 2026-11-08 (dopisane filary 9-11). Źródło: słowa użytkownika
(2026-11-08), spisane przez wątek projektowy w chmurze. To jest stały
punkt odniesienia dla wszystkich agentów - decyzje szczegółowe są
w `HANDOVER.md`, zlecenia w `docs/agent/inbox/`.

## W jednym zdaniu

**Drogowy "river raid" w VR**: bezkresna gra zręcznościowa na losowo
generowanych odcinkach, z rozdzielającymi się nitkami drogi, gdzie
zamiast samolotów i czołgów polują na gracza **samochody furiatów
drogowych**, a za kierownicą siedzą **manekiny od testów zderzeniowych**.

## Filary

1. **Bez końca, odcinkami.** Trasa dzieli się na odcinki generowane
   losowo. Trudność rośnie z numerem odcinka bez końca. Droga
   **rozdziela się na nitki** (wybór drogi jak kanały w grach z lat 80.).
2. **Urozmaicona droga.** Wąwóz, autostrada, tunel, estakady i inne -
   na zmianę, z własnym charakterem każdego typu (inne taktyki botów,
   inne zagrożenia).
3. **Furiaci drogowi.** Zdalnie sterowane albo zautomatyzowane auta
   z **patologicznymi zachowaniami na drodze**: zajeżdżanie, taranowanie,
   spychanie (pit), kleszcze, zygzaki, **zasadzki**, i kolejne.
   Za kierownicą **manekin crash-testowy** (pomysł użytkownika) - stąd
   "ludzkie" zachowanie bez ludzi w środku.
4. **Fizyczna wierność auta.** Realistyczna fizyka jest wyborem
   użytkownika (CLAUDE.md). Pomoce tylko jawne i wyłączalne.
5. **Uszkodzenia wpływają na jazdę** - u gracza **i** u furiatów.
   Uszkodzony silnik, hamulce, zawieszenie zmieniają prowadzenie; bot
   z rozbitym przodem jest wolniejszy, ze zniszczonym zawieszeniem ściąga.
6. **Kaskaderka.** Skocznie, pętle, beczki, zjazdy z góry - w trybie
   ciągłym jako część trasy i w osobnym trybie kaskaderskim.
7. **Warsztat i punkty.** Uszkodzenia naprawia się w warsztacie **za
   punkty**, zdobywane na dwa sposoby:
   - **ucieczka** przed furiatem, **zwłaszcza przed zasadzką**;
   - **uszkodzenia zadane** autom furiatów;
   - **punkty ekstra za eksplozję** auta furiata.
   Paliwo / prąd to osobny zasób (stacje).
8. **Zręcznościówka.** Ma pędzić jak gry z lat 80. - wynik zawsze
   widoczny, krótkie krzykliwe napisy, rytm zdarzeń - ale "w kompletnie
   nowym odkryciu": VR, fizyka, emergentne zachowania botów.

9. **Samodzielnie na goglach, wysoko zoptymalizowana - ale nie kosztem
   fizyki.** Gra działa na samym Queście 3 (bez PC). Optymalizujemy
   grafikę, liczbę obiektów, LOD, boty "na szynie" daleko od gracza,
   sterowanie botów i budowę toru - **fizyki auta gracza i botów
   blisko gracza nie upraszczamy** dla wydajności. Każda nowa funkcja
   ma pomiar kosztu (`Perf.add`, linie "PERF+" z Questa).
10. **Estetyka względnie realistyczna.** Realistyczne światło, materiały,
    skały, auta i drogi - bez kreskówki - na tyle, na ile pozwala Quest.
    Styl lat 80. żyje w rytmie gry i napisach, nie w grafice.
11. **Emocje stopniowane w czasie.** Doświadczenie ma być jak najbardziej
    ekscytujące i coraz trudniejsze: z odcinkiem rośnie liczba i agresja
    furiatów, trudniejsze taktyki i formacje, ciaśniejsze i szybsze
    trasy, mocniejsze auto z warsztatu - krzywa trudności bez końca, ze
    chwilami oddechu (autostrada, stacja, warsztat) między szczytami.

## Manekiny crash-testowe

- Każdy bot ma manekina za kierownicą (widoczny przez szyby). Ręce na
  kierownicy obracają się ze `steer`, głowa kiwa się z przeciążeniem -
  tanio (kilka kości / transformacji), a od razu widać "kierowcę".
- Przy mocnym zderzeniu manekin rzuca się w pasach; przy eksplozji
  może wylecieć (prosty ragdoll albo kilka brył - tylko jeden naraz,
  krótko, wydajność Questa).
- Wygląd **własny i ogólny**: żółto-czarne znaczniki pomiarowe
  (koła podzielone na ćwiartki) to ogólna konwencja, nie cudzy znak.
  Nie kopiować konkretnych postaci ani marek manekinów.
- Pomysły na rozwinięcie: manekin "ze złością" (pochylony nad kierownicą
  w szale), różne kolory/numery manekinów = osobowości botów, manekin
  wylatujący przy eksplozji jako krótka scenka (jak napis "+500 BOOM").

## Jak to się przekłada na system punktów

`scripts/score_keeper.gd`: pościgi (karta pościgu), mandat za uderzenie
spokojnego bota, ucieczka (zgubienie, uspokojenie, unik, **unik
zasadzki** z premią, wmanewrowanie, skok), walka (**obrażenia zadane**
proporcjonalnie do uszkodzeń bota, obrót, **eksplozja z premią**),
seria. `scripts/workshop_shop.gd`: cennik napraw i ulepszeń.
`scripts/stunt_tracker.gd`: sztuczki. Farmienie punktów jest dozwolone
(decyzja użytkownika).

## Otwarte kierunki

- Rozwidlenia dróg (nitki) - w tunelach i poza nimi; każda nitka może
  mieć inny typ drogi i inne ryzyko/nagrodę.
- Nowe taktyki furiatów (lustro, pułapka w zakręcie, sabotaż skoczni,
  tunel bez świateł, ruchoma ściana, puszka, naganianie, sztafeta),
  osobowości, wybór taktyki z oceną sytuacji zamiast losowania.
- Uszkodzenia botów wpływające na ich jazdę (dziś boty mają te same
  układy co gracz - do sprawdzenia, czy `BotDriver` reaguje na słabszy
  silnik i hamulce).
