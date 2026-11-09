#!/usr/bin/env python3
"""Pobiera multimedia do trybu "Autostrada" (lista: docs/MEDIA_AUTOSTRADA.md).

Uruchamia agent lokalny albo użytkownik - DOPIERO PO AKCEPTACJI LISTY przez
użytkownika. Chmura nie pobiera (brak dostępu do tych serwerów).

    python3 tools/fetch_highway_media.py --list          # co jest na liście
    python3 tools/fetch_highway_media.py textures        # tekstury PBR (ambientCG, Poly Haven)
    python3 tools/fetch_highway_media.py models          # paczki modeli (Kenney; Quaternius ręcznie)
    python3 tools/fetch_highway_media.py find-sounds     # kandydaci z Freesound (API, klucz poza repo)
    python3 tools/fetch_highway_media.py sounds          # dźwięki z SOUNDS (po wyborze)
    python3 tools/fetch_highway_media.py --credits       # wpisy do CREDITS.md (tylko pobrane)
    dodatkowo: --force (pobierz od nowa)

Gdzie trafia:
  textures/cc0/<nazwa>/{albedo,normal,roughness}.jpg      (W REPO - CC0, zgoda
                                                          użytkownika 2026-11-09)
  build/media/models/<paczka>/...                          (do ustalenia, co idzie do repo)
  audio/ambient/<nazwa>.ogg                                (Ogg Vorbis 96 kb/s, -20 LUFS)

Pliki pobrane ręcznie (serwisy, które nie dają pobierać skryptom - Quaternius
przez Google Drive, Freesound bez klucza) kładzie się do build/media_in/
pod nazwą z kolumny "plik" - skrypt bierze je stamtąd.

Klucz Freesound (darmowy, https://freesound.org/apiv2/apply) - TYLKO
w ~/.config/canion-raid/freesound.env jako FREESOUND_API_KEY=...
(jak klucze Jamendo; nigdy do repo).
"""
import io
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INCOMING = ROOT / "build" / "media_in"
TEX_OUT = ROOT / "textures" / "cc0"
MODEL_OUT = ROOT / "build" / "media" / "models"
SOUND_OUT = ROOT / "audio" / "ambient"
KEY_FILE = Path.home() / ".config" / "canion-raid" / "freesound.env"
UA = "canionraid-media-fetch/1.0"

ACG = "https://ambientcg.com"
PH_API = "https://api.polyhaven.com"

