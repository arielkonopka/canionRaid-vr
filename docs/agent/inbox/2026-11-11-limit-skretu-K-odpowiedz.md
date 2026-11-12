Od: wątek trakcji / stabilności w chmurze, 2026-11-11
Do: agent lokalny
Dotyczy: outbox/2026-11-11-oscylacje-300.md (pytanie o K)
Status: zrobione

# Limit skrętu "Wg przyczepności": K = 1,5 za mało, 2,5 ok dla lekkich aut, proponujemy 3,5

Sprawdziliśmy to w modelu `tools/car_sim.py` (ten sam model opony co
`stunt_car.gd`): skręt trzymany na limicie atan(K·μ·g·L/v²) przez 3 s,
ESP wył., steer_assist wył., gaz 0,3. Mierzone ustalone przyspieszenie
boczne ay (przyczepność modelu ~0,9-0,97 g).

| auto | v | K=1,5 | K=2,5 | K=3,5 | K=5 |
|---|---|---|---|---|---|
| sedan | 100 km/h | ~0,90 | ~0,92 | ~0,93 | ~0,93 |
| sedan | 200 km/h | 0,84 g | 0,92 | 0,93 | 0,94 |
| sedan | 300 km/h | 0,80 | 0,92 | 0,95 | 0,97 |
| 4x4 2500 kg | 200 km/h | 0,72 | 0,84 | 0,89 | 0,92 |
| 4x4 2500 kg | 300 km/h | 0,63 | 0,78 | 0,85 | 0,90 |

(dla 4x4 przy 300 km/h stary limit 6° daje 0,94 g)

Dlaczego K musi być > 1: wzór liczy kąt kinematyczny (Ackermann). Auto
w zakręcie potrzebuje jeszcze kątów znoszenia opon - przód podsterownego
ciężkiego auta ~5-7° przy granicy, czyli przy 300 km/h dużo więcej niż
kąt kinematyczny (~0,3°). Stąd K = 1,5 to ukryte utrudnienie: auto nie
może dojść do granicy przyczepności, czego gracz nie zrozumie.

Wnioski:
- K = 1,5: odradzamy (sedan traci ~15% przyczepności przy 300 km/h,
  4x4 ~35%).
- K = 2,5: dobre dla sedana, ale ciężki, podsterowny 4x4 zostaje
  na 83-90% przyczepności przy 200-300 km/h.
- **Propozycja: K = 3,5** - wszystkie auta ~93-97% granicy, nadal
  ~10x mniej niż limit 6° przy 300 km/h, więc problem saturacji
  drobnej korekty znika.
- Lepsza alternatywa (jeśli łatwo): limit = atan(2,5·μ·g·L/v²) + ~0,5°
  (zapas na znoszenie przedniej osi; można przeskalować przez gradient
  podsterowności auta). Działa równo dla każdego auta.
- Spojler/docisk: wzór nie uwzględnia docisku, więc przy autach
  z dużym dociskiem μ_eff jest wyższe - warto wziąć μ·(1 + F_docisk/(m·g)),
  jeśli docisk jest dostępny w skrypcie.

Prośba: po zmianie uruchom `tests/esp_highspeed_test.gd` (tryb "wg
przyczepności", drążek 100%) i `tests/drive_test.gd`; wynik do outboxu.

## Odpowiedź agenta lokalnego

(2026-11-11) Wdrożony wariant "lepszy": limit = atan(2,5·μ_eff·g·L/v²)
+ 0,5°, μ_eff = μ·(1 + F_docisku_spojlera/(m·g)) (docisk jak w oporze
powietrza: tylko sedan ze spojlerem). `esp_highspeed_test` (hatchback,
elektryk w kołach, 300 km/h): korekta 30% drążka - znoszenie 1,0°,
ESP nieaktywne, napęd 0,97; pełny drążek - 4,0°, ESP 0,7 s (439 Nm),
napęd 0,35, po korektach spokój. Warunek w zestawie: 30% bez ESP
i < 3°. `drive_test` 3x2 bez zmian (24.12/24.19, 24.22/24.23,
24.22/24.29), pełny `./quest.sh test` OK. Ocena użytkownika (z K 2,5
bez zapasu): "jest nieźle, styl świetny i dynamiczny".
