# Multimedia do trybu "Autostrada" - lista do akceptacji

Status: **tekstury zaakceptowane do repo** (użytkownik 2026-11-09: "dodać
tekstury do repo, jeśli są kompatybilne w sensie licencji" - wszystkie
poniżej są CC0, zgodne z GPL). Trafiają do `textures/cc0/` (wyjątek
w `.gitignore`). Nic jeszcze nie pobrane - chmura nie ma dostępu do tych
serwerów. Modele i dźwięki dalej czekają na akceptację.
Przegląd: wątek w chmurze "Zaprojektuj tryb Autostrada", 2026-11-09.
Pobieranie: `tools/fetch_highway_media.py` (agent lokalny, po akceptacji).
Wpisy do `CREDITS.md`: `python3 tools/fetch_highway_media.py --credits`
(generowane z tego, co faktycznie pobrano).

Zasady (outbox agenta): tylko CC0 / CC-BY / CC-BY-SA, bez cudzych marek
i rozpoznawalnych miejsc, wygląd względnie realistyczny (VISION, filar 10).

## Co sprawdziłem, a czego nie

- **ambientCG** - identyfikatory i rozmiary z ich API (2026-11-09). Wszystko
  CC0. Zip "1K-JPG" ma 3-10 MB, bo zawiera też mapy wysokości/AO; skrypt
  wyciąga tylko kolor, normalną (GL) i chropowatość (~1-2 MB na teksturę).
- **Poly Haven** - API działa (CC0), ale ich tekstury terenu to głównie
  skany "aerial_*" (do dalekiego terenu); jezdnie/elewacje lepsze
  w ambientCG.
- **Kenney / Quaternius** - strony paczek przeczytane (licencja CC0
  na stronie, liczba modeli); zawartości paczek Kenneya strona nie wymienia.
- **Freesound, OpenGameArt, poly.pizza** - nie dało się przeszukać
  z chmury (OpenGameArt blokuje roboty, Freesound wymaga klucza API,
  poly.pizza odrzuca). Dlatego dźwięków **nie wybrałem**: skrypt ma
  tryb `find-sounds`, który z kluczem Freesound (darmowy, trzymany poza
  repo jak klucze Jamendo) wypisze kandydatów CC0/CC-BY do wyboru.
- Słupki, latarnie, ekrany akustyczne, turbiny wiatrowe, palmy, kaktusy,
  krzewy i bryły domów są już **proceduralne** w `scripts/highway_scenery.gd`
  (zero pobierania, tanie w MultiMesh). Paczki modeli to opcjonalne
  ulepszenie wyglądu - najpierw pomiar na Queście.

## Tekstury PBR (1K, kafelkowane, CC0)

