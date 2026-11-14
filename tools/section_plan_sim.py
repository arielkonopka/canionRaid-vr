#!/usr/bin/env python3
"""Odpowiednik scripts/section_plan.gd (SectionPlan) - te same strefy,
pasy i pachołki. W chmurze nie ma Godota, więc logikę sprawdzamy tutaj.
Bez HighwayPlan (miasta, stacje, skocznie nie blokują stref - w Godocie
blokują), więc liczby zgadzają się z SectionPlan.new(SegmentCode, null).

    python3 tools/section_plan_sim.py [ziarno] [km]
"""
import math
import sys

from segment_code_sim import SegmentCode, SEG_LEN

# Geometria jak HighwayGenerator (x w prawo od osi naszej jezdni).
LANE_W = 3.75
WIDTH = 11.25
X_RIGHT = 0.75            # środek prawego pasa 2+2
X_LEFT = -3.0             # środek lewego pasa 2+2
X_SPLIT = -1.125          # linia między pasami 2+2
LANE_W_ROAD = 3.5         # pas zwykłej drogi (1+1, 2+1)

# Strefy
CHANGE_F = [0.0, 0.25, 0.5, 0.75]   # change_at -> ułamek odcinka
GAP_MIN = 500.0           # odstęp od końca poprzedniej strefy (> WARN)
# Najkrótszy środek strefy (pełny przekrój) [m]: zwykła droga krócej niż
# ~1 km wyglądałaby na pomyłkę projektanta.
BODY_MIN = {7: 200.0, 6: 300.0, 2: 400.0, 4: 900.0, 3: 1100.0}
WARN = 400.0              # pierwsza zapowiedź przed strefą (~10 s przy 140)
OUT_TAPER = 60.0          # skos pachołków na wyjeździe ze strefy
CONE_TAPER_STEP = 9.0
CONE_BODY_STEP = 18.0
POST_STEP = 12.0          # słupki rozdzielające kierunki na robotach
MAX_SEGS = 5              # strefa najwyżej tyle odcinków (6 km)
LOOKBACK = MAX_SEGS + 1
HANDLED = (2, 3, 4, 6, 7)  # 1 (podjazd) i 5 (rozjazd) - etap 3

LIMIT = {7: 100.0, 6: 80.0, 4: 90.0, 3: 90.0, 2: 140.0}
SIGN_IN = {7: "A-12", 6: "A-14", 4: "D-10", 3: "D-10", 2: ""}


def taper_len(w, v_kmh):
    """Skos zmiany pasa [m]: L = W * S (stopy, mph) jak w MUTCD; W w m,
    S w mph -> metry. 3,75 m przy 100 km/h = 233 m, przy 80 = 186 m."""
    return w * v_kmh / 1.609


