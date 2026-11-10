# Rendery trybu Autostrada (PC, 1280x720)

Generowane przez agenta lokalnego (chmura nie ma Godota):

    godot --xr-mode off --resolution 1280x720 -s res://tests/render_tour.gd -- docs/renders [ujęcie] </dev/null
    godot --xr-mode off --resolution 1280x720 -s res://tests/biome_shots.gd -- KATALOG </dev/null

`render_tour.gd` startuje trasę w zadanym miejscu planu (`EndlessTrack.start_dist`,
leniwa generacja - bez budowania wcześniejszych km), ziarno 777.
Render na PC (Forward+/Mobile na GPU stacji), nie z gogli - kolory i cienie
mogą się różnić od Questa.

| Plik | Co pokazuje |
|---|---|
| `biome_*_fwd.jpg` | biomy: łąka, pola, pustynia, góry, wybrzeże, wąwóz (auto na autostradzie) |
| `biome_seaside_left.jpg` | morze po lewej w biomie nadmorskim |
| `miasto_male_wjazd.jpg` | dojazd do małego miasta (25 km): ekrany akustyczne, zabudowa |
| `miasto_male_ulica.jpg` | ulica w małym mieście: 2 pasy, chodnik, latarnie, bez barier |
| `miasto_male_z_gory.jpg` | małe miasto z góry |
| `miasto_duze_centrum.jpg` | centrum dużego miasta (100 km), wysokie budynki |
| `miasto_duze_z_gory.jpg`, `miasto_duze_detal.jpg` | duże miasto z góry, chodniki |
| `warsztat_w_miescie.jpg` | warsztat 300 m za początkiem zabudowy |
| `stacja_paliw.jpg` | zjazd na stację (co ~20 km) |
| `wielka_skocznia_*.jpg` | wielka skocznia do 400 km/h (próg 3,5°, stół 170 m) |

Stan 2026-11-10 (noc): poprawione odwrócone ściany pudeł i chodników
(`HighwayScenery._box/_quad`), układ pasów autostrady w `road.gdshader`
(`layout` 1/2), w mieście bez barier energochłonnych i nasypu.
