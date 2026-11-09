# HANDOVER - Canion Raid VR

Dokument przekazania dla agenta, który nie pamięta wcześniejszych sesji.
Ma wystarczyć, żeby od razu kontynuować pracę. Zasady utrzymywania
dokumentu są w `CLAUDE.md`.

Ostatnia aktualizacja: 2026-11-09, sesja 5 (popołudnie: wytrzymałość, opływowość, moc z menu w trasie, diagnostyka wypadków, plan trybu Autostrada)

---

## 1. Czym jest projekt

**Nazwa gry: Canion Raid VR** (od 2026-11-08, prośba użytkownika; wcześniej
"Stunt Track VR" - tak nadal nazywają się katalog, repo lokalne, klasy
`StuntCar`/`StuntTrack` i identyfikator paczki `com.stunttrackvr.game`,
celowo bez zmian: inny identyfikator = druga aplikacja na goglach).

Kaskaderskie wyścigi VR na **Meta Quest 3** w Godocie 4. Tory zawieszone
wysoko na słupach, rampy, przerwy do przeskoczenia, wiraże z przechyłką,
różne nawierzchnie. Realistyczna fizyka auta z wyborem napędu i systemów
wspomagania. Gra jest **własna**, w klasycznym gatunku stunt racerów
z przełomu lat 80. i 90.

**Twarda zasada:** to nie jest port ani odtworzenie istniejącej gry.
Nie kopiujemy cudzych tras, nazw, wyglądu ani aut. Mechaniki gatunku są
dozwolone, a projekty tras i styl mają być nasze. Użytkownik to
zaakceptował ("możemy zrobić równie emocjonujące, własne").

Autor i właściciel: Ariel Konopka. Licencja GPL-3.0-or-later (`LICENSE`
zawiera tylko notę, pełny tekst trzeba dograć).

## 2. Użytkownik i ustalenia

- Komunikacja **po polsku**, luźno ("siemka"). Często dorzuca pomysły
  w trakcie pracy - zapisuj je od razu do kolejki (sekcja 8).
- **Korzystaj z tego, co jest w systemie.** Nie pobieraj narzędzi,
  wtyczek ani assetów bez zgody. Grafikę i dźwięk generuj w kodzie.
  Uwaga: na dysku jest więcej, niż widać w pakietach systemowych
  (sekcja 3) - najpierw szukaj w `~/opt` i w innych projektach w `~/dev`.
- **Fizyka auta ma być realistyczna** (wybór użytkownika zamiast arkady
  czy hybrydy). Bez ukrytych ułatwień. Pomoce dla gracza tylko jawne
  i wyłączalne (ABS, TCS, ESP, `steer_assist`).
- **Wszystko, co dotyczy auta, ma być konfigurowalne** na ekranie
  tytułowym (wprost: "wszystko to chciałbym konfigurowalne"), w podmenu
  (prośba). Teraz: Samochód (napęd, moc, skrzynia, zawieszenie), Systemy
  wspomagania (ABS, TCS, ESP), Sterowanie i widok (czułość drążka,
  przezroczystość kokpitu), Wygląd (lakier).
- **Pierwsza jazda na goglach (2026-11-07)**: "niezłe", ale (1) z kokpitu
  nie widać trasy - kokpit ma być lekko przezroczysty (zrobione,
  regulowane), (2) "dosyć trudno się jeździ" - dodany suwak czułości
  drążka i krzywa drążka. Dopytać, czy to wystarczy, czy potrzeba więcej
  pomocy (np. `steer_assist` w menu, łagodniejsze ustawienia domyślne).
  Potem: (3) "nie bardzo działa zakończenie poziomu" - dodana meta,
  zegar, wyniki, rekord; (4) w trybie lotu brak yaw/pitch - dodane.
