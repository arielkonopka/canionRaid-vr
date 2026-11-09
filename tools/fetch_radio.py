#!/usr/bin/env python3
"""Pobiera i konwertuje muzykę do radia na tablecie (audio/radio/).

Uruchamia agent lokalny albo użytkownik (zgoda użytkownika na dobór
i pobranie muzyki: 2026-11-08). Chmura nie ma dostępu do opengameart.org.

    python3 tools/fetch_radio.py            # pobiera brakujące pliki
    python3 tools/fetch_radio.py --force    # pobiera wszystko od nowa
    python3 tools/fetch_radio.py --check    # tylko zgodność z radio_stations.gd

Dla każdego utworu: strona źródłowa -> link do pliku pasujący do wzorca
-> (rozpakowanie zip) -> ffmpeg: Ogg Vorbis 96 kb/s, 44,1 kHz, stereo,
wyrównana głośność (loudnorm -16 LUFS, żeby stacje grały równo).
Licencje są w scripts/radio_stations.gd (sprawdzone na stronach 2026-11-08);
przy zmianie tabeli niżej popraw też tamten plik.
"""
import html
import io
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# ccMixter nie wydaje plików skryptom (HTTP 403) - pliki pobrane ręcznie
# w przeglądarce kładzie się tutaj (nazwa jak w adresie), skrypt je konwertuje.
INCOMING = ROOT / "build" / "radio_in"
OUT = ROOT / "audio" / "radio"
STATIONS_GD = ROOT / "scripts" / "radio_stations.gd"
OGA = "https://opengameart.org"
CCM = "https://ccmixter.org/files"
UA = "canionraid-radio-fetch/1.0"
AUDIO = (".ogg", ".mp3", ".wav", ".flac")

# plik docelowy, strona źródłowa, wzorzec nazwy pliku na stronie (bez wielkości liter).
# OpenGameArt dopisuje do nazw numer wersji (into_the_night_0.mp3,
# Into The Winds_6.ogg) - stąd (_\d+)? przed rozszerzeniem.
TRACKS = [
    ("fala84/midnight_drive.ogg", OGA + "/content/midnight-drive", r"midnight_drive(_\d+)?\.ogg$"),
    ("fala84/into_the_night.ogg", OGA + "/content/synthwave-to-drive-at-oceanside", r"into_the_night(_\d+)?\.mp3$"),
    ("fala84/moonlight.ogg", OGA + "/content/synthwave-to-drive-at-oceanside", r"moonlight(_\d+)?\.mp3$"),
    ("fala84/sunrise.ogg", OGA + "/content/synthwave-to-drive-at-oceanside", r"sunrise(_\d+)?\.mp3$"),
    ("fala84/the_cruise.ogg", OGA + "/content/synthwave-to-drive-at-oceanside", r"the_cruise(_\d+)?\.mp3$"),
    ("fala84/synthwave_type.ogg", OGA + "/content/synthwavetype", r"synth_type(_\d+)?\.mp3$"),
    ("szuter/into_the_winds.ogg", OGA + "/node/74545", r"into the winds(_\d+)?\.ogg$"),
    ("szuter/on_the_road.ogg", OGA + "/node/117857", r"on_the_road(_\d+)?\.zip$"),
    ("szuter/techno_drive.ogg", OGA + "/content/techno-drive", r"racing tecno_v2\.5(_\d+)?\.ogg$"),
    ("szuter/jump_higher_run_faster.ogg", OGA + "/node/3942", r"jump higher run faster(_\d+)?\.ogg$"),
    ("szuter/alt_rock_song.ogg", OGA + "/node/18237", r"mix a week week 4 and 5(_\d+)?\.mp3$"),
    ("nocna/calm_track.ogg", OGA + "/node/98635", r"calm_track(_\d+)?\.ogg$"),
    ("nocna/contemplation.ogg", OGA + "/node/85636", r"contemplation(_\d+)?\.mp3$"),
    ("nocna/calm_ambient_1.ogg", OGA + "/node/97098", r"001_synthwave_4k(_\d+)?\.mp3$"),
    ("nocna/chill_jungle_ambient.ogg", OGA + "/node/123092", r"\.ogg$"),
    # ccMixter: bezpośredni adres pliku z API (https://ccmixter.org/api/query?ids=N&f=json)
    ("psy/amigos.ogg", CCM + "/F_Fact/52032", "https://ccmixter.org/content/F_Fact/F_Fact_-_Amigos.mp3"),
    ("psy/end_of_days.ogg", CCM + "/F_Fact/43533", "https://ccmixter.org/content/F_Fact/F_Fact_-_End_of_Days.mp3"),
    ("psy/the_beach.ogg", CCM + "/Astral/50472", "https://ccmixter.org/content/Astral/Astral_-_The_Beach_(Original_Mix).mp3"),
    ("psy/psycho_freak.ogg", CCM + "/Psykick/37264", "https://ccmixter.org/content/Psykick/Psykick_-_Psycho_Freak_(Final_Edit).mp3"),
    ("psy/trance_dance.ogg", CCM + "/Psykick/40201", "https://ccmixter.org/content/Psykick/Psykick_-_Trance_Dance.mp3"),
    ("psy/tempest.ogg", CCM + "/Psykick/53063", "https://ccmixter.org/content/Psykick/Psykick_-_Tempest.mp3"),
    ("psy/shiva.ogg", CCM + "/chandubaba/52311", "https://ccmixter.org/content/chandubaba/chandubaba_-_Shiva.mp3"),
    ("psy/psytrance_for_a_game.ogg", OGA + "/content/psytrance-for-a-game-by-kris-klavenes", r"psytrance_for_a_game_by_kris_klavenes(_\d+)?\.mp3$"),
]


