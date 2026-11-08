#!/usr/bin/env python3
"""Powtarzalna tekstura mchu z atlasu UV "Mossy Rock Model" (freepbr.com).

Atlas to kawałki do konkretnego modelu - kafelkowany wprost daje smugi.
Wycinamy 512x512 ze środka dużego kawałka i usuwamy szwy: obraz
przesunięty o pół rozmiaru mieszamy z oryginałem tak, że przy krawędziach
jest środek przesuniętego (krawędzie pasują do siebie).

    python3 tools/make_moss.py [X Y]      # domyślnie 150 600 (atlas 2048)

Wynik: textures/derived/moss_albedo.png, moss_normal.png. Tylko PIL.
"""
import os
import sys
from PIL import Image, ImageChops

SRC = 'textures/mossy-rock-model-bl/mossy-rock-model-'
X, Y = (int(sys.argv[1]), int(sys.argv[2])) if len(sys.argv) > 2 else (150, 600)
N = 512

mask = Image.new('L', (N, N))
px = mask.load()
for y in range(N):
    for x in range(N):
        d = min(x, N - 1 - x, y, N - 1 - y) / (N * 0.25)
        m = max(0.0, min(1.0, d))
        px[x, y] = int(m * m * (3 - 2 * m) * 255)

os.makedirs('textures/derived', exist_ok=True)
for name, out in [('albedo', 'moss_albedo'), ('nmap-ogl', 'moss_normal')]:
    im = Image.open(SRC + name + '.png').convert('RGB').crop((X, Y, X + N, Y + N))
    Image.composite(im, ImageChops.offset(im, N // 2, N // 2), mask).save(
        'textures/derived/' + out + '.png')
print('zapisano textures/derived/moss_albedo.png i moss_normal.png')
