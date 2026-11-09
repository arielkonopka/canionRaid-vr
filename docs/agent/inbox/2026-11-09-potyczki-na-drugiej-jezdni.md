# Potyczki botów widoczne z drugiej jezdni autostrady

Status: nowe
Od: wątek w chmurze "Zaprojektuj nowe strategie botów road rage" (2026-11-09)
Decyzja użytkownika (2026-11-09): "w związku z tym, że na końcu chyba chcę
zrobić jazdę autostradą na całej długości, to np. furia drogowa między
botami mogłaby być widoczna, dla samochodów jadących w drugą stronę."

## Pomysł

Auta z naprzeciwka (`xr_main._update_oncoming`) są kinematyczne, za
barierą, mijają gracza z prędkością względną 250+ km/h. Gracz widzi je
3-6 s, więc pełna fizyka byłaby marnotrawstwem (ustalenie: daleko / poza
zasięgiem gracza bot może się upraszczać). Dlatego potyczka na drugiej
jezdni jest **reżyserowana**: dwa auta z puli oncoming odgrywają krótką
scenkę z klatek kluczowych, a klimaks wypada ~180 m przed graczem.
Koszt: kilka interpolacji na klatkę, zero fizyki.

## W tym PR-ze (odizolowane, czysta logika + test)

- `scripts/oncoming_skirmish.gd` (`OncomingSkirmish`), cztery scenki:
  - `cut` - A wyprzedza B, zajeżdża mu drogę i hamuje, B ucieka na prawy
    pas (klakson, dym opon);
  - `swipe` - A dwa razy uderza B bokiem, B szoruje o barierę (iskry);
  - `pit` - A trąca tył B, B obraca się o 200° i staje na poboczu;
  - `wreck` (rzadko, waga 1 z 9) - B po uderzeniu wjeżdża w barierę
    i wybucha, potem `hidden`.
- `tests/oncoming_skirmish_test.gd`: każda scenka się kończy i wysyła
  swoje zdarzenia, brak przenikania aut poza chwilą uderzenia (dla
  najszerszej i najwęższej dozwolonej jezdni), pit obraca B, wrak chowa
  B, `trigger_gap`, losowanie z wagami. Geometrię sprawdziłem w chmurze
  odpowiednikiem w Pythonie (bez Godota) - **proszę uruchomić test**:
  `godot --headless --xr-mode off -s res://tests/oncoming_skirmish_test.gd </dev/null`

## Integracja (do zrobienia lokalnie, opis też w nagłówku pliku)

1. Tylko na autostradzie i gdy `OncomingSkirmish.fits(width)` (≥ 13 m;
   pasy w klatkach są względne, na wąskiej jezdni auta by nachodziły).
2. Gdy na drugiej jezdni przed graczem jest miejsce (np. co 1-2 km
   autostrady, nie częściej niż jedna naraz): `sk = OncomingSkirmish.random(rng)`,
   dwa auta z puli oncoming, B w `dist_b`, A w `dist_b + sk.gap`.
   Jeśli FeudDirector ma wrogie gangi - pomalować auta ich kolorami
   (spójność z potyczkami na naszej jezdni).
3. Start (`step` zaczyna płynąć), gdy `dist_b - dist_gracza ≤
   sk.trigger_gap(v_gracza + v_bazowe)`. Do startu oba jadą jak zwykłe
   auta z naprzeciwka (lane 0 i -1, v bazowe).
4. Co klatkę: `ev = sk.step(delta)`;
   - B: `dist_b -= v_bazowe * sk.state_b["v"] * delta`;
   - A: `dist_a = dist_b + sk.gap` (**nie** całkować A osobno: odstęp
     liczy scenka przy `V_REF` 35 m/s, dzięki czemu zbliżenia wyglądają
     tak samo przy 110 i 140 km/h);
   - dla obu: `_oncoming_xf(dist, state["lane"], r)`, potem obrót bazy
     o `deg_to_rad(state["yaw"])` wokół osi Y auta i przechył
     `state["roll"]` wokół osi Z; `state["hidden"]` → auto do puli.
5. Zdarzenia (`{"type", "car"}`): `horn` - klakson auta, `hit` - dźwięk
   uderzenia + wgniecenie z boku (jeśli łatwo), `sparks` - iskry przy
   barierze, `smoke` - dym opon, `boom` - `Explosion` jak przy botach.
6. Po `sk.done`: oba auta wracają do zwykłego ruchu z naprzeciwka (B
   po `pit` stoi na poboczu - można go zostawić do minięcia i oddać do
   puli, gdy jest za graczem).
7. **Bez punktów** - gracz nie może uczestniczyć (jest za barierą).

## Związek z FeudDirector (PR #40)

Na naszej jezdni potyczki są fizyczne i zależą od `in_sight`. Do
"widzi gracz" przy `in_sight` warto użyć tego samego stożka co
`TrafficZone` (`VIEW_DIST`, `VIEW_HALF_ANGLE`), a nie samej odległości -
wtedy potyczki z przodu są częstsze niż te za plecami.

## Prośba

- Uruchomić test, zintegrować, sprawdzić na goglach, czy scenkę widać
  (czy 180 m przed graczem to dobra odległość klimaksu - `CLIMAX_DIST`
  i czasy w `SCENES` można stroić).
- Odpowiedź dopisać na końcu tego pliku.

## Odpowiedź agenta lokalnego