def get(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def find_link(page_url: str, pattern: str) -> str:
    page = get(page_url).decode("utf-8", "replace")
    rx = re.compile(pattern, re.I)
    for href in re.findall(r'href="([^"]+)"', page):
        href = html.unescape(href)
        # Pełne pliki; podglądy odtwarzacza (audio_preview, styles) pomijamy.
        if "/sites/default/files/" not in href or "audio_preview" in href or "/styles/" in href:
            continue
        name = urllib.parse.unquote(href.rsplit("/", 1)[-1])
        if rx.search(name):
            return urllib.parse.urljoin(page_url, href)
    raise RuntimeError(f"brak pliku pasującego do /{pattern}/ na {page_url}")


def pick_from_zip(data: bytes, tmp: Path) -> Path:
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        audio = [i for i in z.infolist() if i.filename.lower().endswith(AUDIO)]
        if not audio:
            raise RuntimeError("zip bez pliku audio")
        best = max(audio, key=lambda i: i.file_size)
        out = tmp / ("src" + Path(best.filename).suffix.lower())
        out.write_bytes(z.read(best))
        print(f"    z zipa: {best.filename}")
        return out


def convert(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["ffmpeg", "-nostdin", "-loglevel", "error", "-y", "-i", str(src),
         "-vn", "-af", "loudnorm=I=-16:TP=-1.5:LRA=11", "-ar", "44100", "-ac", "2",
         "-c:a", "libvorbis", "-b:a", "96k", str(dst)],
        check=True)


def check_consistency() -> bool:
    gd = set(re.findall(r'"file":\s*"([^"]+)"', STATIONS_GD.read_text(encoding="utf-8")))
    here = {t[0] for t in TRACKS}
    ok = gd == here
    if not ok:
        print("NIEZGODNOŚĆ z radio_stations.gd:")
        for f in sorted(gd - here):
            print("  tylko w radio_stations.gd:", f)
        for f in sorted(here - gd):
            print("  tylko w fetch_radio.py:", f)
    return ok


def main() -> int:
    if not check_consistency():
        return 1
    if "--check" in sys.argv:
        print("zgodne")
        return 0
    if shutil.which("ffmpeg") is None:
        print("brak ffmpeg")
        return 1
    force = "--force" in sys.argv
    errors = 0
    for file, page, pattern in TRACKS:
        dst = OUT / file
        if dst.exists() and not force:
            print(f"jest: {file}")
            continue
        print(f"pobieram: {file}")
        try:
            with tempfile.TemporaryDirectory() as td:
                tmp = Path(td)
                # Wzorzec zaczynający się od http to bezpośredni adres pliku.
                url = pattern if pattern.startswith("http") else find_link(page, pattern)
                print(f"    {url}")
                local = INCOMING / urllib.parse.unquote(url.rsplit("/", 1)[-1])
                if local.exists():
                    print(f"    z dysku: {local.relative_to(ROOT)}")
                    data = local.read_bytes()
                else:
                    data = get(url)
                if url.lower().endswith(".zip"):
                    src = pick_from_zip(data, tmp)
                else:
                    src = tmp / ("src" + Path(urllib.parse.unquote(url)).suffix.lower())
                    src.write_bytes(data)
                convert(src, dst)
                print(f"    -> {dst.relative_to(ROOT)} ({dst.stat().st_size // 1024} KB)")
        except Exception as e:  # jeden zły utwór nie zatrzymuje reszty
            errors += 1
            print(f"    BŁĄD: {e}")
    total = sum(p.stat().st_size for p in OUT.rglob("*.ogg"))
    print(f"razem: {total / 1e6:.1f} MB, błędów: {errors}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
