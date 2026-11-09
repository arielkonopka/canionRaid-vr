# Strojenie modeli aut z epoki na symulatorze tools/car_sim.py.
#   python3 tools/car_styles_tune.py            - strojenie + raport (docs/car_styles_sim.md)
#   python3 tools/car_styles_tune.py --quick    - sam raport z obecnymi nastawami
# Wynik: docs/car_styles_sim.md i scripts/car_styles.gd (dane dla gry).
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import car_sim as cs

AIR_RHO = 1.225


def cda(cd, area):
    return 0.5 * AIR_RHO * cd * area


# Założenia wejściowe (z propozycji w wątku, 2026-11-09). Wymiary i masa to
# ogólny styl epoki, bez konkretnych modeli. Strojone niżej: final_mult
# (największa prędkość), sprężyny (bez dobicia po upadku z 1,5 m),
# stabilizatory (przechył), podział hamulców (obie osie blokują się naraz).
#   wb, track - rozstaw osi i kół; h_target - wysokość środka masy nad jezdnią;
#   clear - prześwit pod spodem nadwozia; roll - cel przechyłu [deg/g];
#   arb_share - udział przodu w sztywności stabilizatorów.
STYLES = {
    "sedan": dict(label="Sedan z lat 70.", dims=(4.56, 1.78, 1.39), wb=2.57, track=1.64, r=0.33,
                  rest=0.45, mass=1150, h_target=0.58, clear=0.30, cd=0.36, area=2.10,
                  engine="petrol", power=90, drive="rwd", susp="sport", roll=None, arb_share=0.63,
                  bot_weight=(25, 25)),
    "kombi": dict(label="Kombi", dims=(4.62, 1.78, 1.45), wb=2.57, track=1.64, r=0.33,
                  rest=0.45, mass=1230, h_target=0.60, clear=0.30, cd=0.38, area=2.15,
                  engine="petrol", power=90, drive="rwd", susp="soft", roll=3.5, arb_share=0.63,
                  com_back=0.06, bot_weight=(15, 20)),
    "hatchback": dict(label="Hatchback z lat 80.", dims=(3.70, 1.62, 1.38), wb=2.35, track=1.40, r=0.29,
                      rest=0.45, mass=860, h_target=0.53, clear=0.26, cd=0.38, area=1.85,
                      engine="petrol", power=90, drive="fwd", susp="sport", roll=2.5, arb_share=0.50,
                      bot_weight=(20, 15)),
    "klin": dict(label="Klin z lat 80.", dims=(4.30, 1.72, 1.24), wb=2.45, track=1.48, r=0.31,
                 rest=0.40, mass=1120, h_target=0.48, clear=0.24, cd=0.33, area=1.80,
                 engine="petrol", power=130, drive="rwd", susp="stiff", roll=1.6, arb_share=0.60,
                 bot_weight=(10, 10)),
    "kabriolet": dict(label="Kabriolet", dims=(4.40, 1.72, 1.30), wb=2.50, track=1.45, r=0.32,
                      rest=0.44, mass=1180, h_target=0.52, clear=0.27, cd=0.38, area=1.95,
                      engine="petrol", power=90, drive="rwd", susp="sport", roll=2.3, arb_share=0.63,
                      bot_weight=(5, 5)),
    "muscle": dict(label="Muscle z lat 70.", dims=(4.85, 1.88, 1.32), wb=2.80, track=1.56, r=0.34,
                   rest=0.45, mass=1550, h_target=0.54, clear=0.28, cd=0.42, area=2.05,
                   engine="petrol", power=180, drive="rwd", susp="soft", roll=3.5, arb_share=0.65,
                   com_fwd=0.06, bot_weight=(10, 10)),
    "terenowka": dict(label="Terenówka 4x4", dims=(4.45, 1.76, 1.85), wb=2.40, track=1.45, r=0.38,
                      rest=0.55, mass=1680, h_target=0.68, clear=0.36, cd=0.50, area=2.60,
                      engine="diesel", power=90, drive="awd", susp="soft", roll=4.5, arb_share=0.60,
                      bot_weight=(10, 5)),
    "furgon": dict(label="Furgon", dims=(4.55, 1.80, 1.98), wb=2.60, track=1.56, r=0.33,
                   rest=0.50, mass=1480, h_target=0.72, clear=0.20, cd=0.42, area=3.20,
                   engine="diesel", power=90, drive="rwd", susp="soft", roll=4.5, arb_share=0.55,
                   bot_weight=(5, 10)),
}

