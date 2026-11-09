# Symulator auta poza Godotem (wątek w chmurze 2026-11-09, "Dodaj nowe modele
# aut z epoki"). Odwzorowuje fizykę z scripts/stunt_car.gd na płaskiej,
# suchej jezdni: zawieszenie (sprężyna, tłumik bump/rebound, odbój,
# stabilizatory) z przechyłem, pochyleniem i ugięciem nadwozia, opony
# (znormalizowana Magic Formula, poślizg łączony, load sensitivity,
# relaksacja, tłumienie przy małej prędkości, podkroki), koła z momentem
# napędu i hamulca, silnik z krzywą momentu i automatem, LSD, 4x4 z wiskozą,
# ABS/TCS z wyprzedzeniem, ESP, kierowanie z ograniczeniem skrętu
# i Ackermannem, opór powietrza.
#
# Uproszczenia (świadome): kąty przechyłu i pochylenia małe (dachowania nie
# liczymy do końca - zgłaszamy oderwanie dwóch kół jednej strony), jezdnia
# płaska, bez uszkodzeń i paliwa, bez obrotów silnika przy otwartym sprzęgle
# poza ruszaniem.
#
# Układ: x do przodu, y w lewo, z w górę (gra: -Z do przodu, X w prawo).
# Kąt skrętu i prędkość obrotu dodatnie w lewo. Koła: 0 LP, 1 PP, 2 LT, 3 PT
# (jak wheels[] w grze: lewe parzyste).
#
# Użycie: python3 tools/car_sim.py            - raport dla sedana z gry
#         python3 tools/car_styles_tune.py    - strojenie wszystkich modeli
import math

G = 9.81
RPM_PER_RAD_S = 60.0 / (2.0 * math.pi)

# Z ENGINE_TYPES w stunt_car.gd (bez elektryka - auta z epoki).
ENGINE_TYPES = {
    "petrol": {
        "shape": [[800, 0.50], [1500, 0.68], [2500, 0.83], [3500, 0.95],
                  [4500, 1.0], [5500, 0.97], [6500, 0.87], [7200, 0.75]],
        "idle": 850.0, "redline": 7200.0, "inertia": 0.18,
        "brake_a": 18.0, "brake_b": 0.006,
        "gears": [3.30, 2.10, 1.55, 1.20, 0.97, 0.80], "final": 3.9,
        "up": 6700.0, "down": 2600.0, "clutch": 1300.0, "launch": 3800.0,
        "extra_mass": 0.0,
    },
    "diesel": {
        "shape": [[800, 0.45], [1250, 0.70], [1750, 1.0], [2750, 1.0],
                  [3500, 0.86], [4200, 0.70], [4700, 0.52]],
        "idle": 800.0, "redline": 4700.0, "inertia": 0.28,
        "brake_a": 28.0, "brake_b": 0.012,
        "gears": [3.55, 2.05, 1.35, 1.00, 0.80, 0.66], "final": 3.45,
        "up": 4200.0, "down": 1500.0, "clutch": 1050.0, "launch": 2000.0,
        "extra_mass": 50.0,
    },
}

SUSPENSION_PRESETS = {
    "soft": dict(spring_k=22000.0, damper_bump=1500.0, damper_rebound=2800.0,
                 anti_roll_front=11000.0, anti_roll_rear=6000.0),
    "sport": dict(spring_k=36000.0, damper_bump=1900.0, damper_rebound=3600.0,
                  anti_roll_front=19000.0, anti_roll_rear=11000.0),
    "stiff": dict(spring_k=65000.0, damper_bump=2600.0, damper_rebound=4900.0,
                  anti_roll_front=32000.0, anti_roll_rear=20000.0),
}

# Sedan z gry - punkt odniesienia (wartości z @export w stunt_car.gd).
SEDAN = {
    "name": "sedan",
    "mass": 1150.0,                       # body_mass
    "inertia": (480.0, 1750.0, 1950.0),   # przechył, pochylenie, odchylenie (gra: Z, X, Y)
    "com_y": -0.12,                       # środek masy pod płaszczyzną mocowań [m]
    "com_x": 0.03,                        # gra com_offset.z = -0.03 (do przodu)
    "front_x": 1.32, "rear_x": -1.25,     # mocowania kół wzdłuż (gra: -1.32 / 1.25)
    "track": 1.64,
    "wheel_radius": 0.33,
    "rest_length": 0.45,
    "body_bottom": -0.40,                 # spód BodyShape pod punktem odniesienia
    "aero_drag": 0.46,
    "engine": "petrol", "power_kw": 90.0, "drive": "rwd",
    "final_mult": 1.0,
    "suspension": "sport",
    "spring_mult": 1.0, "damper_mult": 1.0,
    "arb_front_mult": 1.0, "arb_rear_mult": 1.0,
    "brake_front": 1900.0, "brake_rear": 1050.0,
    "max_steer_deg": 34.0,
}


