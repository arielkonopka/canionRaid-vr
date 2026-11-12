Od: agent lokalny, 2026-11-11 wieczór
Do: wątek projektu w chmurze
Status: do ustalenia z użytkownikiem (prośba o specyfikację)

# Trzy pomysły użytkownika: kierownica w powietrzu, wibracje, dźwięki innych aut

Użytkownik (2026-11-11, dosłownie): "zastanawiam się, czy możemy dodać
tryb sterowania 'powietrzną kierownicą'" oraz "no i reaktywność drążków,
powinny reagować na uderzenia, i różne takie, brakuje też dźwięków innych
pojazdów i efektów, gdy się je mija, jak dopplera...".
Stan dziś: sterowanie drążkiem (`xr_main._read_drive_input`), brak
wibracji (nigdzie `trigger_haptic_pulse`), boty i auta z naprzeciwka bez
dźwięku (`StuntCar._ready`: bot bez CarAudio - koszt syntezy w GDScript).

## 1. Kierownica w powietrzu (nowa wartość opcji Sterowanie -> Kierownica)

Propozycja agenta:
- kąt = obrót linii między dłońmi wokół osi kolumny kierowniczej
  (`StuntCar` ma `_steering_wheel`, przełożenie 14:1 - wizualna kierownica
  obraca się 1:1 z rękami); jedną ręką - położenie dłoni na wieńcu;
- pełny skręt kół przy obrocie kierownicy o ±180° (może opcja 90-450°);
- gaz/hamulec na spustach bez zmian; drążki wolne: biegi jak dziś (drążek
  w górę/dół albo A/X), ręczny - przycisk B lub drążek w dół, wsteczny -
  automat (hamulec na postoju); grip - "trzymanie" kierownicy (puszczona
  wraca do zera, sama się prostuje z prędkością jak prawdziwa);
- tryb "Wg przyczepności" dalej działa (limit kąta kół).
Pytania do użytkownika: zakres obrotu, czy kierownica ma się sama
prostować, mapowanie ręcznego/wstecznego.

## 2. Wibracje kontrolerów ("reaktywność drążków")

Propozycja: `XRController3D.trigger_haptic_pulse(...)`, opcja "Wibracje"
(wył./słabe/mocne). Zdarzenia: zderzenie (siła z impulsu, `last_hit`),
lądowanie, krawężnik / tarka / szuter (nawierzchnia pod kołami), ABS
(ręka hamulca, pulsowanie), poślizg kół napędzanych / TCS (ręka gazu),
ogranicznik obrotów, lekka faktura drogi rosnąca z prędkością. W trybie
kierownicy - obie ręce (siła na kierownicy z bocznej siły przednich kół?).

## 3. Dźwięki innych aut i Doppler

Propozycja: kilka najbliższych aut (np. 4 w promieniu ~80 m) dostaje
AudioStreamPlayer3D z zapętlonymi próbkami (silnik, opony, wiatr) i
`pitch_scale` z obrotów/prędkości - bez syntezy w GDScript (koszt).
Doppler: `AudioStreamPlayer3D.doppler_tracking` + kamera z
`doppler_tracking` (wbudowane w Godota). Mijanie aut z naprzeciwka:
krótki "szum przelotu" zależny od prędkości względnej. Klakson botów
już jest (3D?). Do sprawdzenia: koszt audio na Queście (bench).

Prośba: dopracujcie z użytkownikiem zakres i kolejność (który pierwszy),
odpowiedź w `inbox/`. Agent lokalny zrobi i zmierzy na goglach.

## Dopisek (2026-11-11, później) - kierownica: potwierdzone, przekazane Wam

Użytkownik: "tak, i powietrzna kierownica, jako opcja sterowania zamiast
manetką", potem: "czy możesz przekazać to części chmurowej?".

Agent lokalny zaczął i zatrzymał się na szkicu (commit z tym dopiskiem):
`scripts/air_wheel.gd` - `AirWheel` (RefCounted, bez zależności od
sceny): `update([[poz_lewej, trzyma], [poz_prawej, trzyma]], środek,
oś_kolumny, w_prawo, delta) -> steer -1..1`; kąt przyrostowo (bez skoku
przy złapaniu / przełożeniu ręki), dwie ręce - obrót linii między
dłońmi, jedna - obrót dłoni wokół środka, puszczona wraca do środka
(`center_rate`), `half_range` = obrót na pełny skręt. Nieprzetestowany.

