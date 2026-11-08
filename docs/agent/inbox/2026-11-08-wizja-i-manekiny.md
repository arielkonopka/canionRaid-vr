# Wizja projektu (docs/VISION.md) + manekiny + 2 dodatki w ScoreKeeper

Status: nowe
Od: wątek w chmurze "Zaprojektuj nowe strategie botów road rage" (2026-11-08)
Decyzje użytkownika (2026-11-08, jego słowa w skrócie):
- Założenia projektu: drogowy "river raid", bezkresny, z rozdzielającymi
  się nitkami; zamiast samolotów i czołgów zdalnie sterowane albo
  zautomatyzowane auta-furiaci; odcinki losowe; kaskaderka, fizyczna
  wierność auta, patologiczne zachowania na drodze; droga urozmaicona
  (autostrada, wąwóz, tunel...); uszkodzenia gracza **i furiatów** wpływają
  na jazdę; warsztat naprawia za punkty z dwóch źródeł: ucieczka
  (**zwłaszcza przed zasadzkami**) i **uszkodzenia zadane** furiatom;
  **punkty ekstra za eksplozję** auta furiata.
- "Posadzić tam manekiny od testów zderzeniowych" - kierowcy furiatów.

## Co zrobiłem

1. `docs/VISION.md` - stała wizja projektu dla wszystkich agentów
   (filary, manekiny, przełożenie na punkty, otwarte kierunki). Proponuję
   odnośnik z `HANDOVER.md` i `CLAUDE.md` ("przeczytaj też VISION.md") -
   zostawiam Tobie, bo to Twoje pliki.
2. `ScoreKeeper` - dodatki **wstecznie zgodne** (nic w Twoim wpięciu się
   nie psuje):
   - `damage_dealt(id, d_structure, now, kmh)` - punkty za obrażenia
     zadane botowi (przyrost jego `damage["structure"]` po kontakcie
     z graczem), wypłata co 10%, 400 pkt bazy za 100%. Wywołuj
     z `_on_body_entered` bota (różnica `structure` przed/po - albo
     w następnym kroku, bo uszkodzenia liczą się w `_integrate_forces`).
   - `end_attack(..., tactic = "")` - przekaż `"ambush"` przy końcu
     zasadzki, wtedy unik to `ambush_dodge` (120 zamiast 40).
   - "wreck" zostaje jako premia za eksplozję (ponad obrażenia).
   - Testy dopisane w `tests/score_test.gd` (`_test_damage_and_ambush`).
     Nieuruchomione - proszę o uruchomienie.

## Manekiny - propozycja do Twojej oceny (wydajność Questa)

- Prosty manekin w każdym bocie: tułów, głowa, ręce na kierownicy
  (kilka MeshInstance3D, jeden wspólny materiał), ręce obracają się
  ze `steer`, głowa kiwa się z przyspieszeniem - bez szkieletu.
- W szale: pochylony do przodu (czytelny sygnał obok czerwonych świateł).
- Eksplozja: manekin wylatuje jako jedna bryła RigidBody na ~3 s (jeden
  naraz) - krótka scenka do napisu "ROZBITY".
- Wygląd ogólny: żółto-czarne znaczniki pomiarowe, bez kopiowania
  konkretnych postaci/marek.
- Boty na szynie (`LOD_FAR`) - manekin bez animacji albo ukryty.

## Pytanie

Czy `BotDriver` już odczuwa uszkodzenia (słabszy silnik, hamulce,
ściąganie)? Wizja chce, żeby uszkodzony furiat jeździł gorzej. Jeśli boty
mają te same układy co gracz, to pewnie działa samo - potwierdź.

## Odpowiedź agenta lokalnego

(puste)
