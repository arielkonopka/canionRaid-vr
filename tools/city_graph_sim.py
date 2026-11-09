#!/usr/bin/env python3
"""Wierny odpowiednik scripts/city_graph.gd w Pythonie - do sprawdzenia
algorytmu bez Godota (w chmurze go nie ma). Ten sam hash (32 bity), więc
te same węzły, krawędzie i liczby co w grze.

    python3 tools/city_graph_sim.py [ziarno] [kroki]

Sprawdza to samo co tests/city_graph_test.gd: determinizm, symetrię
krawędzi, brak ślepych zaułków (stopień >= 2), spójność miasta, ten sam łuk
z obu stron, a w jeździe losowej: bieżąca krawędź zawsze zbudowana,
liczba zbudowanych krawędzi ograniczona, powrót daje tę samą geometrię.
"""
import math
import random
import sys

CELL, JITTER, BEND, AVENUE, P_STREET = 80.0, 9.0, 5.0, 4, 0.55
STUB_LEN, KEEP_BEHIND, STEP = 25.0, 2, 4.0
M32 = 0xFFFFFFFF


def mix(h, v):
    h = (h ^ (v & M32)) & M32
    h = ((h ^ (h >> 16)) * 0x45d9f3b) & M32
    h = ((h ^ (h >> 16)) * 0x45d9f3b) & M32
    return (h ^ (h >> 16)) & M32