def _curve(curve, rpm):
    if rpm <= curve[0][0]:
        return curve[0][1]
    for i in range(1, len(curve)):
        if rpm <= curve[i][0]:
            t = (rpm - curve[i - 1][0]) / (curve[i][0] - curve[i - 1][0])
            return curve[i - 1][1] + (curve[i][1] - curve[i - 1][1]) * t
    return curve[-1][1]


class Wheel:
    def __init__(self, x, y, front, left):
        self.x, self.y, self.front, self.left = x, y, front, left
        self.omega = 0.0
        self.kappa = 0.0
        self.tan_alpha = 0.0
        self.slip = 0.0
        self.load = 0.0
        self.contact = True
        self.comp = 0.0
        self.prev_comp = 0.0
        self.spring_len = 0.0
        self.steer = 0.0
        self.abs_mod = 1.0


class Car:
    """Jedno auto. Parametry jak w stylu (słownik), reszta jak w grze."""

    def __init__(self, style=None, tires_dry=0.94, substeps=6, abs_on=True, tcs_on=True,
                 esp_on=True, steer_assist=True, suspension=None):
        s = dict(SEDAN)
        if style:
            s.update(style)
        self.s = s
        e = ENGINE_TYPES[s["engine"]]
        self.e = e
        # --- masa i bezwładność (jak _apply_mass + bezwładność stylu) ---
        self.m = s["mass"] + e["extra_mass"]
        k_in = self.m / s["mass"]
        self.Ix, self.Iy, self.Iz = (v * k_in for v in s["inertia"])
        self.brake_scale = max(self.m / 1150.0, 1.0)
        # --- geometria ---
        self.L = s["front_x"] - s["rear_x"]
        com_x = s["com_x"]
        if s["drive"] == "fwd":
            com_x += 0.1 * self.L          # FWD_FRONT_SHIFT
        self.com_x = com_x
        t2 = s["track"] * 0.5
        self.wheels = [Wheel(s["front_x"] - com_x, t2, True, True),
                       Wheel(s["front_x"] - com_x, -t2, True, False),
                       Wheel(s["rear_x"] - com_x, t2, False, True),
                       Wheel(s["rear_x"] - com_x, -t2, False, False)]
        self.r_w = s["wheel_radius"]
        self.rest = s["rest_length"]
        # --- zawieszenie: zestaw x masa (jak apply_suspension_preset) x styl ---
        p = SUSPENSION_PRESETS[suspension or s["suspension"]]
        km = self.m / 1150.0
        self.k = p["spring_k"] * km * s["spring_mult"]
        self.c_bump = p["damper_bump"] * km * s["damper_mult"]
        self.c_reb = p["damper_rebound"] * km * s["damper_mult"]
        self.arb_f = p["anti_roll_front"] * km * s["arb_front_mult"]
        self.arb_r = p["anti_roll_rear"] * km * s["arb_rear_mult"]
        self.bump_travel = 0.06
        self.bump_k = 260000.0
        # --- opony ---
        self.mu = 1.1
        self.grip = tires_dry           # całoroczne na suchym
        self.ls = 0.1
        self.pk = 0.11
        self.tan_pa = math.tan(math.radians(7.5))
        self.C = 1.4
        self.B = math.tan(math.pi / (2 * self.C))
        self.relax_lat = 0.45
        self.relax_long = 0.25
        self.rr = 0.013
        self.Iw = 1.2
        self.substeps = substeps
        # --- silnik (apply_engine) ---
        p_w = s["power_kw"] * 1000.0
        shape = e["shape"]
        peak = 0.0
        r = shape[0][0]
        while r <= shape[-1][0]:
            peak = max(peak, _curve(shape, r) * r / RPM_PER_RAD_S)
            r += 50.0
        sc = p_w / peak
        self.curve = [[a, b * sc] for a, b in shape]
        self.gears = list(e["gears"])
        self.final = e["final"] * s["final_mult"]
        if s["power_kw"] > 350.0:
            self.final *= math.sqrt(350.0 / s["power_kw"])
        self.final *= self.r_w / 0.33    # BASE_WHEEL_RADIUS
        self.eff = 0.88
        self.shift_time = 0.18
        self.lsd_k, self.lsd_max = 25.0, 500.0
        self.drive = s["drive"]
        # --- hamulce ---
        self.brake_f = s["brake_front"]
        self.brake_r = s["brake_rear"]
        # --- systemy ---
        self.abs_on, self.tcs_on, self.esp_on = abs_on, tcs_on, esp_on
        self.steer_assist = steer_assist
        self.max_steer = math.radians(s["max_steer_deg"])
        self.aero = s["aero_drag"]
        self.reset()

    # ------------------------------------------------------------------
    def reset(self, speed=0.0):
        self.X = self.Y = self.psi = 0.0
        self.u = speed
        self.v = 0.0
        self.r = 0.0
        self.phi = self.dphi = 0.0       # przechył (lewa strona w górę > 0)
        self.th = self.dth = 0.0         # pochylenie (nos w dół > 0)
        # Ugięcie statyczne: wysokość punktu odniesienia nad jezdnią.
        a = self.wheels[0].x
        b = -self.wheels[2].x
        load_f = self.m * G * b / self.L / 2.0
        load_r = self.m * G * a / self.L / 2.0
        c = (load_f + load_r) / 2.0 / self.k
        self.zo = self.rest - c + self.r_w
        self.dzo = 0.0
        for w in self.wheels:
            w.omega = speed / self.r_w
            w.kappa = w.tan_alpha = 0.0
            w.comp = w.prev_comp = c
        self.gear = 1
        self.pending = 1
        self.shift_timer = 0.0
        self.shift_cd = 0.0
        self.clutch = False
        self.rpm = self.e["idle"]
        self.tcs_f = 1.0
        self.esp_f = 1.0
        self.esp_brake = [0.0] * 4
        self.steer_sm = 0.0
        self.throttle = self.brake = self.steer = self.handbrake = 0.0
        self.t = 0.0
        self.abs_active = self.tcs_active = self.esp_active = False
        self.bottomed = False
        self.min_clear = 9.0
        if speed > 1.0:
            self._pick_gear()

    def _pick_gear(self):
        for g in range(1, len(self.gears) + 1):
            self.gear = g
            if self._wheel_rpm() < self.e["up"] * 0.85:
                break
        self.pending = self.gear

    @property
    def h(self):
        """Wysokość środka masy nad jezdnią."""
        return self.zo + self.s["com_y"]

    # ------------------------------------------------------------------
    def _ratio(self, g):
        return 0.0 if g == 0 else self.gears[g - 1] * self.final

    def _driven(self, w):
        if self.drive == "awd":
            return True
        return w.front == (self.drive == "fwd")

    def _driven_omega(self):
        W = self.wheels
        rear = (W[2].omega + W[3].omega) * 0.5
        front = (W[0].omega + W[1].omega) * 0.5
        if self.drive == "rwd":
            return rear
        if self.drive == "fwd":
            return front
        return 0.4 * front + 0.6 * rear

    def _wheel_rpm(self):
        return self._driven_omega() * self._ratio(self.gear) * RPM_PER_RAD_S

    def _engine_torque(self):
        if self.gear == 0 or self.shift_timer > 0.0:
            return 0.0
        pedal = self.throttle
        if self.rpm >= self.e["redline"]:
            pedal = 0.0
        t = pedal * _curve(self.curve, self.rpm)
        if self.clutch:
            fade = min(max(self.rpm / 400.0, 0.0), 1.0)
            t -= (1.0 - pedal) * (self.e["brake_a"] + self.e["brake_b"] * self.rpm) * fade
        return t

    def _gearbox(self, dt):
        self.shift_cd = max(self.shift_cd - dt, 0.0)
        if self.shift_timer > 0.0:
            self.shift_timer -= dt
            if self.shift_timer <= 0.0:
                self.gear = self.pending
                self.shift_cd = 0.6
            self.clutch = False
            return
        wr = self._wheel_rpm()
        self.clutch = self.gear != 0 and wr >= self.e["clutch"]
        rear_ok = self.wheels[2].contact or self.wheels[3].contact
        if self.gear >= 1 and rear_ok and self.shift_cd <= 0.0:
            if wr > self.e["up"] and self.gear < len(self.gears) and self.throttle > 0.1:
                self._shift(self.gear + 1)
            elif wr < self.e["down"] and self.gear > 1:
                self._shift(self.gear - 1)

    def _shift(self, g):
        self.pending = g
        self.shift_timer = self.shift_time

    def _engine_rpm(self, dt):
        if self.clutch:
            self.rpm = max(self._wheel_rpm(), self.e["idle"])
            return
        idle, red = self.e["idle"], self.e["redline"]
        target = idle + self.throttle * (red - idle)
        if self.shift_timer > 0.0:
            target = min(max(abs(self._driven_omega() * self._ratio(self.pending) * RPM_PER_RAD_S), idle), red)
        elif self.gear != 0 and self.throttle > 0.02:
            target = idle + (self.e["launch"] - idle) * self.throttle
        d = 9000.0 * dt
        self.rpm += max(-d, min(d, target - self.rpm))

    # ------------------------------------------------------------------
    def _fmax(self, w):
        fz0 = self.m * G * 0.25
        mu = self.mu * min(max(1.0 - self.ls * (w.load / fz0 - 1.0), 0.5), 1.3)
        return mu * self.grip * w.load

    def _mf(self, rho):
        return math.sin(self.C * math.atan(self.B * rho))

    @staticmethod
    def _relax(state, inp, vxa, sigma, h):
        a = vxa / sigma
        if a < 1e-3:
            return state + inp / sigma * h
        tg = inp / vxa
        return tg + (state - tg) * math.exp(-a * h)

    def _tire(self, w, vx, vy, h):
        vxa = abs(vx)
        slip_vel = w.omega * self.r_w - vx
        w.kappa = max(-2.0, min(2.0, self._relax(w.kappa, slip_vel, vxa, self.relax_long, h)))
        w.tan_alpha = max(-2.0, min(2.0, self._relax(w.tan_alpha, vy, vxa, self.relax_lat, h)))
        sx = w.kappa / self.pk
        sy = w.tan_alpha / self.tan_pa
        rho = math.hypot(sx, sy)
        w.slip = rho
        fm = self._fmax(w)
        fx = fy = 0.0
        if rho > 1e-6:
            f = fm * self._mf(rho)
            fx = f * sx / rho
            fy = -f * sy / rho
        low = min(max(1.0 - vxa / 4.0, 0.0), 1.0)
        if low > 0.0:
            c = 2.0 * w.load
            fx += c * slip_vel * low
            fy -= c * vy * low
            n = math.hypot(fx, fy)
            if n > fm and n > 0:
                fx *= fm / n
                fy *= fm / n
        return fx, fy

    def _traction_cap(self, w, dirn=1.0):
        slip = w.kappa * dirn
        tgt = self.pk * 0.9
        return self._fmax(w) * self.r_w * min(max(1.0 + 2.0 * (tgt - slip) / self.pk, 0.2), 1.15)

    def _brake_torque(self, w, i):
        t = self.brake * (self.brake_f if w.front else self.brake_r) * self.brake_scale
        t += self.esp_brake[i]
        if self.abs_on and t > 0.0 and w.contact and abs(self.u) > 2.0:
            dirn = 1.0 if self.u >= 0 else -1.0
            slip = -w.kappa * dirn
            cap = self._fmax(w) * self.r_w * min(max(1.0 + 2.0 * (self.pk * 0.9 - slip) / self.pk, 0.2), 1.15)
            w.abs_mod = min(max(cap / max(t, 1.0), 0.0), 1.0)
            t = min(t, cap)
            if w.abs_mod < 0.98:
                self.abs_active = True
        if not w.front:
            t += self.handbrake * 2600.0
        return t

    def _tcs(self, dt):
        self.tcs_active = False
        target = 1.0
        if self.tcs_on and self.throttle > 0.05 and self.gear != 0:
            req = self._engine_torque() * abs(self._ratio(self.gear)) * self.eff
            if req > 1.0:
                cap = sum(self._traction_cap(w) for w in self.wheels if self._driven(w) and w.contact)
                target = min(max(cap / req, 0.05), 1.0)
                self.tcs_active = target < 0.98
        if target < self.tcs_f:
            self.tcs_f = target
        else:
            self.tcs_f = min(target, self.tcs_f + 25.0 * dt)

    def _esp(self, dt):
        self.esp_brake = [0.0] * 4
        self.esp_active = False
        tf = 1.0
        grounded = sum(1 for w in self.wheels if w.contact)
        if self.esp_on and self.u > 5.0 and grounded >= 3:
            W = self.wheels
            d = (W[0].steer + W[1].steer) * 0.5
            v = self.u
            r_ref = v * math.tan(d) / (self.L * (1.0 + (v / 28.0) ** 2))
            r_max = 0.85 * self.mu * self.grip * G / v
            r_ref = max(-r_max, min(r_max, r_ref))
            r = self.r
            err = r - r_ref
            over = abs(r) > abs(r_ref) or (r > 0) != (r_ref > 0)
            axle = max(W[2].slip, W[3].slip) if over else max(W[0].slip, W[1].slip)
            sliding = axle > (0.75 if over else 1.0)
            rear_a = (abs(W[2].tan_alpha) + abs(W[3].tan_alpha)) * 0.5 / self.tan_pa
            beta_cut = min(max(1.0 - (rear_a - 0.5) * 1.5, 0.15), 1.0)
            if beta_cut < 1.0 and over:
                self.esp_active = True
                tf = beta_cut
            if abs(err) > 0.06 and sliding:
                self.esp_active = True
                t = min(max((abs(err) - 0.06) * 5000.0, 0.0), 1600.0)
                # err > 0: za mocno w lewo -> hamować koło po prawej.
                brake_right = err > 0.0
                if over:
                    idx = 1 if brake_right else 0
                    tf = min(tf, min(max(1.0 - (abs(err) - 0.06) * 6.0, 0.2), 1.0))
                else:
                    idx = 3 if brake_right else 2
                self.esp_brake[idx] = t
        if tf < self.esp_f:
            self.esp_f = tf
        else:
            self.esp_f = min(tf, self.esp_f + 25.0 * dt)

    def _steering(self, dt):
        d = max(-1.0, min(1.0, self.steer)) - self.steer_sm
        self.steer_sm += max(-2.5 * dt, min(2.5 * dt, d))
        ma = self.max_steer
        if self.steer_assist:
            t = min(abs(self.u) / 45.0, 1.0)
            ma = ma + (math.radians(6.0) - ma) * t
        a = self.steer_sm * ma
        W = self.wheels
        if abs(a) < 1e-4:
            W[0].steer = W[1].steer = 0.0
            return
        R = self.L / math.tan(a)                  # dodatni = w lewo
        t2 = self.s["track"] * 0.5
        W[0].steer = math.atan(self.L / (R - t2))  # lewe wewnętrzne przy skręcie w lewo
        W[1].steer = math.atan(self.L / (R + t2))

    # ------------------------------------------------------------------
    def step(self, dt=1.0 / 120.0):
        self._steering(dt)
        self._gearbox(dt)
        W = self.wheels
        # --- 1. ugięcia z położenia nadwozia ---
        for w in W:
            dz = w.y * self.phi - w.x * self.th
            sl = self.zo + dz - self.r_w
            w.prev_comp = w.comp
            if sl >= self.rest:
                w.contact = False
                w.spring_len = self.rest
                w.comp = 0.0
            else:
                w.contact = True
                w.spring_len = max(sl, 0.0)
                w.comp = self.rest - w.spring_len
                if sl < 0.0:
                    self.bottomed = True
        # Prześwit pod nadwoziem (spód BodyShape w najniższym rogu).
        lowest = self.zo + self.s["body_bottom"] - abs(self.phi) * 0.85 - abs(self.th) * 2.2
        self.min_clear = min(self.min_clear, lowest)
        # --- 2. siły zawieszenia ---
        for w in W:
            if not w.contact:
                w.load = 0.0
                continue
            cv = (w.comp - w.prev_comp) / dt
            f = self.k * w.comp + (self.c_bump if cv > 0 else self.c_reb) * cv
            if w.spring_len < self.bump_travel:
                f += self.bump_k * (self.bump_travel - w.spring_len)
            w.load = f
        for a_, b_, k in ((W[0], W[1], self.arb_f), (W[2], W[3], self.arb_r)):
            if a_.contact or b_.contact:
                f = (a_.comp - b_.comp) * k
                if a_.contact:
                    a_.load += f
                if b_.contact:
                    b_.load -= f
        for w in W:
            if w.contact:
                w.load = max(w.load, 0.0)
        # --- 3. systemy i napęd ---
        self.abs_active = False
        self._tcs(dt)
        self._esp(dt)
        g_ratio = self._ratio(self.gear)
        axle_t = 0.0
        slipping = self.gear != 0 and self.shift_timer <= 0.0 and not self.clutch and self.throttle > 0.02
        if self.clutch or slipping:
            te = self._engine_torque()
            if te > 0.0:
                te *= min(self.tcs_f, self.esp_f)
            axle_t = te * g_ratio * self.eff
        n_dr = 2.0 if self.drive in ("rwd", "fwd") else 4.0
        refl = self.e["inertia"] * g_ratio * g_ratio / n_dr if self.clutch else 0.0
        # --- 4. opony w podkrokach ---
        dirs = []
        for w in W:
            vx = self.u - self.r * w.y
            vy = self.v + self.r * w.x
            c, s_ = math.cos(w.steer), math.sin(w.steer)
            dirs.append((c, s_, vx * c + vy * s_, -vx * s_ + vy * c))
        n = self.substeps
        h = dt / n
        fxs = [0.0] * 4
        fys = [0.0] * 4
        body_reaction = 0.0
        for _ in range(n):
            lsd = max(-self.lsd_max, min(self.lsd_max, (W[2].omega - W[3].omega) * self.lsd_k))
            lsd_f = max(-self.lsd_max, min(self.lsd_max, (W[0].omega - W[1].omega) * self.lsd_k))
            t_front = axle_t if self.drive == "fwd" else 0.0
            t_rear = 0.0 if self.drive == "fwd" else axle_t
            if self.drive == "awd":
                c_max = max(900.0, 0.35 * abs(axle_t))
                visc = max(-c_max, min(c_max, ((W[0].omega + W[1].omega) - (W[2].omega + W[3].omega)) * 0.5 * 400.0))
                t_front = axle_t * 0.4 - visc
                t_rear = axle_t * 0.6 + visc
            for i, w in enumerate(W):
                d = dirs[i]
                fx = fy = 0.0
                if w.contact and w.load > 1.0:
                    fx, fy = self._tire(w, d[2], d[3], h)
                else:
                    w.slip = 0.0
                td = 0.0
                iw = self.Iw
                if self._driven(w):
                    if w.front:
                        td = t_front * 0.5 + (-lsd_f if w.left else lsd_f)
                    else:
                        td = t_rear * 0.5 + (-lsd if w.left else lsd)
                    iw += refl
                troll = -self.rr * w.load * self.r_w * max(-1.0, min(1.0, w.omega * 2.0))
                tfree = td - fx * self.r_w + troll
                tb = self._brake_torque(w, i)
                of = w.omega + tfree / iw * h
                bdw = tb / iw * h
                if abs(of) <= bdw:
                    applied = -of * iw / h
                    w.omega = 0.0
                else:
                    applied = -math.copysign(tb, of)
                    w.omega = of + applied / iw * h
                body_reaction += (td + applied) / n
                fxs[i] += fx / n
                fys[i] += fy / n
        # --- 5. siły na nadwozie ---
        Fx = Fy = Mz = Mx = My = 0.0
        hc = self.h
        Fz = 0.0
        for i, w in enumerate(W):
            c, s_ = dirs[i][0], dirs[i][1]
            bx = fxs[i] * c - fys[i] * s_
            by = fxs[i] * s_ + fys[i] * c
            Fx += bx
            Fy += by
            Mz += w.x * by - w.y * bx
            # przechył: obciążenia na ramieniu y, siły boczne w punkcie styku (h pod środkiem masy)
            Mx += w.y * w.load + hc * by
            # pochylenie: obciążenia na ramieniu x, siła wzdłużna na piaście
            My += -w.x * w.load - (hc - self.r_w) * bx
            Fz += w.load
        My -= body_reaction            # reakcja napędu podnosi nos (jak apply_torque w grze)
        v2 = self.u * self.u + self.v * self.v
        if v2 > 0.01:
            vv = math.sqrt(v2)
            Fx -= self.aero * v2 * self.u / vv
            Fy -= self.aero * v2 * self.v / vv
        # --- 6. całkowanie ---
        ax = Fx / self.m
        ay = Fy / self.m
        self.u += (ax + self.v * self.r) * dt
        self.v += (ay - self.u * self.r) * dt
        self.r += Mz / self.Iz * dt
        self.dphi += Mx / self.Ix * dt
        self.phi += self.dphi * dt
        self.dth += My / self.Iy * dt
        self.th += self.dth * dt
        self.dzo += (Fz / self.m - G) * dt
        self.zo += self.dzo * dt
        self.psi += self.r * dt
        c, s_ = math.cos(self.psi), math.sin(self.psi)
        self.X += (self.u * c - self.v * s_) * dt
        self.Y += (self.u * s_ + self.v * c) * dt
        self.ay = ay
        self.ax = ax
        self._engine_rpm(dt)
        self.t += dt

    # ------------------------------------------------------------------
    def settle(self, T=1.5):
        """Ustala ugięcie na postoju (bez gazu, na hamulcu)."""
        self.brake = 1.0
        for _ in range(int(T * 120)):
            self.step()
        self.brake = 0.0

    def lifted(self):
        """Ile kół nie ma kontaktu po każdej stronie (lewa, prawa)."""
        W = self.wheels
        return (int(not W[0].contact) + int(not W[2].contact),
                int(not W[1].contact) + int(not W[3].contact))


