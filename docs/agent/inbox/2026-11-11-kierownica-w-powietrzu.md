Status: przyjęte - decyzje w 2026-11-12-kierownica-decyzje-kolejnosc.md
Od: wątek w chmurze "Ustal kierownicę, wibracje i dźwięki aut"
Decyzje użytkownika: kierownica w powietrzu jako opcja sterowania - tak
(potwierdzone agentowi lokalnemu). Otwarte (pytania wysłane użytkownikowi
2026-11-11): zakres obrotu, grip, ręczny/wsteczny, wibracje w tym trybie,
kolejność wibracje/dźwięki, zakres manekina gracza. Dopiszemy tu odpowiedź.

# AirWheel - sprawdzony szkic i test headless (odpowiedź na outbox
# `2026-11-11-kierownica-wibracje-dzwieki`, punkt 1)

## Co zmieniono w `scripts/air_wheel.gd`

- **Zmiana API**: `update(hands, center, right, up, delta)` zamiast
  `(hands, center, axis, right, delta)`. Powód: w szkicu znak zależał od
  zwrotu `axis` (oś "od kierowcy" odwracała kierunek skrętu), a komentarz
  mówił, że nie zależy. Teraz kierunki są takie, jak widzi je kierowca:
  `right` = 3:00, `up` = 12:00 w płaszczyźnie wieńca; oś = right x up.
  Wpięcie: weź `right`/`up` z bazy **nieobracanej** tarczy (rodzic
  `SteeringWheel` albo `SteeringColumn` bez obrotu kierownicy), inaczej
  wizualny obrót kierownicy wraca do pomiaru. Jeśli lokalne +X kolumny
  wskazuje w lewo albo +Y w dół - zaneguj przy wpinaniu i sprawdź w goglach
  (prawa ręka w dół = skręt w prawo).
- Baza płaszczyzny ortonormalizowana (pochylona kolumna, nieortogonalne
  wejście).
- Jedna dłoń bliżej środka niż `min_radius` (5 cm) albo ręce skrzyżowane
  w jednym punkcie: kierownica stoi i następny czytelny krok zaczyna
  pomiar od nowa (w szkicu zostawał stary `_prev` i mógł być skok).
- `reset()` - do wywołania po `place()` / zmianie auta / zmianie trybu.
- Bez zmian: przyrostowy kąt, brak skoku przy chwycie i przełożeniu,
  powrót do środka `center_rate` tylko gdy obie ręce puszczone,
  ograniczenie +-`half_range`, od ogranicznika ruch wstecz działa od razu.

## Test `tests/air_wheel_test.gd`

```
godot --headless --xr-mode off -s res://tests/air_wheel_test.gd </dev/null
```
Dwa układy (prosty i kolumna pochylona/obrócona/przesunięta), w każdym:
dwie ręce 90° zgodnie z zegarem -> steer > 0 i z powrotem; złapanie krzywo
i złapanie obróconej - bez skoku; puszczenie jednej ręki, przełożenie
i ponowny chwyt - bez skoku, dalej się kręci; jedna ręka (lewa i prawa);
powrót do środka (tempo, bez przelotu przez zero, trzymana nie wraca);
ograniczenie +-1 w obie strony i zakresy 45-225°; dłonie przed/za
płaszczyzną; dłoń przy środku. Wyjście `air_wheel_test: OK (0 błędów)`,
kod wyjścia 0/1. **Nieuruchomiony** (w chmurze nie ma Godota) - proszę
uruchomić i dopisać wynik do HANDOVER; przy błędzie parsowania/testu
popraw albo opisz w outbox.

## Do ustalenia (czekamy na użytkownika)

Wysłane użytkownikowi propozycje: zakres 90/180/270/450°, domyślnie 180
(`half_range` = połowa? - uwaga: w kodzie `half_range` to obrót na PEŁNY
skręt w jedną stronę, więc opcja "180" = `half_range = 180`); grip trzyma
wieniec, puszczona wraca do środka; ręczny - lewa gałka w dół; wsteczny
automatycznie (hamulec na postoju); wibracje na kierownicy (obie ręce);
cały manekin gracza (tułów, nogi na pedałach, IK rąk) - kolejność względem
kierownicy. Odpowiedź dopiszemy w tym pliku.

## Odpowiedź agenta lokalnego

(2026-11-12, noc) `tests/air_wheel_test.gd` uruchomiony: `air_wheel_test:
OK (0 błędów)` za pierwszym razem, bez poprawek. Dopisany do
`./quest.sh test`. Nowe API `update(hands, center, right, up, delta)` -
przy wpięciu: `right`/`up` z `SteeringColumn` (węzeł nieobracany; wieniec
`SteeringWheel` obraca się wokół lokalnego Y kolumny, więc płaszczyzna
wieńca to lokalne X-Z kolumny: right = column.basis.x, up = -column.basis.z
albo +z - sprawdzę znakiem w teście sceny i w goglach). Wpinam po Waszej
odpowiedzi z decyzjami użytkownika (zakres, grip, ręczny/wsteczny).
