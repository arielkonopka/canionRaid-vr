# Bryły aut z epoki z paczek CC0 (GGBotNet "PSX Style Cars", Quaternius
# "Realistic Car Pack") dopasowane do modeli CarStyles.
#
#   python3 tools/prepare_period_cars.py geom     - geometria z siatek
#       (rozstaw osi, kół, promień, wymiary, prześwit) -> tools/period_cars_geometry.json;
#       czyta ją tools/car_styles_tune.py (fizyka liczona dla tych brył)
#   python3 tools/prepare_period_cars.py export   - siatki w układzie auta z gry
#       -> models/period_cars/<model>/body.obj, wheel.obj, *.mtl
#       (po strojeniu; tune wywołuje to sam na końcu)
#
# Układ wyjściowy = układ StuntCar: metry, przód -Z, prawo +X, y = 0 na
# płaszczyźnie mocowań kół (punkt odniesienia auta) przy ugięciu statycznym,
# środki kół w mounts - UP * spring_len (statyczne). Koło: oś obrotu X,
# środek w (0, 0, 0), bieżnik na zewnątrz - jak koło sedana.
# Obie paczki mają przód w +Z i lewo w +X, więc obrót o 180° wokół Y.
# Koła w GGBotNet to osobne bryły (spójne składowe po 16 wierzchołków),
# w Quaterniusie grupy *Wheel* - zdejmujemy je z karoserii, bo koła w grze
# kręcą się i skręcają osobno.
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
GEOM = os.path.join(HERE, "period_cars_geometry.json")

# model -> (plik, długość auta w metrach, uwagi). Długość ustala skalę
# (jednolitą: bez rozciągania brył), reszta wymiarów wynika z siatki.
SOURCES = {
    "kombi": ("models/ggbotnet/car_01/Car.obj", 4.62, "kombi z lat 70."),
    "hatchback": ("models/ggbotnet/car_03/Car3.obj", 3.70, "3-drzwiowy hatchback z lat 80."),
    "muscle": ("models/ggbotnet/car_05/Car5.obj", 4.85, "długi sedan/coupe z winylowym dachem"),
    "furgon": ("models/ggbotnet/car_04/Car4.obj", 4.55, "minivan/furgon z lat 80."),
    "klin": ("models/quaternius/SportsCar2.obj", 4.30, "niskie coupe"),
    "kabriolet": ("models/quaternius/SportsCar.obj", 4.40, "coupe z odciętym dachem (cut_roof)"),
    "terenowka": ("models/quaternius/SUV.obj", 4.45, "SUV, wyższy prześwit"),
}
# Kabriolet: ściany ze środkiem powyżej linii okien (y siatki) usuwane.
CUT_ROOF = {"kabriolet": 0.80}


def read_obj(path):
    V, VT, VN, faces, mtllib = [], [], [], [], None
    group, mat = "", None
    for line in open(os.path.join(ROOT, path), errors="replace"):
        t = line.split()
        if not t:
            continue
        if t[0] == "v":
            V.append([float(x) for x in t[1:4]])
        elif t[0] == "vt":
            VT.append([float(x) for x in t[1:3]])
        elif t[0] == "vn":
            VN.append([float(x) for x in t[1:4]])
        elif t[0] in ("o", "g"):
            group = " ".join(t[1:])
        elif t[0] == "usemtl":
            mat = t[1]
        elif t[0] == "mtllib":
            mtllib = " ".join(t[1:])
        elif t[0] == "f":
            vs = []
            for x in t[1:]:
                q = x.split("/")
                vs.append((int(q[0]) - 1, int(q[1]) - 1 if len(q) > 1 and q[1] else None,
                           int(q[2]) - 1 if len(q) > 2 and q[2] else None))
            faces.append({"v": vs, "g": group, "m": mat})
    return {"V": V, "VT": VT, "VN": VN, "F": faces, "mtllib": mtllib}


def components(obj):
    """Spójne składowe (wspólne wierzchołki albo te same położenia)."""
    V = obj["V"]
    par = list(range(len(V)))

    def find(a):
        while par[a] != a:
            par[a] = par[par[a]]
            a = par[a]
        return a
    seen = {}
    for i, v in enumerate(V):
        k = tuple(round(c, 4) for c in v)
        if k in seen:
            par[find(i)] = find(seen[k])
        else:
            seen[k] = i
    for f in obj["F"]:
        a = f["v"][0][0]
        for v in f["v"][1:]:
            par[find(v[0])] = find(a)
    return [find(i) for i in range(len(V))]


