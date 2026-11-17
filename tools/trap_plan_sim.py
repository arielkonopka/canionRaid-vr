#!/usr/bin/env python3
"""Odpowiednik scripts/trap_plan.gd (TrapPlan) - te same pułapki, miejsca
i parametry. W chmurze nie ma Godota, więc logikę sprawdzamy tutaj.
Bez HighwayPlan (StructurePlan i SectionPlan bez biomów i miast), więc
liczby zgadzają się z TrapPlan.new(code, StructurePlan.new(code),
SectionPlan.new(code)).

    python3 tools/trap_plan_sim.py [ziarno] [km]
"""
import math
import sys

from segment_code_sim import SegmentCode, SEG_LEN, mix
from structure_plan_sim import StructurePlan
from section_plan_sim import SectionPlan, WIDTH

# Drabina zapowiedzi wg trap_level: odległość znaku przed pułapką [m]
# (None = bez znaku - zostaje tylko naturalna zapowiedź, np. rękaw wiatru,
# widoczny szczyt, ciemna plama). SIGN_AT_3 = True: na poziomie 3 znak
# późno zamiast braku (decyzja użytkownika 2026-11-17: zawsze znak).
SIGN_DIST = [300.0, 150.0, 60.0, None]
SIGN_AT_3 = True
SIGN_LATE = 60.0
HANDLED = (0, 1, 6, 7, 9, 10, 11, 12, 13, 14)   # 4a; 8 - 4b; 2-5 - 4c (węzły)

# Parametry wg poziomu 0-3.
CURVE_R = [450.0, 350.0, 280.0, 220.0]     # 0: łuk po prostej (zaciska się do 0,7 R)
CURVE_TIGHTEN = 0.7
STRAIGHT_BEFORE = 1500.0
LIE_R = 180.0                              # 14: łuk naprawdę
LIE_TABLET = 120.0                         # 14: tabliczka mówi tyle km/h
DROP_GAP = [300.0, 200.0, 120.0, 60.0]     # 1: od wylotu tunelu do skosu zwężenia
QUEUE_GAP = [400.0, 250.0, 150.0, 80.0]    # 6: od szczytu do końca korka
QUEUE_LEN = [150.0, 200.0, 250.0, 300.0]
CLEAR = [4.6, 4.4, 4.2, 4.0]               # 7: prześwit wiaduktu [m]
TREE_OFF = [3.0, 2.0, 1.2, 0.8]            # 9: drzewo od krawędzi jezdni [m]
TREE_STEP = 12.0
BRIDGE_LANE = [3.75, 3.5, 3.25, 3.0]       # 10: szerokość pasa na moście, bez pobocza
GUST = [6.0, 9.0, 12.0, 15.0]              # 11: najsilniejszy podmuch [m/s]
PATCH_LEN = [30.0, 50.0, 80.0, 120.0]      # 12: plama
PATCH_GRIP = [0.85, 0.75, 0.6, 0.5]        # 12: przyczepność względem suchej
PATCH_KIND = ["milled", "oil", "ruts", "gravel"]
WORKS_TAPER = [1.0, 0.8, 0.6, 0.45]        # 13: skos robót x tyle
WINDSOCK_STEP = 300.0


def sign_d(level):
    if level == 3 and SIGN_AT_3:
        return SIGN_LATE
    return SIGN_DIST[level]


