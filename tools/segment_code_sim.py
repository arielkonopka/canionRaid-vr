#!/usr/bin/env python3
"""Odpowiednik scripts/segment_code.gd (SegmentCode) - ten sam hash, te same
liczby. W chmurze nie ma Godota, więc logikę kodu odcinka sprawdzamy tutaj.

    python3 tools/segment_code_sim.py [ziarno] [km]

Wypisuje pierwsze odcinki, rozkład pól i sprawdza niezmienniki (to samo co
tests/segment_code_test.gd). Pogody tu nie ma (heavy_rain = None).
"""
import sys

SEG_LEN = 1200.0
FIRST_CALM = 3            # pierwsze odcinki bez urozmaiceń
GROUP_MIN, GROUP_MAX = 3, 5
COST_MAX = 4
SAME_STRUCT_GAP = 4       # ta sama budowla nie częściej niż co tyle odcinków
NARROW_MAX = 3            # droga 1+1 / jeden pas najwyżej tyle odcinków z rzędu
LIE_GAP = 33              # "znak kłamie" najwyżej raz na tyle odcinków (~40 km)

# Fazy rytmu
BUILD, PEAK, FADE, REST = "build", "peak", "fade", "rest"
PHASES = {3: [BUILD, PEAK, REST], 4: [BUILD, BUILD, PEAK, REST],
          5: [BUILD, BUILD, PEAK, FADE, REST]}
EVENTS_BY_PHASE = {BUILD: [0, 1, 7], PEAK: [2, 3, 4, 5, 6], FADE: [0, 1, 4], REST: [0]}

# Kalendarz pierwszych wystąpień [km]
UNLOCK_STRUCT = {0: 0, 1: 5, 4: 10, 2: 20, 3: 30, 6: 40, 5: 50, 7: 60}
UNLOCK_SECTION = {0: 0, 7: 8, 4: 15, 6: 25, 3: 35, 5: 45, 1: 10, 2: 60}
UNLOCK_TRAP = {15: 0, 0: 5, 12: 8, 6: 12, 4: 16, 1: 20, 3: 25, 5: 30, 7: 35,
               10: 40, 9: 45, 11: 50, 13: 55, 2: 60, 8: 70, 14: 120}
UNLOCK_EVENT = {0: 0, 1: 3, 4: 6, 2: 12, 5: 18, 3: 24, 7: 30, 6: 40}

# Pułapka wymaga budowli albo przekroju (rytm najpierw, geometria potem).
TRAP_STRUCT = {1: 1, 7: 3, 10: 2, 11: 6}
TRAP_SECTION = {8: 4, 13: 6, 9: 4}

COST_STRUCT = {0: 0, 1: 1, 2: 2, 3: 1, 4: 0, 5: 1, 6: 1, 7: 2}
COST_EVENT = {0: 0, 1: 1, 2: 1, 3: 1, 4: 1, 5: 2, 6: 2, 7: 0}
COST_RAIN = 2
NARROW = (4, 7)


def mix(h, v):
    h = (h ^ (v & 0xFFFFFFFF)) & 0xFFFFFFFF
    h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xFFFFFFFF
    h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xFFFFFFFF
    return (h ^ (h >> 16)) & 0xFFFFFFFF