# ======================================================================
# Manewry
# ======================================================================
DT = 1.0 / 120.0


def _hold_lane(car, y_ref=0.0, psi_ref=0.0):
    """Prosty kierowca: trzyma pas (sterowanie PD na błąd położenia i kursu)."""
    e = (y_ref - car.Y) * 0.04 + (psi_ref - car.psi) * 1.2 - car.r * 0.15
    car.steer = max(-1.0, min(1.0, e * 3.0))


def accel(style, **kw):
    """0-100, 0-160 km/h i prędkość po 60 s (pełny gaz, automat)."""
    car = Car(style, **kw)
    car.settle()
    car.throttle = 1.0
    t100 = t160 = None
    vmax = 0.0
    while car.t < 1.5 + 60.0:
        _hold_lane(car)
        car.step(DT)
        kmh = car.u * 3.6
        vmax = max(vmax, kmh)
        if t100 is None and kmh >= 100.0:
            t100 = car.t - 1.5
        if t160 is None and kmh >= 160.0:
            t160 = car.t - 1.5
    return {"t100": t100, "t160": t160, "vmax": vmax, "gear": car.gear, "rpm": car.rpm}


def braking(style, v0=100.0, **kw):
    """Droga hamowania z v0 km/h, pełny pedał."""
    car = Car(style, **kw)
    car.reset(v0 / 3.6)
    for _ in range(60):
        car.step(DT)
    x0 = car.X
    car.brake = 1.0
    car.throttle = 0.0
    while car.u > 0.3 and car.t < 30:
        _hold_lane(car)
        car.step(DT)
    return car.X - x0


