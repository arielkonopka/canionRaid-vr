#!/usr/bin/env python3
"""Odpowiednik scripts/weather_plan.gd (WeatherPlan) - ten sam hash, te same
liczby. W chmurze nie ma Godota, więc logikę pogody sprawdzamy tutaj.
Biom: stały ("fields" albo z argumentu), bo HighwayPlan losuje biomy
hashem Godota, którego tu nie odtworzymy.

    python3 tools/weather_sim.py [ziarno] [km] [biom]

Wypisuje fronty w pierwszych km, udział czasu z opadem / mokrą jezdnią
i sprawdza niezmienniki (to samo co tests/weather_plan_test.gd).
"""
import math
import sys

FRONT_BLOCK = 12000.0
FRONT_FIRST = 6000.0
P0, P_PER_KM, P_MAX = 0.35, 0.0015, 0.7
APPROACH_MIN, APPROACH_MAX = 2000.0, 3000.0
CORE_MIN, CORE_MAX = 1000.0, 4000.0
CLEAR = 1500.0
RAMP = 300.0
DRY_LAG = 1000.0
DOWNPOUR0, DOWNPOUR_MAX, DOWNPOUR_PER_KM = 0.3, 0.6, 0.001
MOUNTAIN_FREEZE = 0.5
WET_RAIN = 0.5


def mix(h, v):
    h = (h ^ (v & 0xFFFFFFFF)) & 0xFFFFFFFF
    h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xFFFFFFFF
    h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xFFFFFFFF
    return (h ^ (h >> 16)) & 0xFFFFFFFF


def lerp(a, b, t):
    return a + (b - a) * t


def smooth(e0, e1, x):
    # Godot smoothstep: 0 przed e0, 1 za e1, 3t^2 - 2t^3.
    if e1 == e0:
        return 0.0 if x < e0 else 1.0
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


class Weather:
    def __init__(self, seed=1, biome="fields"):
        self.seed = seed
        self.biome = biome

    def h01(self, block, salt):
        h = mix(0x9E3779B9, self.seed)
        h = mix(h, block)
        h = mix(h, salt)
        return h / 4294967296.0

    def front(self, b):
        if b < 0:
            return None
        b0 = b * FRONT_BLOCK
        km = b0 / 1000.0
        p = min(P0 + P_PER_KM * km, P_MAX)
        if self.h01(b, 1) >= p:
            return None
        approach = lerp(APPROACH_MIN, APPROACH_MAX, self.h01(b, 2))
        core = lerp(CORE_MIN, CORE_MAX, self.h01(b, 3))
        total = approach + core + CLEAR
        start = b0 + self.h01(b, 4) * (FRONT_BLOCK - total - DRY_LAG)
        if start < FRONT_FIRST:
            return None
        p_down = min(DOWNPOUR0 + DOWNPOUR_PER_KM * km, DOWNPOUR_MAX)
        f = dict(start=start, rain_start=start + approach, rain_end=start + approach + core,
                 end=start + total, peak=2.0 if self.h01(b, 5) < p_down else 1.0,
                 kind="rain", freezing=False, fog=0.15, wind=0.2 * self.h01(b, 6),
                 wind_sign=1.0 if self.h01(b, 7) < 0.5 else -1.0)
        if self.biome == "desert":
            f.update(kind="dust", peak=0.0, fog=0.6, wind=0.4 + 0.4 * self.h01(b, 6))
        elif self.biome == "mountains":
            f["fog"] = 0.4
            if self.h01(b, 8) < MOUNTAIN_FREEZE:
                f.update(kind="snow", freezing=True)
        elif self.biome == "seaside":
            f.update(kind="wind", fog=0.35, wind=0.5 + 0.5 * self.h01(b, 6))
        return f

    def front_at(self, d):
        b = int(math.floor(max(d, 0.0) / FRONT_BLOCK))
        f = self.front(b)
        if f is None or d < f["start"] or d >= f["end"] + DRY_LAG:
            return None
        return f

    def weather(self, d):
        w = dict(cloud=0.0, rain=0.0, fog=0.0, wind=0.0)
        f = self.front_at(d)
        if f is None or d >= f["end"]:
            return w
        s0, r0, r1, e = f["start"], f["rain_start"], f["rain_end"], f["end"]
        cloud = smooth(s0, r0, d) * (1.0 - smooth(r1, e, d))
        rain = f["peak"] * smooth(r0, r0 + RAMP, d) * (1.0 - smooth(r1 - RAMP, r1, d))
        return dict(cloud=cloud, rain=rain, fog=f["fog"] * cloud, wind=f["wind"] * cloud)

    def surface(self, d, on_bridge=False):
        f = self.front_at(d)
        if f is None or f["peak"] < WET_RAIN:
            return "dry"
        if d < f["rain_start"] or d >= f["rain_end"] + DRY_LAG:
            return "dry"
        if f["freezing"] and on_bridge:
            return "ice"
        return "wet"


