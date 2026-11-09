# Uproszczony napęd botów - prototyp i porównanie z pełnym modelem
# (wątek w chmurze "Zaprojektuj nowe strategie botów road rage", 2026-11-09).
#
# Decyzja użytkownika: oszukiwać wolno tylko na NAPĘDZIE botów. Opony,
# bezwładność (nadwozia, kół, silnika widziana przez przełożenie),
# zawieszenie i kolizje zostają jak w pełnym modelu. Auto gracza bez zmian.
#
# BotCar dziedziczy wszystko z car_sim.Car (kopii fizyki z stunt_car.gd)
# i podmienia tylko napęd:
#   - zamiast skrzyni z 6 biegami, sprzęgła, zmian biegów i obrotów silnika:
#     "przełożenie równoważne" r_eq, które trzyma silnik przy obrotach mocy
#     maksymalnej (jak idealna skrzynia bezstopniowa), ograniczone do
#     przełożeń 1. i najwyższego biegu;
#   - moment silnika = gaz * min(k_fill * P / omega_silnika, T_max);
#     k_fill (< 1) oddaje to, że prawdziwa skrzynia nie trzyma szczytu mocy
#     (dziury między biegami, czas zmiany) - kalibrowane do pełnego modelu;
#   - hamowanie silnikiem ze wzoru jak w grze, przy obrotach z r_eq;
#   - bezwładność silnika widziana na kołach: I_e * r_eq^2 (zostaje!);
#   - bez ESP (bot sam steruje, nie potrzebuje korekt kierowcy);
#   - TCS i ABS zostają jak w pełnym modelu (ABS raz na krok zamiast
#     w podkrokach wydłużał hamowanie o ~9%, a oszczędzał grosze).
#
# Użycie: python3 tools/bot_drive_sim.py
import math
import time

import car_sim as cs
from car_sim import Car, RPM_PER_RAD_S


class BotCar(Car):
    K_FILL = 0.86   # kalibracja do pełnego modelu (0-100 i 0-160 km/h)

    def __init__(self, style=None, **kw):
        super().__init__(style, **kw)
        # Obroty mocy maksymalnej i największy moment z krzywej silnika.
        best_p, rpm_pp, t_max = 0.0, 0.0, 0.0
        r = self.curve[0][0]
        while r <= self.curve[-1][0]:
            t = cs._curve(self.curve, r)
            p = t * r / RPM_PER_RAD_S
            if p > best_p:
                best_p, rpm_pp = p, r
            t_max = max(t_max, t)
            r += 50.0
        self.p_max = best_p
        self.w_pp = rpm_pp / RPM_PER_RAD_S
        self.t_max = t_max
        self.r_first = self.gears[0] * self.final
        self.r_top = self.gears[-1] * self.final
        self.w_idle = self.e["idle"] / RPM_PER_RAD_S
        self.r_eq = self.r_first

    # --- napęd: przełożenie równoważne zamiast skrzyni ---
    def _gearbox(self, dt):
        wo = max(abs(self._driven_omega()), 0.1)
        self.r_eq = min(max(self.w_pp / wo, self.r_top), self.r_first)
        self.gear = 1
        self.clutch = True
        self.shift_timer = 0.0

    def _ratio(self, g):
        return 0.0 if g == 0 else self.r_eq

    def _engine_torque(self):
        w_e = max(abs(self._driven_omega()) * self.r_eq, self.w_idle)
        self.rpm = w_e * RPM_PER_RAD_S
        if self.throttle > 0.02:
            return self.throttle * min(self.K_FILL * self.p_max / w_e, self.t_max)
        # Hamowanie silnikiem jak w grze (stałe + rosnące z obrotami).
        return -(self.e["brake_a"] + self.e["brake_b"] * self.rpm)

    def _engine_rpm(self, dt):
        pass   # obroty wynikają z r_eq, bez osobnego stanu

    # --- wspomagania: bez ESP, ABS raz na krok ---
    def _esp(self, dt):
        self.esp_f = 1.0
        self.esp_active = False

    # TCS i ABS zostają jak w pełnym modelu: ABS liczony raz na krok
    # wydłużał hamowanie o ~9% (pomiar), a oszczędzał grosze.


# ----------------------------------------------------------------------
def run(fn, cls, *a, **kw):
    """Wywołuje manewr z car_sim z podmienioną klasą auta."""
    old = cs.Car
    cs.Car = cls
    try:
        return fn(*a, **kw)
    finally:
        cs.Car = old


