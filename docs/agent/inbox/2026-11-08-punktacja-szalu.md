# Specyfikacja: punkty za ucieczkę i walkę z botami w szale

Status: przyjęte
Od: wątek w chmurze "Zaprojektuj nowe strategie botów road rage" (2026-11-08)
Decyzje użytkownika:
- **ustalone**: ucieczka z ataków botów (sprytna jazda) **albo** ich
  odpieranie (walka) dają punkty do wydania w warsztacie - oba style mają
  pozwalać jechać dalej. Paliwo/prąd zostaje osobnym zasobem obok punktów.
- **ustalone**: punktacja musi być oceniana automatycznie i działać na
  Queście (tanio).
- **otwarte** (zapytaj użytkownika przed wdrożeniem):
  1. czy punkty zastępują obecne "-20 s za potrącenie bota" (`HIT_BONUS`
     w `xr_main.gd`), czy działają obok;
  2. czy pierwsze uderzenie spokojnego bota ma kosztować punkty (mandat);
  3. czy skrócić zasięg paliwa do ~10-15 km (propozycja z HANDOVER.md,
     "Do rozważenia z użytkownikiem").

To propozycja projektowa. Jeśli coś się kłóci z fizyką, wydajnością albo
ustaleniami z `HANDOVER.md`, ważniejsze są one - dopisz uwagę na końcu.

## Idea

Dwa równorzędne style: **uciekinier** i **wojownik**. Różnią się kosztem,
nie tylko nagrodą: walka daje więcej punktów, ale niszczy auto (naprawy
kosztują punkty) i pali paliwo; ucieczka daje mniej, ale jest tania.
Wybór w każdym pościgu ma być prawdziwy.

## Zdarzenia punktowane

Ucieczka:
- **ZGUBIONY** - bot w szale zostaje za graczem dalej niż `behind_max`
  (700 m) i znika (`_update_bots`, gałąź `gone` przy `rage > 0.05`).
- **USPOKOJONY** - szał wygasł (`rage` doszedł do 0), bo gracz jechał
  przepisowo, i w tym pościgu nie było trafienia bota w gracza.
- **UNIK** - koniec fazy ataku (pit/pincer: bot był w strefie "przód przy
  tylnym kole"; ram: dojazd z tyłu; ambush: wyjazd przed maskę; block:
  impuls hamowania) bez `body_entered` z graczem, przy najmniejszej
  odległości: |offset bota - offset gracza| < szerokość auta + 1,5 m
  i |ahead| < 4 m.
- **WMANEWROWANY** - bot w szale uderza w inne auto albo w ścianę
  (duża zmiana prędkości bez kontaktu z graczem) w ciągu ~2 s po uniku.
- **SKOK** - gracz przejeżdża skocznię, a bot w pościgu ląduje twardo albo
  rozbija się na niej.

Walka:
- **ROZBITY** - wybuch bota (gałąź `dead` w `_update_bots`), jeśli
  ostatni kontakt z graczem był najwyżej ~3 s wcześniej.
- **PIT GRACZA** - bot obraca się o > 90° od kierunku drogi w ciągu ~2 s
  po kontakcie z graczem bokiem tylnej części bota.
- **FORMACJA** - przy taktykach grupowych (pincer, przyszłe ściany)
  wyeliminowanie jednego z pary albo przejazd przez lukę.

Kary / ochrona przed farmieniem:
- Szał wywołany przez gracza uderzeniem spokojnego bota: propozycja -
  mandat (odejmuje punkty) i ten pościg punktów nie daje; punkty tylko za
  pościgi z posiłków (`call_reinforcements`) albo rozpoczęte przez bota
  (gdy takie dojdą). Do decyzji użytkownika (pyt. 2).
- Malejąca nagroda za kolejne pościgi w tym samym odcinku.

## Pomiar - tanio na Queście

Prawie wszystko już się liczy w `BotDriver._rage_plan`: `ahead`, `p_off`,
`offset`, `pk`; zderzenia łapie `_on_body_entered`. Nie dodawać nowych
zapytań do toru.

- **Karta pościgu** w `BotDriver` (tylko gdy `rage > 0.05`; boty spokojne
  i na szynie nic nie liczą): `origin` ("player_hit" / "reinforce" /
  "self"), `chase_t`, `attacks`, `dodges`, `hits_on_player`,
  `last_player_contact_t`, `min_gap`, `damage_dealt`, `damage_taken`.
- **Zdarzenia, nie ocena co klatkę**: punkty liczone tylko przy końcu fazy
  ataku, wygaśnięciu szału, zniknięciu i wybuchu bota. Kilkadziesiąt
  wywołań na minutę.