SEDAN_INERTIA = (480.0, 1750.0, 1950.0)   # przechył, pochylenie, odchylenie
SEDAN_DIMS = (4.56, 1.78, 1.39)


def inertia(st):
    """Bezwładność sedana przeskalowana masą i wymiarami bryły."""
    L, W, H = st["dims"]
    L0, W0, H0 = SEDAN_DIMS
    k = st["mass"] / 1150.0
    roll = SEDAN_INERTIA[0] * k * (W * W + H * H) / (W0 * W0 + H0 * H0)
    pitch = SEDAN_INERTIA[1] * k * (H * H + L * L) / (H0 * H0 + L0 * L0)
    yaw = SEDAN_INERTIA[2] * k * (W * W + L * L) / (W0 * W0 + L0 * L0)
    return (round(roll), round(pitch), round(yaw))


def to_sim(name, st, tune=None):
    """Słownik stylu dla car_sim.Car. Geometria jak w grze: mocowania na
    płaszczyźnie y=0 punktu odniesienia, środek masy com_y pod nią."""
    tune = tune or {}
    wb = st["wb"]
    front_x = wb * (1.32 / 2.57)
    rear_x = front_x - wb
    # Wysokość punktu odniesienia na postoju: rest - ugięcie + r. Ugięcie
    # statyczne jak w sedanie (sprężyny skalowane masą): ~0,078 m (sport),
    # dla innych zestawów z proporcji sztywności.
    k_preset = cs.SUSPENSION_PRESETS[st["susp"]]["spring_k"] * tune.get("spring_mult", 1.0)
    static_c = 1150.0 * cs.G / 4.0 / k_preset
    origin_h = st["rest"] - static_c + st["r"]
    com_y = st["h_target"] - origin_h
    com_x = 0.03 + st.get("com_fwd", 0.0) - st.get("com_back", 0.0)
    if name == "sedan":
        com_y, com_x = -0.12, 0.03
    d = dict(name=name, mass=float(st["mass"]), inertia=inertia(st),
             com_y=com_y, com_x=com_x, front_x=front_x, rear_x=rear_x,
             track=st["track"], wheel_radius=st["r"], rest_length=st["rest"],
             body_bottom=st["clear"] - origin_h, aero_drag=cda(st["cd"], st["area"]),
             engine=st["engine"], power_kw=float(st["power"]), drive=st["drive"],
             suspension=st["susp"])
    if name == "sedan":
        d["inertia"] = SEDAN_INERTIA
        d["body_bottom"] = -0.40
    d.update({k: v for k, v in tune.items() if k in cs.SEDAN})
    return d


def ideal_brake_front(sim, decel_g=0.9):
    """Udział przodu w momencie hamowania, przy którym obie osie
    blokują się naraz przy hamowaniu decel_g (obciążenie dynamiczne)."""
    car = cs.Car(sim)
    car.settle()
    a = car.wheels[0].x
    b = -car.wheels[2].x
    return (b + decel_g * car.h) / car.L


def tune_final(sim):
    """final_mult (krok 0,05) dający prawie największą prędkość maksymalną:
    spośród przełożeń do 1 km/h od maksimum - najbliższe 1,0 (krótsze
    przełożenie = lepsze przyspieszenie, a prędkość ta sama)."""
    res = []
    for fm in [0.6 + 0.05 * i for i in range(17)]:
        res.append((cs.accel(dict(sim, final_mult=fm))["vmax"], fm))
    vbest = max(v for v, _ in res)
    ok = [fm for v, fm in res if v >= vbest - 1.0]
    return round(min(ok, key=lambda f: abs(f - 1.0)), 2)