class City:
    def __init__(self, seed=0, bounds=None):  # bounds = (x0, y0, x1, y1) włącznie
        self.seed, self.bounds = seed, bounds
        self.a = self.b = (0, 0)
        self.hist, self.built, self.odo, self.last = [], {}, 0.0, None

    def h01(self, *vals):
        h = mix(0x9E3779B9, self.seed)
        for v in vals:
            h = mix(h, v)
        return h / 4294967296.0

    def inb(self, c):
        if not self.bounds:
            return True
        x0, y0, x1, y1 = self.bounds
        return x0 <= c[0] <= x1 and y0 <= c[1] <= y1

    def av_col(self, i):
        return i % AVENUE == 0 or (self.bounds and i in (self.bounds[0], self.bounds[2]))

    def av_row(self, j):
        return j % AVENUE == 0 or (self.bounds and j in (self.bounds[1], self.bounds[3]))

    def has_edge(self, a, b):
        dx, dy = b[0] - a[0], b[1] - a[1]
        if abs(dx) + abs(dy) != 1 or not (self.inb(a) and self.inb(b)):
            return False
        if dy == 0:
            j = a[1]
            if self.av_row(j):
                return True
            i = min(a[0], b[0])
            return self.h01(1, j, i - i % AVENUE) < P_STREET
        c = a[0]
        if self.av_col(c):
            return True
        jj = min(a[1], b[1])
        return self.h01(2, c, jj - jj % AVENUE) < P_STREET

    def neighbors(self, c):
        return [(c[0] + d[0], c[1] + d[1]) for d in ((1, 0), (0, 1), (-1, 0), (0, -1))
                if self.has_edge(c, (c[0] + d[0], c[1] + d[1]))]

    def node_pos(self, c):
        return (c[0] * CELL + (self.h01(3, *c) * 2 - 1) * JITTER,
                c[1] * CELL + (self.h01(4, *c) * 2 - 1) * JITTER)

    @staticmethod
    def key(a, b):
        lo, hi = (a, b) if (a[0], a[1]) <= (b[0], b[1]) else (b, a)
        return f"{lo[0]},{lo[1]}|{hi[0]},{hi[1]}"

    def edge_points(self, a, b, max_len=-1.0):
        lo, hi = (a, b) if (a[0], a[1]) <= (b[0], b[1]) else (b, a)
        p0, p2 = self.node_pos(lo), self.node_pos(hi)
        dx, dy = p2[0] - p0[0], p2[1] - p0[1]
        ln = math.hypot(dx, dy)
        side = (dy / ln, -dx / ln)   # Vector2.orthogonal() = (y, -x)
        bend = (self.h01(5, lo[0], lo[1], hi[0], hi[1]) * 2 - 1) * BEND
        p1 = ((p0[0] + p2[0]) / 2 + side[0] * bend, (p0[1] + p2[1]) / 2 + side[1] * bend)
        n = max(2, math.ceil(ln / STEP))
        pts = []
        for k in range(n + 1):
            t = k / n
            q0 = (p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t)
            q1 = (p1[0] + (p2[0] - p1[0]) * t, p1[1] + (p2[1] - p1[1]) * t)
            pts.append((q0[0] + (q1[0] - q0[0]) * t, q0[1] + (q1[1] - q0[1]) * t))
        if lo != a:
            pts.reverse()
        if max_len > 0:
            out, acc = [pts[0]], 0.0
            for k in range(1, len(pts)):
                seg = math.dist(pts[k - 1], pts[k])
                if acc + seg >= max_len:
                    f = (max_len - acc) / max(seg, 1e-4)
                    out.append((pts[k - 1][0] + (pts[k][0] - pts[k - 1][0]) * f,
                                pts[k - 1][1] + (pts[k][1] - pts[k - 1][1]) * f))
                    return out
                acc += seg
                out.append(pts[k])
            return out
        return pts

    @staticmethod
    def project(pts, p):
        best, best_s, acc = math.inf, 0.0, 0.0
        for k in range(1, len(pts)):
            a = pts[k - 1]
            ab = (pts[k][0] - a[0], pts[k][1] - a[1])
            l2 = ab[0] ** 2 + ab[1] ** 2
            t = 0.0 if l2 < 1e-9 else min(1.0, max(0.0, ((p[0] - a[0]) * ab[0] + (p[1] - a[1]) * ab[1]) / l2))
            d = math.dist(p, (a[0] + ab[0] * t, a[1] + ab[1] * t))
            if d < best:
                best, best_s = d, acc + math.sqrt(l2) * t
            acc += math.sqrt(l2)
        return best, best_s

    def wanted(self):
        w = {}
        for a, b in self.hist:
            w[self.key(a, b)] = (a, b, -1.0)
        w[self.key(self.a, self.b)] = (self.a, self.b, -1.0)
        for end in (self.b, self.a):
            for n in self.neighbors(end):
                w.setdefault(self.key(end, n), (end, n, STUB_LEN))
        return w

    def start(self, a, b):
        assert self.has_edge(a, b)
        self.a, self.b, self.hist, self.last = a, b, [], None
        return self.sync()

    def update(self, pos):
        if self.last is not None:
            self.odo += math.dist(self.last, pos)
        self.last = pos
        cur = self.key(self.a, self.b)
        best_k, best_d = cur, self.project(self.edge_points(self.a, self.b), pos)[0]
        for k, (ea, eb, ln) in self.built.items():
            if k == cur:
                continue
            d = self.project(self.edge_points(ea, eb, ln), pos)[0]
            if d < best_d - 0.5:
                best_k, best_d = k, d
        switched = False
        if best_k != cur:
            ea, eb, _ = self.built[best_k]
            frm = eb if eb in (self.a, self.b) else ea
            to = ea if frm == eb else eb
            self.hist.append((self.a, self.b))
            self.hist = self.hist[-KEEP_BEHIND:]
            self.hist = [h for h in self.hist if self.key(*h) != best_k]
            self.a, self.b, switched = frm, to, True
        d = self.sync()
        d["switched"] = switched
        return d

    def sync(self):
        w = self.wanted()
        rem = [k for k in self.built if k not in w or w[k][2] != self.built[k][2]]
        for k in rem:
            del self.built[k]
        add = []
        for k, e in w.items():
            if k not in self.built:
                self.built[k] = e
                add.append(k)
        return {"add": add, "remove": rem}


def check(cond, what, fails):
    if not cond:
        fails.append(what)
        print("  BŁĄD:", what)