def split_wheels(obj):
    """Zwraca (ściany karoserii, [ściany 4 kół], [środki i promienie kół])."""
    V = obj["V"]
    wheel_faces = {}
    if any("Wheel" in f["g"] for f in obj["F"]):
        # Quaternius: grupy kół; tylne w jednej grupie - dzielimy po znaku x.
        body = []
        for f in obj["F"]:
            if "Wheel" in f["g"]:
                x = sum(V[v[0]][0] for v in f["v"]) / len(f["v"])
                z = sum(V[v[0]][2] for v in f["v"]) / len(f["v"])
                wheel_faces.setdefault((x > 0, z > 0), []).append(f)
            else:
                body.append(f)
    else:
        comp = components(obj)
        sizes = {}
        for c in comp:
            sizes[c] = sizes.get(c, 0) + 1
        miny = min(v[1] for v in V)
        cands = [c for c, n in sizes.items() if n == 16]
        wheels = [c for c in cands if min(V[i][1] for i in range(len(V)) if comp[i] == c) < miny + 0.01]
        assert len(wheels) == 4, (len(wheels), "kół")
        body = []
        for f in obj["F"]:
            c = comp[f["v"][0][0]]
            if c in wheels:
                x = V[f["v"][0][0]][0]
                z = V[f["v"][0][0]][2]
                wheel_faces.setdefault((x > 0, z > 0), []).append(f)
            else:
                body.append(f)
    info = {}
    for k, fs in wheel_faces.items():
        ids = {v[0] for f in fs for v in f["v"]}
        pts = [V[i] for i in ids]
        lo = [min(p[j] for p in pts) for j in range(3)]
        hi = [max(p[j] for p in pts) for j in range(3)]
        info[k] = {"c": [(lo[j] + hi[j]) / 2 for j in range(3)], "r": (hi[1] - lo[1]) / 2,
                   "w": hi[0] - lo[0]}
    return body, wheel_faces, info


def geometry(name):
    path, length, _ = SOURCES[name]
    obj = read_obj(path)
    body, wf, wi = split_wheels(obj)
    V = obj["V"]
    ids = {v[0] for f in body for v in f["v"]}
    lo = [min(V[i][j] for i in ids) for j in range(3)]
    hi = [max(V[i][j] for i in ids) for j in range(3)]
    s = length / (hi[2] - lo[2])
    # (lewe = x>0, przód = z>0)
    zf = (wi[(True, True)]["c"][2] + wi[(False, True)]["c"][2]) / 2
    zr = (wi[(True, False)]["c"][2] + wi[(False, False)]["c"][2]) / 2
    xt = (wi[(True, True)]["c"][0] - wi[(False, True)]["c"][0])
    r = sum(w["r"] for w in wi.values()) / 4
    yc = sum(w["c"][1] for w in wi.values()) / 4
    ground = yc - r
    # Prześwit: najniższy punkt karoserii między osiami (zderzaki i progi
    # przed/za kołami nie liczą się do kolizji spodu).
    mid = [V[i][1] for i in ids if zr < V[i][2] < zf]
    clear = (min(mid) - ground) * s if mid else (lo[1] - ground) * s
    if name in CUT_ROOF:
        hi[1] = CUT_ROOF[name] + 0.05
    return {
        "source": path, "scale": round(s, 4),
        "length": round((hi[2] - lo[2]) * s, 3), "width": round((hi[0] - lo[0]) * s, 3),
        "height": round((hi[1] - ground) * s, 3),
        "wb": round((zf - zr) * s, 3), "track": round(xt * s, 3), "r": round(r * s, 3),
        "wheel_width": round(sum(w["w"] for w in wi.values()) / 4 * s, 3),
        "clear": round(clear, 3),
        # Do eksportu (jednostki siatki): oś przednia, wysokość środków kół.
        "_zf": zf, "_yc": yc,
    }


def cmd_geom():
    out = {n: geometry(n) for n in SOURCES}
    with open(GEOM, "w") as f:
        json.dump(out, f, indent=1, sort_keys=True)
    for n, g in out.items():
        print(n, {k: v for k, v in g.items() if not k.startswith("_")})