def tune_arb(sim, roll_t, front_share):
    """Mnożniki stabilizatorów dające przechył roll_t [deg/g] przy zadanym
    udziale przodu w sztywności stabilizatorów. Balansu nie stroimy pod
    podsterowność: w modelu opon gry (load sensitivity 0,1) podział
    stabilizatorów prawie jej nie zmienia - pierwsza wersja strojenia
    (2026-11-09) wyzerowała tylny i dała 7x przedni, a podsterowność
    ruszyła się o 0,3 deg/g. Udział przodu to więc cecha konstrukcji."""
    base_share = 19000.0 / 30000.0         # sedan, zestaw sport
    f0 = front_share / base_share
    r0 = (1.0 - front_share) / (1.0 - base_share)
    lo, hi = 0.3, 3.0
    for _ in range(9):
        mid = math.sqrt(lo * hi)
        res = cs.skidpad(dict(sim, arb_front_mult=f0 * mid, arb_rear_mult=r0 * mid))
        if res["roll_deg_per_g"] is None:
            break
        if res["roll_deg_per_g"] > roll_t:
            lo = mid
        else:
            hi = mid
    m = math.sqrt(lo * hi)
    return round(f0 * m, 2), round(r0 * m, 2)


def tune_springs(sim, drop=1.5):
    """Najmniejszy mnożnik sprężyn i tłumików (krok 0,05, do 1,25), przy
    którym upadek płasko z drop [m] dobija nie mocniej niż sedan z gry
    (spód nadwozia najwyżej 2 cm "pod" jezdnią w modelu - sedan ma ~0).
    Twardsze sprężyny psułyby komfort (częstotliwość > 2 Hz), więc limit."""
    for i in range(6):
        k = 1.0 + 0.05 * i
        s = dict(sim, spring_mult=k, damper_mult=math.sqrt(k))
        if cs.landing(s, drop)["min_clear"] > -0.02:
            return round(k, 2)
    return 1.25


def tune(name, st):
    sim = to_sim(name, st)
    t = {}
    if name != "sedan":
        t["final_mult"] = tune_final(sim)
        k = tune_springs(to_sim(name, st, t))
        if k > 1.0:
            t["spring_mult"] = k
            t["damper_mult"] = round(math.sqrt(k), 2)
        sim = to_sim(name, st, t)
        t["arb_front_mult"], t["arb_rear_mult"] = tune_arb(sim, st["roll"], st["arb_share"])
        sim = to_sim(name, st, t)
        share = ideal_brake_front(sim) + 0.04
        total = (1900.0 + 1050.0) * st["r"] / 0.33
        t["brake_front"] = round(total * share, -1)
        t["brake_rear"] = round(total * (1 - share), -1)
    return to_sim(name, st, t), t


def fmt(x, n=1):
    return "-" if x is None else f"{x:.{n}f}".replace(".", ",")


def yn(b):
    return "tak" if b else "nie"


def main():
    quick = "--quick" in sys.argv
    only = [a for a in sys.argv[1:] if not a.startswith("--")]
    rows = []
    tuned_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "car_styles_tuned.json")
    tuned = {}
    if os.path.exists(tuned_path):
        with open(tuned_path) as f:
            tuned = json.load(f)
    for name, st in STYLES.items():
        if only and name not in only:
            continue
        if quick:
            t = tuned.get(name, {})
            sim = to_sim(name, st, t)
        else:
            sim, t = tune(name, st)
        rep = cs.report(sim, name)
        bot = dict(sim, power_kw=250.0)
        rep["bot250"] = cs.power_oversteer(bot)
        rep["bot250_sd"] = cs.sine_dwell(bot)
        rep["bot350_acc"] = cs.accel(dict(sim, power_kw=350.0))
        rows.append((name, st, sim, t, rep))
        print(name, t, {k: rep[k] for k in ("t100", "vmax", "brake100", "ay_max", "ug_deg_per_g",
                                             "roll_deg_per_g", "ssf")}, flush=True)
    for name, st, sim, t, rep in rows:
        tuned[name] = t
    with open(tuned_path, "w") as f:
        json.dump(tuned, f, indent=1, sort_keys=True)
    write_md(rows)
    write_gd(rows)