class SectionPlan:
    def __init__(self, code):
        self.code = code
        self._zones = {}

    def p(self, k):
        s = self.code.segment(k)
        return (k + CHANGE_F[s["change_at"]]) * SEG_LEN

    def sec(self, k):
        if k < 0:
            return 0
        v = self.code.segment(k)["section"]
        return v if v in HANDLED else 0

    def zone(self, k):
        """Strefa zaczynająca się w odcinku k albo None."""
        if k in self._zones:
            return self._zones[k]
        z = self._make(k)
        self._zones[k] = z
        return z

    def _make(self, k):
        s = self.sec(k)
        if s == 0 or self.sec(k - 1) == s:
            return None
        j = k + 1
        while self.sec(j) == s and j - k < MAX_SEGS:
            j += 1
        start, end = self.p(k), self.p(j)
        # Odstęp od poprzedniej strefy (ta kończy się w p(k) albo p(k - 1)),
        # żeby zapowiedzi i ograniczenia nie wpadały w poprzednią strefę.
        if self.sec(k - 1) != 0:
            start += GAP_MIN
        elif self.sec(k - 2) != 0:
            start = max(start, self.p(k - 1) + GAP_MIN)
        seg = self.code.segment(k)
        lim = LIMIT[s]
        t_in = taper_len(LANE_W, lim) if s != 2 else taper_len(LANE_W, lim) * 0.5
        t_out = OUT_TAPER if s in (7, 6) else t_in
        if end - start < t_in + BODY_MIN[s] + t_out:
            return None
        return dict(k=k, section=s, start=start, end=end, t_in=t_in, t_out=t_out, limit=lim,
                    side=seg["variant"] & 1, first=seg["variant"] >> 1 & 1)

    def zones(self, d0, d1):
        out = []
        k0 = max(int(math.floor(d0 / SEG_LEN)) - LOOKBACK, 0)
        k1 = int(math.floor(d1 / SEG_LEN)) + 1
        for k in range(k0, k1 + 1):
            z = self.zone(k)
            if z and z["end"] > d0 - WARN and z["start"] - WARN < d1:
                out.append(z)
        return out

    def zone_at(self, d):
        for z in self.zones(d, d):
            if z["start"] <= d < z["end"]:
                return z
        return None

    def limit_at(self, d):
        """Ograniczenie od strefy (140 poza nią). Stopniowanie: przy celu
        < 100 najpierw 100 od WARN, cel od WARN / 2."""
        for z in self.zones(d, d):
            if d >= z["end"]:
                continue
            if d >= z["start"] - WARN / 2:
                return z["limit"]
            if d >= z["start"] - WARN:
                return max(z["limit"], 100.0) if z["limit"] < 100 else z["limit"]
        return 140.0

    def limit_marks(self, d0, d1):
        """Zmiany ograniczenia od stref [[d, limit]] w [d0, d1) - generator
        dzieli w nich odcinki (jak HighwayPlan.limit_changes) i bierze
        min(plan.limit_at, limit_at)."""
        out = []
        for z in self.zones(d0, d1):
            if z["limit"] >= 140.0:
                continue
            ms = [z["start"] - WARN]
            if z["limit"] < 100.0:
                ms.append(z["start"] - WARN / 2)
            ms.append(z["end"])
            for m in ms:
                if d0 <= m < d1:
                    out.append([m, self.limit_at(m + 0.25)])
        return sorted(out)

    def lanes_at(self, d):
        """{fwd: [x], onc: [x], width, single, closing, other_closed}: środki pasów naszego
        kierunku (0 = najbardziej prawy) i kierunku przeciwnego na NASZEJ
        jezdni [m w prawo od osi naszej jezdni; jezdnia symetryczna wokół
        osi, szerokość `width`]. Pas zamykany (`closing`, x albo None) nie
        jest już w fwd - boty zjeżdżają z niego przed skosem. Pasy, które
        trwają, przesuwają się płynnie (bez skoków)."""
        z = self.zone_at(d)
        if z is None:
            return dict(fwd=hwy_lanes(2, WIDTH), onc=[], width=WIDTH, single=False, closing=None,
                        other_closed=False)
        s, side = z["section"], z["side"]
        u, t_in, t_out = d - z["start"], z["t_in"], z["t_out"]
        v = z["end"] - d                       # do końca strefy
        f = min(u / t_in, 1.0, v / t_out)      # 0 na brzegach, 1 w środku strefy
        body = u >= t_in and v > t_out
        out = dict(fwd=[], onc=[], width=WIDTH, single=False, closing=None,
                   other_closed=s in (6, 4, 3))
        if s in (7, 6):
            lanes = hwy_lanes(2, WIDTH)        # [prawy, lewy]
            keep = 0 if (s == 6 or side) else 1
            out["fwd"] = [lanes[keep]]
            if u < t_in:
                out["closing"] = lanes[1 - keep]
            if s == 6 and body:
                out["onc"] = [lanes[1]]        # przeciwny kierunek na naszym lewym pasie
        elif s == 2:
            w = WIDTH + LANE_W * f
            out["width"] = w
            if body:
                out["fwd"] = hwy_lanes(3, w)
            else:
                out["fwd"] = hwy_lanes(2, w)
                if v <= t_out:
                    out["closing"] = hwy_lanes(3, w)[0]
        else:                                  # 4: 1+1, 3: 2+1 - zwykła droga
            w_body = (2 if s == 4 else 3) * LANE_W_ROAD + 1.0
            out["width"] = WIDTH + (w_body - WIDTH) * f
            out["single"] = f > 0.0
            right = X_RIGHT + (w_body / 2 - 0.5 - LANE_W_ROAD / 2 - X_RIGHT) * f
            if not body:
                out["fwd"] = [right]
                if u < t_in:
                    out["closing"] = hwy_lanes(2, WIDTH)[1]
                return out
            if s == 4:
                out["fwd"], out["onc"] = [right], [right - LANE_W_ROAD]
            else:
                ub = u - t_in
                ours = (int(ub / ALT_LEN) + z["first"]) % 2 == 0
                left_in_phase = ALT_LEN - (ub % ALT_LEN)
                mid, left = right - LANE_W_ROAD, right - 2 * LANE_W_ROAD
                if ours:
                    if left_in_phase < ALT_END or v - t_out < ALT_END:
                        out["fwd"], out["onc"], out["closing"] = [right], [left], mid
                    else:
                        out["fwd"], out["onc"] = [right, mid], [left]
                else:
                    if left_in_phase < ALT_END or v - t_out < ALT_END:
                        out["fwd"], out["onc"] = [right], [left]
                    else:
                        out["fwd"], out["onc"] = [right], [mid, left]
        return out

    def items(self, d0, d1):
        """Pachołki, słupki i znaki: [{d, x, kind}] posortowane po d."""
        out = []
        for z in self.zones(d0, d1):
            out += self._zone_items(z)
        return sorted([i for i in out if d0 <= i["d"] < d1], key=lambda i: (i["d"], i["x"]))

    def _zone_items(self, z):
        s, side, a, e, t = z["section"], z["side"], z["start"], z["end"], z["t_in"]
        out = []
        # Zapowiedzi: znak ostrzegawczy i ograniczenie (B-33 stawia generator
        # przy zmianie "limit"), po prawej, jak dziś znaki.
        if SIGN_IN[s]:
            out.append(dict(d=a - WARN, x=WIDTH / 2 + 1.0, kind=SIGN_IN[s]))
        if s in (7, 6):
            closed = X_LEFT if (s == 6 or side) else X_RIGHT
            sgn = -1.0 if closed < 0 else 1.0
            outer = closed + sgn * (LANE_W / 2 - 0.3)   # przy krawędzi pasa zamkniętego
            inner = X_SPLIT + sgn * 0.3                 # przy linii między pasami
            out.append(dict(d=a - 10.0, x=outer, kind="arrow_board"))
            n = int(t / CONE_TAPER_STEP)
            for i in range(n + 1):
                f = i / n
                out.append(dict(d=a + f * t, x=outer + (inner - outer) * f, kind="cone"))
            dd = a + t + CONE_BODY_STEP
            step = POST_STEP if s == 6 else CONE_BODY_STEP
            while dd < e - OUT_TAPER:
                out.append(dict(d=dd, x=inner, kind="post" if s == 6 else "cone"))
                dd += step
            n = int(OUT_TAPER / CONE_TAPER_STEP)
            for i in range(n + 1):
                f = i / n
                out.append(dict(d=e - OUT_TAPER + f * OUT_TAPER, x=inner + (outer - inner) * f, kind="cone"))
        if s in (4, 3):
            out.append(dict(d=a + t, x=-WIDTH / 2 - 1.0, kind="carriageway_closed"))
        return out