def lane_change(style, v0=100.0, **kw):
    """Zmiana pasa o 4,6 m w ~1,6 s przy v0 (typowy manewr bota w szale).
    Zwraca największy kąt znoszenia [deg], przesunięcie po 2 s [m]."""
    car = cs.Car(style, **kw)
    car.reset(v0 / 3.6)
    car._pick_gear()
    for _ in range(60):
        car.step(cs.DT)
    t0 = car.t
    beta = 0.0
    car.throttle = 0.4
    while car.t - t0 < 4.0:
        tt = car.t - t0
        y_ref = 4.6 * (0.5 - 0.5 * math.cos(math.pi * min(tt / 1.6, 1.0)))
        cs._hold_lane(car, y_ref=y_ref)
        car.step(cs.DT)
        beta = max(beta, abs(math.degrees(math.atan2(car.v, max(car.u, 0.1)))))
        if abs(tt - 2.0) < cs.DT / 2:
            y2 = car.Y
    return {"beta_max": beta, "y_2s": y2}


def timing(cls, n=6000, **kw):
    """Średni czas kroku [us] przy pełnym gazie i lekkim skręcie."""
    car = cls(None, **kw)
    car.settle()
    car.throttle = 1.0
    car.steer = 0.15
    t = time.perf_counter()
    for i in range(n):
        if i % 600 == 300:
            car.brake, car.throttle = 1.0, 0.0
        elif i % 600 == 0:
            car.brake, car.throttle = 0.0, 1.0
        car.step(cs.DT)
    return (time.perf_counter() - t) / n * 1e6


def compare(style, label, **kw):
    full = dict(substeps=2, **kw)     # bot dziś: pełny model, 2 podkroki
    rows = []
    a_f = run(cs.accel, Car, style, **full)
    a_b = run(cs.accel, BotCar, style, **full)
    rows.append(("0-100 km/h [s]", a_f["t100"], a_b["t100"]))
    rows.append(("0-160 km/h [s]", a_f["t160"], a_b["t160"]))
    rows.append(("v po 60 s [km/h]", a_f["vmax"], a_b["vmax"]))
    rows.append(("hamowanie 100-0 [m]", run(cs.braking, Car, style, **full),
                 run(cs.braking, BotCar, style, **full)))
    s_f = run(cs.skidpad, Car, style, **full)
    s_b = run(cs.skidpad, BotCar, style, **full)
    rows.append(("łuk R60: max ay [g]", s_f["ay_max"], s_b["ay_max"]))
    l_f = run(lane_change, Car, style, **full)
    l_b = run(lane_change, BotCar, style, **full)
    rows.append(("zmiana pasa: kąt znoszenia [deg]", l_f["beta_max"], l_b["beta_max"]))
    rows.append(("zmiana pasa: przesunięcie po 2 s [m]", l_f["y_2s"], l_b["y_2s"]))
    p_f = run(cs.power_oversteer, Car, style, esp_on=False, **full)
    p_b = run(cs.power_oversteer, BotCar, style, esp_on=False, **full)
    rows.append(("pełny gaz na łuku: kąt znoszenia [deg]", p_f["beta_max"], p_b["beta_max"]))
    print(f"\n## {label}\n")
    print("| manewr | pełny model (2 podkroki) | bot uproszczony | różnica |")
    print("|---|---|---|---|")
    for name, f, b in rows:
        if f is None or b is None:
            print(f"| {name} | {f} | {b} | - |")
            continue
        d = (b - f) / f * 100.0 if abs(f) > 1e-9 else 0.0
        print(f"| {name} | {f:.2f} | {b:.2f} | {d:+.1f}% |")


if __name__ == "__main__":
    bot = {"power_kw": 250.0}          # bot spokojny (xr_main: apply_engine 250)
    rage = {"power_kw": 350.0}         # bot w szale (co najmniej 350 kW)
    compare(bot, "Bot 250 kW, tył, sport")
    compare(rage, "Bot w szale 350 kW, tył, sport")
    t_player = timing(Car, substeps=6)
    t_full = timing(Car, substeps=2)
    t_bot = timing(BotCar, substeps=2)
    print("\n## Czas kroku w Pythonie (orientacyjnie, GDScript ma podobny narzut na wywołania)\n")
    print("| model | us/krok | względem bota dziś |")
    print("|---|---|---|")
    print(f"| gracz (6 podkroków) | {t_player:.0f} | {t_player / t_full * 100:.0f}% |")
    print(f"| bot dziś (pełny, 2 podkroki) | {t_full:.0f} | 100% |")
    print(f"| bot uproszczony napęd | {t_bot:.0f} | {t_bot / t_full * 100:.0f}% |")