def skidpad(style, R=60.0, **kw):
    """Jazda po okręgu R z wolno rosnącą prędkością. Zwraca maksymalne
    przyspieszenie boczne [g], gradient podsterowności [deg/g] (kąt kół vs ay
    przy 0,1-0,5 g) i przechył [deg/g]."""
    car = Car(style, **kw)
    car.reset(8.0)
    car._pick_gear()
    pts = []
    best = 0.0
    v_ref = 8.0
    lost = 0.0
    while car.t < 120.0:
        # Kierowca: punkt w przód po okręgu (pure pursuit), środek okręgu (0, R).
        cx, cy = 0.0, R
        ang = math.atan2(car.Y - cy, car.X - cx) + 12.0 / R
        tx, ty = cx + R * math.cos(ang), cy + R * math.sin(ang)
        dx, dy = tx - car.X, ty - car.Y
        lx = dx * math.cos(car.psi) + dy * math.sin(car.psi)
        ly = -dx * math.sin(car.psi) + dy * math.cos(car.psi)
        curv = 2.0 * ly / max(lx * lx + ly * ly, 1.0)
        ma = car.max_steer
        if car.steer_assist:
            ma += (math.radians(6.0) - ma) * min(abs(car.u) / 45.0, 1.0)
        want = math.atan(curv * car.L) * 1.0
        car.steer = max(-1.0, min(1.0, want / ma + (curv - car.r / max(car.u, 1.0)) * 4.0))
        v_ref += 0.08 * DT * 60.0 / 60.0 * 2.0      # ~0,16 m/s na sekundę
        e = v_ref - car.u
        car.throttle = max(0.0, min(1.0, e * 0.8 + 0.25))
        car.brake = max(0.0, min(1.0, -e * 0.5))
        car.step(DT)
        rad_err = math.hypot(car.X - cx, car.Y - cy) - R
        ay = car.u * car.r / G
        if abs(rad_err) < 1.5:
            lost = 0.0
            if car.t > 5.0:
                best = max(best, ay)
                d = (car.wheels[0].steer + car.wheels[1].steer) * 0.5
                pts.append((ay, math.degrees(d), math.degrees(car.phi)))
        else:
            lost += DT
            if lost > 1.0:
                break
    ug = roll_g = None
    sel = [p for p in pts if 0.1 <= p[0] <= 0.5]
    if len(sel) > 20:
        n = len(sel)
        mx = sum(p[0] for p in sel) / n
        my = sum(p[1] for p in sel) / n
        mr = sum(p[2] for p in sel) / n
        sxx = sum((p[0] - mx) ** 2 for p in sel)
        ug = sum((p[0] - mx) * (p[1] - my) for p in sel) / sxx
        roll_g = abs(sum((p[0] - mx) * (p[2] - mr) for p in sel) / sxx)
    return {"ay_max": best, "ug_deg_per_g": ug, "roll_deg_per_g": roll_g}