ALT_LEN = 1000.0          # 2+1: długość odcinka z dwoma pasami
ALT_END = 150.0           # 2+1: koniec pasu wyprzedzania (zjazd przed zmianą)
SHOULDER_L = 0.75


def hwy_lanes(n, width):
    """Środki n pasów autostrady liczone od lewej krawędzi (jak
    HighwayGenerator.lane_center), od prawego (indeks 0)."""
    return [-width / 2 + SHOULDER_L + LANE_W * (n - 1 - i + 0.5) for i in range(n)]


def check(sp, km):
    errors = []
    d1 = km * 1000.0
    zones = sp.zones(0.0, d1)
    prev_end = -1e9
    for z in zones:
        if z["start"] - WARN < prev_end:
            errors.append("zapowiedź w poprzedniej strefie %s" % z)
        prev_end = z["end"]
        if z["end"] - z["start"] < z["t_in"] + BODY_MIN[z["section"]] + z["t_out"] - 1e-6:
            errors.append("za krótka strefa %s" % z)
    d = 0.0
    prev = None
    while d < d1:
        l = sp.lanes_at(d)
        if prev is not None and len(prev["fwd"]) == len(l["fwd"]):
            for a, b in zip(prev["fwd"], l["fwd"]):
                if abs(a - b) > 0.1:
                    errors.append("skok pasa %.2f -> %.2f na %.0f m" % (a, b, d))
        if prev is not None and abs(prev["width"] - l["width"]) > 0.1:
            errors.append("skok szerokości na %.0f m" % d)
        prev = l
        if not l["fwd"]:
            errors.append("brak pasa w naszą stronę na %.0f m" % d)
        if l["closing"] is not None and l["closing"] in l["fwd"]:
            errors.append("zamykany pas otwarty na %.0f m" % d)
        hw = l["width"] / 2
        for x in l["fwd"] + l["onc"]:
            if abs(x) > hw - 1.5:
                errors.append("pas %.2f poza jezdnią %.2f na %.0f m" % (x, l["width"], d))
        lim = sp.limit_at(d)
        if sp.zone_at(d) and lim != sp.zone_at(d)["limit"]:
            errors.append("limit %s w strefie na %.0f m" % (lim, d))
        d += 2.0
    for m in sp.limit_marks(0.0, d1):
        if sp.limit_at(m[0] - 0.5) == sp.limit_at(m[0] + 0.5):
            errors.append("znacznik bez zmiany limitu %s" % m)
    d = 0.25
    last = 140.0
    marks = {round(m[0], 3) for m in sp.limit_marks(0.0, d1)}
    while d < d1:
        lim = sp.limit_at(d)
        if lim != last and not any(abs(d - m) <= 0.5 for m in marks):
            errors.append("zmiana limitu bez znacznika na %.1f m" % d)
        last = lim
        d += 0.5
    for it in sp.items(0.0, d1):
        z = sp.zone_at(it["d"])
        if it["kind"] == "cone" and z is not None:
            lanes = sp.lanes_at(it["d"])
            for x in lanes["fwd"]:
                if abs(it["x"] - x) < 1.2:
                    errors.append("pachołek na otwartym pasie %.0f m x %.2f" % (it["d"], it["x"]))
    return zones, errors


def main():
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 777
    km = float(sys.argv[2]) if len(sys.argv) > 2 else 300.0
    sp = SectionPlan(SegmentCode(seed))
    zones, errors = check(sp, km)
    from collections import Counter
    c = Counter(z["section"] for z in zones)
    cover = sum(z["end"] - z["start"] for z in zones) / (km * 1000.0)
    print("ziarno %d, %.0f km: stref %d %s, %.0f%% trasy w strefach" % (seed, km, len(zones), dict(sorted(c.items())), 100 * cover))
    for z in zones[:8]:
        print("  k %3d prz %d %.0f-%.0f m (%.0f m), skos %.0f, limit %.0f, strona %d" % (
            z["k"], z["section"], z["start"], z["end"], z["end"] - z["start"], z["t_in"], z["limit"], z["side"]))
    items = sp.items(0.0, km * 1000.0)
    ci = Counter(i["kind"] for i in items)
    print("  elementy:", dict(ci), "(na km: %.0f)" % (len(items) / km))
    print("SECTION_SIM: OK" if not errors else "SECTION_SIM: BŁĘDY %d\n  %s" % (len(errors), "\n  ".join(errors[:10])))
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())
