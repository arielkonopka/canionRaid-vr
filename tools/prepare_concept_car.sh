#!/bin/sh
# Model "Car Concept" dla gry: models/concept_car/car_player.glb i car_bot.glb.
#   tools/prepare_concept_car.sh ŚCIEŻKA/CarConcept.glb
# Wymaga gltf-transform (npm, ~/opt/gltf-transform) i Pythona z PIL.
set -e
SRC="$1"
GTDIR="$HOME/opt/gltf-transform"
GT="$GTDIR/node_modules/.bin/gltf-transform"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/../models/concept_car"
TMP="$(mktemp -d)"
mkdir -p "$OUT" "$HERE/concept_car_tex"
python3 - "$HERE/concept_car_tex" <<'PY'
import sys
from PIL import Image, ImageDraw
d = sys.argv[1]
# Tablica: jasne pole z ramką, bez napisów. Bok opony: jednolita guma.
p = Image.new('RGB', (512, 128), (232, 232, 224))
ImageDraw.Draw(p).rectangle((4, 4, 507, 123), outline=(40, 40, 40), width=6)
p.save(d + '/plate.png')
Image.new('RGB', (1024, 1024), (30, 30, 30)).save(d + '/tireside.png')
Image.new('RGB', (64, 64), (128, 128, 255)).save(d + '/flat_normal.png')
PY
# Skrypt .mjs korzysta z paczek zainstalowanych obok gltf-transform.
NODE_PATH="$GTDIR/node_modules" cp "$HERE/prepare_concept_car.mjs" "$GTDIR/prep.mjs"
cp -r "$HERE/concept_car_tex" "$GTDIR/"
(cd "$GTDIR" && node prep.mjs "$SRC" "$TMP/player.glb" && node prep.mjs "$SRC" "$TMP/bot.glb" bot)
"$GT" optimize "$TMP/player.glb" "$OUT/car_player.glb" --compress false --texture-compress false \
	--texture-size 1024 --join false --flatten false --instance false --palette false \
	--simplify true --simplify-ratio 0.3 --simplify-error 0.002
"$GT" optimize "$TMP/bot.glb" "$OUT/car_bot.glb" --compress false --texture-compress false \
	--texture-size 256 --join true --join-named false --flatten false --instance false --palette false \
	--simplify true --simplify-ratio 0.15 --simplify-error 0.01
rm -rf "$TMP"
ls -la "$OUT"