def write_md(rows):
    p = os.path.join(os.path.dirname(__file__), "..", "docs", "car_styles_sim.md")
    L = []
    L.append("# Modele aut z epoki - parametry z symulacji\n")
    L.append("Wygenerowane przez `python3 tools/car_styles_tune.py` (symulator `tools/car_sim.py`, "
             "odwzorowanie fizyki z `stunt_car.gd` na płaskiej suchej jezdni, opony całoroczne). "
             "Nie edytuj ręcznie - zmień założenia w `STYLES` i uruchom skrypt ponownie.\n")
    L.append("## Nastawy\n")
    L.append("| Model | Masa [kg] | Rozstaw osi / kół [m] | Promień koła [m] | Środek masy nad jezdnią [m] | Przód [%] | "
             "Bezwładność przechył/pochylenie/odchylenie | Cd·A [m²] | Napęd | Moc fabryczna | Zawieszenie | "
             "final_mult | Sprężyny (×) | Stabilizatory P/T (×) | Hamulce P/T [Nm] |")
    L.append("|" + " --- |" * 15)
    for name, st, sim, t, rep in rows:
        L.append(f"| {st['label']} | {st['mass']} | {fmt(st['wb'],2)} / {fmt(st['track'],2)} | {fmt(st['r'],2)} | "
                 f"{fmt(rep['h_cg'],2)} | {fmt(rep['front_pct'],0)} | {sim['inertia'][0]} / {sim['inertia'][1]} / {sim['inertia'][2]} | "
                 f"{fmt(st['cd']*st['area'],2)} | {st['drive']}, {st['engine']} | {st['power']} kW | {st['susp']} | "
                 f"{fmt(t.get('final_mult',1.0),2)} | {fmt(t.get('spring_mult',1.0),2)} | {fmt(t.get('arb_front_mult',1.0),2)} / {fmt(t.get('arb_rear_mult',1.0),2)} | "
                 f"{int(sim.get('brake_front',1900))} / {int(sim.get('brake_rear',1050))} |")
    L.append("\n## Wyniki manewrów (moc fabryczna, ABS/TCS/ESP włączone, chyba że napisano inaczej)\n")
    L.append("| Model | 0-100 [s] | 0-160 [s] | V po 60 s [km/h] | 100-0 [m] | Skidpad R60 [g] | Podsterowność [deg/g] | "
             "Przechył [deg/g] | SSF | Częst. przód/tył [Hz] | Prześwit / po upadku z 1,5 m [m] |")
    L.append("|" + " --- |" * 11)
    for name, st, sim, t, rep in rows:
        L.append(f"| {st['label']} | {fmt(rep['t100'])} | {fmt(rep['t160'])} | {fmt(rep['vmax'],0)} | {fmt(rep['brake100'])} | "
                 f"{fmt(rep['ay_max'],2)} | {fmt(rep['ug_deg_per_g'],2)} | {fmt(rep['roll_deg_per_g'],1)} | {fmt(rep['ssf'],2)} | "
                 f"{fmt(rep['f_front'],2)} / {fmt(rep['f_rear'],2)} | {fmt(rep['static_clear'],2)} / {fmt(rep['min_clear'],2)}"
                 f"{' (dobicie)' if rep['bottomed'] else ''} |")
    L.append("\n## Stabilność i dachowanie\n")
    L.append("Sinus z przerwą (test ESC, 80 km/h): obrót 1 s i 1,75 s po skręcie względem szczytu "
             "(norma ≤ 0,35 / ≤ 0,20). Hak (fishhook, 80 km/h): największy przechył i czy dwa koła "
             "jednej strony oderwały się od jezdni. Gaz w łuku: pełny gaz przy 60% przyczepności na R40.\n")
    L.append("| Model | Sinus ESP | Sinus bez ESP | Sinus 120 km/h ESP | Hak ESP: przechył / 2 koła w górze | Hak bez ESP | "
             "Gaz w łuku ESP+TCS: znoszenie | Gaz w łuku bez pomocy | Bot 250 kW: gaz w łuku / sinus | Bot 350 kW: 0-100 / Vmax |")
    L.append("|" + " --- |" * 10)
    for name, st, sim, t, rep in rows:
        def sd(r):
            return f"{fmt(r['r1'],2)} / {fmt(r['r175'],2)} {'OK' if r['pass'] else 'NIE'}" + (" obrót" if r["spin"] else "") \
                + (" 2 koła" if r["lift2"] else "")
        def fh(r):
            return f"{fmt(r['roll'],1)}° / {yn(r['lift2'])}" + (f" ({fmt(r['lift_time'],2)} s)" if r["lift2"] else "")
        def po(r):
            return f"{fmt(r['beta_max'],1)}°" + (" obrót" if r["spin"] else "")
        L.append(f"| {st['label']} | {sd(rep['sd_esp'])} | {sd(rep['sd_noesp'])} | {sd(rep['sd120_esp'])} | {fh(rep['fish_esp'])} | {fh(rep['fish_noesp'])} | "
                 f"{po(rep['po_esp'])} | {po(rep['po_off'])} | {po(rep['bot250'])} / {sd(rep['bot250_sd'])} | "
                 f"{fmt(rep['bot350_acc']['t100'])} s / {fmt(rep['bot350_acc']['vmax'],0)} |")
    L.append("\n## Rozkład botów (wagi %)\n")
    L.append("| Model | Wąwóz i tunel | Autostrada |")
    L.append("| --- | --- | --- |")
    for name, st, sim, t, rep in rows:
        L.append(f"| {st['label']} | {st['bot_weight'][0]} | {st['bot_weight'][1]} |")
    with open(p, "w") as f:
        f.write("\n".join(L) + "\n")


