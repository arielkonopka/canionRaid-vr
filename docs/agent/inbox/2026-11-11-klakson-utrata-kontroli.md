# Boty tracą panowanie po klaksonie

Status: nowe
Od: wątek w chmurze "Napraw utratę kontroli botów po klaksonie"
Decyzje użytkownika: zgłoszenie 2026-11-11 - "Boty, gdy na nie zatrąbić,
często tracą kontrolę nad jazdą... Zdarza się, że tylko od tego mają
wypadek". Reakcja ma być wiarygodna fizycznie, bez samorozbijania.

## Diagnoza (z kodu, bez uruchamiania)

`player_horn()` → `BotDriver.enrage("horn")` dla wszystkich botów w 250 m.
W tym samym kroku fizyki:

1. `rage = 1` od razu, więc `target_off` skacze z osi pasa na cel taktyki
   (np. `p_off ± lane_w·1,2` albo pas gracza) - skok o 3-5 m.
2. Człon toru w `car.steer` to `-(offset - target_off) * 0.22` niezależnie
   od prędkości. Przy 100 km/h (max kąt z ograniczeniem skrętu ~16,6°)
   błąd 1 m daje ~3,6° skrętu, czyli kinematycznie ~2 g bocznie; skok
   o 4 m to pełne wychylenie. W spokoju działało, bo błąd to centymetry.
3. `target_kmh` skacze o +30..45 km/h (albo -25 przy "ram" za graczem),
   a `apply_engine` daje od razu ≥ 350 kW - pełny gaz w trakcie skrętu.
4. Ten sam skok robi zmiana taktyki co 8-14 s i przejście gracza na drugą
   stronę bota (`side` w block/zigzag/ambush) - stąd też "dziwne" poślizgi
   w trakcie pościgu, nie tylko po klaksonie.

## Poprawka (na tej gałęzi, `scripts/bot_driver.gd`)

To umiejętność kierowcy, nie ukryta pomoc: opony, masa i bezwładność bez
zmian (zgodne z zasadą "boty mogą oszukiwać napęd, nie opony").

- Czas reakcji `RAGE_REACT` 0,5 s, potem `_aggr` narasta 0→1 przez
  `RAGE_RAMP` 1,5 s; plan szału (tor i prędkość) miesza się z jazdą
  spokojną przez `_aggr`. Gaz w tym czasie ≤ 0,3 + 0,7·`_aggr`.
  "Nauczka" hamowaniem (`_brake_pulse`) dopiero przy pełnym `_aggr`.
  Start w `enrage()` (tylko świeży szał) i `feud_with()`.
- Cel w poprzek drogi wygładzony: `_tgt_off_s` idzie do `target_off`
  z prędkością `LAT_RATE` 2 m/s (pas 3,5 m w ~1,8 s). Reset po zejściu
  z szyny.
- Człon toru: wzmocnienie ×clamp(12/v, 0,25, 1) i ograniczenie do kąta
  kinematycznego na `LAT_GRIP` = 0,5 μ·g (atan(a·L/v²), z tym samym
  ograniczeniem skrętu co auto). Człon kursu (`head_err * 2.5`) bez zmian,
  więc łuki drogi nadal są brane jak dotąd.

- Pierwsza taktyka po świeżym szale zależy od położenia gracza
  (użytkownik 2026-11-11: "Musi też wiedzieć, czy gracz jest przed, czy
  za botem"): gracz za botem → block / zigzag / ambush (bot zostaje przed
  nim), gracz przed botem → ram / pit / pincer (pościg). Dotąd taktyka była
  losowa, więc bot przed graczem mógł dostać "ram" i z rozpędu ostro
  hamować ze zjazdem na drugi pas. Tylko przy strategii "mixed"; potem
  zmiany taktyki co 8-14 s jak dotąd. `_pick_opening_tactic()` w `enrage()`.

## Test

Nowy `tests/horn_control_test.gd` (wąwóz, z `-- autostrada` autostrada):
4 boty 70-200 m przed graczem, klakson, 10 s. Błąd, gdy któryś bot obróci
się > 60° przy > 20 km/h, wyjedzie > 1 m poza jezdnię albo się przewróci.
Wypisuje też największe przyspieszenie boczne. Napisany bez Godota -
popraw, jeśli coś nie pasuje (np. pas startowy botów na autostradzie).

Prośba do agenta lokalnego:
1. Uruchom `horn_control_test` na `main`/`boty-szal-tekstury` **przed**
   poprawką (czy odtwarza problem) i **po** niej, oba tryby.
2. `bot_rage_test`, `horn_test`, `feud_test`, `feud_play_test`,
   `bot_drive_test`, `drive_test` - czy szał nadal goni i trafia, a jazda
   spokojna trzyma pas (zmienione wzmocnienie toru działa też w spokoju
   przy > 12 m/s).
3. Jeśli pościg zrobi się za "miękki", podnieś `LAT_GRIP` (0,6-0,7) albo
   `LAT_RATE`, zamiast wracać do skoku. Wyniki do HANDOVER.md i tu.

Otwarte dla użytkownika (nie wdrożone): rzadka cecha "nerwus" - ułamek
botów reaguje na klakson paniką (gwałtowne hamowanie z odbiciem) i może
wtedy naprawdę wpaść w poślizg. Tylko jako jawna, rzadka cecha.
