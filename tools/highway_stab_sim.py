# Stabilność odchylenia przy 60-400 km/h na prostej (wątek w chmurze,
# 2026-11-11, odpowiedź na outbox/2026-11-11-stabilnosc-200.md). Używa
# tools/car_sim.py: auto 2500 kg, 4x4, "sport" (Cd·A 0,555), bez spojlera,
# toczenie bez gazu. Porównuje autopilota z testów (endless/regen_highway)
# z autopilotem opartym na modelu rowerowym i z kierownicą trzymaną na zero.
# Użycie: python3 tools/highway_stab_sim.py
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from car_sim import Car, DT  # noqa: E402

STYLE = dict(mass=2500.0, drive="awd", power_kw=700.0, aero_drag=0.5 * 1.225 * 0.555)


def max_angle(car):
    t = min(abs(car.u) / 45.0, 1.0)
    return math.radians(34.0) + (math.radians(6.0) - math.radians(34.0)) * t


def pilot_game(car):
    """Jak w testach: clampf(25/v, 0,3, 1) x (-off*0,25 - head_err*2,5)."""
    gain = min(max(25.0 / max(car.u, 1.0), 0.3), 1.0)
    car.steer = max(-1.0, min(1.0, (-car.Y * 0.25 - car.psi * 2.5) * gain))


def pilot_bicycle(car, Ty=2.0, Tp=0.5, kr=1.0):
    """Kurs docelowy z odchyłki (zbliżanie w Ty s), prędkość obrotu z błędu
    kursu (Tp s), skręt z modelu rowerowego + tłumienie prędkością obrotu."""
    v = max(car.u, 5.0)
    psi_t = max(-0.3, min(0.3, -car.Y / (v * Ty)))
    r_c = (psi_t - car.psi) / Tp
    delta = car.L * (r_c + kr * (r_c - car.r)) / v
    car.steer = max(-1.0, min(1.0, delta / max_angle(car)))


def pilot_fixed(car):
    car.steer = 0.0


def run(pilot, v_kmh, T=10.0):
    car = Car(dict(STYLE))
    car.reset(v_kmh / 3.6)
    car.Y = 0.5          # pół metra od środka pasa
    car.r = 0.03         # mała zaburzenie obrotu
    my = mr = mb = 0.0
    while car.t < T:
        pilot(car)
        car.throttle = 0.0
        car.step(DT)
        if car.t > 5.0:
            my = max(my, abs(car.Y))
            mr = max(mr, abs(car.r))
        mb = max(mb, abs(math.degrees(math.atan2(car.v, car.u))))
    return my, mr, mb


if __name__ == "__main__":
    for name, p in (("autopilot z testów", pilot_game), ("model rowerowy", pilot_bicycle),
                    ("kierownica na zero", pilot_fixed)):
        row = []
        for v in (60, 120, 210, 300, 400):
            my, mr, mb = run(p, v)
            row.append("%d: |Y| %.2f m, r %.3f, β %.2f°" % (v, my, mr, mb))
        print("%-20s %s" % (name, " | ".join(row)))