Prośba do Was (zgodnie z zasadą: nowe, odizolowane pliki + testy headless):
1. Sprawdźcie/dokończcie `AirWheel` i dopiszcie test headless
   (`tests/air_wheel_test.gd`): skręt w prawo = obrót zgodny z ruchem
   wskazówek z widoku kierowcy -> steer > 0; złapanie i przełożenie ręki
   bez skoku; jedna ręka; powrót do środka; ograniczenie do +-1.
2. Ustalcie z użytkownikiem: zakres obrotu (propozycja opcji 90/180/
   270/450°, domyślnie 180), czy grip ma "trzymać" kierownicę, przyciski
   ręcznego (propozycja: lewy drążek w dół) i wstecznego (automat:
   hamulec na postoju), czy wibracje na kierownicy w tym trybie.
Wpięcie (agent lokalny, po Waszej odpowiedzi): opcja Sterowanie ->
Kierownica: "w powietrzu", `xr_main._read_drive_input` (środek i oś
z węzła `SteeringColumn/SteeringWheel` auta - oś obrotu to lokalne Y
kolumny; w prawo - lokalne X), wizualna kierownica obracana 1:1 kątem
`AirWheel.angle` zamiast 14x kąta kół.

## Dopisek - ręce gracza jako ręce manekina

Użytkownik: "czy ręce będą żółte, gdyż też jestem manekinem w grze?".
Dziś kontrolery są w grze niewidoczne (XRController3D bez siatki).
Propozycja agenta: dłonie + przedramiona wycięte z tego samego modelu
(`tools/prepare_dummy.py`, kości hand.* / f_* / forearm.*), palce
w chwycie, przypięte do kontrolerów; w trybie kierownicy obejmują
wieniec, przy drążku - manetkę; palce lekko zaciskane spustem/gripem.
Otwarte do ustalenia z użytkownikiem: czy także tułów i nogi manekina
w fotelu gracza (widoczne przy spojrzeniu w dół) - więcej pracy
(ramiona do kontrolerów = IK, ryzyko dziwnych łokci). Agent zrobi
dłonie (Blender jest lokalnie), gdy ustalicie zakres.

## Dopisek - gracz jako cały manekin (życzenie użytkownika)

Użytkownik: "fajnie by było się widzieć jako ten manekin, co ma nogi na
pedałach gazu i hamulca :)". Czyli: tułów i nogi manekina w fotelu
gracza, prawa stopa na gazie/hamulcu zgodnie ze spustami (przenosi się
między pedałami), lewa przy sprzęgle (w manualu wciska przy zmianie
biegu), ręce prowadzone do kontrolerów (IK dwóch kości: ramię-łokieć-
dłoń; dłonie na wieńcu w trybie kierownicy).
Technicznie: potrzebny model ze szkieletem (Skeleton3D) - eksport glTF
z Blendera wymaga `python3-numpy` - zainstalowany, eksport ze szkieletem
sprawdzony (2026-11-11), rig
Rigify z modelu jest. Widok z kokpitu: głowa manekina ukryta (kamera
w jej miejscu), ciało z warstwy widocznej w kokpicie.
Prośba: ująć w specyfikacji razem z kierownicą i dłońmi (kolejność,
zakres), odpowiedź w inbox.

## Dopisek 2026-11-12 - decyzja użytkownika

"chciałbym dłonie w powietrzu, jako alternatywne sterowanie" (użytkownik
ma dziś migrenę, nie pojeździ). Agent lokalny wpina kierownicę w powietrzu
z dłońmi manekina, szczegóły na proponowanych wartościach (±180°, grip
trzyma wieniec, puszczona wraca, ręczny - lewy drążek w dół, wsteczny -
hamulec na postoju). Jeśli użytkownik w rozmowie z Wami zdecyduje inaczej -
dopiszcie w inbox, poprawię.
