#!/usr/bin/env python3
"""Odpowiednik scripts/structure_plan.gd (StructurePlan) - te same strefy
budowli i profil wysokości. W chmurze nie ma Godota, więc logikę
sprawdzamy tutaj. Bez HighwayPlan (biomy, miasta, stacje, skocznie nie
filtrują budowli - w Godocie filtrują), więc liczby zgadzają się
z StructurePlan.new(SegmentCode, null).

    python3 tools/structure_plan_sim.py [ziarno] [km] [płasko: 0/1]
"""
import math
import sys

from segment_code_sim import SegmentCode, SEG_LEN

APPROACH = 200.0          # budowla zaczyna się tyle metrów za początkiem odcinka
GAP = 400.0               # odstęp od końca poprzedniej budowli
# Długości [m] wg s_len (0-3) dla budowli.
LEN = {1: [400.0, 800.0, 1300.0, 2000.0],      # tunel
       2: [80.0, 150.0, 250.0, 400.0],         # most: szerokość rzeki
       3: [14.0, 14.0, 14.0, 14.0],            # wiadukt kolejowy: szerokość pomostu
       4: [1200.0, 1800.0, 2400.0, 3600.0],    # podjazd
       5: [1000.0, 1500.0, 2000.0, 2500.0],    # zjazd z serpentynami
       6: [400.0, 700.0, 1000.0, 1500.0]}      # estakada
BRIDGE_BANK = 60.0        # przęsła nad brzegiem po obu stronach rzeki
GRADE = [3.0, 4.0, 4.5, 5.0, 5.5, 6.0, 7.0, 8.0]   # [%] wg s_param (podjazd, zjazd)
G_RETURN = 2.0            # [%] powrót na dół poza budowlami, gdy droga jest wysoko
H_MAX = 300.0             # najwyżej tyle nad poziomem bazowym [m]
K_VC = 60.0               # łuk pionowy: długość = K * |zmiana pochylenia w %| [m]
VC_MIN = 80.0
MIN_PIECE = 150.0         # najkrótszy kawałek profilu (łuk pionowy musi się zmieścić)
LEAD = 70.0               # poziomo przed i za płaską budowlą (> połowa łuku 2%)
CLEAR_RAIL = 6.5          # prześwit pod wiaduktem [m] (pułapka 7: niski)
CLEAR_RAIL_LOW = 4.4
TUNNEL_COVER = [30.0, 60.0, 90.0, 140.0]   # góra nad tunelem wg s_param & 3
PIER_STEP = {2: 45.0, 6: 55.0}
PIER_MIN = 3.0            # niższy filar = przyczółek, nie stawiamy
LIMIT = {1: 100.0, 5: 80.0}               # tunel, serpentyny (reszta bez zmiany)
SERP_R = [250.0, 300.0, 350.0, 400.0]   # promień łuków zjazdu wg s_param & 3 (górska autostrada)
HANDLED = (1, 2, 3, 4, 5, 6)              # 7 (miasto) - etap 5