class TrapPlan:
    def __init__(self, code, structures, sections):
        self.code = code
        self.st = structures
        self.sec = sections
        self._cache = {}

    def trap(self, k):
        if k not in self._cache:
            self._cache[k] = self._make(k)
        return self._cache[k]

    def _structure_in(self, k, kind):
        for z in self.st.zones(k * SEG_LEN, (k + 1) * SEG_LEN):
            if z["structure"] == kind and z["start"] >= k * SEG_LEN and z["start"] < (k + 1) * SEG_LEN:
                return z
        return None

    def _make(self, k):
        seg = self.code.segment(k)
        t, lvl, var = seg["trap"], seg["trap_level"], seg["variant"]
        if t not in HANDLED:
            return None
        base = (k + (seg["trap_at"] + 0.5) / 4.0) * SEG_LEN
        tr = dict(k=k, trap=t, level=lvl)
        if t == 1:
            z = self._structure_in(k, 1)
            if z is None:
                return None
            tr.update(d=z["end"], drop_start=z["end"] + DROP_GAP[lvl], glare=True)
        elif t == 6:
            z = None
            for c in self.st.zones((k - 1) * SEG_LEN, (k + 1) * SEG_LEN):
                if c["structure"] == 4 and (k - 1) * SEG_LEN <= c["end"] < (k + 1) * SEG_LEN:
                    z = c
            if z is None:
                return None
            q_end = z["end"] + QUEUE_GAP[lvl]
            tr.update(d=z["end"], queue_end=q_end, queue_start=q_end + QUEUE_LEN[lvl],
                      hazards=lvl <= 2)
        elif t == 7:
            z = self._structure_in(k, 3)
            if z is None:
                return None
            tr.update(d=z["start"], clear=CLEAR[lvl])
        elif t == 10:
            z = self._structure_in(k, 2)
            if z is None:
                return None
            tr.update(d=z["start"], end=z["end"], lane_w=BRIDGE_LANE[lvl], shoulder=False)
        elif t == 11:
            z = self._structure_in(k, 6)
            if z is None:
                return None
            tr.update(d=z["start"], end=z["end"], gust=GUST[lvl])
        elif t in (9, 13):
            z = self.sec.zone(k)
            want = 4 if t == 9 else 6
            if z is None or z["section"] != want:
                return None
            if t == 9:
                tr.update(d=z["start"] + z["t_in"], end=z["end"] - z["t_out"], tree_off=TREE_OFF[lvl])
            else:
                tr.update(d=z["start"], end=z["end"], taper_k=WORKS_TAPER[lvl],
                          late_arrow=lvl >= 1, ghost_lines=lvl >= 2)
        elif t in (0, 14):
            if self._busy(base - STRAIGHT_BEFORE, base + 500.0):
                return None
            r = CURVE_R[lvl] if t == 0 else LIE_R
            tr.update(d=base, r=r, r_end=r * CURVE_TIGHTEN if t == 0 else r,
                      dir=1 if var & 4 else -1, angle=25.0 + 5.0 * (var & 3))
            if t == 14:
                tr["tablet"] = LIE_TABLET
        elif t == 12:
            if self._busy(base - 100.0, base + 200.0):
                return None
            tr.update(d=base, end=base + PATCH_LEN[lvl], grip=PATCH_GRIP[lvl], kind=PATCH_KIND[var & 3])
        return tr

    def _busy(self, d0, d1):
        """Budowla albo strefa przekroju w [d0, d1] - tam łuk/plama się nie mieści."""
        if self.st.zones(d0, d1):
            return True
        for z in self.sec.zones(d0, d1):
            if z["end"] > d0 and z["start"] < d1:
                return True
        return False

    def traps(self, d0, d1):
        out = []
        for k in range(max(int(math.floor(d0 / SEG_LEN)) - 2, 0), int(math.floor(d1 / SEG_LEN)) + 2):
            tr = self.trap(k)
            if tr and tr.get("end", tr["d"]) >= d0 - 400.0 and tr["d"] - 400.0 < d1:
                out.append(tr)
        return out

    def items(self, d0, d1):
        """Znaki i naturalne zapowiedzi [{d, x, kind}] posortowane po d."""
        out = []
        for tr in self.traps(d0, d1):
            out += self._items(tr)
        return sorted([i for i in out if d0 <= i["d"] < d1], key=lambda i: (i["d"], i["x"]))

    def _items(self, tr):
        t, lvl, d = tr["trap"], tr["level"], tr["d"]
        sd = sign_d(lvl)
        right = WIDTH / 2 + 1.0
        out = []
        sign = {0: "A-1" if tr.get("dir", 1) > 0 else "A-2", 1: "A-12", 6: "A-30", 7: "B-16",
                9: "", 10: "A-12c", 11: "A-19", 12: "A-15", 13: "", 14: "A-1" if tr.get("dir", 1) > 0 else "A-2"}[t]
        if t == 14:
            # Znak kłamie: zapowiedź jak na poziomie 0, tabliczka z prędkością za wysoką.
            out.append(dict(d=d - SIGN_DIST[0], x=right, kind=sign))
            out.append(dict(d=d - SIGN_DIST[0], x=right, kind="tablet_%d" % int(tr["tablet"])))
            return out
        if sign and sd is not None:
            at = tr["drop_start"] if t == 1 else (tr.get("queue_end", d))
            out.append(dict(d=at - sd, x=right, kind=sign))
        if t == 7:
            out.append(dict(d=d, x=0.0, kind="clearance_bar"))   # belka z wysokością na pomoście
        if t == 0:
            for i in range(6):
                out.append(dict(d=d + 20.0 + 25.0 * i, x=-right if tr["dir"] > 0 else right, kind="U-3"))
        if t == 6 and tr["hazards"]:
            out.append(dict(d=tr["queue_end"], x=0.0, kind="hazard_lights"))
        if t == 11:
            dd = d
            while dd < tr["end"]:
                out.append(dict(d=dd, x=right + 1.0, kind="windsock"))
                dd += WINDSOCK_STEP
        if t == 12:
            out.append(dict(d=d, x=0.0, kind="patch_" + tr["kind"]))
        if t == 9:
            dd = d
            while dd < tr["end"]:
                for x in (-1.0, 1.0):
                    out.append(dict(d=dd, x=x * (4.0 + tr["tree_off"]), kind="tree"))
                dd += TREE_STEP
        return out

    def surface_at(self, d):
        """Plama (pułapka 12): {kind, grip} albo None."""
        for tr in self.traps(d, d + 0.001):
            if tr["trap"] == 12 and tr["d"] <= d < tr["end"]:
                return dict(kind=tr["kind"], grip=tr["grip"])
        return None

    def gust(self, d, t):
        """Wiatr boczny [m/s, + w prawo] na estakadzie z pułapką 11 w chwili t [s].
        Porywy: suma dwóch sinusów (okresy 7 i 2,3 s) z fazą z hasha, zawsze
        0..gust, łagodnie narasta na pierwszych/ostatnich 100 m."""
        for tr in self.traps(d, d + 0.001):
            if tr["trap"] == 11 and tr["d"] <= d < tr["end"]:
                ph = mix(0x51ED270B, tr["k"]) / 4294967296.0 * 2 * math.pi
                s = 0.5 + 0.35 * math.sin(2 * math.pi * t / 7.0 + ph) + 0.15 * math.sin(2 * math.pi * t / 2.3 + 2 * ph)
                edge = min(1.0, (d - tr["d"]) / 100.0, (tr["end"] - d) / 100.0)
                side = 1.0 if tr["k"] % 2 == 0 else -1.0
                return side * tr["gust"] * max(s, 0.0) * edge
        return 0.0


