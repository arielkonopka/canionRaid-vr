Status: nowe
Od: wątek w chmurze "Popraw trakcję przy przyspieszaniu"
Dotyczy: outbox/2026-11-11-stabilnosc-200.md
Decyzje użytkownika: zasada stała - fizyka realistyczna, pomoce jawne.
Nic w fizyce auta nie zmieniam.

# Stabilność > 200 km/h: oscyluje autopilot testów, nie auto

## Odpowiedzi

**1. Autopilot.** `tools/highway_stab_sim.py` (na `tools/car_sim.py`:
2500 kg, 4x4, Cd·A 0,555, bez spojlera, bez gazu, start 0,5 m od środka
pasa, zaburzenie obrotu 0,03 rad/s), maks. w 5-10 s:

| kierowca | 120 km/h | 210 km/h | 300 km/h | 400 km/h |
|---|---|---|---|---|
| autopilot z testów | β 0,9°, stabilny | **β 8,9°**, r 0,52, \|Y\| 4,5 m | β 13,8° | obrót |
| kierownica na zero | β 0,07° | β 0,11° | β 0,15° | β 0,20° |
| model rowerowy (niżej) | β 0,06° | β 0,07°, \|Y\| 0,05 m | β 0,08° | β 0,11° |

Autopilot z testów przy 210 km/h wpada w rosnące kołysanie (okres ~2 s,
odchyłka 0,5 → 2,3 m w 6 s) - to Wasze ~6°. Samo auto z kierownicą na
zero tłumi zaburzenie przy każdej prędkości.

Przyczyna: wzmocnienia są stałe względem prędkości, a auto nie.
Przyspieszenie boczne od skrętu rośnie jak v²/L, prędkość obrotu jak
v/L, więc regulator PD na odchyłce i kursie potrzebuje wzmocnień
∝ 1/v² i 1/v. `clampf(25/v, 0,3, 1)` daje 1/v tylko do 83 m/s i nie
skaluje członu odchyłki. Do tego skręt jest ograniczony prędkością
zmiany (`steer_rate`), co opóźnia fazę - przy dużym wzmocnieniu pętla
zaczyna się kołysać.

**2. Auto.** W tym modelu nic nie wywołuje niestabilności przy toczeniu
do 400 km/h (wcześniejszy model 2D z PR #35 pokazywał to samo:
niestabilne jest tylko auto z tyłem nasyconym napędem, czyli przy pełnym
gazie RWD). 700 kW 4x4 z pełnym gazem do 300 km/h i puszczeniem: β 0,04°
z poprawionym autopilotem. Silników w kołach `car_sim.py` nie ma, ale
przy toczeniu bez odzysku moment w kołach = 0, więc układ napędu nie
gra roli.

**3. `car_sim.py`** pokazuje to samo co gra, gdy jedzie z autopilotem
z testów; z kierownicą na zero lub poprawionym autopilotem - nie.

## Druga rzecz: pomiar β w testach liczy też kąt pionowy

`fwd.signed_angle_to(car.linear_velocity.normalized(), car.global_basis.y)`
zwraca **pełny kąt 3D** między wektorami, a oś daje tylko znak. Prędkość
pionowa względem nadwozia (pochylenie przy puszczeniu gazu albo mocnym
odzysku, garb, lądowanie, zmiana nachylenia autostrady) wchodzi do
"znoszenia". Przy 58 m/s 3 m/s pionowo to już 3°. Wyniki 10-35° przy
mocnym odzysku mogą być w dużej części tym. Poprawka:

```gdscript
var up := car.global_basis.y
var v_flat := car.linear_velocity - up * car.linear_velocity.dot(up)
var beta := rad_to_deg(absf(fwd.signed_angle_to(v_flat.normalized(), up)))
```

To samo w `INCYDENT`/`_watch_incident`, jeśli liczy kąt tak samo.

## Proponowany autopilot (testy: endless_test, regen_highway_test, ...)

Kurs docelowy z odchyłki (zbliżanie do środka pasa w ~2 s), prędkość
obrotu z błędu kursu (0,5 s), skręt z modelu rowerowego, tłumienie
prędkością obrotu. Znaki jak w testach (`off` > 0 = w prawo, `steer` >
0 = w prawo, `head_err` > 0 = tor skręca w lewo):

```gdscript
var v := maxf(car.speed, 5.0)
var psi_t := clampf(off / (v * 2.0), -0.3, 0.3)      # kurs docelowy [rad, + w lewo]
var r_c := (psi_t + head_err) / 0.5                  # żądany obrót [rad/s, + w lewo]
var r_left := car.angular_velocity.dot(car.global_basis.y)
var delta := car._wheelbase * (r_c + (r_c - r_left)) / v
var max_a := deg_to_rad(car.max_steer_deg)
if car.steer_assist:
	max_a = deg_to_rad(lerpf(car.max_steer_deg, car.high_speed_steer_deg,
			clampf(absf(car.speed) / car.steer_assist_speed, 0.0, 1.0)))
car.steer = clampf(-delta / max_a, -1.0, 1.0)
```

Na łukach można dodać człon wyprzedzający `r_c += v * krzywizna`
(krzywizna próbki w rad/m) - bez niego autopilot łapie łuk z błędem
kursu, jak dotąd.

## Do sprawdzenia lokalnie

1. `regen_highway_test -- 210 90 off` z poprawionym β, ze starym
   autopilotem - ile zostaje z 6°.
2. To samo z nowym autopilotem; potem `strong`.
3. Jeśli przy `strong` nadal > 3° po poprawce β: to już fizyka odzysku
   (hamowanie 4 kół silnikami przy 200 km/h) - prześlijcie log
   (`w.slip`, `_regen_wheel`, `_esp_factor`), policzę osobno.
4. `endless_test` z nowym autopilotem (czy łuki przejeżdża tak samo).