class StructurePlan:
    def __init__(self, code, slopes=True):
        self.code = code
        self.slopes = slopes
        self.zones_k = []      # strefy po kolei
        self.nodes = [(0.0, 0.0, True)]   # węzły profilu (d, h), liniowo między nimi
        self.k_done = -1
        self.busy_until = -1e9
        self.h = 0.0           # wysokość na końcu policzonego profilu
        self.d_end = 0.0       # do kąd policzony profil

    # --- budowa po kolei ---
    def _ensure(self, d):
        while self.d_end < d + 4 * SEG_LEN:
            self._step(self.k_done + 1)

    def _go(self, d_to, grade, lock=False):
        """Profil od d_end do d_to ze stałym pochyleniem [%] (z obcięciem
        do 0 i H_MAX - wtedy płasko dalej)."""
        if d_to <= self.d_end:
            return
        g = grade / 100.0
        h_to = self.h + g * (d_to - self.d_end)
        if g < 0 and h_to < 0:
            d0 = self.d_end + self.h / -g
            self._node(d0, 0.0)
            self._node(d_to, 0.0, lock)
        elif g > 0 and h_to > H_MAX:
            d0 = self.d_end + (H_MAX - self.h) / g
            self._node(d0, H_MAX)
            self._node(d_to, H_MAX, lock)
        else:
            self._node(d_to, h_to, lock)

    def _node(self, d, h, lock=False):
        """Nowy węzeł profilu. Węzły zablokowane (brzegi płaskich budowli)
        się nie ruszają; krótszy niż MIN_PIECE kawałek przed nowym węzłem
        znika (łuk pionowy nie zmieściłby się), a ten sam kierunek
        przesuwa ostatni węzeł."""
        if d <= self.nodes[-1][0] + 1e-6:
            return
        if len(self.nodes) >= 2 and not self.nodes[-1][2] \
                and self.nodes[-1][0] - self.nodes[-2][0] < MIN_PIECE:
            self.nodes.pop()
        if len(self.nodes) >= 2 and not self.nodes[-1][2]:
            (d1, h1, _), (d2, h2, _) = self.nodes[-2], self.nodes[-1]
            if abs((h2 - h1) / (d2 - d1) - (h - h2) / (d - d2)) < 1e-9:
                self.nodes.pop()
        self.nodes.append((d, h, lock))
        self.d_end, self.h = d, h

    def _plain(self, d_to):
        # Zjazd na dół co najmniej na 2 * VC_MIN metrach (resztka wysokości
        # nie robi krótkiego załamania).
        self._go(d_to, -min(G_RETURN, 100.0 * self.h / (2 * VC_MIN)) if self.h > 0 else 0.0)

    def _step(self, k):
        self.k_done = k
        seg = self.code.segment(k)
        st, p = seg["structure"], seg["s_param"]
        z = None
        if st in HANDLED and (self.slopes or st not in (4, 5)):
            start = k * SEG_LEN + APPROACH
            if start - LEAD >= self.busy_until + GAP and start - LEAD >= self.d_end - 1e-6:
                z = self._zone(k, seg, start)
        if z is None:
            self._plain((k + 1) * SEG_LEN)
            return
        st = z["structure"]
        if st in (4, 5):
            self._plain(z["start"])
            z["h"] = self.h
            self._go(z["end"], z["grade"] if st == 4 else -z["grade"])
        else:
            # Budowla płaska: poziomo już LEAD przed nią i LEAD za nią, żeby
            # łuki pionowe nie wchodziły na most / do tunelu.
            self._plain(z["start"] - LEAD)
            dl, hl, _ = self.nodes[-1]
            self.nodes[-1] = (dl, hl, True)
            z["h"] = self.h
            self._go(z["end"] + LEAD, 0.0, True)
        z["h_end"] = self.h
        self.zones_k.append(z)
        self.busy_until = z["end"] + (0.0 if st in (4, 5) else LEAD)
        self._plain(max((k + 1) * SEG_LEN, z["end"]))

    def _zone(self, k, seg, start):
        st, ln, p = seg["structure"], seg["s_len"], seg["s_param"]
        z = dict(k=k, structure=st, start=start, trap=seg["trap"])
        if st == 2:
            river = LEN[2][ln]
            z.update(river=river, clear=8.0 + 3.0 * p, length=river + 2 * BRIDGE_BANK)
        elif st == 3:
            z.update(length=LEN[3][ln], clear=CLEAR_RAIL_LOW if seg["trap"] == 7 else CLEAR_RAIL,
                     train=p & 3, freight=bool(p & 4))
        elif st == 1:
            z.update(length=LEN[1][ln], lit=(p & 3) != 1, curved=(p & 3) == 2,
                     cover=TUNNEL_COVER[p & 3], limit=LIMIT[1])
        elif st == 4:
            z.update(length=LEN[4][ln], grade=GRADE[p])
        elif st == 5:
            g = GRADE[p]
            ln_m = min(LEN[5][ln], self.h / (g / 100.0)) if self.h > 0 else 0.0
            if ln_m < 600.0:
                return None       # zjazd z płaskiego: nie ma skąd zjeżdżać
            z.update(length=ln_m, grade=g, serp_r=SERP_R[p & 3], limit=LIMIT[5])
        elif st == 6:
            z.update(length=LEN[6][ln], depth=20.0 + 8.0 * p)
        z["end"] = start + z["length"]
        return z

    # --- odczyt ---
    def zones(self, d0, d1):
        self._ensure(d1)
        return [z for z in self.zones_k if z["end"] > d0 and z["start"] < d1]

    def zone_at(self, d):
        for z in self.zones(d, d + 0.001):
            if z["start"] <= d < z["end"]:
                return z
        return None

    def _seg_index(self, d):
        lo, hi = 0, len(self.nodes) - 1
        while hi - lo > 1:
            m = (lo + hi) // 2
            if self.nodes[m][0] <= d:
                lo = m
            else:
                hi = m
        return lo

    def _grade_piece(self, i):
        (d1, h1, _), (d2, h2, _) = self.nodes[i], self.nodes[i + 1]
        return (h2 - h1) / (d2 - d1)

    def _vc(self, i):
        """Łuk pionowy w węźle i (1..n-2): (długość, g1, g2)."""
        g1, g2 = self._grade_piece(i - 1), self._grade_piece(i)
        l_prev = self.nodes[i][0] - self.nodes[i - 1][0]
        l_next = self.nodes[i + 1][0] - self.nodes[i][0]
        lc = max(K_VC * abs(g2 - g1) * 100.0, VC_MIN)
        lc = min(lc, 0.9 * min(l_prev, l_next))
        return lc, g1, g2

    def height_at(self, d):
        """Wysokość jezdni nad poziomem bazowym (ROAD_Y) [m], z łukami
        pionowymi (parabola) w węzłach profilu."""
        d = max(d, 0.0)
        self._ensure(d)
        i = self._seg_index(d)
        for j in (i, i + 1):
            if 1 <= j <= len(self.nodes) - 2:
                lc, g1, g2 = self._vc(j)
                dj, hj, _ = self.nodes[j]
                if abs(d - dj) < lc / 2:
                    x = d - (dj - lc / 2)
                    return hj - g1 * lc / 2 + g1 * x + (g2 - g1) * x * x / (2 * lc)
        (d1, h1, _), (d2, h2, _) = self.nodes[i], self.nodes[i + 1]
        return h1 + (h2 - h1) * (d - d1) / (d2 - d1)

    def grade_at(self, d):
        return (self.height_at(d + 1.0) - self.height_at(d - 1.0)) / 2.0

    def ground_at(self, d):
        """{y, water, over}: wysokość terenu pod jezdnią (bez nasypu: y =
        height_at), woda pod mostem, `over` = szczyt góry nad tunelem albo
        None."""
        h = self.height_at(d)
        z = self.zone_at(d)
        out = dict(y=h, water=False, over=None)
        if z is None:
            return out
        u = d - z["start"]
        if z["structure"] == 2:
            depth = z["clear"] + 1.0
            r0, r1 = BRIDGE_BANK, BRIDGE_BANK + z["river"]
            if r0 <= u < r1:
                out.update(y=h - depth, water=True)
            else:
                t = u / r0 if u < r0 else (z["length"] - u) / r0
                out["y"] = h - depth * (1.0 - t)        # brzeg opada do wody
        elif z["structure"] == 6:
            t = u / z["length"]
            out["y"] = h - z["depth"] * math.sin(math.pi * t)
        elif z["structure"] == 1:
            t = u / z["length"]
            out["over"] = h + 8.0 + z["cover"] * math.sin(math.pi * t)
        return out

    def piers(self, d0, d1):
        """Filary mostów i estakad: [{d, top, bottom}]."""
        out = []
        for z in self.zones(d0, d1):
            if z["structure"] not in PIER_STEP:
                continue
            step = PIER_STEP[z["structure"]]
            n = max(int(z["length"] / step), 1)
            for i in range(1, n):
                d = z["start"] + i * z["length"] / n
                if d0 <= d < d1:
                    g = self.ground_at(d)
                    if self.height_at(d) - g["y"] >= PIER_MIN:
                        out.append(dict(d=d, top=self.height_at(d), bottom=g["y"]))
        return out

    def limit_at(self, d):
        z = self.zone_at(d)
        if z is not None and "limit" in z:
            return z["limit"]
        return 140.0