def check(tp, km):
    errors = []
    d1 = km * 1000.0
    trs = tp.traps(0.0, d1)
    for tr in trs:
        seg = tp.code.segment(tr["k"])
        if seg["phase"] == "rest":
            errors.append("pułapka w odpoczynku %s" % tr)
        if tr["trap"] == 0 and tr["r_end"] * tr["r_end"] < 0:
            errors.append("x")
        if tr["trap"] in (0, 14) and tp._busy(tr["d"] - STRAIGHT_BEFORE, tr["d"] + 500.0):
            errors.append("łuk bez prostej %s" % tr)
    for it in tp.items(0.0, d1):
        if it["kind"] == "tree" and abs(it["x"]) < 4.0 + 0.7:
            errors.append("drzewo na jezdni %s" % it)
    t = 0.0
    for tr in trs:
        if tr["trap"] != 11:
            continue
        for i in range(200):
            g = tp.gust((tr["d"] + tr["end"]) / 2, i * 0.37)
            if abs(g) > tr["gust"] + 1e-6:
                errors.append("poryw ponad limit %s" % tr)
    for tr in trs:
        if tr["level"] != 3 or tr["trap"] == 14:
            continue
        signs = [i for i in tp._items(tr) if i["kind"][:2] in ("A-", "B-")]
        if not SIGN_AT_3 and signs:
            errors.append("znak na poziomie 3 %s" % tr)
        if SIGN_AT_3 and tr["trap"] not in (9, 13) and not signs:
            errors.append("poziom 3 bez znaku %s" % tr)
    lies = [tr["k"] for tr in trs if tr["trap"] == 14]
    for a, b in zip(lies, lies[1:]):
        if b - a < 33:
            errors.append("znak kłamie za często %d %d" % (a, b))
    return trs, errors


def main():
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 777
    km = float(sys.argv[2]) if len(sys.argv) > 2 else 300.0
    code = SegmentCode(seed)
    tp = TrapPlan(code, StructurePlan(code), SectionPlan(code))
    trs, errors = check(tp, km)
    from collections import Counter
    c = Counter(tr["trap"] for tr in trs)
    print("ziarno %d, %.0f km: pułapek %d %s (co %.1f km)" % (seed, km, len(trs), dict(sorted(c.items())), km / max(len(trs), 1)))
    for tr in trs[:8]:
        print("  k %3d puł %2d poz %d na %.0f m" % (tr["k"], tr["trap"], tr["level"], tr["d"]))
    ci = Counter(i["kind"] for i in tp.items(0.0, km * 1000.0))
    print("  elementy:", dict(sorted(ci.items())))
    print("TRAP_SIM: OK" if not errors else "TRAP_SIM: BŁĘDY %d\n  %s" % (len(errors), "\n  ".join(errors[:10])))
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())