def check(seed, km, biome):
    w = Weather(seed, biome)
    errors = []
    step = 25.0
    n = int(km * 1000 / step)
    raining = wet = 0
    for i in range(n):
        d = i * step
        x = w.weather(d)
        s = w.surface(d)
        if x["rain"] >= WET_RAIN:
            raining += 1
            if s != "wet":
                errors.append("opad %.2f, a jezdnia %s na %.0f m" % (x["rain"], s, d))
        if s == "wet":
            wet += 1
        if d < FRONT_FIRST and (x["cloud"] > 0 or s != "dry"):
            errors.append("pogoda przed FRONT_FIRST na %.0f m" % d)
        if not (0.0 <= x["cloud"] <= 1.0 and 0.0 <= x["rain"] <= 2.0):
            errors.append("zakres na %.0f m: %s" % (d, x))
    # Zapowiedź: pierwsza kropla nie wcześniej niż APPROACH_MIN za początkiem chmur,
    # a chmury w miejscu pierwszej kropli są już > 0,9.
    fronts = [w.front(b) for b in range(int(km * 1000 / FRONT_BLOCK) + 1)]
    fronts = [f for f in fronts if f]
    for f in fronts:
        if f["rain_start"] - f["start"] < APPROACH_MIN - 1e-6:
            errors.append("za krótka zapowiedź %s" % f)
        if w.weather(f["rain_start"] + RAMP)["cloud"] < 0.9 and f["peak"] > 0:
            errors.append("pada spod jasnego nieba %s" % f)
        if f["end"] + DRY_LAG > (math.floor(f["start"] / FRONT_BLOCK) + 1) * FRONT_BLOCK + 1e-6:
            errors.append("front wychodzi poza blok %s" % f)
    return w, fronts, raining / n, wet / n, errors


def main():
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 777
    km = float(sys.argv[2]) if len(sys.argv) > 2 else 300.0
    biome = sys.argv[3] if len(sys.argv) > 3 else "fields"
    w, fronts, rain_frac, wet_frac, errors = check(seed, km, biome)
    print("ziarno %d, %.0f km, biom %s: frontów %d (co %.1f km średnio)" % (
        seed, km, biome, len(fronts), km / max(len(fronts), 1)))
    for f in fronts[:6]:
        print("  km %.1f-%.1f, opad %.1f-%.1f, %s %s" % (
            f["start"] / 1000, f["end"] / 1000, f["rain_start"] / 1000, f["rain_end"] / 1000,
            f["kind"], "ulewa" if f["peak"] == 2.0 else ("mżawka" if f["peak"] == 1.0 else "bez opadu")))
    print("opad >= %.1f: %.1f%% trasy, mokra jezdnia: %.1f%% trasy" % (WET_RAIN, 100 * rain_frac, 100 * wet_frac))
    print("WEATHER_SIM: OK" if not errors else "WEATHER_SIM: BŁĘDY %d\n  %s" % (len(errors), "\n  ".join(errors[:10])))
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())