def main():
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 4242
    steps = int(sys.argv[2]) if len(sys.argv) > 2 else 3000
    fails = []
    for bounds in (None, (-6, -5, 7, 6)):
        c, c2 = City(seed, bounds), City(seed, bounds)
        rng_cells = [(i, j) for i in range(-6, 8) for j in range(-5, 7)]
        nodes = [x for x in rng_cells if c.inb(x) and c.neighbors(x)]
        # Symetria, determinizm, stopień >= 2.
        for n in rng_cells:
            check(c.node_pos(n) == c2.node_pos(n), f"node_pos {n}", fails)
            for d in ((1, 0), (0, 1)):
                m = (n[0] + d[0], n[1] + d[1])
                check(c.has_edge(n, m) == c.has_edge(m, n), f"symetria {n}-{m}", fails)
        for n in nodes:
            check(len(c.neighbors(n)) >= 2, f"ślepy zaułek {n} ({bounds})", fails)
        # Spójność (miasto ograniczone).
        if bounds:
            seen, todo = {nodes[0]}, [nodes[0]]
            while todo:
                for m in c.neighbors(todo.pop()):
                    if m not in seen:
                        seen.add(m)
                        todo.append(m)
            check(len(seen) == len(nodes), f"spójność {len(seen)}/{len(nodes)}", fails)
        # Ten sam łuk z obu stron.
        a, b = nodes[0], c.neighbors(nodes[0])[0]
        fw, bw = c.edge_points(a, b), c.edge_points(b, a)
        check(all(math.dist(p, q) < 1e-6 for p, q in zip(fw, reversed(bw))), "łuk z obu stron", fails)
        deg = [len(c.neighbors(n)) for n in nodes]
        print(f"bounds={bounds}: węzłów {len(nodes)}, stopnie 2:{deg.count(2)} 3:{deg.count(3)} 4:{deg.count(4)}")

        # Jazda losowa po mieście: na każdym skrzyżowaniu losowy wylot.
        rng = random.Random(seed)
        start = (0, 0) if c.neighbors((0, 0)) else nodes[0]
        c.start(start, c.neighbors(start)[0])
        geo = {}

        def record(d):
            # Krawędź zbudowana w całości drugi raz (powrót) - ta sama geometria.
            for k in d["add"]:
                ea, eb, ln = c.built[k]
                if ln < 0:
                    g = c.edge_points(*sorted([ea, eb]))
                    if k in geo:
                        check(g == geo[k], f"ta sama geometria po powrocie {k}", fails)
                        revisits[0] += 1
                    geo[k] = g
        revisits = [0]
        max_built, turns, n_steps = 0, 0, 0
        frm, to = c.a, c.b
        for _ in range(steps // 20):
            path = c.edge_points(frm, to)
            for p in path[1:]:
                n_steps += 1
                record(c.update(p))
                check(c.key(c.a, c.b) in c.built and c.built[c.key(c.a, c.b)][2] < 0,
                      "bieżąca krawędź zbudowana w całości", fails)
                max_built = max(max_built, len(c.built))
            # Skrzyżowanie: wybór wylotu (czasem zawrócenie, rzadko).
            outs = [m for m in c.neighbors(to) if m != frm] or [frm]
            nxt = frm if rng.random() < 0.1 else rng.choice(outs)   # 10% zawrotek
            frm, to = to, nxt
            # Pierwszy krok w nowej krawędzi przełącza bieżącą.
            p = c.edge_points(frm, to)[3]
            n_steps += 1
            record(c.update(p))
            turns += 1
            check(c.key(c.a, c.b) == c.key(frm, to), f"po skręcie bieżąca {c.a}->{c.b} zamiast {frm}->{to}", fails)
        print(f"  jazda: {turns} skrzyżowań, {n_steps} kroków, {c.odo / 1000:.1f} km, "
              f"zbudowanych naraz maks. {max_built}, różnych krawędzi {len(geo)}, powrotów {revisits[0]}")
        check(revisits[0] > 0, "jazda nie wróciła na żadną ulicę - test powrotu nic nie sprawdził", fails)
        check(max_built <= 2 + KEEP_BEHIND + 6 + 1, f"za dużo zbudowanych naraz: {max_built}", fails)
    print("city_graph_sim:", "OK" if not fails else f"BŁĄD ({len(fails)})")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