def sine_dwell(style, amp=1.0, v0=80.0, **kw):
    """Sinus z przerwą (jak test ESC FMVSS 126): 0,7 Hz, przerwa 0,5 s na
    drugim szczycie. Zwraca stosunek prędkości obrotu 1,0 s i 1,75 s po
    końcu skrętu do szczytu (norma: <= 0,35 i <= 0,20), przesunięcie boczne
    po 1,07 s (norma: >= 1,83 m) i czy koła oderwały się po jednej stronie."""
    car = Car(style, **kw)
    car.reset(v0 / 3.6)
    for _ in range(60):
        car.step(DT)
    t0 = car.t
    y0 = car.Y
    f = 0.7
    T1 = 0.75 / f
    peak = 0.0
    lift2 = False
    end = None
    rates = []
    lat107 = None
    while car.t - t0 < 6.0:
        tt = car.t - t0
        if tt < T1:
            st = amp * math.sin(2 * math.pi * f * tt)
        elif tt < T1 + 0.5:
            st = -amp
        elif tt < T1 + 0.5 + 0.25 / f:
            st = amp * math.sin(2 * math.pi * f * (tt - 0.5))
        else:
            st = 0.0
            if end is None:
                end = tt
        car.steer = st
        car.throttle = 0.0
        car.step(DT)
        peak = max(peak, abs(car.r))
        if lat107 is None and tt >= 1.07:
            lat107 = abs(car.Y - y0)
        l, r_ = car.lifted()
        if l >= 2 or r_ >= 2:
            lift2 = True
        rates.append((tt, car.r))
    def at(t):
        for tt, r in rates:
            if tt >= t:
                return abs(r)
        return abs(rates[-1][1])
    r1 = at(end + 1.0) / max(peak, 1e-6)
    r175 = at(end + 1.75) / max(peak, 1e-6)
    spin = abs(car.psi) > math.radians(90)
    return {"r1": r1, "r175": r175, "lat107": lat107, "lift2": lift2, "spin": spin,
            "pass": r1 <= 0.35 and r175 <= 0.20 and (lat107 or 0) >= 1.83}