| Nazwa w grze | Zasób | Autor / źródło | Rozmiar zipa 1K | Do czego |
|---|---|---|---|---|
| asphalt | [Asphalt033](https://ambientcg.com/view?id=Asphalt033) | ambientCG | 9,7 MB | asfalt autostrady (linie dalej rysuje shader) |
| asphalt_city | [Road012A](https://ambientcg.com/view?id=Road012A) | ambientCG | 8,3 MB | zużyty asfalt w mieście |
| sidewalk | [PavingStones138](https://ambientcg.com/view?id=PavingStones138) | ambientCG | 4,9 MB | chodnik |
| cobble | [PavingStones150](https://ambientcg.com/view?id=PavingStones150) | ambientCG | 5,3 MB | kostka w centrum dużego miasta |
| plaster | [Plaster001](https://ambientcg.com/view?id=Plaster001) | ambientCG | ~5-10 MB* | tynk elewacji (kolor z instancji) |
| plaster_painted | [PaintedPlaster017](https://ambientcg.com/view?id=PaintedPlaster017) | ambientCG | ~5-10 MB* | malowany tynk |
| plaster_patched | [PaintedPlaster006](https://ambientcg.com/view?id=PaintedPlaster006) | ambientCG | 9,0 MB | tynk z łatami (starsze domy) |
| brick | [Bricks105](https://ambientcg.com/view?id=Bricks105) | ambientCG | ~5-10 MB* | cegła (beżowa; czerwonej w API brak) |
| facade_glass | [Facade001](https://ambientcg.com/view?id=Facade001) | ambientCG | 2,9 MB | szklany biurowiec (duże miasto) |
| concrete | [Concrete046](https://ambientcg.com/view?id=Concrete046) | ambientCG | ~5-10 MB* | bariery New Jersey, cokoły ekranów |
| grass | [Grass004](https://ambientcg.com/view?id=Grass004) | ambientCG | ~5-10 MB* | łąka |
| grass_short | [Grass005](https://ambientcg.com/view?id=Grass005) | ambientCG | ~5-10 MB* | pobocza, pola |
| desert_sand | [Ground093C](https://ambientcg.com/view?id=Ground093C) | ambientCG | 5,1 MB | pustynia (falki wiatru) |
| beach_sand | [Ground080](https://ambientcg.com/view?id=Ground080) | ambientCG | 6,9 MB | plaża |
| beach_wet | [Ground054](https://ambientcg.com/view?id=Ground054) | ambientCG | 8,7 MB | mokry piasek przy wodzie |
| dry_ground | [Ground110](https://ambientcg.com/view?id=Ground110) | ambientCG | 10,4 MB | sucha ziemia/żwir (ściernisko, góry) |
| aerial_beach (opcja) | [aerial_beach_01](https://polyhaven.com/a/aerial_beach_01) | Poly Haven | ~1,5 MB (3 mapy 1K) | daleki teren nad morzem |
| aerial_grass_rock (opcja) | [aerial_grass_rock](https://polyhaven.com/a/aerial_grass_rock) | Poly Haven | ~1,5 MB | daleki teren w górach |

\* rozmiar nie wrócił z API przy tym zapytaniu - typowo 5-10 MB.

Pobieranie razem ~200 MB, na dysku po wyciągnięciu ~45 MB (3 mapy 1K
na teksturę, `textures/cc0/<nazwa>/`), **w repo**.

### Dopisane: wąwóz, tunele, estakady, miasto (2026-11-09)

Z wątku "Usuń pozostałości dróg na estakadach" (ID sprawdzone w API).
Skały i mech zastępują dzisiejsze tekstury z freepbr.com (licencja
niepotwierdzona, tylko lokalnie).

| Nazwa w grze | Zasób | Do czego |
|---|---|---|
| canyon_rock | [cliff_side](https://polyhaven.com/a/cliff_side) (Poly Haven) | ściany wąwozu, warstwowy osad |
| canyon_rock_alt | [Rock063](https://ambientcg.com/view?id=Rock063) | zapas: skała warstwowa |
| mountain_rock | [Rock058](https://ambientcg.com/view?id=Rock058) | góry nad tunelami |
| moss | [Moss002](https://ambientcg.com/view?id=Moss002) | mech na zboczach w cieniu |
| gravel | [Gravel043](https://ambientcg.com/view?id=Gravel043) | pobocze, dno wąwozu pod estakadą |
| concrete_rough | [Concrete047A](https://ambientcg.com/view?id=Concrete047A) | tunel, filary estakad |
| roof_tiles | [RoofingTiles013A](https://ambientcg.com/view?id=RoofingTiles013A) | dachówka |
| roof_slate | [RoofingTiles001](https://ambientcg.com/view?id=RoofingTiles001) | dach z łupku |
| corrugated_steel | [CorrugatedSteel009](https://ambientcg.com/view?id=CorrugatedSteel009) | warsztat, stacja, garaże |
| asphalt_worn | [Road013A](https://ambientcg.com/view?id=Road013A) | spękany asfalt dróg lokalnych |
| field_soil | [Ground109](https://ambientcg.com/view?id=Ground109) | pole orne |
| snow | [Snow015](https://ambientcg.com/view?id=Snow015) | śnieg w górach (opcja) |
| brick_red | [brick_wall_001](https://polyhaven.com/a/brick_wall_001) (Poly Haven) | czerwona cegła |
| wood_planks | [brown_planks_03](https://polyhaven.com/a/brown_planks_03) (Poly Haven) | deski: płoty, stodoły, szopy |
| plaster_house | [beige_wall_001](https://polyhaven.com/a/beige_wall_001) (Poly Haven) | tynk domu |

**Zamienniki** (użytkownik: "tam, gdzie nie udało się pobrać, bierz
zamienniki"): `FALLBACKS` w skrypcie - gdy pozycja się nie pobierze,
skrypt sam bierze zastępczą (też CC0), a `--credits` podpisuje to, co
faktycznie pobrano (`SOURCE.txt`).

Elewacji mieszkalnej **z oknami** nie ma w żadnym z serwisów - okna rysuje
`facade.gdshader` na tynku (`plaster_house`, `plaster*`). Woda morska - bez tekstury: jest
proceduralny `ocean.gdshader`. Skały gór - te same co w wąwozie.

Braki: **pole uprawne / ściernisko** (w API nie znalazłem; zastępczo
`dry_ground` + `grass_short` mieszane w shaderze terenu pasami), **czerwona
cegła**. Do dobrania przez agenta lokalnego z przeglądarki, jeśli trzeba.

## Modele low-poly (CC0)

| Paczka | Autor | Licencja | Zawartość (ze strony) | Do czego |
|---|---|---|---|---|
| [City Kit (Suburban)](https://kenney.nl/assets/city-kit-suburban) | Kenney | CC0 | 40 plików, domy | domy jednorodzinne w małym mieście |
| [City Kit (Commercial)](https://kenney.nl/assets/city-kit-commercial) | Kenney | CC0 | 50 plików, budynki/wieżowce | śródmieście dużego miasta |
| [City Kit (Roads)](https://kenney.nl/assets/city-kit-roads) | Kenney | CC0 | 70 plików | latarnie, znaki (wybrane elementy) |
| [Nature Kit](https://kenney.nl/assets/nature-kit) | Kenney | CC0 | 330 modeli: drzewa, skały, rośliny | krzewy, skały, kaktusy |
| [Ultimate Nature Pack](https://quaternius.com/packs/ultimatenature.html) | Quaternius | CC0 | 150 modeli (FBX/OBJ): sosny, palmy, kaktusy, skały | palmy nad morzem, sosny w górach |
| [Ultimate Buildings Pack](https://quaternius.com/packs/ultimatetexturedbuildings.html) | Quaternius | CC0 | 76 modułowych budynków z atlasem | odmiana zabudowy |
| [Farm Buildings Pack](https://quaternius.com/packs/farmbuildings.html) | Quaternius | CC0 (strona nie czytana) | wiatrak, płoty, stodoły | biom pola |

Rozmiarów paczek strony nie podają (Kenney zwykle 5-30 MB, Quaternius
10-60 MB z plikami .blend - skrypt bierze tylko modele i tekstury).
Kenney ma styl uproszczony - do "względnie realistycznej" estetyki lepiej
pasują bryły proceduralne z teksturą tynku + okna z shadera; modele
Kenneya raczej na detale (latarnie, krzewy). Do decyzji po zrzucie ekranu.
Auta: paczki z wątku "Dodaj nowe modele aut z epoki" (osobna akceptacja).

Co do repo: modele po wyborze konkretnych plików (kilka MB) - do ustalenia
z użytkownikiem; całe paczki zostają w `build/media/` (poza gitem).

## Dźwięki otoczenia (pętle OGG)

Do wyboru przez `find-sounds` (Freesound, CC0 i CC-BY, 45-600 s):

| Plik | Zapytanie | Gdzie gra |
|---|---|---|
| city.ogg | city street ambience traffic | w mieście (zamiast/obok szumu autostrady) |
| sea.ogg | sea waves seagulls | biom nad morzem |
| desert_wind.ogg | desert wind | pustynia |
| meadow.ogg | crickets meadow evening | łąka, pola |
| highway_far.ogg | distant highway traffic hum | strefy ruchu wokół miast |
| mountain_wind.ogg | mountain wind howling | góry, wąwóz |

Skrypt bierze podgląd HQ (OGG, bez logowania OAuth), normalizuje do
-20 LUFS i zapisuje 96 kb/s stereo; pętlę trzeba sprawdzić uchem (albo
ciąć z przenikaniem w `env_audio.gd`). Szacunek: 6 × 1-2 MB - mogą iść do
repo jak muzyka radia (`audio/ambient/`), do decyzji użytkownika.
CC-BY wymaga podpisu w CREDITS (skrypt zapisuje autora i licencję obok pliku).

## Muzyka

Radio ma 23 utwory CC + stację Jamendo online. Więcej muzyki nie szukałem -
źródła skryptowe (OpenGameArt) są już wykorzystane, ccMixter blokuje skrypty.