def check(sp, km):
    errors = []
    d1 = km * 1000.0
    zs = sp.zones(0.0, d1)
    prev = -1e9
    for z in zs:
        if z["start"] < prev + GAP - 1e-6:
            errors.append("budowle za blisko %s" % z)
        prev = z["end"]
        if z["structure"] in (4, 5) and not sp.slopes:
            errors.append("podjazd przy płaskiej drodze %s" % z)
    d = 0.0
    hp = sp.height_at(0.0)
    gp = 0.0
    while d < d1:
        h = sp.height_at(d)
        if h < -1e-6 or h > H_MAX + 1e-6:
            errors.append("wysokość %.1f na %.0f m" % (h, d))
        g = (h - hp) / 5.0
        if d > 0 and abs(g) > GRADE[-1] / 100.0 + 1e-6:
            errors.append("pochylenie %.1f%% na %.0f m" % (g * 100, d))
        if d > 5 and abs(g - gp) > 0.004:
            errors.append("skok pochylenia %.2f%% na %.0f m" % ((g - gp) * 100, d))
        if not sp.slopes and abs(h) > 1e-6:
            errors.append("płasko, a wysokość %.1f na %.0f m" % (h, d))
        z = sp.zone_at(d)
        if z is not None and z["structure"] in (1, 2, 3, 6):
            u = d - z["start"]
            if abs(sp.height_at(z["start"]) - h) > 0.05 and VC_MIN < u < z["length"] - VC_MIN:
                errors.append("budowla %d nie jest płaska na %.0f m" % (z["structure"], d))
        gr = sp.ground_at(d)
        if gr["y"] > h + 1e-6:
            errors.append("teren nad jezdnią na %.0f m" % d)
        hp, gp = h, g
        d += 5.0
    for p in sp.piers(0.0, d1):
        if p["top"] - p["bottom"] < 3.0:
            errors.append("filar za niski %s" % p)
    return zs, errors