def fishhook(style, v0=80.0, **kw):
    """Hak (fishhook, NHTSA): skręt w jedną stronę, szybko na pełno w drugą
    i trzymanie. Zwraca maksymalny przechył [deg], najmniejszy docisk koła
    wewnętrznego [% statycznego] i czy oderwały się dwa koła jednej strony."""
    car = Car(style, **kw)
    car.reset(v0 / 3.6)
    for _ in range(60):
        car.step(DT)
    t0 = car.t
    stat = car.m * G / 4
    max_roll = 0.0
    min_load = 1e9
    lift2 = False
    lift_t = 0.0
    while car.t - t0 < 4.0:
        tt = car.t - t0
        car.steer = 1.0 if tt < 0.6 else -1.0
        car.throttle = 0.0
        car.step(DT)
        max_roll = max(max_roll, abs(math.degrees(car.phi)))
        if tt > 0.6:
            min_load = min(min_load, min(car.wheels[1].load, car.wheels[3].load))
        l, r_ = car.lifted()
        if l >= 2 or r_ >= 2:
            lift2 = True
            lift_t += DT
    return {"roll": max_roll, "min_inner": min_load / stat, "lift2": lift2, "lift_time": lift_t}


def power_oversteer(style, R=40.0, **kw):
    """Na okręgu przy ~60% przyczepności pełny gaz: czy tył ucieka (kąt
    znoszenia nadwozia > 15 deg albo obrót > 90 deg)."""
    car = Car(style, **kw)
    ay_t = 0.6 * car.mu * car.grip * G
    v = math.sqrt(ay_t * R)
    car.reset(v)
    car._pick_gear()
    beta_max = 0.0
    while car.t < 6.0:
        cx, cy = 0.0, R
        ang = math.atan2(car.Y - cy, car.X - cx) + 10.0 / R
        tx, ty = cx + R * math.cos(ang), cy + R * math.sin(ang)
        dx, dy = tx - car.X, ty - car.Y
        lx = dx * math.cos(car.psi) + dy * math.sin(car.psi)
        ly = -dx * math.sin(car.psi) + dy * math.cos(car.psi)
        curv = 2.0 * ly / max(lx * lx + ly * ly, 1.0)
        ma = car.max_steer
        if car.steer_assist:
            ma += (math.radians(6.0) - ma) * min(abs(car.u) / 45.0, 1.0)
        car.steer = max(-1.0, min(1.0, math.atan(curv * car.L) / ma))
        car.throttle = 0.35 if car.t < 2.0 else 1.0
        car.step(DT)
        if car.t > 2.0:
            beta_max = max(beta_max, abs(math.degrees(math.atan2(car.v, max(car.u, 0.1)))))
    return {"beta_max": beta_max, "spin": beta_max > 15.0}


