# Maski lakieru dla aut z epoki z teksturą (GGBotNet): lakier = piksele,
# które różnią się między dwoma wariantami koloru tej samej tekstury.
# Wynik: models/period_cars/<model>/paint_mask.png
#   R = 1 na lakierze, G = jasność piksela względem średniej lakieru / 2
#   (cienie i przetłoczenia z tekstury zostają w kolorze gangu).
# Czyta shaders/period_paint.gdshader. Uruchom po prepare_period_cars.py:
#   python3 tools/make_paint_masks.py
import os
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
PAIRS = {
    "kombi": ("models/ggbotnet/car_01/car.png", "models/ggbotnet/car_01/car_red.png"),
    "hatchback": ("models/ggbotnet/car_03/car3.png", "models/ggbotnet/car_03/car3_red.png"),
    "furgon": ("models/ggbotnet/car_04/car4.png", "models/ggbotnet/car_04/car4_grey.png"),
    "muscle": ("models/ggbotnet/car_05/car5.png", "models/ggbotnet/car_05/car5_green.png"),
}


def lum(p):
    return 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]


for name, (a, b) in PAIRS.items():
    A = Image.open(os.path.join(ROOT, a)).convert("RGB")
    B = Image.open(os.path.join(ROOT, b)).convert("RGB")
    w, h = A.size
    paint = []
    for y in range(h):
        for x in range(w):
            pa, pb = A.getpixel((x, y)), B.getpixel((x, y))
            if sum(abs(pa[k] - pb[k]) for k in range(3)) > 40:
                paint.append((x, y))
    mean = sum(lum(A.getpixel(p)) for p in paint) / max(len(paint), 1)
    out = Image.new("RGB", (w, h))
    for x, y in paint:
        g = min(255, int(lum(A.getpixel((x, y))) / mean * 0.5 * 255))
        out.putpixel((x, y), (255, g, 0))
    path = os.path.join(ROOT, "models/period_cars", name, "paint_mask.png")
    out.save(path)
    print(name, len(paint), "px lakieru, średnia jasność %.0f" % mean, "->", path)