def main():
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 777
    km = float(sys.argv[2]) if len(sys.argv) > 2 else 300.0
    slopes = (sys.argv[3] != "1") if len(sys.argv) > 3 else True
    sp = StructurePlan(SegmentCode(seed), slopes)
    zs, errors = check(sp, km)
    from collections import Counter
    c = Counter(z["structure"] for z in zs)
    cover = sum(z["end"] - z["start"] for z in zs) / (km * 1000.0)
    hs = [sp.height_at(d * 100.0) for d in range(int(km * 10))]
    print("ziarno %d, %.0f km, %s: budowli %d %s, %.0f%% trasy, wysokość max %.0f m, średnio %.0f m" % (
        seed, km, "pochylenia" if slopes else "płasko", len(zs), dict(sorted(c.items())), 100 * cover, max(hs), sum(hs) / len(hs)))
    for z in zs[:8]:
        print("  k %3d bud %d %.0f-%.0f m, h %.1f -> %.1f" % (z["k"], z["structure"], z["start"], z["end"], z["h"], z["h_end"]))
    print("  filarów: %d" % len(sp.piers(0.0, km * 1000.0)))
    print("STRUCTURE_SIM: OK" if not errors else "STRUCTURE_SIM: BŁĘDY %d\n  %s" % (len(errors), "\n  ".join(errors[:10])))
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())