- **Nasłuch skrzynki** (użytkownik: "wydziel wątek, który będzie
  nasłuchiwał tych wiadomości"): `tools/watch_inbox.sh [s]` - co 120 s
  `git fetch --all`, kończy się, gdy pojawi się nowy commit zmieniający
  `docs/agent/` na którejkolwiek gałęzi zdalnej. Agent uruchamia go
  w tle (`run_in_background`), po powiadomieniu czyta wiadomość, robi
  `git pull` i uruchamia nasłuch ponownie.
- **Wizja projektu**: `docs/VISION.md` (spisana przez wątek w chmurze ze
  słów użytkownika 2026-11-08): drogowy "river raid" w VR, furiaci
  z manekinami crash-testowymi za kierownicą, uszkodzenia wpływają na
  jazdę gracza i botów, punkty za ucieczkę (zwłaszcza przed zasadzkami),
  za uszkodzenia zadane i ekstra za eksplozję furiata.
- **Komunikacja z wątkami projektowymi w chmurze** (ustalone
  2026-11-08, użytkownik zatwierdził propozycję): `docs/agent/` -
  `inbox/` (zlecenia i specyfikacje z chmury, blok statusu: nowe /
  przyjęte / w toku / zrobione / odrzucone, odpowiedź agenta lokalnego na
  końcu pliku), `outbox/` (pomiary z Questa, wrażenia z jazdy, pytania).
  Skrzynkę sprawdzać na początku sesji i po każdym `git pull`; odbiór =
  zmiana statusu + commit. Wątki w chmurze nie zmieniają kodu ani
  HANDOVER.md (tylko `docs/agent/`, osobna gałąź + PR). Specyfikacje to
  propozycje - decyzje należą do użytkownika.
- **Punktacja wpięta w grę** (2026-11-08): `xr_main.score`
  (ScoreKeeper z chmury) zamiast "-20 s za potrącenie" (`HIT_BONUS`
  usunięty). Zdarzenia: `BotDriver.enrage(origin)` - "player_hit"
  (uderzenie spokojnego bota: mandat -100, pościg bez punktów),
  "reinforce" (posiłki), "overtake" (furia po wyprzedzeniu);
  `_on_body_entered` → `score_contact` + po 0,2 s `score_damage`
  (przyrost `damage["structure"]` bota); `_score_step` (10 Hz, tylko
  w szale): strefa ataku |ahead| < 6 m i odstęp boków < 3 m, wyjście ze
  strefy → `score_end_attack(hit, min_gap, taktyka)` (unik / unik
  zasadzki); szał wygasł → "calmed"; `_update_bots`: bot w szale znika
  za graczem → "lost", wybucha → "wreck". Wyświetlanie: "N pkt xS"
  w kolumnie przy mapce, pula 3 Label3D z napisami ("+150 UNIK x2", gasną
  w 1,6 s, tylko modulate), 8-bitowy sygnał (mandat - niższy).
  Linie "SCORE: ..." w logu do strojenia. Test `tests/score_play_test.gd`
  (w `./quest.sh test`). Jeszcze nie: sklep w warsztacie (WorkshopShop),
  StuntTracker, manekiny.
- **Plan gry z chmury** (`docs/agent/inbox/2026-11-08-plan-gry-podzial-pracy.md`,
  przyjęty): tryb ciągły "Furia" (unikanie albo walka z botami w szale,
  punkty na naprawy w warsztacie, styl gier zręcznościowych z lat 80.)
  i później tryb kaskaderski (pętle, beczki). Użytkownik: **farmienie
  punktów nie przeszkadza** (`diminish_k = 0`), mandat zostaje. Chmura
  pisze odizolowane pliki z czystą logiką (`scripts/score_keeper.gd` +
  `tests/score_test.gd` - lokalnie OK), agent lokalny wpina je w gorące
  pliki i sprawdza na Queście. Chmura może przeglądać i scalać PR-y.
- **Punktacja szału (specyfikacja z chmury,
  `docs/agent/inbox/2026-11-08-punktacja-szalu.md`, przyjęta, do
  wdrożenia)** - decyzje użytkownika: punkty **zastępują** "-20 s za
  potrącenie bota"; **mandat** za pierwsze uderzenie spokojnego bota
  i brak punktów za taki pościg; **zasięg paliwa/prądu ~10-15 km**
  (wcześniej 150 km - pytanie z sekcji 9 rozstrzygnięte).
- **Ustalenia z sesji 3 (2026-11-08):**
  - **Wąwóz to jedyny tryb gry.** Wybór trasy zniknął z menu; estakady
    i trasa pokazowa zostały w kodzie tylko dla testów. Ekran tytułowy
    też stoi w wąwozie (`TITLE_SEED` 2026).
  - **Nawierzchnie po kolorze**: sucha #404040, mokra #101010 (czarna),
    oblodzona #304070 (lekko niebieska) - kolory podał użytkownik.
    **Śliskie obszary długie**: strefy mokre 150-400 m, lód 100-250 m
    (wcześniej pojedyncze moduły).
  - **Mokro = pada**: nad strefą mokrą mżawka albo deszcz, wycieraczki
    włączają się same (mżawka: przerywany tryb, deszcz: ciągły).
    **W tunelach nie pada** (prośba wprost) - tunel jest suchy i bez opadu.
  - **Wskaźnik uszkodzeń jako LCD w prędkościomierzu** (osobna tabliczka
    na desce "wyglądała sztucznie"; "w stylu LCD").
  - **Menu startowe i warsztatowe podążają za wzrokiem** (pojawiały się
    za wysoko). Menu ma się trzymać wysokości oczu.
  - **Sterowanie: prawy drążek = kierownica, lewy drążek = biegi**
    (w górę wyżej, w dół niżej). Opcja "Kierownica" zamienia strony.
  - **Przyciski w jeździe (gogle)**: klik prawego drążka = nowe auto
    (strata życia), klik lewego = wolna kamera, A = ABS, B = ESP,
    X = TCS, Y krótko = ograniczenie skrętu (`steer_assist`, teraz też
    w menu "Systemy wspomagania"); "pozostałe przyciski zostają" -
    spusty, gripy, Menu, Y przytrzymany (centrowanie) bez zmian.
    W warsztacie i po mecie A zatwierdza. Tabela w README.
  - **Północne zbocza wąwozu zielone od mchu i bluszczu** (prośba).
    "Północ" = kierunek przeciwny do słońca (strona w cieniu), patrz
    sekcja 5.
  - **Czasem jedna ściana wąwozu jest niska i widać za nią ocean**:
    ~100 m na 5 km (użytkownik). Nie musi być geograficznie spójne
    ("nie musi się mieścić na jakiejkolwiek mapie"). Niski próg nie musi
    zatrzymywać auta - przeskoczenie = upadek, strata auta.
  - **Zielone tablice odcinków nie mogą wchodzić w ścianę** - teraz
    mniejsze (1,9 m) i na poboczu.
  - **Auto (sesja 3, cd.)**: moc do 700 kW ("nierealistyczna"), napęd na
    tył albo 4x4, elektryk z jednym silnikiem albo w każdym kole; **1000 kW
    (4 × 250) tylko dla silników w kołach** ("wariant 1": najmocniejszy
    sumarycznie; ma dawać wyższą prędkość maksymalną, nie musi lepszego
    przyspieszenia). Opony do wyboru (całoroczne domyślnie), masa
    950-2500 kg, spojler jako docisk.
  - **Szał drogowy konfigurowalny** w podmenu: przekraczanie przepisów,
    minimalny czas szału (aż do "nigdy nie mija" - użytkownik sam
    ustawiał w kodzie 500/1024 s), czas uspokajania, strategia:
    zajeżdżanie drogi z hamowaniem / stukanie w tył / na zmianę.
  - **Strategie szału wszystkie, domyślnie mieszane** (block, ram, pit,
    zigzag, ambush, pincer) + posiłki (szał zaraża boty w 400 m).
  - **Liczba aut**: 4 na start, +1 co 2 odcinki do 20, potem +1 co 100
    odcinków (`XrMain.bot_limit`).
  - **Zjazd do warsztatu był nie do znalezienia** - dodane znaki 300 m
    i 100 m przed zjazdem, znak ze strzałką na zjeździe i miniatura przy
    mapce 400 m przed.
  - **Tekstury z freepbr.com** (katalog `textures/`, dodany przez
    użytkownika): zielone części - mossy rock, ściany wąwozu - cavern
    walls, góry (nad tunelami) - ocean rock. **Nie wrzucać ich na GitHuba**
    (`.gitignore`), lokalne buildy je mają; bez nich proceduralny łupek.
    Licencja freepbr (wg użytkownika, 2026-11-08): darmowe pliki tylko do
    użytku niekomercyjnego; komercyjnie trzeba kupić Mega Pack; surowych
    plików nie wolno redystrybuować. Gdyby gra miała być sprzedawana -
    Mega Pack albo zamiana na tekstury CC0 (pobieranie tylko za zgodą
    użytkownika).
    **Decyzja użytkownika: gra całkowicie darmowa, bez żadnych zysków** -
    darmowa licencja freepbr wystarcza; tekstury dalej poza repo.
  - **Ekran tytułowy z jazdy** (użytkownik: "widok z jakiegoś bota"):
    auto jedzie samo wąwozem (BotDriver), **kamera goni je z tyłu**
    (z fotela na starcie bywał widok spod jezdni), **menu przypięte do
    kamery** (dziecko XRCamera3D, nieruchome w polu widzenia; użytkownik:
    "powinno być względem kamery"). Przypięte do kamery też skakało
    (prawdopodobnie niska płynność w goglach) - **ekran tytułowy jest
    statyczny** (użytkownik: "stopklatka, scena statyczna"): auto stoi
    zamrożone kołami na jezdni, kamera stoi za nim, menu nieruchome
    w świecie (dziecko stojącego XROrigin). Jazda w menu w kodzie za
    `TITLE_DRIVE` (false).
    **Menu 1 m przed oczami** (użytkownik: przy 2,6 m bywało daleko
    i słabo czytelne): `MENU_DISTANCE` 1, cały węzeł skalowany 1/2,6
    (układ napisów liczony na 2,6 m); ustawiane przed głową przez
    pierwsze 0,6 s (`_place_menu`, gdy gogle już śledzą), potem stoi.
  - **Sedan "najfajniejszy"** - domyślny model; concept do wyboru.
    Dynamika jazdy concept cara oceniona jako w porządku.
  - **Auto gracza ma mieć dach** - widoczny z kokpitu.
  - **Concept car** (Khronos "Car Concept", CC BY 4.0) jako model auta -
    w toku, patrz sekcja 8.
  - **Maksimum ostrości, jakie da sprzęt** (użytkownik): rozdzielczość
    domyślnie 160% (opcja 100-180%), foweacja w menu (domyślnie słaba),
    bez dynamicznej rozdzielczości Meta, anizotropia 16x - **na Queście
    ~8 kl./s i gogle "prawie się zagotowały"**. Foweacja średnia,
    anizotropia 4x. Użytkownikowi 160% podobało się wizualnie - cel:
    odzyskać je optymalizacjami. Prawdziwego "4K jak monitor" się nie
    da (~25 px/°). Od 2026-11-09 domyślnie 110% (uczciwy pomiar, sekcja 5).
  - **Zmiana rozdzielczości ma działać od razu, bez restartu aplikacji**
    (użytkownik, 2026-11-09) - działa, pod warunkiem wyłączonej
    dynamicznej rozdzielczości Meta (sekcja 3, pułapki).
  - **README ma opisywać obecną grę** (był jeszcze o torze na słupach).
  - **Autostrada zamiast wąwozu** (użytkownik, wybory z pytania): co
    kilka odcinków cały odcinek, wąwóz otwiera się i zamyka na jej
    końcach; druga jezdnia za barierą **z ruchem z naprzeciwka**;
    skocznie zostają + wiadukty nad drogą, limit 140.
  - **Furia po wyprzedzeniu**: czasem wyprzedzony (niepotrącony) bot
    wpada w szał, ale posiłki wzywa dopiero po kontakcie.
  - **Pasy na dwa auta obok siebie** - jezdnia 14,8 m na starcie.
  - **Tunele wiercone, przekrój koła**; przy rozwidleniu **dwie osobno
    wiercone nitki**, które za górą znów się łączą.
  - **Instalacja na goglach razem z użytkownikiem** - po przygotowaniu
    zmian poczekaj na niego, nie wgrywaj sam (prośba 2026-11-08).
  - **Dźwięk ma odwzorowywać otoczenie**: inaczej w wąwozie, w tunelu,
    w deszczu (pogłos, echo).
- **Trasa bez końca** (decyzje użytkownika): generowana odcinkami jak
  w River Raid (tylko mechanika jako odniesienie), **bez końca**,
  **trudność zależy od dystansu od startu** (nie od auta). Jezdnia
  **trzypasmowa (11 m) przynajmniej na początku**, potem się zwęża.
- **NOWA FORMUŁA (użytkownik, 2026-11-07, w trakcie realizacji):**
  "zmienimy też nieco gatunek gry":
  - **Boty** - czasem na drodze inne auta; **puste, zdalnie sterowane**
    (dlatego zderzenia nikomu nie szkodzą). Jeżdżą **zgodnie z zaleceniami
    prędkości** (znaki). **Uderzone wpadają w szał drogowy** (gonią,
    taranują); **uspokaja je tylko jazda gracza zgodnie z przepisami**.
  - **Zderzenia zgodnie z fizyką** (pełne auta-ciała sztywne, wgniecenia
    i uszkodzenia po obu stronach).
  - **Standardowe znaki drogowe** (ograniczenia prędkości, ostrzegawcze,
    prędkość zalecana) - definiują też "przepisy" dla botów i gracza.
  - **Wsteczny** (użytkownik): **grip na kontrolerze z gazem**, działa
    **dopiero po zatrzymaniu** (ochrona skrzyni). Ręczny zostaje pod
    gripem ręki z hamulcem (opcja "ręczny przy gazie" usunięta - kolizja).
    `car.dedicated_reverse` / `reverse_request`: w goglach bez
    "hamulec na postoju = wsteczny" i bez zamiany pedałów na R;
    klawiatura/pad po staremu. Test: `tests/reverse_test.gd`.
  - Ustawienia gracza na goglach zostają z poprzednich wersji - migracja
    `SETTINGS_VERSION` 2 przestawia stary wybór "endless" na wąwóz.
- **Znaki i boty - zrobione (2026-11-07, sesja 2, koniec):**
  - Każda próbka toru ma `limit` [km/h] (przechodzi na kolejne odcinki;
    w `end_state` też). Generator: prosta 100 (`LIMIT_OPEN`), łuk
    `curve_limit(R, przechyłka, grip)` z v² = gR(μ+tanβ)/(1-μ·tanβ),
    μ = 0,7·grip, w dół do 10, 40-100; garb - prędkość oderwania;
    rozbieg skoczni - prędkość ze znaku +10; warsztat 50.
  - Znaki wg polskich wzorów (`_road_sign`), **bez tabliczek z napisami**
    (użytkownik: napisy się nie mieszczą): B-33 ograniczenie przy każdym
    nowym limicie, **B-34 koniec ograniczenia** przy powrocie na otwartą
    drogę (zamiast nowego "100"), A-1/A-2 zakręt 45 m przed łukiem
    (`meta.curve_sign`), **A-23 stromy podjazd / A-22 zjazd z procentem**
    (`meta.grade` = tan(kąt)·100 - **100% to 45°**, nie 90°; użytkownik
    myślał, że 90° - wyjaśnione). Przed skocznią tylko B-33, za nią B-34.
    Znaki stoją pionowo także na przechylonej jezdni. Klucz `meta.sign`
    (rozbieg skoku) został - używają go dźwig i autopilot, nie rysowanie.
    Trójkąt z wierzchołków (`_sign_tri`) - CylinderMesh o 3 bokach dawał
    romb. Stare żółte/pomarańczowe tablice zastąpione.
  - **Boty** (`bot_driver.gd`, `BotDriver`; `StuntCar.is_bot`): pełne auta
    bez zegarów i dźwięku, 2 podkroki opon (`TIRE_SUBSTEPS` jest teraz
    zmienną), najwyżej 2 naraz (`MAX_BOTS`), pojawiają się 220-360 m przed
    graczem na prawym pasie co 10-25 s, znikają 250 m za nim; rozbity
    albo 3 s na dachu - wybuch. Spokój: prawy pas, limit z drogą hamowania
    i łuki (zmierzone: trzymają limit ±3 km/h). Szał: zderzenie z graczem
    (`get_colliding_bodies`, v_rel > 1,5 m/s) → celuje w gracza, do 1,4×
    limitu, przednie światła pulsują na czerwono (`set_rage_lights`);
    opada tylko, gdy gracz jedzie przepisowo (`player_compliant()`:
    prędkość ≤ limit + 5) - w ~6 s, **ale dopiero po 10 s pościgu**
    (`MIN_RAGE_TIME`; użytkownik zgłosił, że bot po uderzeniu nie gonił).
    Zderzenie łapie sygnał `body_entered` (odpytywanie kontaktów gubiło
    krótkie uderzenia). W szale bot jedzie tyle, ile trzeba, żeby dogonić
    (do 230 km/h), trąbi (klakson generowany w kodzie, 420+498 Hz),
    znika dopiero 700 m za graczem (spokojny - 250 m). Boty mają 250 kW
    (przy 130 kW nie nadążały). Wychodzenie z utknięcia: stoi z gazem
    > 1,2 s albo odwrócony > 100° → 1,6 s cofania z kołami skręconymi
    przeciwnie (automat: hamulec na postoju = wsteczny).
    Test: `tests/bot_rage_test.gd` (gracz najeżdża bota, 15 s za szybko,
    potem przepisowo). **Znany problem**: po mocnym zderzeniu bot czasem
    obraca się o 150°+ i wraca na drogę ~10 s albo wcale - gracz zdąży
    odjechać. Do poprawy: lepszy manewr (np. sterowanie według kierunku
    do drogi, nie tylko przeciwny skręt) albo dłuższy pościg.
  - **Znak ograniczenia** (B-33, miga przy przekroczeniu) - obok
    miniatury znaku ostrzegawczego przy mapce (`TrackHud.show_limit`);
    użytkownik kazał usunąć pole pod wskaźnikiem uszkodzeń (było tam
    wcześniej, `Gauges.set_limit` jest już bez działania).
  - Postęp (odcinek, km, czas, auta) to mała kolumna
    tuż przy prawej krawędzi mapki trasy, w jej skali (użytkownik: "obok
    HUD, stosownie wyskalowane").
  - **Wjazd do tunelu jak w górę** (użytkownik: płaska ściana wyglądała
    źle): nad tunelem masyw z łupku - przekroje co próbkę, grań do ~74 m,
    stok 45 m od wylotów (`RISE`); na wylotach betonowy portal (filary
    i belka, `_obox`) i ściana czołowa do 8,5 m.
  - **Odcinki oznaczone zielonym znakiem "miejscowości"** (E-17a)
    "ODCINEK n" (`_town_sign`) zamiast bramownicy + **8-bitowe
    ćwierknięcie** (`_make_chirp`: fala prostokątna H5-E6-H6 po 1/12 s =
    0,25 s, **2 razy** co 0,5 s, cicho -16 dB - użytkownik: "dwa, i
    ciszej") przy wjeździe na nowy odcinek. Ostre łuki: A-1/A-2 + **tablice kierujące U-3**
    co 12 m po zewnętrznej (`_chevron`, `meta.curve_len`).
  - **Koniec odcinka**: zielona tablica poprzedniego odcinka
    przekreślona czerwonym ukosem (jak E-18a), tuż przed nową
    (`_town_sign(..., crossed)`); użytkownik: "meta to zielony znak
    z przekreślonym aktualnym odcinkiem".
  - **A-15 śliska jezdnia** 30 m przed każdą strefą mokrą i lodem
    (zamiast osobnych oznaczeń); nawierzchnię widać po kolorze jezdni.
  - **Tunele** (`TrackGenerator._tunnel`, `StuntTrack._build_tunnel`,
    tylko wąwóz, częściej dalej: szansa 0,10 + 0,03/km do 0,30): 120-240 m,
    betonowe ściany i sklepienie 6 m z kolizją, **pas jarzeniówek na
    suficie** (prośba użytkownika; emisyjny pasek) + OmniLight co 40 m bez
    cieni, nad tunelem blok skalny do 34 m z czołowymi ścianami na wylotach.
  - **Rozwidlenie jak w River Raid** (`_split`, `_build_island`):
    jezdnia rozszerza się do 2·szer. + 5 m, skalna wyspa z ostrymi dziobami
    i kolizją rozdziela ją na dwie, potem znów jedna. Tor pozostaje jedną
    ścieżką (wyspa dzieli szeroką drogę) - to uproszczenie świadome;
    prawdziwe rozgałęzienie wymagałoby grafu tras.
  - **Pętle (> 150 km/h, użytkownik chce w trudniejszych poziomach,
    najlepiej w tunelach)** - **nie zrobione**: obecna rama toru (yaw +
    pitch) nie obsługuje pionu ani jazdy do góry nogami. Potrzebna rama
    obracana (np. rotation-minimizing frame / quaternion na próbce)
    i fizyka: na szczycie pętli v² ≥ g·R (z zapasem na przyczepność).
  - **Prześwity na łączeniach odcinków** (zgłoszone przez użytkownika):
    `sample_segments` dokłada próbkę końcową dokładnie w punkcie styku,
    ściany wąwozu też ją obejmują. Pierwszy kawałek zna `start_state.limit`
    - bez zbędnego znaku na łączeniu.
- **Ostatnie poprawki (2026-11-07, koniec sesji 2):**
  - **Potrącenie bota = -20 s od czasu** (nagroda - "musi kusić, by
    uderzać"), raz na zderzenie; ryzyko: bot w szale oszukuje - trąbi raz
    i dostaje silnik 350 kW, goni i taranuje (uszkodzenia → życie).
    (Najpierw błędnie zrobione jako +20 s - poprawione.)
  - **Bez oznaczeń mety na trasach bez końca** (bez szachownicy startu,
    bez przekreślonej tablicy końca odcinka) - tylko "ODCINEK n".
    Trasa pokazowa ma metę jak dotąd.
  - **Wirowanie po odrodzeniu** (nowe auto obijało się o części wraku -
    RigidBody z wybuchu - i traciło życie): części ignorują auta
    (`Explosion.ignore`, collision exception), auto staje 6 m dalej,
    3 s ochrony (`_grace_t`).
  - **Wirowanie po wybuchu - nadal zgłaszane** (wybuch po upadku z wysoka,
    auto całe czerwone). `tests/respawn_test.gd` (prosta, dach, rozbite
    po upadku z 15 m) **tego nie odtwarza** - auto po odrodzeniu stabilne.
    Hipoteza o wyspie na osi drogi obalona (kolizja wyspy to powierzchnia,
    nie wypycha). Wprowadzone zabezpieczenia: `_safe_pose` (prawy pas,
    zapytanie fizyki o wolne miejsce, do 8 prób co 8 m), zamrożone auto nie
    liczy fizyki (`if freeze: return` - siły na zamrożoną bryłę mogły się
    kumulować), 0,5 s stabilizacji po `place()` (`_settle_t`), czyszczenie
    kolejek uderzeń. **Jeśli dalej wiruje - zebrać `./quest.sh log`
    z gogli zaraz po zdarzeniu.**
  - **Wyjazd poza wąwóz** (pewna przyczyna "wirowania na zielonym placu"):
    w wąwozie jezdnia jest 2-25 m nad ziemią, więc reguła "spadł" (> 5 m
    pod jezdnią) się nie włączała i auto na trawie zostawało tam. Teraz
    poza trasą (> szer/2 + 15 m w bok albo > 6 m nad/pod jezdnią) przez
    1,5 s = utrata życia. Początek wąwozu zamknięty skalną ścianą za startem.
  - **Odrodzenie na początku bieżącego odcinka** (użytkownik), boty od nowa
    w tym samym rozkładzie (ziarno `_bot_rng` = numer odcinka; przy wjeździe
    na nowy odcinek też) - każda próba odcinka jak w River Raid
    (`_restart_section`, `_reset_bot_pattern`).
  - **Lusterko wsteczne** (`_build_mirror`): SubViewport 256×80 co drugą
    klatkę, kamera tuż za tylnym zderzakiem patrzy do tyłu, obraz na
    prostokącie u góry szyby z odbiciem lewo-prawo (uv1_scale -1).
- **Miniatury znaków ostrzegawczych** obok mapki trasy, pod kolumną
  postępu (`TrackHud.show_warning`, `xr_main._update_warning`): najbliższy
  zakręt / podjazd-zjazd z % / śliska jezdnia do 250 m przed autem.
- **Tunele dłuższe**: 300-800 m.
- **Użytkownik nie ma choroby lokomocyjnej** - można odpuścić
  ograniczenia komfortu VR (dynamiczna kamera, mniej "winietowania").
  Gra nie nakłada winiety; ciemną ramkę dają dach i słupki - winyl
  prześwituje 1,5× mocniej niż reszta kabiny (`_vinyl_mat`), domyślna
  przezroczystość kokpitu 60%. Do dopytania, jeśli chodziło o coś innego.
- **Paliwo i zjazdy (zrobione)**. Ustalenia: zasięg **~12 km** (od
  2026-11-08; wcześniej 150 km), **zjazd
  na stację co 5 odcinków** (pierwotnie "co 50 km" - zmienione), tankuje
  się **przejeżdżając powoli** pasem zjazdu; **warsztat też jako zjazd**
  ("wymaga zjechania tam"); **znak zjazdu co najmniej 800 m przed nim**.
  - `StuntCar.fuel` (0..1), `tank_kwh` 3,6 (≈12 km przy ~30 kW średnio;
    było 45 kWh / 150 km),
    zużycie z mocy oddawanej przez silnik + 1,5 kW wolnych obrotów
    (spalinowe); bez paliwa brak momentu. `refuel()`, `range_km()`.
  - Generator: `service` w sekcji (stacja: `index % 5 == 0`, warsztat:
    11., 21., ...), znak `meta.service_ahead` na początku sekcji, zjazd
    wstawiany po ≥ 820 m (`SERVICE_SIGN_DIST`; dopełnienie prostą).
    `_service`: 40 m poszerzenia o 8 m (limit 70), 110 m zjazdu
    (`meta.service`), 40 m powrotu.
  - Tor: `_build_service` → wysepka-krawężnik z kolizją (`_build_separator`,
    x = szer/2 + 0,7) + stacja (dystrybutory i ładowarki z kolizją za pasem,
    zadaszenie, napis) albo hala warsztatu. Znaki: niebieski "fuel"
    (dystrybutor) i "repair" (klucz). API `services(kind)`, `stations()`,
    `workshops()`, `EndlessTrack.next_station()`.
  - Gra: tankowanie w strefie zjazdu, na prawo od wysepki
    (`_lateral > lane_x`), < 35 km/h, pełny bak w ~8 s; warsztat, gdy auto
    stoi (< 8 km/h) w zatoce. Pusty bak i postój = utrata życia. Nowe auto,
    warsztat i nowa jazda = pełny bak. **Paliwo na wskaźniku w obrotomierzu**
    (użytkownik): łuk E-F w dolnej części tarczy, wskazówka, kontrolka
    rezerwy < 15% (miga < 5%) - `Gauges._build_fuel`/`set_fuel`; jednostki
    tarcz nad środkiem. W kolumnie postępu tylko "TANKOWANIE" i odległość
    do stacji; miniatura znaku ostrzegawczego 10,5 cm pod kolumną.
  - Test: `tests/service_test.gd` (ziarno 777: stacje odcinek 5/10/15,
    warsztat 11, znaki 860-1007 m przed zjazdem).
  - Zasięg skrócony (decyzja użytkownika 2026-11-08): przy 150 km paliwo
    nie miało znaczenia; teraz ominięcie dwóch stacji z rzędu = pusty bak.
- **Kierunek gry: dynamika jak w River Raid** - priorytet nad realizmem
  ruchu drogowego (przepisy są, ale gra ma pędzić).
- **NASTĘPNY DUŻY KROK - rozwidlenia tuneli z odnogami** (prośba
  użytkownika): w tunelu droga rozdziela się na dwie odnogi po ~1 km
  i łączy z powrotem. **Ustalone: obie odnogi kaskaderskie** (np. długo
  w górę, potem gwałtownie w dół, długi wyskok), **czasem z możliwością
  przeskoczenia z jednej odnogi na drugą**, a nawet **przejazdu po suficie
  tunelu z jednej na drugą przy odpowiedniej prędkości - możliwe tylko
  w najmocniejszej konfiguracji** ("gra ma być naprawdę dynamiczna").
  (Wcześniejsza interpretacja "jedna nudna z przepisami" była błędna.)
  Przejazd po suficie wymaga ramy toru obsługującej jazdę do góry nogami
  (jak pętle) - patrz niżej.
  Plan techniczny:
  - tor przestaje być jedną listą próbek: kawałek "rozwidlenie" ma dwie
    ścieżki próbek (A i B) między wspólnym początkiem i końcem;
  - B = A przesunięte w bok i w pionie funkcją równą 0 na obu końcach
    (np. sin² po długości) - łączenie w tym samym punkcie gwarantowane;
    dla wersji kaskaderskiej offset pionowy: długi podjazd, stromy zjazd,
    rampa;
  - EndlessTrack/StuntTrack: zapytania (nearest_sample, lateral_offset,
    samples_from) muszą wybierać ścieżkę, na której jest auto (najbliższa
    próbka z obu); HUD rysuje obie;
  - geometria: osobna siatka i kolizja dla B, tunel wokół obu, ściany
    rozdzielające.
- **STAN NAJNOWSZYCH USTALEŃ (zrobione i wgrane 2026-11-07):**
  - Wąwóz z łupku jest domyślną trasą ("Wąwóz"); estakady (dawny tor na
    filarach) i trasa pokazowa zostały jako opcje.
  - **Życia = auta** (ustalenie późniejsze niż "bez dźwigów"): życie
    traci się, gdy auto **skończy na dachu** (nie da się jechać), gdy jest
    **rozbite (uszkodzenia 100%)** albo (estakady) spadnie. **Każda utrata
    życia = eksplozja**, kamera odjeżdża i pokazuje wybuch, potem nowe auto
    na miejscu wypadku. Bez żyć - koniec jazdy.
  - Zegary jak w aucie (analogowe tarcze) i **wskaźnik uszkodzeń jako
    obrys auta** w kolorach: zielony ok, żółty średnio, czerwony
    krytycznie, czarny zniszczone.
  - **HUD trasy** nad kierownicą: mała, przezroczysta mapka 1,5 km.
  - **Podmenu konfiguracji sterowania.**
- **KIERUNEK (ustalenia z wcześniejszej rozmowy - historia decyzji):**
  - Dźwigi są "nienaturalne" - **znikają**. Gra toczy się w **ciasnym
    wąwozie**; wyjazd poza drogę (uderzenie w ściany, twarde lądowania)
    **uszkadza auto**. Uszkodzenia **zależne od miejsca uderzenia**:
    przód → silnik/chłodnica (mniej mocy), okolice kół → hamulce
    i zawieszenie (słabsze hamowanie, ściąganie), twarde lądowanie →
    zawieszenie i skrzynia. Kontrolki uszkodzeń na desce. **Koniec jazdy,
    gdy auto rozbite (100%)**; warsztat naprawia.
  - Skała ścian: **łupek** (pomysł użytkownika) - cienkie poziome warstwy
    z osadów spokojnego morza, łupią się na płaskie płyty: shader
    w poziome pasy, geometria ze schodkowymi półkami.
  - **Przerwy w jezdni nie mają sensu w wąwozie** (użytkownik, później
    niż wybór "rozpadliny"): na dnie ciągła droga, skoki jako skocznie
    (rampa, stół, zeskok - za wolno/za szybko = twarde lądowanie).
    Przerwy tylko na **konstrukcjach nad ziemią: na palach, w pętlach,
    beczkach**. Plan: estakady na palach z przerwami nad dnem wąwozu
    (spadnięcie = ląduje się na dnie, uszkodzenia, jazda dalej dołem),
    potem pętle i beczki (wymagają nowej ramy toru - obecna yaw/pitch
    nie obsługuje pionu i jazdy do góry nogami).
  - Auto na dachu: zamiast dźwigu "postaw na koła" w miejscu.
  - Sterowanie (potwierdzone): gaz prawy spust, hamulec lewy spust,
    ręczny lewy grip; teraz konfigurowalne w podmenu "Sterowanie".
- **Warsztat co 10 odcinków** (prośba, zrobiony - sekcja 5): zmiana
  napędu; pierwsze 10 odcinków słabszy silnik, potem mocniejszy, potem
  z większym momentem itd. Trudność trasy jest pod to strojona.
- **Auto z zewnątrz: sedan z lat 70.** (prośba użytkownika). Ogólny styl
  epoki, nie konkretny model.
- **Wytrzymałość auta** (użytkownik 2026-11-09: "to gra, gdzie człowiek
  ma się przekonać, jak niebezpieczna jest szybka jazda, ale auto
  powinno trochę więcej znieść"): opcja menu "Wytrzymałość" x1 (realna,
  domyślna), x2, x3, x5, x10 - dzieli uszkodzenia mechaniczne (silnik,
  skrzynia, hamulce, zawieszenie, struktura) z uderzeń i lądowań.
  Wgniecenia blachy celowo bez zmian (widać, jak groźne było uderzenie).
  Boty zawsze x1.
- **Opływowość nadwozia** (użytkownik 2026-11-09: "130 kW ledwo ponad
  150", "w najwyższej opcji naprawdę ponad 300 km/h", "dodatkowy czynnik
  oporu powietrza"): opcja menu "Opływowość" (`StuntCar.AERO`,
  `set_aero`): sedan z epoki Cd 0,36 × 2,1 m² (domyślnie), współczesna
  0,29 × 2,0, sportowa 0,30 × 1,85, rekordowa 0,22 × 1,75. Pomiar
  (`tests/topspeed_test.gd`, jazda w -Z): 130 kW 213/229/232/264 km/h;
  350 kW ~282 wszędzie (ogranicza 6. bieg na odcince); 700 kW
  378/393/393/398 km/h, 0-300 17-19 s.
- **HUD z mapką na prawo od kierownicy** (użytkownik do chmury, PR #29):
  panel `HudPanel` w `seat + HUD_FROM_EYES`, nie zasłania zegarów.
- **TRYB AUTOSTRADA (ustalony 2026-11-09, do zrobienia - sekcja 8)**:
  - **Nowy tryb obok wąwozu** (wybór trasy w menu; wąwóz zostaje).
  - Autostrada **na całej długości**, **2 pasy w każdą stronę**, dwie
    jezdnie za barierą, na drugiej ruch z naprzeciwka.
  - Sceneria zmienia się **co 50 km ± losowo 10 km**: wąwóz, góry,
    nad morzem, równiny (pola, łąki, pustynia).
  - **Miasta**: co 25 km małe (jedzie się przez ~1 km), co 100 km duże
    (~5 km). Droga przechodzi w **ulicę w zabudowie** (ta sama droga,
    domy, chodniki), **strefa 30 km/h**. Wokół miasta zawsze **3-5 aut
    na kilometr**; te, które nie są w furii, mogą znikać do 5 km od
    miasta, **tylko gdy gracz ich nie widzi**.
  - **Skocznie rzadko, jako atrakcja** (objazd ze skocznią / rampa obok
    drogi, którą można ominąć) - głównie zwykła jazda.
  - **Słupki kilometrowe przy drodze** (użytkownik zauważył, że ich nie
    ma, a pomagają ocenić prędkość).
- **Klucze API Jamendo** (użytkownik 2026-11-09, "będzie potrzebne
  później" - stacja radia z Jamendo): `~/.config/canion-raid/jamendo.env`
  (`JAMENDO_CLIENT_ID`, `JAMENDO_CLIENT_SECRET`, chmod 600). **Nigdy do
  gita** ani do plików w repo; skrypty mają je czytać z tego pliku.
- **Docelowy sprzęt: Meta Quest 3.** Wszystko (dźwięk, grafika) musi
  być rozsądne wydajnościowo na Queście.
- **Repozytorium git** (od 2026-11-08, prośba użytkownika):
  `git@github.com:arielkonopka/canionRaid-vr.git`, gałąź `main`, klucze
  SSH są w GitHubie. Commituj i wypychaj tylko na prośbę użytkownika
  (albo gdy wprost poprosi o regularne wypychanie). Licencja GPL-3.0
  (pełny tekst w `LICENSE` z GitHuba), wtyczka OpenXR Vendors w `addons/`
  (MIT, ~82 MB binarek) jest w repo, żeby klon się budował; `build/`
  i `android/` są w `.gitignore`.

## 3. Środowisko (sprawdzone 2026-11-07)

| co | stan |
|---|---|
| Godot | `/usr/bin/godot`, 4.6.3 (pakiet Debiana). Jolt jest domyślną fizyką. |
| Szablony eksportu | `~/.local/share/godot/export_templates/4.6.3.stable/` (Android) |
| Android SDK | **`~/opt/android-sdk`**: build-tools 36.1.0, platforms android-36, ndk, platform-tools, cmdline-tools. Ścieżka wpisana w ustawieniach edytora. |
| JDK do Androida | **`~/opt/jdk17`** (Temurin 17), wpisany w ustawieniach edytora. Systemowy OpenJDK 21 jest osobno. |
| Debug keystore | `~/.local/share/godot/keystores/debug.keystore` (hasło `android`), w ustawieniach edytora |
| Gradle | cache w `~/.gradle` (Gradle 8.11.1 i zależności) - build działa offline |
| Wtyczka OpenXR Vendors | `addons/godotopenxrvendors` 5.1.0, skopiowana z `~/dev/asteroids-vr` (kopia źródłowa też w `~/opt/_dl/vx/asset`) |
| adb | `/usr/bin/adb` i `~/opt/android-sdk/platform-tools/adb` |
| OpenXR na PC | tylko loader, **brak runtime'u**. Na PC gra zawsze działa na płasko. |
| Dane gry na PC | `~/.local/share/godot/app_userdata/Canion Raid VR/settings.cfg` |
| Ustawienia edytora | `~/.config/godot/editor_settings-4.6.tres` (ścieżki `export/android/*`) |

Projekt-wzór: **`~/dev/asteroids-vr`** - inny projekt użytkownika na
Questa 3 w Godocie 4.6, z działającym eksportem. Stamtąd pochodzą
wtyczka, `openxr_action_map.tres` i układ skryptu budowania (`quest.sh`).

- **adb przez Wi-Fi** (od 2026-11-08, użytkownik chciał bez kabla):
  `./quest.sh wifi` raz z kablem - czyta IP gogli (`wlan0`), `adb tcpip
  5555`, łączy (kilka prób, adb w goglach się restartuje), zapisuje adres
  w `build/.quest_wifi`. Potem `wait_device` sam robi `adb connect`
  i wybiera urządzenie przez `ANDROID_SERIAL` (kabel i Wi-Fi to te same
  gogle widziane dwa razy). Ważne do restartu gogli - potem znowu `wifi`
  z kablem. Gogle: 192.168.2.192 (sieć domowa użytkownika). Log w tle:
  `adb -s 192.168.2.192:5555 logcat -v time godot:V '*:S'`.
- **Pułapka: serwer adb na PC sam się wyłączał** ("daemon not running")
  - zabijał go eksport Godota (`shutdown_adb_on_exit`, wyłączone
  2026-11-09, sekcja pułapek). Jeśli wróci, gogle często wracają do
  "unauthorized" - użytkownik musi znów zatwierdzić debugowanie
  w goglach. Zbieranie logu w tle przerywa się wtedy z kodem 255.

### Pułapki środowiska i silnika (objaw → przyczyna)

- **Opcja rozdzielczości w menu nic nie zmienia / "działa dopiero po
  restarcie", a VrApi pokazuje `SF=0.50`** → dynamiczna rozdzielczość
  Meta (wtyczka vendors) nadpisuje mnożnik. Wyłączona w `project.godot`
  (`openxr/extensions/meta/dynamic_resolution=false`). Nie włączaj -
  fałszuje też pomiary wydajności.
- **Skały kosztują pół klatki GPU** → tekstury z `textures/` miały import
  `compress/mode=0` (bez kompresji VRAM) i `mipmaps/generate=false`;
  auto-wykrywanie "3D" działa tylko w edytorze, którego nie otwieramy.
  Teraz `compress/mode=2`, mipmapy, mapy normalnych z
  `compress/normal_map=1` (tylko RG - `rock.gdshader` odtwarza Z
  w `nrm_tap`). Pliki `.import` w `textures/` są lokalne (katalog poza
  repo) - po ponownym rozpakowaniu tekstur ustaw to od nowa. Każdą nową
  teksturę 3D importuj z kompresją VRAM i mipmapami.
- **Demon adb pada po każdym `./quest.sh build`, gogle wracają do
  "unauthorized"** → eksport Godota na Androida woła przy wyjściu
  `adb kill-server`. Wyłączone w ustawieniach edytora:
  `export/android/shutdown_adb_on_exit = false`
  (`~/.config/godot/editor_settings-4.6.tres`). Po tej zmianie adb
  przeżywa build.
- **Gra na goglach w ogóle nie startuje (pomiar daje GPU 0 ms), logcat:
  "TrackingService: Notifying idle due to no 6dof tracking"** → gogle
  leżą w ciemnym pokoju, bez śledzenia aplikacja VR nie rusza. Pomiary
  tylko przy zapalonym świetle.

- **Godot z CLI "nic nie wypisuje" i wisi** → bez runtime'u OpenXR
  zawiesza się przy wyjściu, a zabicie procesu gubi buforowane wyjście.
  **Zawsze** uruchamiaj z `--xr-mode off` i `</dev/null`. Bez
  `/dev/null` błąd skryptu może wpuścić Godota w interaktywny debugger.
  Wyjątek: eksport w `quest.sh build` (XR jest tam potrzebny do eksportu
  ustawień, a proces kończy się sam).
- **Użytkownik widzi okienko o OpenXR** → alert startowy. Wyłączony przez
  `xr/openxr/startup_alert=false`. Nie przywracaj.
- **Auto przelatuje przez jezdnię** → odwrotny winding trójkątów. W Godocie
  przednia ściana jest nawinięta **zgodnie z ruchem wskazówek zegara**,
  zarówno przy renderowaniu, jak i w kolizji `ConcavePolygonShape3D`.
- **Obciążenie kół skacze 0 ↔ 7000 N przy stałym kontakcie** → szum ułamka
  z `cast_motion`, różniczkowany przez tłumik przy 240 Hz. Rozwiązane:
  ugięcie liczone analitycznie z punktu i normalnej styku (`_probe_wheel`).
- **W teście `-s` ustawienia auta są nadpisywane** → `_ready` sceny
  głównej odpala się po kodzie testu i stosuje `GameSettings`. Testy
  ustawiają `GameSettings` albo zmieniają auto dopiero w pierwszej
  klatce fizyki.
- **Testy mogą zostawić wybór i rekord w ustawieniach gracza** → testy
  ustawiają `GameSettings.persist = false` (wtedy `save_settings()` nic
  nie zapisuje). Pilnuj tego w nowych testach.
- **Zmiana znaczenia lub domyślnej wartości opcji nie dociera do gracza**
  → zapisany wybór w `settings.cfg` wygrywa z nowym domyślnym (tak gogle
  dalej jeździły na estakadach po zmianie domyślnej trasy na wąwóz).
  Przy takiej zmianie podbij `GameSettings.SETTINGS_VERSION` i dopisz
  migrację w `load_settings()`.
- **`./quest.sh test` urywa się po pierwszym teście** → `grep` bez
  dopasowania + `set -o pipefail`. Poprawione (`|| true`); przy zmianie
  wyjścia testu popraw wzorzec w `run_test`.
- **Zmienna bez typu psuje `:=`** → `var track` (StuntTrack albo
  EndlessTrack) nie ma typu, więc `var x := track.coś()` to błąd
  kompilacji ("Cannot infer the type"). Pisz typ jawnie.
- **`--import` nie wyłapuje błędów kompilacji skryptów sceny** → APK
  zbudowałby się z niedziałającą grą. `quest.sh` sprawdza każdy skrypt
  `--check-only`; ten tryb nie zna autoloadów ("Identifier not found:
  GameSettings" - odfiltrowane).
- **Gogle wracają do "unauthorized"** (użytkownik: zakładanie gogli przy
  każdym wgrywaniu jest uciążliwe) → brakowało `~/.android/adbkey.pub`
  (był tylko klucz prywatny), więc zgoda "Zawsze zezwalaj" mogła się nie
  utrwalać. Odtworzone: `adb pubkey ~/.android/adbkey > ~/.android/adbkey.pub`
  (ten sam klucz). Do tego Android unieważnia zgody ADB po 7 dniach -
  wyłączone: `adb shell settings put global adb_allowed_connection_time 0`
  (zrobione na goglach użytkownika; `./quest.sh awake` też to ustawia).
  Uśpione gogle (zdjęte z głowy) nie pokażą okna zgody -
  `./quest.sh awake` wymusza czujnik "na głowie"
  (`com.oculus.vrpowermanager.prox_close`), `./quest.sh sleep` przywraca.
- W `-s` autoloady **są** dostępne (`root.get_node("GameSettings")`).
- `var x := {...}[klucz]` się nie parsuje (brak typu) - pisz `var x: float = ...`.
- Nazwy zmiennych `str`, `tr`, `name`, `scale` zasłaniają wbudowane
  funkcje lub właściwości. Nie używaj ich.
- **Wszystko, co skierowane w górę, jest ciemnoniebieskie** → słońce
  świeciło od dołu. W `.tscn` `Transform3D(...)` to **wiersze** bazy, nie
  kolumny; szkielet miał je pomylone. Naprawione w obu scenach (światło
  w dół pod 50°). Przy ręcznym wpisywaniu transformacji licz bazę
  w Pythonie i zapisuj wiersze.
- **Zrzut ekranu pokazuje poprzednie ujęcie** → tekstura viewportu ma
  kilka klatek opóźnienia; `tests/screenshot.gd` trzyma ujęcie 10 klatek.
- **Gogle przeskakują między "brak urządzenia" a "unauthorized", okno
  zgody na debugowanie USB znika** → dwie wersje adb: `/usr/bin/adb` (34,
  Debian) i `~/opt/android-sdk/platform-tools/adb` (37). Każda zabija
  serwer drugiej. Używaj **tylko adb z SDK** (`quest.sh` tak robi);
  w razie kłopotów: `~/opt/android-sdk/platform-tools/adb kill-server`
  i ponownie `./quest.sh install`.
- **Auto po upadku na ziemię leży na podwoziu, koła nie mają kontaktu**:
  punkty mocowania kół wchodzą pod `WorldBoundaryShape3D` i sfera koła
  startuje wewnątrz kształtu. Nieszkodliwe, bo dźwig i tak podnosi auto.
  Do naprawy, jeśli kiedyś będzie jazda po ziemi.

## 4. Struktura plików

| plik | rola |
|---|---|
| `project.godot` | scena startowa `title.tscn`, autoload `GameSettings`, 240 Hz fizyki, renderer mobile, MSAA 4x, ETC2/ASTC, OpenXR (`reference_space=0` - local, na siedząco) |
| `export_presets.cfg` | preset **"Quest"**: Android arm64, gradle, Meta plugin, tylko Quest 3, pakiet `com.stunttrackvr.game`, wyklucza `tests/*` |
| `quest.sh` | **jedno polecenie na wszystko**: testy, build APK, wgranie na gogle, start, logi (`./quest.sh help`) |
| `icon.svg` | ikona aplikacji (własna: tor na słupach, auto nad przerwą) |
| `openxr_action_map.tres` | domyślna mapa akcji OpenXR (nazwy akcji używane w kodzie: trigger, grip, primary, ax_button, by_button, menu_button, primary_click, trigger_click) |
| `addons/godotopenxrvendors/` | loader OpenXR dla Mety (82 MB) |
| `scenes/title.tscn` + `scripts/title.gd` | ekran tytułowy: menu Label3D budowane z `GameSettings.OPTIONS` |
| `scenes/main.tscn` + `scripts/xr_main.gd` | jazda: wejście, kamery, tryb lotu, dźwig, przełączanie TCS w trakcie jazdy |
| `scripts/game_settings.gd` | autoload: opcje (OPTIONS), zapis/odczyt, `apply_to_car()`, `enable_xr()` |
| `scripts/stunt_car.gd` | `StuntCar`: fizyka, napędy (`ENGINE_TYPES`), zawieszenia (`SUSPENSION_PRESETS`), ABS/TCS/ESP, geometria auta |
| `scripts/stunt_track.gd` | `StuntTrack`: generator toru, nawierzchnie (`SURFACES`), siatka, kolizja, API |
| `tests/*.gd` | testy headless i zrzuty ekranu, sekcja 6 |

## 5. Jak to działa

### Tor (`stunt_track.gd`)
- Lista odcinków `{len, curve, pitch, bank, width, gap, surface}`
  całkowana do próbek co `sample_step` m. Kierunek z yaw i pitch, nie
  z ramy Freneta. `pitch`, `bank` i `width` interpolowane smoothstepem;
  `surface` nie przechodzi na następny odcinek (domyślnie `dry`).
- **Znak bank:** dodatni = prawa krawędź niżej, czyli przechyłka do
  środka zakrętu w prawo (`curve > 0`).
- **Nawierzchnie** (`SURFACES`): dry 1,0, wet 0,7, ice 0,12 - mnożnik
  tarcia opony. Każda nawierzchnia to osobne `StaticBody3D` z metadanymi
  `grip` i `surface` (sucha nazywa się `TrackBody`, pozostałe
  `TrackBody_wet` / `TrackBody_ice`) oraz osobna powierzchnia siatki
  z materiałem: `road.gdshader` z uniformem `asphalt` ustawianym
  w `_surface_material` (#404040 / #101010 / #304070), mokra i lód
  różnią się też połyskiem (roughness).
- **Tunele wiercone** (`_build_tunnel`, `_tunnel_arc`, `_tunnel_facade`,
  `TUNNEL_YC` 0,35, `TUNNEL_SEG` 24): rura o przekroju koła, środek
  0,35·R nad jezdnią, okrąg przecina poziom jezdni tuż za krawędziami
  (R ≈ 9,2 m przy 14,8 m jezdni, szczyt ~12,4 m). Ściana czołowa: każdy
  odcinek łuku łączony z brzegiem prostokąta w tym samym kierunku od
  środka koła + trójkąty w narożnikach; betonowy pierścień. **Pułapka**:
  kierunek jazdy z prawego wektora to `UP.cross(r)`, nie `r.cross(UP)` -
  przy odwrotnym ściana czołowa patrzyła do środka tunelu i z zewnątrz
  jej nie było (niebo wokół rury, góra "wisiała").
  **Dwie nitki** (`TrackGenerator._tunnel`, szansa 0,4, meta `twin`):
  45 m rozszerzenia jak w rozwidleniu (wyspa `ISLAND_W` przez całą
  długość), dwie rury nad połowami jezdni, wspólna ściana czołowa (każda
  rura domyka ją do osi między nitkami), 45 m zwężenia za górą.
- **Autostrada** (`TrackGenerator.is_highway`: odcinki 3, 8, 13, ...
  (`HIGHWAY_EVERY` 5, `HIGHWAY_PHASE` 3) - nie trafia na stację ani
  warsztat; `_highway_section`): wjazd z meta `highway`, zejście do
  `HIGHWAY_HEIGHT` 4 m nad terenem (`_highway_level`, rampy ≤4°), znak
  `road_sign: "highway"`, 5 modułów (łuki r 350-600 z małą przechyłką,
  garby 2-3°, długie proste; jedna skocznia ze stołem), meta `overpass`
  → wiadukt; na końcu "highway_end" i podjazd na 8 m. **Uwaga**: klucz
  `meta.sign` to napis z prędkością przed skocznią (czyta go autopilot
  testowy i mapka) - znaki drogowe z generatora mają `road_sign`
  (wcześniej kolizja nazw: błąd `v_sign` w endless_test). EndlessTrack:
  `chunk.highway`, `chunk.canyon = false` dla autostrady,
  `section_index`. `StuntTrack._build_highway`: druga jezdnia = próbki
  przesunięte w lewo o szerokość + `HIGHWAY_MEDIAN` 3 m (ta sama siatka
  `_build_mesh` z podmienionymi `_samples`, kolizja), bariera New Jersey
  0,85 m, trawa w pasie rozdziału, bariery energochłonne, nasyp 1:2 do
  y = 0 (`_grass_material` = ground.gdshader); `_build_overpass` - pomost
  6,5 m nad jezdnią + filary + przyczółki, z kolizją. Wąwóz przy styku
  z autostradą: `_open_factor` (150 m) - ściany do progu, płaskowyż do
  terenu (jak okno na morze, tylko do y -0,5). Znaki "highway" /
  "highway_end" w `_road_sign`. Ruch z naprzeciwka (`xr_main`,
  `_update_oncoming`): do 4 aut na drugiej jezdni, kinematyczne
  (`FREEZE_MODE_KINEMATIC`), 110-140 km/h, tylko na odcinkach autostrady.
  `endless_test ... canyon`: przejeżdża autostradę (3. odcinek) bez
  upadku. Po przeglądzie PR #7 (chmura): pobocza i pas rozdziału mają
  kolizję (bez niej auto zepchnięte ~0,5 m za krawędź spadało pod nasyp;
  test `tests/highway_test.gd`), auta z naprzeciwka z puli
  (`_oncoming_pool`), koła do przodu, wysokość 0,41 + promień; wiadukt
  jedną siatką i jednym ciałem; `EndlessTrack.is_highway_at`. Znane: przy wyjeździe z autostrady początek wąwozu widać jako
  płaskie "półki" płaskowyżu.
- **Furia po wyprzedzeniu** (`BotDriver._check_overtake`, opcja
  `rage_overtake` 0/10/25/50%, domyślnie 25): gracz przechodzi z tyłu
  na przód bota (< 6 m w poprzek, szybszy) → losowo `enrage()` bez
  posiłków; posiłki przy pierwszym kontakcie (`_reinforced`).
- **Szerokość jezdni**: `difficulty().width` = 14,8 - 0,5/km, min. 10 m
  (3 pasy po ~4,6 m); start `EndlessTrack` 14,8. Linie i koleiny
  w `road.gdshader` liczą się z szerokości.
- **Boty: liczba i "szyna"** (`xr_main.bot_limit`, `BotDriver._update_rail`):
  limit z numeru odcinka, nowe auta co 2-6 s, 220-900 m przed graczem,
  prawy albo środkowy pas. Bot bez szału dalej niż `LOD_FAR` 380 m od
  gracza jest zamrożony i przesuwany po torze z prędkością przepisową
  (30 Hz, `_rail_acc`), bliżej niż `LOD_NEAR` 320 m wraca fizyka. Pomiar
  na PC (headless, takt 240 Hz = 4,17 ms): 20 botów (16 na szynie) 4,15 ms
  na krok; bez ograniczenia szyny do 30 Hz było 4,8 ms (nie nadążał) -
  szukanie na trasie (`samples_from`, `transform_at_distance`) jest
  drogie. Na Queście nie mierzone.
- **Szał drogowy** (`bot_driver.gd`, grupa menu "rage"): parametry
  z `GameSettings` w `_ready` (`rage_overspeed` 0 = bez limitu,
  `rage_time` -1 = nigdy nie mija, `rage_calm`, `rage_strategy`).
  `_rage_plan`, taktyki `TACTICS`: "pit" - pas obok, przód przy tylnym
  kole gracza i skręt w jego bok; "zigzag" - przed graczem sinus przez
  całą szerokość; "ambush" - wyprzedza z zapasem (+45), staje na
  poboczu 28-60 m przed graczem i wyjeżdża mu przed maskę; "pincer" -
  dwa boty w szale (`main.rage_partner`) po obu bokach ściskają (bez
  partnera = pit); "mixed" losuje co 8-14 s. Posiłki:
  `main.call_reinforcements` → `BotDriver.enrage()` (klakson, silnik).
  "ram" - za graczem dojazd +18/+35 km/h na jego tor,
  przed nim zwalnia i schodzi z linii; "block" - wyprzedza sąsiednim
  pasem (+30), wjeżdża przed gracza i co 3-5 s hamuje 1,2 s
  (`_brake_pulse`); "mixed" - zmiana co 8-14 s. Limit szału =
  ograniczenie + przekroczenie, łuki zawsze (`_curve_speed`). Bot w szale
  dostaje max(350 kW, moc gracza).
- **Rozdzielczość i foweacja** (`GameSettings.apply_xr_quality`, opcja
  `xr_resolution`, domyślnie **110%**): `OpenXRInterface.
  render_target_size_multiplier` ustawiany z kodu **działa od razu**
  (log gogli: `OpenXR_GPUMemTrace: Swapchain creation, width: 2688`
  zaraz po zmianie; VrApi `SF=` śledzi opcję w ciągu ~1 s). Warunek:
  `openxr/extensions/meta/dynamic_resolution=false` w `project.godot`
  (ustawienie wtyczki godotopenxrvendors, rozszerzenie
  `XR_META_recommended_layer_resolution`). Z nim gogle same wybierały
  rozmiar obrazu (`SF=0.50` przy opcji 160%) - opcja z menu nie działała,
  użytkownik widział zmianę "dopiero po restarcie", a wszystkie pomiary
  wydajności sprzed 2026-11-09 były zawyżone (gogle rysowały w połowie
  rozdzielczości). Uczciwe pomiary (S1, po kompresji tekstur): 100% -
  GPU 10 ms, 72 kl./s; 130% - 15,8 ms, 53 kl./s. Foweacja z opcji
  `xr_foveation` (0-3, dynamiczna). `SETTINGS_VERSION` 8 obcina zapisane
  >110% do 110%. Gra wpisuje do logu co 5 s "PERF..." (`xr_main._log_perf`).
- **Liczniki wydajności** (`scripts/perf.gd`, `Perf.add/dump`, linia
  "PERF+ ms/s" w logu co 5 s obok "PERF:"): auto_fiz/bot_fiz, auto_wyg/
  bot_wyg, dzwiek, bot_ster, boty_mgr, trasa, budowa_trasy, hud, deszcz.
  Wyniki na Queście (130%): **sterowanie botów na szynie 250 ms/s** →
  przyczyna: `samples_from`/`transform_at_distance`/`_sample_near`
  przeglądały liniowo wszystkie próbki (EndlessTrack: ~2000 przy każdym
  wywołaniu) → teraz wyszukiwanie binarne po `_dists`
  (PackedFloat64Array), bot_ster ~47 ms/s. `nearest_sample` szuka od
  ostatniego trafienia (`_near_hint`, okno ±40), `EndlessTrack.lateral_offset`
  nie szuka drugi raz. **Budowa odcinka ~0,5 s zamrożenia** (110 ms/s) →
  `StuntTrack.slice_build`: próbki + jezdnia z kolizją od razu
  (`_build_road_collision`), ściany/znaki/tunele po `await _slice()`
  (klatka po klatce; kawałek usunięty w trakcie przerywa budowę);
  początkowe odcinki w całości; ściany co 3 próbki i kolizja tylko do
  `CANYON_COLLIDE_K` (7 z 13 punktów profilu, ~18 m) → 15 ms/s.
  GPU: deszcz 1000 smug (było 2400), światła w tunelu co 80 m, MSAA 2x.
  Ostatni pomiar: 10. odcinek 56 kl./s, GPU 13,6 ms; **9. odcinek GPU
  35-65 ms** przez dłuższą chwilę - podejrzane tunel (dwunitkowy?) albo
  ulewa - do zbadania (dopisać do PERF: tunel/deszcz). Gogle się grzeją.
- **Wydajność na Queście** (pomiary z logu "PERF", 130%, przed
  optymalizacjami): 40-55 kl./s, GPU 15-25 ms (budżet 13,9 ms przy 72 Hz),
  fizyka ~95 ms na klatkę, gdy pojawiał się bot z fizyką. Profil na PC
  (instrumentacja, usunięta): auto 0,43 ms na krok fizyki, z tego 60%
  badanie podłoża (cast_motion + get_rest_info × 4 koła), opony 0,1 ms.
  Zmiany: **podłoże badane promieniem** (`ray_probe`, `_probe_wheel_ray`,
  dla wszystkich aut; testy jazdy identyczne - stiff wypada na tym samym
  skoku co ze sferą), auto 0,215 ms, bot ~0,12 ms; **fizyka 120 Hz**
  (było 240), `TIRE_SUBSTEPS` gracza 6 (boty 2) - wszystkie testy dają to
  samo co przy 240 Hz (meta 23,48 vs 23,52 s, ABS/ESP, odradzanie,
  wgniecenia). GPU: cienie słońca 2 strefy do 80 m (było 4 do 120 m),
  `rock.gdshader` bez map normalnych dalej niż 40 m (`normal_dist`).
  Pomiarów na Queście po tych zmianach jeszcze nie ma.
- **Ekran tytułowy** (`title.gd`): `_place_car` + `BotDriver` (bez gracza
  i sceny - `main` null, szał wyłączony), kamera w fotelu
  (`_follow_car`), trasa dobudowywana co 0,5 s, auto wywrócone/utknięte
  wraca na prawy pas 25 m dalej, ziemia jedzie za autem. Menu
  (`GazeFollow`) 0,25 m nad oczami z szybkim nadążaniem w pionie
  (`height_rate` 30) - inaczej na podjazdach zjeżdżało na zegary.
- **Dach** (`stunt_car.gd`): osobny materiał "roof" (grupa wgnieceń
  "roof") z połową przezroczystości kokpitu, słupki dalej 1,5×; od środka
  jasna podsufitka (`Headliner`).
- **Oznaczenie zjazdów** (`_build_service`, `_exit_arrow`,
  `TrackHud.show_warning("repair"/"fuel")`): znaki 300 i 100 m przed
  początkiem poszerzenia (start usługi - 40 m), znak ze strzałką na nim;
  `_update_warning` pokazuje niebieską miniaturę ze strzałką, gdy zjazd
  bliżej niż 400 m (pierwszeństwo przed ostrzeżeniami).
- **Skały z tekstur** (`shaders/rock.gdshader`, `_rock_material`,
  `ROCK_TEXTURES`): mapowanie trójpłaszczyznowe w świecie (wagi |n|^6,
  rzut o wadze < 0,02 pominięty), normalne "whiteout", wersje "-bl"
  (normalne OpenGL). Ściany i wyspy - cavern walls (kafel 6 m), góry nad
  tunelami - ocean rock (10 m), mech - wycinek atlasu Mossy Rock Model
  (`tools/make_moss.py`, kafel 2,5 m, `moss_tint` podbija zieleń - sama
  tekstura jest oliwkowo-brązowa i ginęła na brązowej skale). Maska mchu
  jak wcześniej (strona przeciwna do słońca + szum). Bez plików tekstur
  (świeży klon) `_rock_material` daje proceduralny `shale.gdshader`.
  Warianty -ue/-unity i katalog modelu mchu mają `.gdignore` (nie są
  importowane; .obj odwołuje się do brakującego .mtl - błąd importu);
  nieużywane mapy (height/ao/metallic/roughness/preview) wykluczone
  z eksportu w `export_presets.cfg`. Góry na horyzoncie (`Scenery`)
  zostały z kolorami wierzchołków - są kilometry dalej.
- **Model auta** (`StuntCar.set_body_model`, opcja "Model auta" w
  "Nadwozie i opony", domyślnie concept; `SETTINGS_VERSION` 6 przestawia):
  "sedan" - własny, z wgnieceniami; "concept" - Khronos Car Concept
  (`models/concept_car/car_player.glb`, robi go
  `tools/prepare_concept_car.sh` z oryginału w `~/opt/_dl/car-concept/`;
  narzędzie `gltf-transform` w `~/opt/gltf-transform`, npm). Concept:
  model obrócony o 180° (przód w +Z), `CONCEPT` - mocowania kół z modelu
  (rozstaw osi 2,80, kół 1,96), promień 0,49 (przełożenie ×r/0,33
  w `apply_engine` - te same prędkości na biegach), kolizja z bryły,
  środek masy obniżony o różnicę promieni i ustawiony względem środka osi
  jak w sedanie (`_model_com`) - bez tego zsuwał się z łuków. Koła modelu
  przepięte pod `w.node` (początek węzła koła w modelu = środek koła).
  Kierownica modelu obracana w `SteerPivot` wokół osi piasta→koło.
  Fotel na środku (`seat` (0, 0,15, -0,40); układ jak McLaren F1),
  zegary na desce za kierownicą (`CONCEPT.gauges`). Materiały
  (`_fix_concept_material`): szkło z KHR_materials_transmission
  (Godot go nie ma - białe szyby) na zwykłą przezroczystość, AO wyłączone
  (atlas 2048 po uproszczeniu dawał plamy na lakierze), felga "Rim2"
  przyciemniona (lustrzana biel), lakier mniej metaliczny; lakier z menu
  na materiały "Paint *". Ukryte przy concept: karoseria i kabina sedana,
  koła sedana, spojlery (aerodynamika spojlera dalej działa), wycieraczki.
  Prowadzenie: na wąskiej trasie pokazowej (9 m) `drive_test ... concept`
  sport wypada na łuku ze zjazdem ~300 m (szerszy rozstaw - sedan tam
  zjeżdża na -2,2 m i wraca, concept wypada kołami za krawędź); soft
  przejeżdża; trasa bez końca 7 odcinków z jednym upadkiem na końcu.
  `drive_test` ma 4. argument (sedan/concept), domyślnie sedan.
- **Okna na morze** (`StuntTrack.sea_factor`, `SEA_*`, `_canyon_profile`,
  `_build_sea`, `shaders/ocean.gdshader`): w każdym przedziale 5 km jedno
  okno 100 m (+ przejścia po 40 m) w miejscu i po stronie z hasha numeru
  przedziału - bez danych w generatorze, kawałki zgadzają się na styku.
  Profil ściany: wysokość → `PARAPET_H` 0,5 m, płaskowyż → stok w dół
  pod lustro wody. Morze: jedna płaszczyzna 9 km na `SEA_Y` 0,3 (trawa
  ma 0) wysunięta w stronę morza; istnieje tylko z kawałkiem toru, więc
  nie zalewa innych miejsc na długo. W tunelu (`roof`) okna nie ma.
  Ocean: fale w normalnych, Fresnel do koloru nieba, bez geometrii fal.
- **Zielone tablice odcinków** (`_town_sign`): 1,9×0,6 m na środku
  hw + 1,0, słupki ±0,55, podstawa na wysokości krawędzi jezdni
  (przechyłka). Ściana zaczyna się na hw + 1,8 - szersza tablica w nią
  wchodzi.
- **Mech i bluszcz** (`shaders/shale.gdshader`): na ścianach, których
  pozioma normalna patrzy w `north_dir` = przeciwnie do słońca
  (-0,57, -0,82). Pułapka: przy północy = -Z zieleni prawie nie było,
  bo trasa biegnie głównie na -Z i ściany patrzą na wschód i zachód.
  Przy zmianie słońca w scenach popraw `north_dir`. Mech: plamy szumu,
  gęściej w szczelinach i nisko; bluszcz: pionowe pasma z ziarnem liści.
- **Strefy śliskie** (`TrackGenerator._maybe_slippery_zone` przed każdym
  modułem, `_push`): moduły podają nawierzchnię "" (= według strefy,
  `_surface()` zwraca ""), `_push` wstawia nawierzchnię strefy albo
  "dry". Jawne "dry" (skocznie: rozbieg, rampa, lądowanie; tunel) wygrywa.
  Łuk liczy limit prędkości z przyczepności nawierzchni strefy.
  Pułapka: gdy `_surface()` zwracało "dry", strefa nie obejmowała
  modułów (miały jawną nawierzchnię) i wychodziły 30-metrowe kawałki.
  W strefie mokrej segmenty dostają `rain` (1 mżawka / 2 deszcz, deszcz
  częściej dalej: 0,3 + 0,02/km do 0,6), tunel `roof: true` - próbki
  niosą `rain` i `roof`.
  Ziemia w `main.tscn` ma metadane trawy: grip 0,45.
- **Zasady projektowania przy realistycznej fizyce** (z testów):
  - oś w przerwie musi schodzić w dół (lądowisko niżej niż wybicie);
  - lądowisko musi być długie (teraz 50 m), w powietrzu się nie hamuje;
  - przy μ ≈ 1,1 łuk 1,5°/m (R ≈ 38 m) jest przejezdny przy ~60 km/h,
    na mokrym odpowiednio wolniej (√0,7).
- Tor przykładowy: ok. 517 m, otwarty, z mokrym łukiem w lewo, 25 m lodu,
  metą po ~417 m i 100 m prostej na wyhamowanie za metą.
- **Trasa bez końca** (`endless_track.gd`, `track_generator.gd`):
  - `StuntTrack.sample_segments()` (statyczna) liczy próbki od dowolnego
    stanu `{pos, yaw, pitch, bank, width, dist}`; `start_state` i
    `end_state()` łączą kawałki bez szwu. Próbki mają `yaw/pitch/bank`
    i `meta` (z klucza `meta` odcinka: `checkpoint`, `sign`/`v_sign`, `jump`).
  - `EndlessTrack`: jeden `StuntTrack` na sekcję (~480 m), zawsze 2 sekcje
    przed autem i 1 za nim (`update_progress(dist)` z `_watch_track`).
    API jak StuntTrack + `section_at`, `checkpoint_before`,
    `runup_start_before`, `samples_from`; `finish_distance()` = INF.
    Budowa sekcji 10-20 ms na PC - **na Queście będzie szarpnięcie**,
    do przeniesienia do wątku.
  - `TrackGenerator.difficulty(dist)`: prędkość wybicia 55 km/h + 11 km/h
    na km (do 230), rozbieg 150 m - 9 m/km (min 60), rampa 10-16°,
    łuki R 110 → 35 m, jezdnia 11 → 7 m, mokro/lód coraz częściej,
    2-5 modułów, 1 skok na sekcję (2 od 6 km). Strojone pod warsztat co
    10 odcinków: odcinek 10 (~4,5 km) ≈ 105 km/h na wybiciu.
  - Moduły: brama (punkt kontrolny), prosta, łuk z przechyłką, szykana,
    garb, podjazd/zjazd (wysokość 18-70 m), skok. Kurs ograniczony do
    ±55° od początkowego - tor nie zawraca i się nie przecina.
  - **Skok z balistyki** na prawdziwych próbkach: v² = g·D² /
    (2·cos²θ·(D·tanθ + H)), D i H między krawędziami przerwy +
    `CAR_CLEARANCE` 3,5 m (tylne koła); długość przerwy bisekcją do
    prędkości docelowej. Znak przed rozbiegiem: prędkość u podstawy rampy
    (+ strata na wysokość rampy, +5%, w górę do 5 km/h).
  - **Za szybko na skoku też źle** (z testu): 175 km/h na skoku 60 km/h
    → przejście na rampę ściska zawieszenie ~4 g, tył odbija, auto
    w locie obraca się nosem w dół do -79° i spada. Fizycznie poprawne
    - znak z prędkością ma znaczenie w obie strony. Autopilot w
    `endless_test` trzyma prędkość ze znaku +10% i w locie puszcza pedały.
  - **Skoki strojone pomiarem** (`tests/runup_test.gd`, tablica
    `RUNUP_CAP` w generatorze): prędkość po rozbiegu 60-150 m ze 60 km/h
    dla progów 90-350 kW (rodzaj napędu prawie bez znaczenia - ogranicza
    moc). `jump_schedule(index)`: w obrębie progu (10 odcinków) prędkość
    u podstawy rampy rośnie od 92% granicy poprzedniego silnika do 93%
    obecnego, rozbieg 150 → 105 m. Poprzednia krzywa (z dystansu) była
    za stroma: 130 kW odpadało na 12. odcinku.
  - Warsztat uruchamiał się dwa razy (auto staje przy linii) - poprawione
    (`_ws_done_stop`).
  - **Wynik testu (ziarno 777, 200 s)**: 90 kW - pierwszy upadek na
    odcinku 10 (5,0 km), zgodnie z planem warsztatu; 180 kW - upadki na
    odcinku 7, dojazd do 10; 350 kW - upadki na 4, 6, 6, koniec na 7.
    Przyczyna u mocnych aut: autopilot nie ma limitu na prostych i wjeżdża
    w **garby** z 200+ km/h - auto odlatuje na szczycie i ląduje w łuku.
    Fizycznie poprawne. Do zrobienia: limit prędkości z krzywizny
    pionowej w autopilocie (v² < g·R) i **znaki ostrzegawcze przed
    garbami** w grze (jak przed skokami).
  - **Strażnik wysokości** (`TrackGenerator._guarded`, `lowest_edge`,
    `_rise`; błąd użytkownika 2026-11-08 "droga pod wodą / pod łąką,
    bo jest zielona"): teren to wciąż jedna płaska trawa na y = 0
    (`main.tscn` Ground + `WorldBoundaryShape3D`, pozostałość toru na
    palach), morze z okna na `SEA_Y` 0,3. Wąwóz nie ma własnego dna, więc
    jezdnia poniżej ~0,3 m znika pod trawą albo wodą. Przyczyna: wysokość
    sprawdzano tylko **przed** modułem, a skocznia (stół + zeskok -12°)
    schodzi o 5-10 m w jego trakcie - na autostradzie (4 m) prawie zawsze
    pod trawę (do -2,2 m), w wąwozie od ~6 m w dół. Symulacja w Pythonie
    (port wysokości generatora, 300 ziaren × 40 odcinków): 8% odcinków
    z jezdnią < 0,3 m, ponad połowa na autostradzie. Teraz każdy moduł
    (i skocznia/garb autostrady) jest najpierw budowany na próbę na kopii
    stanu przy tym samym `rng.state`; jeśli najniższy punkt (z niższą
    krawędzią na przechyłce) < `d.hmin` (2 m), przed modułem idzie
    podjazd (`_climb` w wąwozie, `_highway_level` na autostradzie)
    i próba od nowa. Geometria modułu nie zależy od wysokości startu,
    więc moduł wychodzi ten sam, tylko wyżej. Losowanie
    modułu bez zmian; dalszy przebieg trasy może się różnić, bo podjazdy
    zmieniają wysokość. Test:
    `tests/track_height_test.gd`. **Nie usuwaj płaskiej trawy, zanim
    nie będzie innego terenu** - autostrada stoi na nasypie do y = 0.
  - Pułapka strojenia: każdy skok obniża tor o ~10 m, więc podjazd był
    wybierany prawie zawsze i znikały łuki - podjazd tylko blisko dolnej
    granicy i od razu po skoku, jeśli nisko.
- **Warsztat** (trasa bez końca): `TrackGenerator` daje sekcji 11, 21,
  31... (`WORKSHOP_EVERY` = 10) prostą 170 m z `meta.workshop = próg`;
  `StuntTrack._build_workshop` stawia halę z napisami i żółtą linię
  postoju 95 m od początku prostej. `EndlessTrack.next_workshop(dist)`.
  **Start z mocą z menu** (decyzja użytkownika 2026-11-09; do tej pory
  zawsze 90 kW - stąd "1000 kW ledwo wjeżdża pod górkę"): `restart_race`
  bierze `effective_power(...)`, `_tier` = jej indeks w `POWER_TIERS`.
  Przejazd przez linię postoju (`_check_workshop`, płaszczyzna jak meta)
  → stan `Race.WORKSHOP`: zegar stoi, auto hamuje, przed kierowcą lista:
  benzyna/diesel/elektryk na progu `max(próg z trasy, _tier + 1)`
  (z momentem z prawdziwej krzywej) + "bez zmian"; na ostatnim progu
  tylko "bez zmian". Silniki w kołach tylko z ostatniego progu albo gdy
  elektryk już je miał. Drążek/strzałki + A/Enter (`workshop_choose`).
  Przy okazji `repair()` i +1 dźwig.
- **Znaki przed garbami**: `_hill` dokłada 30 m prostej z `meta.warn`
  ("GARB maks. X km/h", `v_warn`), pomarańczowa tablica. Prędkość:
  największa krzywizna przejścia +p → -p (smoothstep) κ = 1,5·2p/(1,6·l),
  auto trzyma się jezdni dopóki v² < g/κ; na znaku 95% w dół do 5 km/h.
  **`warn` to inny klucz niż `sign`** - `sign` oznacza rozbieg skoku
  (dźwig, `runup_start_before`), pomylenie ich psuje respawn.
- **Wąwóz** (`StuntTrack.canyon`, `_build_canyon`, `shaders/shale.gdshader`):
  profil po każdej stronie od krawędzi jezdni: pobocze 1,8 m, 5 stopni
  łupku (ściana z odchyleniem 0,12·h + półka 0,6-1,6 m), płaskowyż 300 m;
  wysokość ~30 m ± z gładkich sinusów dystansu (sąsiednie próbki się
  zgadzają). Ściany pionowe względem świata. Kolizja StaticBody3D
  `surface = "rock"`, `grip = 0.55`. `_quad_facing` wybiera nawinięcie
  wg kierunku (front CW). Bez filarów i bez drzew (otoczenie tylko na
  estakadach). Generator z `canyon = true`: bez przerw - skocznia = rampa
  + stół (pitch 0) + zeskok -12°, znak "SKOCZNIA X km/h"; wysokość toru
  2-25 m (start 6 m). Shader łupku: pakiety warstw 1,3 m (kolor z hasha
  numeru warstwy, czasem rdzawy), laminacja co ~16 cm, ciemne szczeliny,
  rumosz na poziomych powierzchniach.
- **Uszkodzenia** (`stunt_car.gd`, `damage`): z tych samych impulsów co
  wgniecenia (`_impact_queue` → `_damage_impact`), powaga =
  (J - 700)/`damage_impulse_scale` (9000). Przód z < -1,5 → silnik
  (+0,30·sev), tył z > 1,7 → silnik (+0,08), w promieniu 0,75 m od
  mocowania koła → hamulec i zawieszenie koła (+0,35), zawsze
  `structure` +0,17·sev. Lądowanie > 7,5 m/s → zawieszenie i skrzynia.
  Skutki: moc ×(1-0,75·silnik), hamulec koła ×(1-0,8·d), ściąganie
  kierownicy z różnicy zawieszeń lewo/prawo, zmiana biegu do 4× wolniej.
  `structure` ≥ 1 → `wrecked` (auto nie ma mocy). Kalibracja
  (`dent_test`): ściana 30 km/h → stan -13%, silnik 22%; 60 km/h → stan
  ~-35%, silnik 58%; dach z 3 m → ~-13%.
- **Życia i eksplozja** (`xr_main.lose_life`, `scripts/explosion.gd`):
  stan `Race.EXPLODING`; `Explosion` = błysk OmniLight, kula ognia,
  iskry i dym (CPUParticles3D - **rozmiar cząstki ustawiać na siatce**,
  skala cząstek była pomijana i wychodziły metrowe kwadraty), 9 części
  karoserii jako RigidBody3D. Auto ukryte i zamrożone; kamera
  (`_cinematic`) płynnie 2,2 s w tył (13 m) i w górę (6 m), w goglach
  tylko obrót w poziomie; po 4,5 s `_after_explosion` - nowe auto na
  kołach w miejscu wypadku, naprawione; `cranes_left` to teraz życia
  (opcja "Życia (auta)": 3/5/bez limitu). B na trasie bez końca:
  na kołach i utknięte → `_right_car`, na dachu → utrata życia.
- **Zegary** (`scripts/gauges.gd`, `Gauges`): tarcze z Cylinder/Torus,
  kreski BoxMesh, liczby Label3D, wskazówki; zakres 270° od lewego dołu;
  obrotomierz przebudowywany przy `apply_engine` (`set_rpm_range`).
  Wskaźnik uszkodzeń: okienko LCD 36×50 mm w dolnej (bez skali) części
  prędkościomierza (`DamageLCD`, `LCD_ZONES`): segmenty
  engine/cabin/rear/w0-w3 zielony/żółty/czerwony, zniszczony gaśnie
  i zostaje blady "duch" segmentu (`_set_zone`).
  Materiały bez cieniowania. `dash_label` pod tarczami: tylko bieg
  i kontrolki ABS/TCS/ESP.
- **HUD trasy** (`scripts/track_hud.gd`, `TrackHud`): panel 16×13 cm nad
  kierownicą, trasa 1,5 km w układzie auta (kierunek jazdy w górę), linia
  w kolorze nawierzchni, znaczniki: skok żółty, garb pomarańczowy,
  warsztat zielony, brama biała; odświeżanie co 0,25 s, próbki pobierane
  tylko wtedy (`sampler` jako Callable). `StuntTrack.samples_from`.
- **Sterowanie konfigurowalne** (grupa "Sterowanie"): `gas_hand`
  (prawy/lewy spust; hamulec na drugim), `steer_stick` (domyślnie prawy;
  drugi drążek zmienia biegi - jedno wychylenie ↑/↓ = jeden bieg,
  `_shift_ready`; migracja `SETTINGS_VERSION` 3 ustawia prawy), `handbrake_grip`
  (przy hamulcu / przy gazie), `stick_expo` (1,6 / 1,0 / 2,2),
  `stick_sensitivity`.
- **Deszcz** (`xr_main._build_rain/_update_rain`): GPUParticles3D 2400
  smug w świecie (auto w nie wjeżdża), emiter 8 m nad autem i 0,5 s drogi
  przed nim, `amount_ratio` z intensywności; szum deszczu (pętla WAV).
  Dwie prędkości: smugi i szum (`_rain_vis`) idą za opadem szybko
  i `restart()` przy zgaśnięciu (wjazd do tunelu ucina deszcz), szyba
  (`car.rain`) mokrnie i schnie ~3 s.
- **Wycieraczki i krople** (`stunt_car._build_wipers/_update_wipers`,
  `shaders/raindrops.gdshader`): dwa ramiona na osiach w układzie szyby,
  kąt = sweep·sin(π·faza), cykl 1,1 s, przy mżawce przerwa 2,5 s.
  Krople bez stanu na piksel: shader liczy chwilę ostatniego przetarcia
  punktu z fazy cyklu (`c_start`, `c_prev`) i pokazuje tym więcej kropli,
  im dłużej od przetarcia (`rate`). Górny pas szyby poza zasięgiem ramion
  zostaje mokry - jak w prawdziwym aucie.
- **Akustyka otoczenia** (`scripts/env_audio.gd`, `EnvAudio`): szyna
  "Env" (tworzona w kodzie, `ensure_bus`) z AudioEffectDelay (echo: lewa
  ściana tap1 w lewym kanale, prawa tap2 w prawym, opóźnienie 2d/343 s,
  ciszej z odległością; w tunelu sprzężenie = trzepotanie) i
  AudioEffectReverb (wąwóz krótko i mało, tunel długo i dużo, deszcz
  tłumi). Ściany mierzy `xr_main._update_env` promieniami w bok co 0,2 s.
  Na szynie grają `CarAudio` i klaksony botów; deszcz i ćwierknięcie na
  Master. `CarAudio` ma syk wody spod opon (koła na "wet" × prędkość).
- **Gra na trasie bez końca** (`xr_main.gd`): `GameSettings.track_mode`
  ("canyon" - jedyny w grze; "endless"/"demo" tylko testy), `cranes` (3/5/bez limitu). Dźwig
  (`_use_crane`) zabiera życie, po ostatnim `_game_over()` (odcinek,
  dystans, czas, rekord `best_distance`); A = nowa trasa (przeładowanie
  sceny). Po upadku przy skoku powrót na początek rozbiegu, nigdy dalej
  wstecz niż brama bieżącego odcinka. Na desce: odcinek, km, czas, dźwigi.
  Ziemia (siatka) jedzie za autem.
- **Start i meta**: `START_DISTANCE` (8 m), odcinek z `"finish": true`
  wyznacza metę (`finish_distance()`; bez niego 100 m przed końcem).
  Linie w szachownicę na jezdni, nad metą brama z banerem i napisem META
  (`_build_line`).
- API: `nearest_sample()`, `lateral_offset()` (liniowe, wolne),
  `transform_at_distance(d)`, `total_length()`,
  `last_gap_end_before(d)`, `is_gap_at(d)`.

### Samochód (`stunt_car.gd`) - realistyczny model
- `RigidBody3D`, jawny środek masy i tensor bezwładności. Przód = -Z.
  **Celowo bez `VehicleBody3D`.**
- **Koło** = sfera rzucana w dół z mocowania (`cast_motion`, potem
  `get_rest_info`). Ugięcie analityczne. Nawierzchnia z metadanych ciała,
  w które trafiło koło (`w.grip`, `w.surface`), więc każde koło może
  stać na innej.
- **Zawieszenie:** sprężyna, tłumik bump/rebound, odbój, stabilizatory.
  `SUSPENSION_PRESETS`: soft ~1,4 Hz, sport ~1,8 Hz, stiff ~2,4 Hz.
- **Mieszanka opon** (`TIRE_COMPOUNDS`, `tires`, opcja menu "Opony"):
  mnożnik `w.grip` zależny od nawierzchni. Całoroczne (domyślne,
  użytkownik: "raczej całoroczne niż letnie") sucho 0,94 / mokro 1,08 /
  lód 1,6; letnie 1/1/1 (dawne zachowanie); zimowe 0,86 / 1,05 / 2,3.
  Limity prędkości na łukach generator liczy z `SURFACES` bez opon.
- **Układ napędu** (`drive_layout`, `hub_motors`, opcje "Napędzane koła"
  i "Silnik elektryczny"): "rwd" tył z LSD; "awd" - centralny dyferencjał
  planetarny 40/60 (`AWD_FRONT_SHARE`; wał = 0,4·przód + 0,6·tył),
  wiskoza między osiami (`center_coupling`), LSD na obu osiach.
  Silniki w kołach (`_hub()` = hub_motors i elektryk; warsztat może
  zmienić napęd): każde koło 1/4 momentu, bez dyferencjałów, TCS osobno
  na koło (`_hub_tcs`), zawsze 4x4. TCS w 4x4 liczy poślizg względem
  prędkości auta (nie ma kół nienapędzanych).
- **Masa** (`body_mass`, `set_body_mass`, opcja "Masa" 950-2500 kg):
  masa i bezwładność; zawieszenie (sprężyny, tłumiki, stabilizatory)
  skalowane proporcjonalnie, więc częstotliwość drgań zostaje.
- **Spojler** (`SPOILERS`, `set_spoiler`): docisk ½ρ·ClA·v² nad tylną osią
  (lotka ClA 0,45, skrzydło 1,1 - ~480 kg przy 300 km/h) i dodatkowy opór
  CdA 0,03 / 0,08 - spojler podnosi przyczepność, prędkość maks. trochę
  spada. Widoczne bryły na klapie (`_build_spoilers`).
- **1000 kW** (`GameSettings.HUB_ONLY_KW`, `effective_power`): tylko
  elektryk z silnikami w kołach; inny napęd z tą opcją dostaje 700 kW
  (podpowiedź w menu to mówi). Ostatni warsztat (po 700) proponuje tylko
  ten wariant (`opt.hub`). Pomiar: 0-100 2,9 s, 0-200 6,2 s, 409 km/h
  po 25 s (wciąż przyspiesza; przełożenie ×0,5 → ogranicznik ~440).
- **Moc do 700 kW** (`POWER_TIERS` 90..700, użytkownik: "nierealistyczna,
  700 kW"). Powyżej 350 kW (elektryk: 250 kW) dłuższe przełożenie
  (×√(P0/P)), inaczej ogranicznik przy ~290/234 km/h. Prędkościomierz do
  400 km/h. Pomiar (sucho, całoroczne): 700 kW benzyna tył 0-100 4,6 s,
  0-200 9,9 s, 349 km/h po 25 s; 4x4 3,4 s / 7,1 s / 363; elektryk 4x4
  3,1 / 6,5 / 361, w kołach 2,9 / 6,5. Napęd na tył ponad 350 kW jest
  ograniczony przyczepnością - na rozbiegu do 150 m prawie nic nie
  zyskuje (`RUNUP_CAP`, wiersze 500/700). Bot w szale dostaje
  max(350 kW, moc gracza).
- **Opony:** znormalizowana Magic Formula, połączony poślizg, load
  sensitivity, relaxation length całkowana wykładniczo, tłumienie przy
  niskich prędkościach, 4 podkroki na krok fizyki. `f_max = μ·grip·Fz`.
- **Napędy** (`ENGINE_TYPES`, `apply_engine(typ, kW)`): krzywa momentu
  skalowana tak, żeby szczyt mocy = wybrana moc.
  - benzyna: szczyt momentu ~4500 obr., odcinka 7200, 6 biegów;
  - diesel: płaski szczyt 1750-2750, odcinka 4700, dłuższe biegi,
    mocniejsze hamowanie silnikiem, +50 kg;
  - elektryk: stały moment do 4800 obr., potem stała moc, 16 000 obr.,
    **jeden bieg 9:1**, bez sprzęgła (`electric = true`), rekuperacja
    jako "hamowanie silnikiem" (zanika przy zerowych obrotach),
    +200 kg i niżej środek masy (bateria).
  - Masa i bezwładność zmieniają się z napędem (`_base_mass` itd.).
- **Skrzynia:** automat (decyzje z obrotów kół, tylko z kontaktem tylnych
  kół, przerwa po zmianie, wsteczny = hamulec na postoju, na R pedały
  zamienione) albo manual (R-N-1..6, blokada wstecznego > 2 m/s).
- **Hamulce:** rozdział przód/tył, ręczny na tył (omija ABS).
- **Systemy wspomagania** - liczone z tego, co prawdziwe auto mierzy:
  - **ABS**: cykliczna modulacja ciśnienia na koło (`_abs_mod`): spust
    25/s, gdy κ < -1,15·szczyt, docisk 20/s. Stały procent ciśnienia nie
    działał na lodzie (15% pedału wciąż blokowało koło).
  - **TCS (= ASR)**: prędkość odniesienia z przednich (nienapędzanych)
    kół; gdy tył buksuje ponad `tcs_target_slip`, mnożnik momentu silnika
    spada. Odcina tylko moment napędowy, nie hamowanie silnikiem.
  - **ESP**: oczekiwany obrót z modelu rowerowego, ograniczony szacowanym
    tarciem (`grip` kół w kontakcie). Ingeruje tylko, gdy błąd obrotu >
    martwa strefa **i** opony danej osi są blisko szczytu kąta znoszenia.
    Bez drugiego warunku ESP brał przechyłkę na łuku za nadsterowność
    i działał przez 38% jazdy, teraz ~2-7%. Nadsterowność = hamowanie
    zewnętrznego przedniego koła i odcięcie gazu, podsterowność =
    hamowanie wewnętrznego tylnego.
  - `abs_active`, `tcs_active`, `esp_active` → kontrolki na desce.
- **Siły na nadwozie:** boczna w punkcie styku, wzdłużna na piaście,
  reakcja napędu i hamulców jako moment wokół osi X (gaz w locie
  podnosi nos).
- Deska (Label3D, tymczasowa): km/h, A/M + bieg, obroty, kontrolki.
- **Wygląd: sedan z lat 70.** (`_build_body`): długość 4,56 m, dach
  1,39 m, oczy kierowcy 1,15 m nad jezdnią (`seat`), prześwit 0,25 m.
  Długa maska i bagażnik, winylowy dach, szeroki słupek C, chromowane
  zderzaki, listwy i kołpaki, cztery okrągłe reflektory, grill
  w poprzeczki, tylne lampy świecące przy hamowaniu (`_tail_mat`).
  Kabina pusta w środku (cienkie boki), kanapy przód/tył, kierownica
  14:1 obracająca się ze skrętem (`_steering_wheel`). Lakier jednym
  materiałem (`set_paint()`), kolory w `GameSettings.PAINTS`.
- **Wgniecenia** (sekcja "Wgniecenia" w `stunt_car.gd`): karoseria
  z podzielonych prymitywów (oczko 15 cm, ~4800 wierzchołków), scalona
  w jedną siatkę na materiał (paint, vinyl, chrome, dark, glass, tail,
  head). `_integrate_forces` czyta impuls kontaktów; powyżej
  `dent_threshold` (700 N·s na krok) kolejkuje wgniecenie w kierunku
  impulsu, głębokość `(J - próg)·dent_per_impulse` (4,5e-5), promień
  0,30 m + 2,5·głębokość, zanik kosinusowy, limit 22 cm na wierzchołek.
  Siatka przebudowywana w `_process` tylko po zmianie. Wnętrze, koła
  i kierownica się nie wgniatają. Kolizja sztywna. `repair()` przywraca
  kształt (jeszcze nigdzie niewołane - dźwig nie naprawia).
  Kalibracja: dach z 3 m → 13 cm, bok z 2 m → 9 cm, normalny przejazd
  toru (z twardymi lądowaniami) → 0 wgnieceń. Jedno wgniecenie 0,19 ms
  na PC.
- **Kolizja nadwozia**: dwa pudła - dół (do -0,40 m pod punktem
  odniesienia, czyli 0,30 m nad jezdnią) i kabina (ważne przy
  dachowaniu). Nadwozie dotyka jezdni tylko przy twardym lądowaniu
  (~23 klatki na przejazd) - realistyczne dobicie.

### Scena jazdy (`xr_main.gd`)
- Przy starcie `GameSettings.apply_to_car(car)`.
- Tryby `DRIVE` / `FLY`. XROrigin3D z `physics_interpolation_mode = OFF`,
  ustawiany w `_process` z `car.get_global_transform_interpolated()`.
- **Dźwig** (`_watch_track`, co 0,2 s): bezpieczne miejsce = ≥ 3 koła na
  jezdni. Podnosi po 1,5 s (spadło, na dachu, y < -50) albo po 3 s
  (zawisło na krawędzi). Cofa o 35 m, ale nigdy wstecz przez przerwę.
- **Przejazd** (`update_race`, stany `Race.READY/RACING/FINISHED`):
  zegar rusza, gdy auto ruszy; dźwig nie zatrzymuje zegara; meta =
  przejście przez płaszczyznę linii mety w kierunku jazdy (`_check_finish`,
  co krok fizyki, tanio). Po mecie auto samo hamuje (za metą tylko prosta
  i przepaść), dźwig wyłączony, przed kierowcą tablica wyników (czas,
  rekord / NOWY REKORD). A / R / Enter / pad A: `restart_race()` (od linii
  startu, `car.repair()`). Zegar nad deską (`_race_label`). Rekord
  w `GameSettings.best_time` (sekcja `records` w settings.cfg) - jeden na
  trasę, niezależnie od auta.
- **Kamera lotu w goglach**: prawy drążek ↔ yaw, ↕ lot; z prawym gripem
  ↕ = pitch; lewy drążek ruch w bok i góra/dół. Obrót wokół głowy
  (`_rotate_origin_around_head`), nie środka pokoju.
- **Grafika - kanciasta z wyboru** (prośba: "bardziej realistyczny...
  może być kanciasty kształt, ale renderowany jakby tak miało być"):
  - `shaders/road.gdshader`: asfalt (ziarno, łaty, koleiny), linie
    krawędziowe, przerywane linie 3 pasów, biało-czerwone krawężniki;
    mokra/lód jako parametry. Wymaga UV jezdni z `_build_mesh`: UV.x =
    poprzecznie [m], UV.y = wzdłuż [m], UV2.x = szerokość. Zero
    dodatkowej geometrii.
  - `shaders/concrete.gdshader` (boki/spód płyty, filary) i
    `shaders/ground.gdshader` (trawa, płaty ziemi) - w układzie świata.
  - Materiały wspólne dla wszystkich kawałków toru (`_shared_mats`).
  - Filary jak w wiadukcie: stopa 4,2 m, słup dwuczłonowy 2,4 → 2,0 m,
    poprzecznica pod najniższym punktem płyty (`_obox`).
  - `scripts/scenery.gd`: drzewa iglaste/liściaste i głazy jako MultiMesh
    na każdym kawałku toru (nic bliżej niż 16 m od osi), góry na
    horyzoncie (pierścień 1,5-2,5 km, jedzie za autem; kamera far 4000).
  - Auto: linie drzwi, klamki, lusterka, kły zderzaków, obwódki lamp,
    tablice (bez napisów), rura wydechowa, wycieraczki, koło jako jedna
    siatka (bieżnik, ścianki, kołpak z żebrami, `_wheel_mesh`), ciemne
    nadkola. Detale są w grupach wgniatalnych.
  - Światło: tonemap AgX, cieplejsze słońce, mgła 0,0007 z perspektywą
    powietrzną, otoczenie z nieba tylko w 55% (inaczej cienie były
    jaskrawo niebieskie).
  - Do zrobienia: fazowane krawędzie karoserii (teraz ostre pudła).
- **Dźwięk** (`car_audio.gd`, `CarAudio` - AudioStreamPlayer3D w komorze
  silnika, tworzony w `StuntCar._ready`): AudioStreamGenerator 22 kHz mono,
  synteza w `_synth()` co klatkę. Silnik spalinowy: zapłony 4 cyl.
  (obr/30 Hz) + harmoniczne + pół-rząd + szum spalania w rytm zapłonów;
  diesel niżej i z klekotem. Elektryk: falownik 8× obroty + przekładnia
  23× obroty, cicho. Pisk opon: filtr pasmowy ~1 kHz na szumie, z
  `wheel.slip` > 1. Wiatr ~ v². Łupnięcie: `landed` i wgniecenia.
  `tanh` na wyjściu (bez przesteru). Koszt ~1,2% rdzenia na PC
  (szac. 5-6% na Queście) - jeśli za drogo, pętla do GDExtension.
  Poziomy (z `audio_demo`): wolne obroty ~-23 dB, gaz ~-16 dB, elektryk
  ~10 dB ciszej, łupnięcie ~-10 dB, bez przesteru. Słychać też na ekranie
  tytułowym (auto stoi na wolnych obrotach).
- **Przezroczystość kokpitu** (`car.set_cockpit_transparency`,
  `GameSettings.cockpit_alpha`, domyślnie 40%): tylko w widoku z kokpitu
  (VR zawsze, PC po C), z zewnątrz i w trybie lotu auto pełne. Materiały
  karoserii i wnętrza (bez szyb i świateł) w trybie
  `TRANSPARENCY_ALPHA_DEPTH_PRE_PASS` - bez migania nakładających się ścian.
  Przez maskę i podłogę widać jezdnię i przednie koła (sprawdzone zrzutem).
- **Krzywa drążka** (`_stick_curve`): martwa strefa 0,08, |x|^1,6, potem
  czułość `GameSettings.stick_sensitivity` (50-150%). Tylko gogle i pad,
  klawiatura bez zmian.
- **Pomoce w trakcie jazdy** (`toggle_assist`): A ABS, B ESP, X TCS,
  Y krótko ograniczenie skrętu (gogle); TCS też T (PC), Back (pad).
  Y przytrzymany 0,8 s = centrowanie widoku. Zmiana zapisuje się
  w `GameSettings`. Pełne sterowanie w README.

### Ekran tytułowy (`title.gd`) i ustawienia (`game_settings.gd`)
- `GameSettings.OPTIONS`: lista opcji `{key, group, label, values, names,
  hints}`, grupy w `GameSettings.GROUPS`. **Nowa opcja = zmienna + wpis
  w OPTIONS z istniejącą grupą + jej użycie** (`apply_to_car()` albo scena
  jazdy) - menu buduje się samo. Grupa może mieć najwyżej 7 opcji
  (`MAX_ROWS` = 8 wierszy z "Wróć").
- Menu główne: grupy + START; pod grupą skrót jej ustawień. W grupie:
  opcje + "Wróć". Enter/spust/A wchodzi i wraca, B/Esc wraca, w prawo na
  grupie też wchodzi. `enter_group(id)` - używane też przez test.
- Menu to Label3D w węźle `GazeFollow` (`scripts/gaze_follow.gd`):
  2,6 m przed głową na wysokości oczu, za obrotem głowy idzie leniwie
  (dopiero po odejściu wzroku o 25°, płynnie wraca na wprost). Tego
  samego używa menu warsztatu (1,5 m). Tło: wąwóz (`EndlessTrack`,
  `TITLE_SEED`), gracz stoi na jezdni za autem. W goglach XROrigin =
  podłoga na poziomie jezdni (wcześniej stał metr wyżej i menu było za
  wysoko); na PC kamera 1,6 m. Tylko ASCII
  i polskie litery w tekstach (domyślny font może nie mieć symboli).
- Przy napędzie i mocy podpowiedź pokazuje maks. moment liczony na aucie
  z tła (`car.apply_engine` + `peak_torque()`). Przy elektryku skrzynia
  wyświetla "1 bieg". Auto z tła pokazuje wybrany lakier na żywo.

### Budowanie na Questa 3
```
./quest.sh            # build + wgranie + start (czeka na podłączenie i zgodę gogli)
./quest.sh all        # testy + build + wgranie + start
./quest.sh build      # tylko build/stunt-track-vr.apk (debug, debug keystore)
./quest.sh install    # wgranie gotowego APK + start
./quest.sh test       # testy headless (~5 min); wykrywa błędy skryptów
./quest.sh log        # logcat -s godot
./quest.sh stop       # zatrzymanie gry
```
Pierwszy build instaluje szablon gradle'owy w `android/` (ignorowany).

## 6. Testowanie

```
cd /home/c/dev/stunt-track-vr
godot --headless --import --xr-mode off </dev/null     # po dodaniu plików/klas
godot --headless --xr-mode off -s res://tests/drive_test.gd -- 95 sport auto </dev/null
godot --headless --xr-mode off -s res://tests/assist_test.gd -- dry </dev/null   # dry/wet/ice
godot --headless --xr-mode off -s res://tests/engine_test.gd </dev/null
godot --headless --xr-mode off -s res://tests/title_test.gd </dev/null
godot --headless --xr-mode off -s res://tests/track_height_test.gd </dev/null  # sam generator, sekundy
```

- `track_height_test` (generator): 10 ziaren × 40 odcinków wąwozu
  z autostradą, najniższa jezdnia (z krawędzią na przechyłce) ≥ 1,9 m,
  inaczej "BŁĄD". Wynik: **jeszcze nie uruchomiony** (napisany w chmurze,
  bez Godota) - uruchomić i wpisać.

- `drive_test` (prędkość, zawieszenie, skrzynia): jedzie do mety (max 70 s),
  woła `main.update_race`; autopilot planuje
  prędkość z poziomej krzywizny i przyczepności nawierzchni. To kierowca
  testowy, nie AI. Na koniec liczy klatki aktywności ESP/TCS/ABS.
- `assist_test` (nawierzchnia): ABS (hamowanie ze 100 km/h ze skrętem),
  TCS (ruszanie), ESP (zmiana pasa przy 90 km/h), każdy wł./wył.,
  na płaskiej ziemi z gripem wybranej nawierzchni.
- `engine_test`: 0-100 i prędkość po 25 s dla napędów × mocy.
- `title_test`: ustawia opcje przez API menu, sprawdza auto w scenie jazdy.
- `audio_demo.gd` (KATALOG): renderuje `silnik_petrol/diesel/electric.wav`
  (11 s: wolne obroty, gaz, zmiana biegu, 120 km/h, pisk, łupnięcie,
  zwalnianie) - do odsłuchu bez gogli; użytkownik ma je w `build/audio/`.
- `generator_test` (ziarno): parametry 12 sekcji (długość, wysokość, kurs,
  łuki, nawierzchnie, skoki) i czas dobudowy.
- `endless_test` (kW, napęd, ziarno, limit s): autopilot na trasie bez
  końca do utraty 3 dźwigów; zna znaki skoków. Wypisuje upadki i wynik.
- `dent_test`: auto spada dachem z 3 m i bokiem z 2 m; głębokość
  wgnieceń per materiał i czas jednego wgniecenia.
- `screenshot.gd` (**z oknem**, nie headless; na chwilę otwiera okno):
  `godot --xr-mode off --resolution 960x600 -s res://tests/screenshot.gd -- KATALOG [dent] </dev/null`
  (z `dent` auto dostaje trzy wgniecenia przed zdjęciami)
  zapisuje `car_front34/rear34/side/cockpit/chase.png`. Z `rain` ulewa
  (krople, wycieraczki, smugi). Obejrzyj je
  narzędziem do czytania obrazów - **tak sprawdzaj każdą zmianę wyglądu**.

Wyniki (2026-11-08, sesja 3, `./quest.sh test` - wszystko OK):
- drive_test 95 sport auto: meta 23,87 s (przejazd 0:23,32), auto staje
  56 m przed końcem toru.
- assist_test wet: ABS wł. 64 m, 21 m w bok, obrót -78°, koła
  zablokowane 2%; wył. 61 m prosto, zablokowane 90%. TCS 31,6 km/h po
  3 s w obu (na mokrym prawie nie ingeruje). ESP wł. β 10°, bez obrotu;
  wył. β 76°, obrót. (ABS: duży obrót przy skręcie na mokrym - do
  obejrzenia, czy to nie przesada; w sesji 2 na suchym było 16 m w bok.)
- respawn_test: 4 scenariusze, obrót 0,00 rad/s, koła 4.
- service_test: stacje na odc. 5, 10, 15, warsztat na 11; znaki
  860-976 m przed zjazdem.
- endless_test 180 petrol 777 150: jeden upadek (odc. 4), po 150 s
  odcinek 6, 3,48 km.
- **Pułapka testów: `place()` przez 0,5 s mnoży prędkość przez 0,5
  co krok** (`_settle_t`, poprawka odradzania). Test, który po `place()`
  nadaje prędkość albo spuszcza auto z wysokości, musi ustawić
  `car._settle_t = 0.0` - tak robią `assist_test`, `runup_test`,
  `dent_test` (objaw: hamowanie z "100 km/h" na 0,1 m, rozbiegi ~15 km/h
  niższe niż w tabeli, słabe wgniecenia po upadku).
- **Naprawione testy**: `assist_test` ustawia `car._settle_t = 0` po
  `place()` (od poprawki odradzania `place()` przez 0,5 s zeruje
  prędkość - test wychodził z 0 km/h: "droga hamowania 0,1 m");
  `drive_test` ustawia `track_mode = "demo"` (po usunięciu wyboru trasy
  z menu scena budowała wąwóz, węzeł `Track` znikał i test wisiał -
  objaw: brak linii META, timeout).

Wyniki (2026-11-07, sesja 2):
- drive_test, wszystkie 4 konfiguracje: cały tor bez upadku (mokry łuk
  i lód też); jedyny upadek to zjazd z końca otwartego toru. ESP aktywny
  2-7% czasu, TCS ~15%, ABS ~10% (autopilot hamuje ostro).
- assist_test: ABS wł. na suchym 46 m i 16 m ominięcia, wył. 44 m prosto
  (89% czasu koła zablokowane). Dłuższa droga z ABS to efekt skrętu
  (część tarcia idzie w bok), nie wada ABS. Na lodzie ABS: koła
  zablokowane 8% czasu zamiast 86%, auto sterowne. TCS na mokrym: 45 vs
  37 km/h po 3 s, poślizg 0,14 vs 1,55. ESP na mokrym: β 10° vs obrót
  auta; na suchym β 8° vs 29°.
- engine_test (180 kW): benzyna 5,7 s / 209 km/h, diesel 5,3 s / 210,
  elektryk 5,5 s / 206; elektryk 350 kW 4,5 s, ale tylko 219 km/h
  (limit obrotów silnika, jak w prawdziwych EV).
- title_test: diesel 250 kW (792 Nm, 1200 kg), manual, twarde, ESP wył.
  dociera do auta.
- Build APK (`./quest.sh build`): OK w ~25 s offline, 82 MB (debug;
  75 MB to silnik Godota w wersji debug). Manifest sprawdzony aapt2:
  `com.oculus.supportedDevices = quest3|quest3s`, kategoria VR, loader
  OpenXR. **Na goglach jeszcze nieuruchomione** - nie były podłączone.

Render na PC **da się sprawdzić** zrzutami (`screenshot.gd`). Gogli
nie - komfort VR i wydajność na Queście ocenia użytkownik.

## 7. Historia sesji

### 2026-11-07, sesja 1
- Zastany szkielet: tor, scena latania. Opisy odwoływały się do konkretnej
  starej gry - przepisane na "własna gra w gatunku".
- Auto arkadowe, potem realistyczne; ekran tytułowy (skrzynia,
  zawieszenie). Naprawione m.in.: winding jezdni, oś w przerwie,
  odwrotna przechyłka, szum ugięcia, błędy automatu, pętla dźwigu.

### 2026-11-07, sesja 2 (wieczór)
- ABS, TCS, ESP jako opcje menu; TCS przełączany w trakcie jazdy.
  ABS przerobiony na cykliczny (stały procent nie działał na lodzie).
  ESP dostał warunek nasycenia opon (był nadgorliwy).
- Nawierzchnie dry/wet/ice per odcinek toru, trawa pod torem.
- Napędy benzyna/diesel/elektryk i moc 90-350 kW w menu.
- Menu przerobione na listę opcji z `GameSettings.OPTIONS`.
- Sedan z lat 70. zamiast pudełka (nowe proporcje, kolizja w dwóch
  częściach), lakier w menu z podglądem na żywo.
- Pierwsze zrzuty ekranu ujawniły słońce świecące od dołu - naprawione.
- Trasa bez końca (generator, EndlessTrack, dźwigi, koniec jazdy,
  3-pasmowy start), dźwięk generowany w kodzie, wgrane na gogle.
- Meta, zegar, wyniki i rekord; kamera lotu z obrotem w goglach; testy
  nie zapisują ustawień (`persist`). Autopilot: meta 23,7 s, auto staje
  55 m przed końcem toru.
- Pierwsza jazda użytkownika na Queście 3 (gra działa: OpenXR Oculus,
  Adreno 740). Po uwagach: przezroczysty kokpit, czułość i krzywa drążka,
  menu z podmenu. `quest.sh` (jedno polecenie: testy/build/wgranie/start).
- Wgniecenia karoserii przy uderzeniach (prośba użytkownika, "kontynuujmy
  do uzyskania binarki" - zrobione wgniecenia wizualne i APK; skutki
  uszkodzeń dla jazdy jeszcze nie).
- Build na Questa 3: wtyczka, preset, mapa akcji, `tools/build.sh`
  (wzór z `~/dev/asteroids-vr`), własna ikona `icon.svg`; potem
  `quest.sh` w miejsce `tools/build.sh` (prośba: "skrypt, który buduje
  wszystko i pozwala wrzucić do questa") (bez niej eksport
  zgłasza błąd). `export_presets.cfg` usunięty
  z `.gitignore` - nie zawiera sekretów (keystore jest w ustawieniach
  edytora), a jest częścią projektu.

### 2026-11-08, sesja 3
- Strefy śliskie 150-400 m (mokro) i 100-250 m (lód) zamiast pojedynczych
  modułów; kolory nawierzchni od użytkownika. Naprawiony błąd: moduły
  z jawnym "dry" przerywały strefę (krótkie kawałki).
- Deszcz/mżawka nad strefami mokrymi (bez deszczu w tunelach), ruchome
  wycieraczki z kroplami na szybie, szum deszczu.
- Wskaźnik uszkodzeń przeniesiony jako LCD do prędkościomierza.
- Wąwóz jedynym trybem; ekran tytułowy w wąwozie; menu tytułowe
  i warsztatowe podążają za wzrokiem, na wysokości oczu.
- Prawy drążek kierownica, lewy biegi; nowy układ przycisków (A ABS,
  B ESP, X TCS, Y ograniczenie skrętu, kliki drążków: nowe auto / kamera).
- Akustyka otoczenia: echo od ścian wąwozu, pogłos tunelu, syk mokrych
  opon.
- Mech i bluszcz na zacienionych ("północnych") zboczach.
- Napęd 4x4, elektryk z silnikami w kołach, moc do 700 kW (dłuższe
  przełożenia, prędkościomierz do 400), typ opon w menu (całoroczne
  domyślnie). `engine_test` mierzy układy i 0-200; `RUNUP_CAP`
  dopomiarowany dla 500/700 kW.
- Repozytorium git na GitHubie (`canionRaid-vr`), pierwszy push.
- Potem: 7 strategii szału (domyślnie mieszane) i posiłki, do 20+ botów
  z jazdą "po szynie" daleko od gracza, oznaczenie zjazdów do warsztatu
  i na stację, tekstury freepbr (lokalnie, bez repo), README przepisane
  pod wąwóz. Naprawione: boty przy rozstawianiu traciły prędkość
  (`place()`), błąd tablicy typowanej przy otarciu o ścianę.
- Dalej w sesji 3: 1000 kW tylko dla silników w kołach, masa i spojler
  (nowa grupa menu "Nadwozie i opony"), podmenu "Szał drogowy botów"
  (przekraczanie, czas, uspokojenie, 3 strategie), pasy na dwa auta,
  tunele wiercone okrągłe i dwunitkowe, poprawiona ściana czołowa tunelu.
  `engine_test` naprawia auto między przejazdami (uszkodzenia się
  sumowały - kolejne auta coraz wolniejsze, ostatnie stało).
- Okna na morze (niska ściana ~100 m co 5 km), zielone tablice odcinków
  przeniesione ze ściany na pobocze.
- Naprawione dwa testy (assist, drive), które psuły się po cichu od
  poprzednich zmian (szczegóły w sekcji 6); wszystkie testy przechodzą.

### 2026-11-08, wątek w chmurze "Napraw drogę pod wodą i łąką"
- Błąd użytkownika: droga czasem pod wodą albo pod trawą. Przyczyna:
  generator sprawdzał wysokość tylko przed modułem, skocznie schodziły
  w trakcie poniżej y = 0 (płaska trawa z czasów toru na palach) i SEA_Y.
  Naprawione strażnikiem wysokości (`_guarded`, sekcja 5) i nowym
  testem `track_height_test` (w `quest.sh test`). Kod napisany bez
  Godota - lokalny agent musi uruchomić testy i sprawdzić na goglach.

### 2026-11-09, sesja 4 (noc, użytkownik śpi, pracowałem sam)
- Zgłoszenie: "gra się wyłącza, gdy w trybie wyższej rozdzielczości
  przełączyć nadwozie na concept car". Pomiar w goglach: sam ekran
  tytułowy przy 160% miał 19 kl./s, GPU 100%, ~950 MB pamięci GPU -
  przeładowanie modelu dobijało grę. Przy 100% przełączanie (co 3 s,
  wielokrotnie) nie zamyka gry. Poprawki: ekran tytułowy bez cieni
  słońca (jak scena jazdy), scena concept cara wczytywana raz
  (`StuntCar._concept_scene`), tekstury skompresowane (niżej). Przy 160%
  po poprawkach **nie sprawdzone w goglach** (gogle straciły śledzenie).
- Zgłoszenie: "zmiana rozdzielczości działa dopiero po restarcie".
  Przyczyna: dynamiczna rozdzielczość Meta - wyłączona; zmiana działa od
  razu (sprawdzone logiem gogli). Domyślnie 110% (pomiar), migracja v8.
- Główny zysk wydajności: kompresja VRAM i mipmapy tekstur skał
  (S1 100%: GPU 22,6 → 10,0 ms; 130%: 32 → 15,8 ms).
- adb przestał padać po buildzie (ustawienie edytora, sekcja 3).
- `user://bench.cfg` jednorazowy (Bench kasuje go po wczytaniu - plik
  zostawiony w goglach przełączał każde uruchomienie w tryb pomiaru);
  w pomiarze czerwony napis "BENCH S1" nad mapką (uwagi z chmury).
- Scalone z chmury: wnętrze sedana z epoki (PR #24), zrzuty obejrzane.
- Rano (użytkownik): "nowe lusterko nie działa, stare tak, ale
  nielogicznie umieszczone". Atrapa z nowego wnętrza ma teraz obraz:
  `StuntCar.mirror_mount` (+ chromowana tafla "MirrorFace" bez sceny
  jazdy), `xr_main._build_mirror` kładzie na niej szkło z kamery.
  Concept car dalej ma osobną ramkę nad deską.
- **Radio** (moduły z chmury: `car_radio.gd`, `radio_catalog.gd`,
  `radio_stations.gd`): 15 utworów z OpenGameArt w 3 stacjach
  (`audio/radio/`, 24 MB, **w repo** - decyzja użytkownika; licencje
  CC0/CC-BY/CC-BY-SA sprawdzone na stronach 2026-11-09, podpisy w
  `CREDITS.md`). `tools/fetch_radio.py` pobiera i konwertuje (ffmpeg);
  OpenGameArt dopisuje do nazw plików numer wersji (`_0`, `_6`) -
  wzorce mają `(_\d+)?`, podglądy (`audio_preview`) pomijane.
  `CarRadio` tworzy odtwarzacze przy pierwszym użyciu (`_setup`).
- **Menu pauzy** (`scripts/pause_menu.gd`, `PauseMenu extends
  GazeFollow`): lewy przycisk menu w jeździe (PC: Esc) - **wcześniej
  wracał od razu do ekranu tytułowego**, teraz pauza; wyjście do menu
  głównego jest pozycją pauzy. Ustalone z użytkownikiem: radio sterowane
  tylko z pauzy (wł./wył., stacja, głośność) - żaden przycisk w jeździe
  się nie zmienił. Pauza = `get_tree().paused`; `PROCESS_MODE_ALWAYS`
  mają menu, `CarRadio` i **XROrigin3D** (bez tego w pauzie zamarza
  śledzenie głowy i kontrolerów). W pauzie A zatwierdza, drążek
  góra/dół wybiera, w bok zmienia. "Co gra": napis nad radiem na desce
  sedana (concept: pod mapką) i krótki napis w HUD przy zmianie utworu.
  Test `tests/pause_test.gd`.
- Zgłoszenie: "auto praktycznie nie jest w stanie ruszyć pod górę"
  (gogle: benzyna 1000->700 kW, 4x4, automat, 2500 kg, TCS). Nowy
  `tests/hill_test.gd` (w `./quest.sh test`): pochylnia 15% i 35%, cztery
  konfiguracje - wszystkie wjeżdżają (700 kW: 186 / 141 km/h po 12 s;
  diesel 90 kW: 81 / 52). Log z gogli nadpisany, przyczyna niepotwierdzona;
  podejrzenie: pusty bak - 700 kW na pełnym gazie opróżnia 3,6 kWh
  w ~25 s (`fuel` liczony z chwilowej mocy). Pytanie do użytkownika
  w sekcji 9.
- Użytkownik: "w benzynie i dieslu brak paliwa - silnik gaśnie".
  `StuntCar.engine_running` (`_update_engine_state`): pusty bak - obroty
  opadają do 0, napęd i bezwładność silnika rozłączone (auto się toczy),
  dźwięk silnika cichnie (`car_audio`), po zatankowaniu znowu pracuje.
  Elektryk nie gaśnie. Test `tests/fuel_test.gd` (w `./quest.sh test`).
- Testy po tych zmianach: wszystkie OK (drive_test 0:23,48).
- **Przyczepność** (użytkownik: "w prawdziwych autach jest lepsza,
  zwłaszcza na suchym", "przy ruszaniu też"). Pomiary (`grip_test`,
  `launch_test`, oba w `./quest.sh test`): w zakręcie było dobrze
  (0,93-0,98 g), hamowanie i ruszanie za słabe. Naprawione:
  - ABS z wyprzedzeniem (`_tire_peak_force`): moment ograniczony do
    siły szczytowej opony x promień, korekta odchyłką poślizgu.
    Stary cykl "spuść/dołóż" oscylował (poślizg 0..0,64), auto z ABS
    hamowało dłużej niż z zablokowanymi kołami. 100-0: 51-55 m -> 40,5 m
    (całoroczne), 38 m (letnie).
  - Hamulce skalowane masą (`_brake_scale`): 2500 kg miało hamulce
    auta 1150 kg.
  - TCS z wyprzedzeniem (`_traction_cap`): stary regulator
    proporcjonalny trzymał poślizg 0,2-0,3 (za szczytem 0,11).
  - Sprzęgło międzyosiowe 4x4: limit `CENTER_COUPLING_SHARE` (35%)
    momentu na osiach zamiast stałych 900 Nm (przy 9700 Nm na 1. biegu
    buksował odciążony przód). 4x4 700 kW 2500 kg 0-100: 3,86 -> 3,56 s.
  - Tylny napęd 700 kW 1200 kg ~5 s do 100 to granica przyczepności tyłu
    (~0,6 g), nie błąd.
- `engine_test` tankuje przed każdym przejazdem (po zmianie "silnik
  gaśnie" diesel stał z obrotami 0).
- **Zasięg 20-30 km** (użytkownik 2026-11-09, wcześniej 10-15 km):
  `tank_kwh` 3,6 -> 7,5 (~25 km spokojnej jazdy; 700 kW na pełnym gazie
  wypalało 3,6 kWh w ~25 s).
- **Lądowanie z gazem** (użytkownik: "przy lądowaniu wcisnę gaz - auto
  się obraca, może i dobrze, ale sprawdź"). `tests/landing_test.gd`:
  w locie koła rozkręcały się do ~2x prędkości auta; bez TCS tylny
  napęd po lądowaniu na gazie obraca się o 180° (fizyka - zostaje).
  TCS działa teraz też w locie (`_tcs_air`: poślizg koła względem
  prędkości auta, jak czujniki obrotów w prawdziwym TCS) - z TCS
  kurs po lądowaniu trzymany.
- **Napęd na przód** (użytkownik: "w opcjach jest tył, nie ma przodu"):
  `drive_layout = "fwd"`, `_is_fwd()`, `_is_driven(w)`; LSD przedni.
  Sedan ma rozkład 50/50 - przy FWD przód odciążony przy ruszaniu
  (0-100 8,2 s, 35% podjazd ledwo), więc `apply_engine` przesuwa środek
  masy o `FWD_FRONT_SHIFT` (0,1 rozstawu) do przodu = ~60/40 jak auto
  z silnikiem z przodu. Ustawiać `drive_layout` przed `apply_engine`
  (GameSettings.apply_to_car tak robi). Teraz 180 kW: 0-100 6,9 s,
  0,93 g w zakręcie. Testy: launch, hill, grip, engine z FWD.
  (Przy okazji sprawdzone: przenoszenie ciężaru przy przyspieszaniu jest
  realistyczne; pozorne "za duże" było odczytem obciążeń przed osiadaniem
  auta po `place()`.)
- Zgaśnięty silnik: obroty opadają 3000 obr./min na s (było 1500 -
  przy większym baku fuel_test łapał jeszcze ~350 obr.).
- **Pliki na gogle**: `./quest.sh push PLIK... [-- KATALOG]` (domyślnie
  `/sdcard/Download/`, działa po Wi-Fi) i `./quest.sh pull`. MTP
  (Dolphin): gogle wystawiają przez USB tylko adb, dopóki użytkownik nie
  zatwierdzi w goglach "Zezwolić na dostęp do danych"; `adb shell svc usb
  setFunctions mtp,adb` nie działa (Quest wymaga zgody w goglach).
- Radio w goglach (użytkownik): "radio poprawia komfort jazdy",
  głośność względem silnika w porządku, wszystkie stacje pasują.
  Użytkownik lubi do auta **psytrance** - 4. stacja "Psy Wąwóz"
  (8 utworów CC-BY, lista zaakceptowana 2026-11-09; 7 z ccMixter,
  1 z OpenGameArt). **ccMixter odrzuca pobieranie skryptem (HTTP 403)** -
  nie obchodzić (nagłówki przeglądarki = obejście zabezpieczenia);
  użytkownik pobiera pliki w przeglądarce do `build/radio_in/`, potem
  `python3 tools/fetch_radio.py` je konwertuje. Brakujące pliki radio
  pomija (log "RADIO: brak pliku").
- Testy (`./quest.sh test`, po scaleniu): wszystkie OK; drive_test 95
  sport auto - przejazd 0:23,48.

### 2026-11-09, sesja 5 (popołudnie, użytkownik jeździ w goglach na kablu)

- Nowe opcje: Wytrzymałość x1-x10, Opływowość (sekcja 2). Testy:
  `durability_test` (w zestawie), `topspeed_test`, `coast_test`
  (puszczony gaz 0,10-0,12 g - w normie), `ramp_entry_test`
  (diagnostyka skoczni).
- Log: "PERF tempo gry" co 5 s i "INCYDENT" przy > 1,5 g / > 60°.
  Z logu gogli: tempo 95-100%, silnik uszkodzony 46-92% po wypadkach
  - przyczyna "wolnego" auta (razem ze startem zawsze z 90 kW).
- ESP: wykrywanie ślizgu osi z poślizgu łącznego, odcinanie napędu
  z kąta znoszenia tylnych opon, spadek od razu (niestabilność 700 kW
  przy 240 km/h - sekcja 8, pkt 00).
- Scalone PR #28 i #29 z chmury; **sprzęgło z #28 cofnięte** (hill_test:
  180 kW na 35% utykało na 13 km/h). Moc z menu w trasie bez końca
  i poprawki niespójności menu (inbox z chmury).
- Klucze Jamendo zapisane poza repo (sekcja 2).
- Do chmury (outbox `2026-11-09-niestabilnosc-i-autostrada.md`):
  przegląd modelu opon, specyfikacja trybu Autostrada, szukanie
  multimediów (pomysł użytkownika).

## 8. Kolejka zadań

Kolejność to kolejność próśb użytkownika; zapytaj, od czego zacząć.

000. **Tryb Autostrada** (ustalenia w sekcji 2, 2026-11-09). Plan
   etapami: (1) tryb w menu + generator odcinków samej autostrady
   (2+2 pasy, łagodne łuki, bez skoczni) i słupki co 100 m / km;
   (2) strefy scenerii co 50±10 km (równiny/pola/łąki/pustynia, góry,
   morze, wąwóz) - teren i obiekty z MultiMesh (`scenery.gd`);
   (3) miasta 1 km / 5 km z zabudową i strefą 30, ruch 3-5 aut/km
   z znikaniem poza wzrokiem; (4) rzadkie objazdy ze skocznią.
00. **"Dziwne wypadki" i "auto wolno się rozpędza" (użytkownik
   2026-11-09)** - stan dochodzenia:
   - Log z gogli (linia "PERF tempo gry", co 5 s): **tempo 95-100%** -
     gogle NIE zwalniają fizyki. Za to **silnik był uszkodzony 46-92%**
     (-35..-70% mocy) po uderzeniu 171 -> 7 km/h i twardych lądowaniach.
     Stąd "130 kW ledwo ponad 150".
   - `tests/ramp_entry_test.gd` (diagnostyka, nie w zestawie): skocznia
     z generatora, wjazd 80/110/140 km/h z gazem i bez. Przy prędkości
     dużo wyższej niż projektowa auto przelatuje lądowisko, w locie
     obraca się nosem w dół (do -28°), ląduje na przodzie i wbija się
     zderzakiem (4x4 140 km/h bez gazu: 122 -> 11 km/h w 0,25 s) -
     uszkodzony silnik. Do rozważenia z użytkownikiem: czy skocznie mają
     być bezpieczniejsze przy nadmiarze prędkości (dłuższe lądowisko).
   - Linia **"INCYDENT"** w logu (xr_main `_watch_incident`): przy
     > 1,5 g opóźnienia albo przechyle > 60° - stan auta, pedały, koła,
     najmocniejszy kontakt nadwozia (`StuntCar.last_hit`: ścieżka
     obiektu, impuls, punkt), odcinek, dystans. Po następnej jeździe
     `./quest.sh log` (najlepiej zapis do pliku na kablu - bufor logcat
     w goglach szybko się nadpisuje) i przeczytać.
   - **Niestabilność przy dużej prędkości**: 700 kW tył, ~240 km/h,
     kierownica 0 - auto samo wchodzi w dryf (yaw podwaja się co
     ~0,15 s), w kierunku -Z idealna symetria to ukrywa (jedzie prosto do
     347 km/h), w +X zaokrąglenia wystarczą. Tylne koła na granicy
     przyczepności wzdłużnej (TCS trzyma szczyt) nie mają zapasu bocznego
     (poślizg łączny); podwozie ~neutralne (sztywność opon ∝ obciążeniu).
     ESP poprawione (poślizg łączny osi zamiast samego kąta, odcięcie
     napędu z kąta znoszenia tylnych opon, spadek od razu) - pomaga
     częściowo; zostaje ustalony dryf z ~0,8 g bez skrętu. Pomysły: szersze
     tylne opony przy dużej mocy (jak w prawdziwych autach), zbieżność
     tyłu, TCS z zapasem bocznym. Diagnostyka: skrypt
     `_dbg_top.gd` (był w tests/, usunięty) - jazda w +X z (3000, 3000).

00. **Wydajność - stan 2026-11-09** (plan: `docs/PERF_PLAN.md`, inbox
   `2026-11-08-plan-wydajnosci.md`). Pomiary sprzed tej daty są
   nieważne (dynamiczna rozdzielczość Meta). Do zrobienia przy
   zapalonym świetle (gogle muszą śledzić): seria
   `tools/bench_quest.sh` S1-S5 przy 100/110/130%, A/B `rock_simple`,
   `tunnel_lights`, `rain`, `mirror`; sprawdzić concept car przy 160%
   (przełączanie w menu - wcześniej zamykało grę). Cel użytkownika:
   160% płynnie. Pomysły na shader skał: mapowanie dwupłaszczyznowe
   (biplanar, 2 odczyty zamiast 3), krótszy `normal_dist`, mech bez
   mapy normalnych. Uwaga: ekran tytułowy przy 100% miał 29 ms GPU
   jeszcze przed kompresją tekstur - po kompresji nie mierzony.

0. **PILNE, odłożone na następną sesję (użytkownik, 2026-11-08):
   "po odcinku 8 skończyła mi się trasa"** - na goglach, na APK z sesji 3
   (już z oknami na morze, zmianami generatora: strefy śliskie, `rain`,
   `roof`). Nie zbadane. Log z gogli zebrany zaraz potem
   (`build/logs/trasa_po_odcinku_8.log`, od 00:06) nie zawiera żadnego
   błędu skryptu Godota (tylko komunikaty systemu: aplikacja zatrzymana,
   bez fokusu) - przy następnej próbie zbierać
   `./quest.sh log` w trakcie jazdy. Podejrzenia do sprawdzenia:
   błąd skryptu przy budowie sekcji 9/10 (np. `_build_sea`,
   `_canyon_profile` z `sea_factor`, `_push` ze strefą), sekcja 10 to
   stacja paliw (`service`), ziarno losowe - `endless_test` z kilkoma
   ziarnami do 12+ odcinków (`generator_test` sprawdza tylko generator,
   nie budowę geometrii) i sprawdzenie `EndlessTrack.update_progress`.
0a. **Concept car - wstawiony, do oceny w goglach.** Zostało: wgniecenia
   na concept carze (na razie brak), wycieraczki i krople na jego szybie
   (ukryte), dach od środka/przezroczystość pod jego materiały (teraz
   jedna wartość dla wszystkich), prowadzenie (patrz niżej), położenie
   mapki trasy i lusterka w jego kokpicie (przesunięte o `cockpit_offset`,
   nieskalibrowane), boty dalej sedany (`car_bot.glb` gotowy, nieużyty).
0b. Do przetestowania w goglach z użytkownikiem (instaluje razem z nim):
   nowe opcje auta, strategie szału, tunele, szersza jezdnia.
   Też: wydajność z wieloma botami na Queście, widoczność mchu, nowe
   znaki zjazdów.

1. **Dalsze wrażenia z gogli**: czy przezroczystość, czułość drążka,
   meta i kamera lotu działają; płynność; komfort przy skokach.
   APK z sesji 3 jest wgrany (2026-11-08). Do sprawdzenia w goglach:
   deszcz i wycieraczki, LCD uszkodzeń, menu za wzrokiem, nowe przyciski
   i biegi na lewym drążku, pogłos/echo (nikt go jeszcze nie słyszał),
   okna na morze, mech.
2. **Dalej z wąwozem**: estakady na palach z przerwami nad dnem wąwozu
   (spadnięcie = lądowanie na dnie), potem pętle i beczki (nowa rama
   toru - obecna yaw/pitch nie obsługuje pionu i jazdy do góry nogami).
   Zakończenie początku wąwozu za linią startu (teraz otwarte). Budowa
   sekcji w wątku (szarpnięcie na Queście?), fazowane krawędzie karoserii.
   Autopilot testowy w wąwozie jedzie czysto (2,9 km, 0% uszkodzeń) -
   brak testu uderzeń w ściany w jeździe (jest tylko `dent_test`).
   Pierwotny opis: (prośba: "jak river
   raid generować trasę podzieloną na odcinki, generowaną programowo, tak
   by poziom trudności wymagał coraz większych prędkości i przyspieszeń").
   River Raid to tylko odniesienie do mechaniki (odcinki, rosnąca
   trudność) - nie kopiujemy niczego z gry. Plan (nie zaczęty):
   - generator z ziarnem (seed) składa trasę z modułów: prosta, łuk
     z przechyłką, rampa + przerwa, garb, dołek, szykana, zwężenie,
     plamy mokrej nawierzchni i lodu;
   - odcinki (sekcje) z rosnącym poziomem; między nimi punkt kontrolny
     (brama) - dźwig cofa najwyżej do niego;
   - **skoki liczone z balistyki**: dla kąta wybicia θ i spadku lądowiska
     H wymagana prędkość v² = g·L² / (2·cos²θ·(L·tanθ + H)); generator
     dobiera długość przerwy L do prędkości docelowej poziomu (np. 60 →
     150 km/h), a rozbieg skraca tak, żeby wymagał coraz mocniejszego
     przyspieszania (z osiągów auta: 0-100 z `engine_test`);
   - po złożeniu: walidacja (sprawdzenie skoków na prawdziwych próbkach
     toru) i test autopilotem;
   - menu: wybór trasy (pokazowa / generowana), ziarno, liczba odcinków;
   - do decyzji użytkownika: skończona liczba odcinków czy bez końca
     (wtedy tor dobudowywany kawałkami przed autem i usuwany za nim).
   Komfort kokpitu, pozycja `seat`, czytelność menu, kamera związana
   z przechyłami auta (ewentualnie opcja "horyzont stały"), strojenie
   fizyki na wyczucie.
3. **Wnętrze sedana - z epoki (ustalone, 2026-11-08)**. Użytkownik
   w wątku w chmurze: "kierownica jest strasznie siermiężna, czy może
   bardziej wyglądać jak w fiacie 125?" - włoski sedan przełomu lat 60.
   i 70., nie nowoczesny SUV. Zrobione w chmurze (PR #24, scalony,
   `_build_interior` w `stunt_car.gd`; rendery i testy lokalnie OK
   2026-11-09). Zostało: ocena w goglach (czy nic nie zasłania drogi,
   czy klatka się trzyma). Na zegarach dalej: moc chwilowa, odometr.
4. **Robot-kierowca w stylu art déco lat 20.** Gracz jest robotem.
   Dwa widoki do wyboru: z fotela kierowcy (widzi swoje metalowe ręce
   na kierownicy) albo z fotela pasażera (robot prowadzi obok).
   Użytkownik zaproponował robota z "Metropolis" (1927) jako
   "domenę publiczną" - **to prawda tylko w USA**. W UE (użytkownik jest
   w Polsce) prawa trwają 70 lat od śmierci twórców: Fritz Lang
   i projektant robota Walter Schulze-Mittendorff zmarli w 1976 r.,
   więc chronione do końca 2046. Ustalenie: **własny robot w stylistyce
   epoki** (polerowany metal, geometria art déco), nie kopia
   Maschinenmensch.
5. **Udźwiękowienie - pierwsza wersja ZROBIONA** (sekcja 5). Czeka na
   opinię użytkownika (brzmienie, głośność). Pierwotny plan: dźwięk
   generowany programowo. Na Queście rozsądne: `AudioStreamGenerator`,
   silnik jako kilka oscylatorów z harmonicznymi zależnymi od
   `engine_rpm` i obciążenia, szum opon z `wheel.slip`, wiatr z prędkości,
   uderzenia z `landed`. Próbkowanie 22 kHz, bufor ~0,1 s, synteza
   wektorowo albo w GDExtension, jeśli GDScript okaże się za wolny.
   Elektryk: wysoki ton falownika zamiast silnika spalinowego.

6. **Powtórki** - użytkownik o nich wspomniał ("ewentualnie na
   powtórkach, o których jeszcze nie rozmawialiśmy"). Nie ustalono nic.
   Naturalny sposób: nagrywanie transformacji auta i stanu kół co klatkę
   fizyki, odtwarzanie z kamer zewnętrznych.

7. **Skutki uszkodzeń dla jazdy** (wgniecenia wizualne już są, sekcja 5):
   krzywe zawieszenie po twardym lądowaniu ściąga auto (z `landed`
   i dobicia odboju), uszkodzony silnik traci moc, pęknięta szyba,
   odpadający zderzak, naprawa (`repair()`) - przy dźwigu albo w menu.
   Pod spodem wgniecenia przy lądowaniach się nie liczą (impuls rozkłada
   się na koła) - do rozważenia przy modelu uszkodzeń.

Propozycje (do uzgodnienia):
- Globalna opcja "pogoda" (cały tor mokry / oblodzony) jako nadpisanie
  nawierzchni odcinków.
- Własne trasy projektowane pod VR, wybór trasy w menu, domknięcie
  w pętlę.
- Etap 4: uszkodzenia z sygnału `landed`.
- Etap 5: przeciwnik AI (punkt wyjścia: autopilot z `drive_test`).
- Wydajność na Queście: 4 sfery + `get_rest_info` × 240 Hz, liniowe
  `nearest_sample`. Zmierzyć na sprzęcie.
- Przełączanie ABS i ESP w trakcie jazdy, jak TCS (wolny jest jeszcze
  klik lewego drążka).

## 9. Otwarte pytania do użytkownika

- (2026-11-09) Czy przy "nie rusza pod górę" bak był pusty i gdzie to
  było (zwykły podjazd / rozbieg skoczni / po dźwigu)? (Zużycie:
  ustalono zasięg 20-30 km, sekcja 7.)

- Styl wizualny: propozycja low-poly z płaskim cieniowaniem.
  Niepotwierdzone.
- Czy ABS i ESP też przełączać w trakcie jazdy, i pod jakimi przyciskami?
- Trasa generowana: skończona liczba odcinków czy bez końca? Trudność
  zależna od mocy wybranego auta czy stała?