# ---------------------------------------------------------------------------
# Tekstury PBR, 1K (Quest: 1K wystarcza dla kafelków; 2K tylko jezdnia, jeśli
# pomiar pozwoli). Wszystkie CC0. Identyfikatory sprawdzone w API ambientCG
# 2026-11-09 (rozmiary zipów 1K-JPG z API; zip ma też mapy wysokości i AO,
# z których bierzemy tylko kolor, normalną GL i chropowatość).
# (nazwa, źródło, id, do czego)
# ---------------------------------------------------------------------------
TEXTURES = [
    ("asphalt", "acg", "Asphalt033", "asfalt autostrady (linie rysuje road.gdshader)"),
    ("asphalt_city", "acg", "Road012A", "zużyty asfalt ulicy w mieście"),
    ("sidewalk", "acg", "PavingStones138", "chodnik, szara kostka"),
    ("cobble", "acg", "PavingStones150", "kostka w centrum dużego miasta"),
    ("plaster", "acg", "Plaster001", "tynk elewacji (mnożony przez kolor instancji)"),
    ("plaster_painted", "acg", "PaintedPlaster017", "malowany tynk, odmiana"),
    ("plaster_patched", "acg", "PaintedPlaster006", "tynk z łatami, starsze domy"),
    ("brick", "acg", "Bricks105", "cegła elewacji (beżowa; czerwonej brak w API)"),
    ("facade_glass", "acg", "Facade001", "szklana elewacja biurowca (duże miasto)"),
    ("concrete", "acg", "Concrete046", "gładki beton barier New Jersey i ekranów"),
    ("grass", "acg", "Grass004", "łąka (teren biomu meadow)"),
    ("grass_short", "acg", "Grass005", "krótka trawa, pobocza"),
    ("desert_sand", "acg", "Ground093C", "piasek pustyni z falami wiatru"),
    ("beach_sand", "acg", "Ground080", "plaża (biom seaside)"),
    ("beach_wet", "acg", "Ground054", "wilgotny piasek przy wodzie"),
    ("dry_ground", "acg", "Ground110", "sucha ziemia ze żwirem (pola po żniwach, góry)"),
    ("aerial_beach", "ph", "aerial_beach_01", "plaża z lotu ptaka - teren daleko (opcja)"),
    ("aerial_grass_rock", "ph", "aerial_grass_rock", "trawa ze skałą - góry, teren daleko (opcja)"),
    # --- wąwóz, tunele, estakady, miasto (wątek "Usuń pozostałości dróg na
    # estakadach", 2026-11-09; ID sprawdzone w API ambientCG i Poly Haven).
    # Skały i mech zastępują tekstury z freepbr.com (licencja niepotwierdzona,
    # tylko lokalnie).
    ("canyon_rock", "ph", "cliff_side", "ściany wąwozu: warstwowy osad (zamiast cavern-walls)"),
    ("canyon_rock_alt", "acg", "Rock063", "ściany wąwozu, zapas: skała warstwowa"),
    ("mountain_rock", "acg", "Rock058", "góry nad tunelami (zamiast ocean-rock)"),
    ("moss", "acg", "Moss002", "mech na zboczach w cieniu (zamiast derived/moss)"),
    ("gravel", "acg", "Gravel043", "pobocze ze żwiru, dno wąwozu pod estakadą"),
    ("concrete_rough", "acg", "Concrete047A", "okładzina tunelu, filary estakad"),
    ("roof_tiles", "acg", "RoofingTiles013A", "dachówka ceramiczna (domy)"),
    ("roof_slate", "acg", "RoofingTiles001", "dach z łupku (starsze kamienice)"),
    ("corrugated_steel", "acg", "CorrugatedSteel009", "blacha falista: warsztat, stacja, garaże"),
    ("asphalt_worn", "acg", "Road013A", "spękany asfalt: drogi lokalne, wyjazdy z wąwozu"),
    ("field_soil", "acg", "Ground109", "pole orne (biom pola)"),
    ("snow", "acg", "Snow015", "topniejący śnieg z trawą (góry, opcja)"),
    # Braki ambientCG uzupełnione z Poly Haven (CC0).
    ("brick_red", "ph", "brick_wall_001", "czerwona cegła (elewacje, stare hale)"),
    ("wood_planks", "ph", "brown_planks_03", "spłowiałe deski: płoty, stodoły, szopy"),
    ("plaster_house", "ph", "beige_wall_001", "malowany tynk domu (okna rysuje facade.gdshader)"),
]

# Zamienniki (użytkownik 2026-11-09: "tam, gdzie nie udało się pobrać, bierz
# zamienniki"): gdy pozycja się nie pobierze (zmieniony ID, 404), skrypt
# próbuje tej. Wszystkie CC0, ID widziane w API 2026-11-09.
FALLBACKS = {
    "asphalt": ("ph", "aerial_asphalt_01"),
    "asphalt_worn": ("acg", "Road012B"),
    "canyon_rock": ("acg", "Rock063"),
    "canyon_rock_alt": ("ph", "dark_rock_02"),
    "mountain_rock": ("acg", "Rock051"),
    "moss": ("acg", "Rock064"),
    "gravel": ("acg", "Ground081"),
    "concrete": ("acg", "Concrete034"),
    "concrete_rough": ("acg", "Concrete048"),
    "roof_tiles": ("acg", "RoofingTiles012A"),
    "roof_slate": ("acg", "RoofingTiles003"),
    "corrugated_steel": ("acg", "CorrugatedSteel007A"),
    "field_soil": ("acg", "Ground106"),
    "snow": ("acg", "Snow014"),
    "brick_red": ("ph", "brick_wall_006"),
    "wood_planks": ("ph", "dark_planks"),
    "plaster_house": ("ph", "blue_plaster_wall"),
}