def write_gd(rows):
    p = os.path.join(os.path.dirname(__file__), "..", "scripts", "car_styles.gd")
    L = ["class_name CarStyles", "",
         "## Modele aut z epoki: wymiary i fizyka (dane, bez logiki).",
         "## Wygenerowane przez tools/car_styles_tune.py z symulacji tools/car_sim.py -",
         "## nie edytuj ręcznie; wyniki manewrów w docs/car_styles_sim.md.",
         "## Układ jak w StuntCar: przód = -Z, mocowania kół na y = 0, com_offset",
         "## względem punktu odniesienia. inertia = (X pochylenie, Y odchylenie, Z przechył).",
         "## Mnożniki zawieszenia działają na zestaw z SUSPENSION_PRESETS (już skalowany masą).",
         "", "const STYLES := {"]
    for name, st, sim, t, rep in rows:
        fx = sim["front_x"]
        rx = sim["rear_x"]
        t2 = sim["track"] / 2
        ix = sim["inertia"]
        L.append(f'\t"{name}": {{')
        L.append(f'\t\t"label": "{st["label"]}",')
        L.append(f'\t\t"size": Vector3({st["dims"][1]}, {st["dims"][2]}, {st["dims"][0]}),')
        L.append(f'\t\t"mounts": [Vector3({-t2:.3f}, 0.0, {-fx:.3f}), Vector3({t2:.3f}, 0.0, {-fx:.3f}),')
        L.append(f'\t\t\t\tVector3({-t2:.3f}, 0.0, {-rx:.3f}), Vector3({t2:.3f}, 0.0, {-rx:.3f})],')
        L.append(f'\t\t"wheel_radius": {st["r"]}, "rest_length": {st["rest"]},')
        L.append(f'\t\t"mass": {float(st["mass"])}, "com_offset": Vector3(0.0, {sim["com_y"]:.3f}, {-sim["com_x"]:.3f}),')
        L.append(f'\t\t"inertia": Vector3({float(ix[1])}, {float(ix[2])}, {float(ix[0])}),')
        L.append(f'\t\t"body_bottom": {sim["body_bottom"]:.3f}, "cd": {st["cd"]}, "area": {st["area"]},')
        L.append(f'\t\t"engine": "{st["engine"]}", "power_kw": {st["power"]}, "drive": "{st["drive"]}",')
        L.append(f'\t\t"suspension": "{st["susp"]}", "final_mult": {t.get("final_mult", 1.0)},')
        L.append(f'\t\t"arb_front_mult": {t.get("arb_front_mult", 1.0)}, "arb_rear_mult": {t.get("arb_rear_mult", 1.0)},')
        L.append(f'\t\t"spring_mult": {t.get("spring_mult", 1.0)}, "damper_mult": {t.get("damper_mult", 1.0)},')
        L.append(f'\t\t"brake_front": {float(sim.get("brake_front", 1900.0))}, "brake_rear": {float(sim.get("brake_rear", 1050.0))},')
        L.append(f'\t\t"bot_weight": [{st["bot_weight"][0]}, {st["bot_weight"][1]}],   # wąwóz, autostrada')
        L.append("\t},")
    L.append("}")
    with open(p, "w") as f:
        f.write("\n".join(L) + "\n")


if __name__ == "__main__":
    main()