def _write_mtl(src_obj, dst_dir, obj):
    """Kopia MTL z poprawionymi ścieżkami tekstur (względne do models/,
    wielkość liter z dysku - Car3.mtl wskazuje Car3.png, a plik to car3.png)."""
    if not obj["mtllib"]:
        return None
    sdir = os.path.dirname(os.path.join(ROOT, src_obj))
    files = {f.lower(): f for f in os.listdir(sdir)}
    out = []
    for line in open(os.path.join(sdir, obj["mtllib"]), errors="replace"):
        t = line.split()
        if t and t[0] in ("map_Kd", "map_Ka"):
            fn = files.get(os.path.basename(t[1]).lower())
            if fn:
                rel = os.path.relpath(os.path.join(sdir, fn), dst_dir)
                line = f"{t[0]} {rel}\n"
        out.append(line)
    name = "body.mtl"
    with open(os.path.join(dst_dir, name), "w") as f:
        f.writelines(out)
    return name


def _write(path, obj, faces, xf_v, xf_n, mtl):
    V, VT, VN = obj["V"], obj["VT"], obj["VN"]
    used = sorted({v[0] for f in faces for v in f["v"]})
    vmap = {o: i + 1 for i, o in enumerate(used)}
    tused = sorted({v[1] for f in faces for v in f["v"] if v[1] is not None})
    tmap = {o: i + 1 for i, o in enumerate(tused)}
    nused = sorted({v[2] for f in faces for v in f["v"] if v[2] is not None})
    nmap = {o: i + 1 for i, o in enumerate(nused)}
    L = ["# Wygenerowane przez tools/prepare_period_cars.py - nie edytuj ręcznie.",
         f"# Źródło: {obj['_src']} (CC0, patrz CREDITS.md)."]
    if mtl:
        L.append(f"mtllib {mtl}")
    for o in used:
        x, y, z = xf_v(V[o])
        L.append(f"v {x:.5f} {y:.5f} {z:.5f}")
    for o in tused:
        L.append(f"vt {VT[o][0]:.5f} {VT[o][1]:.5f}")
    for o in nused:
        x, y, z = xf_n(VN[o])
        L.append(f"vn {x:.5f} {y:.5f} {z:.5f}")
    cur = None
    for f in faces:
        if f["m"] != cur and f["m"]:
            cur = f["m"]
            L.append(f"usemtl {cur}")
        # Obrót o 180° wokół Y nie zmienia skrętności - kolejność wierzchołków zostaje.
        parts = []
        for v in f["v"]:
            s = str(vmap[v[0]])
            if v[1] is not None or v[2] is not None:
                s += "/" + (str(tmap[v[1]]) if v[1] is not None else "")
            if v[2] is not None:
                s += "/" + str(nmap[v[2]])
            parts.append(s)
        L.append("f " + " ".join(parts))
    with open(path, "w") as fh:
        fh.write("\n".join(L) + "\n")


def export(name, front_x, static_spring_len):
    """front_x - oś przednia przed punktem odniesienia [m] (gra: mounts z = -front_x),
    static_spring_len - długość sprężyny na postoju [m] (środek koła = -spring_len)."""
    g = geometry(name)
    path = SOURCES[name][0]
    obj = read_obj(path)
    obj["_src"] = path
    body, wf, wi = split_wheels(obj)
    s = g["scale"]
    zf, yc = g["_zf"], g["_yc"]
    if name in CUT_ROOF:
        cut = CUT_ROOF[name]
        V = obj["V"]
        body = [f for f in body if sum(V[v[0]][1] for v in f["v"]) / len(f["v"]) <= cut]

    def xf_v(p):
        return (-p[0] * s, (p[1] - yc) * s - static_spring_len, -(p[2] - zf) * s - front_x)

    def xf_n(n):
        return (-n[0], n[1], -n[2])
    d = os.path.join(ROOT, "models", "period_cars", name)
    os.makedirs(d, exist_ok=True)
    mtl = _write_mtl(path, d, obj)
    _write(os.path.join(d, "body.obj"), obj, body, xf_v, xf_n, mtl)
    # Koło: lewe przednie z siatki (lewo = +x siatki, więc jego zewnętrzna
    # strona leży na +x), środek w zerze, bez obrotu. Tak jak siatka koła sedana:
    # zewnętrzna strona na +X, StuntCar obraca ją o 180° dla lewych kół.
    c = wi[(True, True)]["c"]

    def xw(p):
        return ((p[0] - c[0]) * s, (p[1] - c[1]) * s, (p[2] - c[2]) * s)
    _write(os.path.join(d, "wheel.obj"), obj, wf[(True, True)], xw, lambda n: (n[0], n[1], n[2]), mtl)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "geom":
        cmd_geom()
    else:
        print("użycie: prepare_period_cars.py geom   (eksport robi car_styles_tune.py)")