# ---------------------------------------------------------------------------
# Paczki modeli (CC0). Kenney: zip ze strony (link szukany na stronie).
# Quaternius: pobieranie przez Google Drive / itch.io - ręcznie do
# build/media_in/<plik>. (nazwa, źródło, strona, plik w media_in, do czego)
# ---------------------------------------------------------------------------
MODELS = [
    ("kenney_city_suburban", "kenney", "https://kenney.nl/assets/city-kit-suburban", None,
     "domy jednorodzinne (małe miasto), płoty, drzewa"),
    ("kenney_city_commercial", "kenney", "https://kenney.nl/assets/city-kit-commercial", None,
     "budynki handlowe i wysokie (duże miasto)"),
    ("kenney_city_roads", "kenney", "https://kenney.nl/assets/city-kit-roads", None,
     "latarnie, znaki, elementy ulic (wybrane)"),
    ("kenney_nature", "kenney", "https://kenney.nl/assets/nature-kit", None,
     "krzewy, skały, kaktusy, drzewa"),
    ("quaternius_ultimate_nature", "manual", "https://quaternius.com/packs/ultimatenature.html",
     "Ultimate Nature Pack.zip", "palmy, sosny, kaktusy, skały (FBX/OBJ)"),
    ("quaternius_buildings", "manual", "https://quaternius.com/packs/ultimatetexturedbuildings.html",
     "Ultimate Buildings Pack.zip", "modułowe budynki z atlasem tekstur"),
    ("quaternius_farm", "manual", "https://quaternius.com/packs/farmbuildings.html",
     "Farm Buildings Pack.zip", "wiatrak, płoty, stodoły (biom pola) - licencja do sprawdzenia na stronie"),
]

# ---------------------------------------------------------------------------
# Dźwięki otoczenia: zapytania do Freesound (tylko CC0 i CC-BY, >= 45 s).
# SOUNDS uzupełnia się po wyborze kandydatów (find-sounds) i akceptacji
# użytkownika: (plik wyjściowy, id Freesound).
# ---------------------------------------------------------------------------
SOUND_QUERIES = [
    ("city", "city street ambience traffic"),
    ("sea", "sea waves seagulls"),
    ("desert_wind", "desert wind"),
    ("meadow", "crickets meadow evening"),
    ("highway_far", "distant highway traffic hum"),
    ("mountain_wind", "mountain wind howling"),
]
SOUNDS: list[tuple[str, int]] = [
    # ("city.ogg", 123456),
]
LICENSE_FILTER = 'license:("Creative Commons 0" OR "Attribution")'


def get(url: str, headers: dict | None = None) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA, **(headers or {})})
    with urllib.request.urlopen(req, timeout=180) as r:
        return r.read()


def incoming(name: str) -> bytes | None:
    p = INCOMING / name
    if p.exists():
        print(f"    z dysku: {p.relative_to(ROOT)}")
        return p.read_bytes()
    return None


# --------------------------------------------------------------------------- tekstury

MAPS = {"albedo": ("_Color.jpg", "Diffuse"), "normal": ("_NormalGL.jpg", "nor_gl"),
        "roughness": ("_Roughness.jpg", "Rough")}


def fetch_acg(asset: str, out: Path) -> None:
    name = f"{asset}_1K-JPG.zip"
    data = incoming(name) or get(f"{ACG}/get?file={name}")
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        names = z.namelist()
        for key, (suffix, _ph) in MAPS.items():
            hit = [n for n in names if n.endswith(suffix)]
            if not hit:
                raise RuntimeError(f"brak {suffix} w {name}: {names}")
            (out / f"{key}.jpg").write_bytes(z.read(hit[0]))


def fetch_ph(asset: str, out: Path) -> None:
    files = json.loads(get(f"{PH_API}/files/{asset}"))
    for key, (_suffix, ph) in MAPS.items():
        url = files[ph]["1k"]["jpg"]["url"]
        (out / f"{key}.jpg").write_bytes(get(url))


def textures(force: bool) -> int:
    errors = 0
    for name, src, asset, _use in TEXTURES:
        out = TEX_OUT / name
        if (out / "albedo.jpg").exists() and not force:
            print(f"jest: {name}")
            continue
        print(f"pobieram: {name} ({src} {asset})")
        try:
            out.mkdir(parents=True, exist_ok=True)
            try:
                (fetch_acg if src == "acg" else fetch_ph)(asset, out)
            except Exception as e:
                if name not in FALLBACKS:
                    raise
                src, asset = FALLBACKS[name]
                print(f"    nie wyszło ({e}) - zamiennik: {src} {asset}")
                (fetch_acg if src == "acg" else fetch_ph)(asset, out)
            (out / "SOURCE.txt").write_text(f"{src} {asset} CC0\n", encoding="utf-8")
            size = sum(p.stat().st_size for p in out.glob("*.jpg"))
            print(f"    -> {out.relative_to(ROOT)} ({size // 1024} KB)")
        except Exception as e:
            errors += 1
            print(f"    BŁĄD: {e}")
    return errors