- Sprawdzanie uniku wystarczy ~10 Hz (licznik jak `_window_timer`).
- **Jeden `ScoreKeeper`** (np. w `xr_main.gd`): przyjmuje zdarzenia
  (`score_event(kind, bot, data)`), liczy
  `punkty = baza[kind] × niebezpieczeństwo × seria × malejąca_nagroda`,
  gdzie niebezpieczeństwo rośnie z czasem szału, liczbą botów w szale
  i prędkością; seria - kolejne zdarzenia w ciągu ~10-15 s.
- Wszystkie współczynniki w jednej tabeli w `GameSettings`, żeby stroić
  bez zmiany logiki.
- Nowa kategoria `Perf.add("punkty", ...)`, żeby w "PERF+" z Questa było
  widać koszt.
- Linia w logu przy każdym zdarzeniu: `SCORE: <kind> +<pkt> (chase_t,
  bots, kmh, combo)` - do strojenia po przejazdach na goglach.

Wyświetlanie (VR):
- Label3D przebudowuje siatkę przy każdej zmianie tekstu - napis z punktami
  aktualizować tylko przy zdarzeniu, nigdy co klatkę.
- Wyskakujące napisy ("+150 UNIK") z małej puli gotowych Label3D przy
  desce, bez tworzenia węzłów w trakcie jazdy.
- Część informacji dźwiękiem (krótki sygnał przy uniku) - wzrok gracza
  jest na drodze.

## Warsztat - na co wydawać (propozycja)

- Naprawa płatna strefami (silnik, hamulce, zawieszenie - zgodnie
  z obecnymi uszkodzeniami zależnymi od miejsca uderzenia). Główna
  dźwignia ekonomii.
- Próg mocy: płatny albo dalej darmowy, z opcją przeskoczenia progu za
  punkty.
- Wzmocnienia z realną fizyką: orurowanie przodu (lepsze taranowanie,
  większa masa, gorsze hamowanie), opony, spojler, większy bak/bateria.
- Dodatkowe auto (życie).
- Jawne, wyłączalne pomoce (zgodnie z CLAUDE.md), np. "radio CB":
  boty w szale i ich taktyka na mapce.

## Testy

- Nowy test headless w stylu `tests/bot_rage_test.gd` ze skryptowym
  graczem w trzech wariantach: (a) ucieka przepisowo, (b) robi uniki,
  (c) taranuje do wybuchu bota. Sprawdza, że każdy styl daje punkty
  w podobnym przedziale na km i że farmienie spokojnych aut się nie
  opłaca.
- Po zmianie: `tests/drive_test.gd` i `tests/bot_rage_test.gd` jak
  zwykle (CLAUDE.md), wynik do `HANDOVER.md`.

## Na później (powiązane)

Te same zdarzenia z odwróconym znakiem to ocena taktyk botów (unik
gracza = porażka taktyki, trafienie = sukces). Można z nich karmić wybór
taktyki zamiast losowania w "mixed" (utility AI, uczenie się, co działa
na danego gracza), a później nagrodę dla wyuczonej polityki. Pozostałe
pomysły na nowe taktyki (lustro, pułapka w zakręcie, sabotaż skoczni,
tunel bez świateł, ruchoma ściana, puszka, naganianie, sztafeta,
osobowości botów, celowanie w przewidywaną pozycję gracza) są w wątku -
użytkownik jeszcze nie wybrał kierunku.

## Odpowiedź agenta lokalnego

2026-11-08 - przyjęte do realizacji. Użytkownik rozstrzygnął otwarte
pytania:

1. **Punkty zastępują "-20 s za potrącenie bota"** (`HIT_BONUS` znika).
2. **Mandat**: pierwsze uderzenie spokojnego bota kosztuje punkty, a ten
   pościg punktów nie daje. Punkty dają pościgi z posiłków i z furii po
   wyprzedzeniu (nowe w tej sesji: bot czasem wpada w szał, gdy gracz go
   wyprzedzi, bez kontaktu - posiłki wzywa dopiero po kontakcie; opcja
   `rage_overtake`, domyślnie 25%) - to jest odpowiednik "rozpoczętych
   przez bota".
3. **Zasięg paliwa/prądu skrócony do ~10-15 km.**

Uwagi z mojej strony (wydajność na Queście, pomiary z logu):
- `BotDriver` już kosztuje ~45-90 ms/s przy kilku botach, więc karta
  pościgu i sprawdzanie uników tylko dla botów w szale i ~10 Hz -
  zgodnie ze specyfikacją; boty "po szynie" nic nie liczą.
- Napisy z punktami: pula gotowych Label3D, zmiana tylko przy zdarzeniu
  - zgadzam się (Label3D przebudowuje siatkę przy zmianie tekstu).
- Od tej sesji gra ma autostradę (co 5 odcinków, druga jezdnia z ruchem
  z naprzeciwka) - auta z naprzeciwka nie wchodzą w szał i nie dają
  punktów (kinematyczne, bez BotDriver).

Status zmienię na "w toku", gdy zacznę wdrażać; wynik w `HANDOVER.md`.