def landing(style, drop=1.5, **kw):
    """Upadek płasko z wysokości drop [m]: najmniejszy prześwit spodu
    nadwozia i czy zawieszenie dobiło do końca (spód uderza o jezdnię)."""
    car = Car(style, **kw)
    car.settle()
    static_clear = car.zo + car.s["body_bottom"]
    car.zo += drop
    car.min_clear = 9.0
    car.bottomed = False
    for _ in range(int(2.5 * 120)):
        car.step(DT)
    return {"static_clear": static_clear, "min_clear": car.min_clear, "bottomed": car.min_clear <= 0.0}


def ride(style, **kw):
    """Częstotliwości własne przód/tył [Hz] i współczynnik stabilności
    statycznej SSF = t/(2h) (im mniej, tym łatwiej dachuje)."""
    car = Car(style, **kw)
    car.settle()
    a = car.wheels[0].x
    b = -car.wheels[2].x
    mf = car.m * b / car.L / 2
    mr = car.m * a / car.L / 2
    fr = math.sqrt(car.k / mf) / (2 * math.pi)
    rr = math.sqrt(car.k / mr) / (2 * math.pi)
    return {"f_front": fr, "f_rear": rr, "h_cg": car.h, "ssf": car.s["track"] / (2 * car.h),
            "front_pct": 100.0 * b / car.L}


def report(style, name=None, **kw):
    out = {"name": name or (style or SEDAN).get("name", "?")}
    out.update(ride(style, **kw))
    out.update(accel(style, **kw))
    out["brake100"] = braking(style, **kw)
    out.update(skidpad(style, **kw))
    out["sd_esp"] = sine_dwell(style, **kw)
    kw2 = dict(kw)
    kw2["esp_on"] = False
    out["sd_noesp"] = sine_dwell(style, **kw2)
    out["sd120_esp"] = sine_dwell(style, v0=120.0, **kw)
    out["fish_esp"] = fishhook(style, **kw)
    out["fish_noesp"] = fishhook(style, **kw2)
    out["po_esp"] = power_oversteer(style, **kw)
    kw3 = dict(kw2)
    kw3["tcs_on"] = False
    out["po_off"] = power_oversteer(style, **kw3)
    out.update(landing(style, **kw))
    return out


if __name__ == "__main__":
    import json
    print(json.dumps(report(None), indent=1, default=str))