class SegmentCode:
    def __init__(self, seed=1):
        self.seed = seed
        self.groups = [0]          # początki grup rytmu (numer odcinka)
        self.codes = []            # odcinki policzone po kolei (leniwie)
        self.heavy_rain = None     # funkcja d -> bool (w grze z WeatherPlan)

    def h(self, k, salt):
        x = mix(0x9E3779B9, self.seed)
        x = mix(x, k)
        x = mix(x, salt)
        return x

    def h01(self, k, salt):
        return self.h(k, salt) / 4294967296.0

    # --- rytm ---
    def _extend_groups(self, k):
        while self.groups[-1] <= k:
            g = len(self.groups)
            n = GROUP_MIN + self.h(g, 100) % (GROUP_MAX - GROUP_MIN + 1)
            self.groups.append(self.groups[-1] + n)

    def phase(self, k):
        if k < FIRST_CALM:
            return REST
        self._extend_groups(k)
        lo = 0
        while self.groups[lo + 1] <= k:
            lo += 1
        start, end = self.groups[lo], self.groups[lo + 1]
        return PHASES[end - start][k - start]

    # --- odcinki ---
    def segment(self, k):
        while len(self.codes) <= k:
            self.codes.append(self._make(len(self.codes)))
        return self.codes[k]

    def _make(self, k):
        km = k * SEG_LEN / 1000.0
        ph = self.phase(k)
        prev = self.codes[k - 1] if k > 0 else None

        # 1. Zdarzenie z fazy.
        allowed = [e for e in EVENTS_BY_PHASE[ph] if UNLOCK_EVENT[e] <= km]
        if not allowed:
            allowed = [0]
        event = allowed[self.h(k, 1) % len(allowed)]
        ev_level = min(self.h(k, 2) % 4, 1 + int(km // 60))

        # 2. Pułapka z fazy.
        trap = 15
        if ph != REST and k >= FIRST_CALM:
            raw = self.h(k, 3) % 16
            if ph == PEAK and raw == 15:
                raw = self.h(k, 4) % 15
            if UNLOCK_TRAP[raw] <= km:
                trap = raw
            if trap == 14 and any(c["trap"] == 14 for c in self.codes[max(0, k - LIE_GAP):k]):
                trap = 15
        lvl_max = 3 if km >= 100 else (2 if km >= 30 else 1)
        trap_level = min(self.h(k, 5) % 4, lvl_max)
        if ph in (BUILD, FADE):
            trap_level = min(trap_level, 1)
        trap_at = self.h(k, 6) % 4

        # 3. Budowla i przekrój - surowe, potem dopasowane do pułapki.
        struct = self.h(k, 7) % 8
        if UNLOCK_STRUCT[struct] > km or k < FIRST_CALM:
            struct = 0
        section = self.h(k, 8) % 8
        if UNLOCK_SECTION[section] > km or k < FIRST_CALM:
            section = 0
        if section == 1 and struct != 4:
            section = 0                       # pas dla wolnych tylko na podjeździe
        if trap in TRAP_STRUCT:
            need = TRAP_STRUCT[trap]
            if UNLOCK_STRUCT[need] <= km:
                struct = need
            else:
                trap = 15
        if trap in TRAP_SECTION:
            need = TRAP_SECTION[trap]
            if UNLOCK_SECTION[need] <= km:
                section = need
            else:
                trap = 15
        if trap == 1:
            section = 7                       # zwężenie za tunelem
            trap_at = 3

        # 4. Gramatyka sąsiedztwa.
        if struct != 0:
            recent = [c["structure"] for c in self.codes[max(0, k - SAME_STRUCT_GAP + 1):k]]
            climb_go_on = struct == 4 and prev is not None and prev["structure"] == 4
            if struct in recent and not climb_go_on:
                if trap in TRAP_STRUCT:
                    trap = 15
                struct = 0
        narrow_run = 0
        for c in reversed(self.codes[max(0, k - NARROW_MAX):k]):
            if c["section"] in NARROW:
                narrow_run += 1
            else:
                break
        if section in NARROW and narrow_run >= NARROW_MAX - 1:
            if trap in TRAP_SECTION or trap == 1:
                trap = 15
            section = 0
        if section == 1 and struct != 4:
            section = 0

        # 5. Koszt na Queście (ten i poprzedni odcinek zbudowane naraz).
        def cost(st, ev, d):
            c = COST_STRUCT[st] + COST_EVENT[ev]
            if self.heavy_rain is not None and self.heavy_rain(d):
                c += COST_RAIN
            return c
        d_mid = (k + 0.5) * SEG_LEN
        prev_cost = prev["cost"] if prev else 0
        # Budowla bez kosztu (podjazd) zostaje - jej wycięcie nic nie daje,
        # a zostawiało pas dla wolnych bez podjazdu (ziarno 5 z pogodą).
        if cost(struct, event, d_mid) + prev_cost > COST_MAX and COST_STRUCT[struct] > 0:
            if trap in TRAP_STRUCT:
                trap = 15
            struct = 0
        if cost(struct, event, d_mid) + prev_cost > COST_MAX:
            event = 0

        if trap == 15:
            trap_level = 0
        if event == 0:
            ev_level = 0
        seg = dict(k=k, phase=ph, structure=struct, s_len=self.h(k, 9) % 4,
                   s_param=self.h(k, 10) % 8, section=section,
                   change_at=self.h(k, 11) % 4 if trap != 1 else 3,
                   variant=self.h(k, 12) % 8, trap=trap, trap_at=trap_at,
                   trap_level=trap_level, event=event, ev_level=ev_level,
                   accent=self.h(k, 13) % 8)
        seg["cost"] = cost(struct, event, d_mid)
        seg["code"] = pack(seg)
        return seg


def pack(s):
    b0 = s["structure"] | (s["s_len"] << 3) | (s["s_param"] << 5)
    b1 = s["section"] | (s["change_at"] << 3) | (s["variant"] << 5)
    b2 = s["trap"] | (s["trap_at"] << 4) | (s["trap_level"] << 6)
    b3 = s["event"] | (s["ev_level"] << 3) | (s["accent"] << 5)
    return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)


ROUNDABOUT_R = [22.0, 28.0, 34.0, 40.0]


def roundabout_r(s):
    """Rondo w mieście: structure 7 i s_param 0-3 (indeks promienia)."""
    if s["structure"] != 7 or s["s_param"] >= 4:
        return 0.0
    return ROUNDABOUT_R[s["s_param"]]


def check(sc, n):
    errors = []
    segs = [sc.segment(k) for k in range(n)]
    lies = []
    for s in segs:
        k, km = s["k"], s["k"] * SEG_LEN / 1000.0
        if s["phase"] == REST and (s["trap"] != 15 or s["event"] != 0):
            errors.append("odpoczynek z pułapką/zdarzeniem %d" % k)
        if k < FIRST_CALM and (s["structure"] or s["section"] or s["trap"] != 15 or s["event"]):
            errors.append("urozmaicenie na starcie %d" % k)
        if UNLOCK_STRUCT[s["structure"]] > km or UNLOCK_SECTION[s["section"]] > km \
                or UNLOCK_TRAP[s["trap"]] > km or UNLOCK_EVENT[s["event"]] > km:
            errors.append("przed kalendarzem %d: %s" % (k, s))
        if s["trap"] in TRAP_STRUCT and s["structure"] != TRAP_STRUCT[s["trap"]]:
            errors.append("pułapka bez budowli %d" % k)
        if s["trap"] in TRAP_SECTION and s["section"] != TRAP_SECTION[s["trap"]]:
            errors.append("pułapka bez przekroju %d" % k)
        if s["section"] == 1 and s["structure"] != 4:
            errors.append("pas dla wolnych poza podjazdem %d" % k)
        if k > 0 and s["cost"] + segs[k - 1]["cost"] > COST_MAX:
            errors.append("koszt %d" % k)
        if s["structure"] not in (0, 4):
            for j in range(max(0, k - SAME_STRUCT_GAP + 1), k):
                if segs[j]["structure"] == s["structure"]:
                    errors.append("budowla %d powtórzona w %d i %d" % (s["structure"], j, k))
        if s["trap"] == 14:
            if lies and k - lies[-1] < LIE_GAP:
                errors.append("znak kłamie za często %d" % k)
            lies.append(k)
        if s["code"] >> 32:
            errors.append("kod > 32 bity")
    run = 0
    for s in segs:
        run = run + 1 if s["section"] in NARROW else 0
        if run > NARROW_MAX - 1:
            errors.append("za długo wąsko do %d" % s["k"])
    # rytm: odpoczynek co 3-5 odcinków
    rests = [s["k"] for s in segs if s["phase"] == REST and s["k"] >= FIRST_CALM]
    for a, b in zip(rests, rests[1:]):
        if not GROUP_MIN <= b - a <= GROUP_MAX:
            errors.append("odpoczynek po %d odcinkach (%d)" % (b - a, b))
    return segs, errors


def main():
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 777
    km = float(sys.argv[2]) if len(sys.argv) > 2 else 300.0
    n = int(km * 1000 / SEG_LEN)
    sc = SegmentCode(seed)
    segs, errors = check(sc, n)
    print("ziarno %d, %d odcinków (%.0f km)" % (seed, n, km))
    for s in segs[:12]:
        print("  %3d %-5s %08X bud %d prz %d puł %2d/%d zd %d" % (
            s["k"], s["phase"], s["code"], s["structure"], s["section"], s["trap"], s["trap_level"], s["event"]))
    from collections import Counter
    for f in ("structure", "section", "trap", "event"):
        c = Counter(s[f] for s in segs)
        print("  %-9s %s" % (f, dict(sorted(c.items()))))
    distinct = len(set((s["structure"], s["section"], s["trap"], s["event"]) for s in segs))
    print("  ronda w mieście: %d na %d odcinków miasta" % (
        sum(1 for s in segs if roundabout_r(s) > 0), sum(1 for s in segs if s["structure"] == 7)))
    print("  różnych układów (bud, prz, puł, zd): %d" % distinct)
    print("SEGMENT_SIM: OK" if not errors else "SEGMENT_SIM: BŁĘDY %d\n  %s" % (len(errors), "\n  ".join(errors[:10])))
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())