# --------------------------------------------------------------------------- modele

def kenney_zip(page_url: str) -> str:
    page = get(page_url).decode("utf-8", "replace")
    for href in re.findall(r'href="([^"]+\.zip)"', page):
        return urllib.parse.urljoin(page_url, href)
    raise RuntimeError(f"brak linku .zip na {page_url} - pobierz ręcznie do build/media_in/")


def models(force: bool) -> int:
    errors = 0
    for name, src, page, file, _use in MODELS:
        out = MODEL_OUT / name
        if out.exists() and any(out.iterdir()) and not force:
            print(f"jest: {name}")
            continue
        print(f"pobieram: {name}")
        try:
            data = incoming(file) if file else None
            if data is None:
                if src == "manual":
                    raise RuntimeError(f"pobierz ręcznie z {page} do build/media_in/{file}")
                url = kenney_zip(page)
                print(f"    {url}")
                data = incoming(url.rsplit("/", 1)[-1]) or get(url)
            out.mkdir(parents=True, exist_ok=True)
            with zipfile.ZipFile(io.BytesIO(data)) as z:
                # Tylko modele i tekstury (bez podglądów, plików .blend i źródeł).
                keep = [n for n in z.namelist()
                        if n.lower().endswith((".glb", ".gltf", ".bin", ".obj", ".mtl", ".fbx", ".png", ".txt"))
                        and "preview" not in n.lower()]
                for n in keep:
                    dst = out / n
                    dst.parent.mkdir(parents=True, exist_ok=True)
                    dst.write_bytes(z.read(n))
            size = sum(p.stat().st_size for p in out.rglob("*") if p.is_file())
            print(f"    -> {out.relative_to(ROOT)} ({len(keep)} plików, {size / 1e6:.1f} MB)")
        except Exception as e:
            errors += 1
            print(f"    BŁĄD: {e}")
    return errors


# --------------------------------------------------------------------------- dźwięki

def freesound_key() -> str:
    if not KEY_FILE.exists():
        raise RuntimeError(f"brak {KEY_FILE} (FREESOUND_API_KEY=...) - klucz nie idzie do repo")
    for line in KEY_FILE.read_text(encoding="utf-8").splitlines():
        if line.startswith("FREESOUND_API_KEY="):
            return line.split("=", 1)[1].strip()
    raise RuntimeError(f"w {KEY_FILE} brak FREESOUND_API_KEY")


def fs_api(path: str, params: dict) -> dict:
    params = {**params, "token": freesound_key()}
    return json.loads(get(f"https://freesound.org/apiv2/{path}?{urllib.parse.urlencode(params)}"))


def find_sounds() -> int:
    for name, query in SOUND_QUERIES:
        r = fs_api("search/text/", {
            "query": query, "filter": f"{LICENSE_FILTER} duration:[45 TO 600]",
            "sort": "downloads_desc", "page_size": 8,
            "fields": "id,name,username,license,duration,url"})
        print(f"\n== {name}: \"{query}\"")
        for s in r.get("results", []):
            lic = s["license"].rstrip("/").rsplit("/", 2)[-2:]
            print(f"  {s['id']:>7}  {s['duration']:6.0f} s  {'/'.join(lic):12}  {s['username']}: {s['name']}  {s['url']}")
    print("\nWybrane wpisz do SOUNDS (plik, id) i pokaż użytkownikowi do akceptacji.")
    return 0


def sounds(force: bool) -> int:
    if shutil.which("ffmpeg") is None:
        print("brak ffmpeg")
        return 1
    errors = 0
    SOUND_OUT.mkdir(parents=True, exist_ok=True)
    for file, sid in SOUNDS:
        dst = SOUND_OUT / file
        if dst.exists() and not force:
            print(f"jest: {file}")
            continue
        try:
            info = fs_api(f"sounds/{sid}/", {"fields": "id,name,username,license,url,previews"})
            # Podgląd HQ (OGG ~192 kb/s) - pełny oryginał wymaga OAuth; na pętle
            # otoczenia na Queście jakość podglądu wystarcza.
            src = INCOMING / f"freesound_{sid}.ogg"
            data = src.read_bytes() if src.exists() else get(info["previews"]["preview-hq-ogg"])
            tmp = SOUND_OUT / f".{sid}.src"
            tmp.write_bytes(data)
            subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-y", "-i", str(tmp), "-vn",
                            "-af", "loudnorm=I=-20:TP=-2:LRA=7", "-ar", "44100", "-ac", "2",
                            "-c:a", "libvorbis", "-b:a", "96k", str(dst)], check=True)
            tmp.unlink()
            (SOUND_OUT / (file + ".json")).write_text(json.dumps({
                "id": sid, "name": info["name"], "author": info["username"],
                "license": info["license"], "url": info["url"]}, ensure_ascii=False), encoding="utf-8")
            print(f"    -> {dst.relative_to(ROOT)} ({dst.stat().st_size // 1024} KB) - pętla do sprawdzenia uchem")
        except Exception as e:
            errors += 1
            print(f"    BŁĄD {file}: {e}")
    return errors


# --------------------------------------------------------------------------- lista, podziękowania

def list_all() -> int:
    print("TEKSTURY (CC0):")
    for name, src, asset, use in TEXTURES:
        print(f"  {name:20} {src:4} {asset:20} {use}")
    print("MODELE (CC0):")
    for name, src, page, file, use in MODELS:
        print(f"  {name:28} {page}  {use}")
    print("DŹWIĘKI: zapytania", ", ".join(q for _n, q in SOUND_QUERIES), f"- wybranych: {len(SOUNDS)}")
    return 0


def credits() -> int:
    lines = ["## Tekstury, modele i dźwięki (tools/fetch_highway_media.py)", ""]
    tex = []
    for n, s, a, _u in TEXTURES:
        src_file = TEX_OUT / n / "SOURCE.txt"
        if (TEX_OUT / n / "albedo.jpg").exists():
            if src_file.exists():      # zamiennik mógł zastąpić pozycję z listy
                s, a = src_file.read_text(encoding="utf-8").split()[:2]
            tex.append((n, s, a))
    if tex:
        lines.append("### Tekstury (CC0)")
        lines.append("")
        for n, s, a in tex:
            url = f"{ACG}/view?id={a}" if s == "acg" else f"https://polyhaven.com/a/{a}"
            who = "ambientCG (Lennart Demes)" if s == "acg" else "Poly Haven"
            lines.append(f"- {n}: \"{a}\" - {who}, CC0, {url}")
        lines.append("")
    mods = [(n, p) for n, _s, p, _f, _u in MODELS if (MODEL_OUT / n).exists()]
    if mods:
        lines.append("### Modele (CC0)")
        lines.append("")
        for n, p in mods:
            who = "Kenney (kenney.nl)" if n.startswith("kenney") else "Quaternius (quaternius.com)"
            lines.append(f"- {n}: {who}, CC0, {p}")
        lines.append("")
    snd = sorted(SOUND_OUT.glob("*.ogg.json")) if SOUND_OUT.exists() else []
    if snd:
        lines.append("### Dźwięki otoczenia")
        lines.append("")
        for j in snd:
            d = json.loads(j.read_text(encoding="utf-8"))
            lic = "CC0" if "zero" in d["license"] else d["license"]
            lines.append(f"- \"{d['name']}\" - {d['author']}, {lic}, {d['url']}")
        lines.append("")
    print("\n".join(lines))
    return 0


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    force = "--force" in sys.argv
    if "--list" in sys.argv or not sys.argv[1:]:
        return list_all()
    if "--credits" in sys.argv:
        return credits()
    errors = 0
    for what in args:
        try:
            errors += {"textures": textures, "models": models, "sounds": sounds}[what](force) \
                if what != "find-sounds" else find_sounds()
        except KeyError:
            print(f"nieznane: {what}")
            return 2
        except Exception as e:
            print(f"BŁĄD: {e}")
            errors += 1
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
