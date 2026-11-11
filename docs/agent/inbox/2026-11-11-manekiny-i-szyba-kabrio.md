Status: nowe
Od: wątek w chmurze "Znajdź darmowe modele manekinów"
Decyzje użytkownika: użytkownik chce posadzić manekiny crash-test w autach
(zwłaszcza w kabriolecie). 2026-11-11 18:42 UTC użytkownik wybrał
"Crash Test Dummy mark1" (blendswap.com/blend/19677, CC0) - to jest zgoda
na pobranie tego jednego modelu do repo (models/, wpis w CREDITS.md).
Jeden model wszędzie, bez drugiego modelu CC-BY dla dalekich botów.

Prośba użytkownika (2026-11-11 18:34 UTC): "poszukaj darmowych modeli crash
test dummies... powsadzam je do samochodów, zwłaszcza w kabrio będzie to
lepiej wyglądać, bo cabriolet wygląda dziwnie, nie ma nawet przedniej szyby..."

# 1. Drobna poprawka: kabriolet bez przedniej szyby

Przyczyna jest w `tools/prepare_period_cars.py`: `CUT_ROOF = {"kabriolet": 0.80}`
usuwa **każdą** ścianę ze środkiem powyżej y=0,80 (jednostki siatki
`models/quaternius/SportsCar.obj`), więc razem z dachem znika przednia
szyba i słupki A. Powyżej progu jest 104 ścian materiału `Orange`
(z od -1,43 do 0,61, y 0,81-1,14) i 34 ściany `Windows` (z od -1,28 do
0,67, y 0,85-1,01). Siatka ma z od -1,98 do 1,98.

Propozycja: ciąć tylko za górną krawędzią przedniej szyby, czyli zostawić
ściany powyżej progu, które leżą w pasie szyby i słupków A (przedni koniec
kabiny w osi z; który znak z to przód, sprawdź tak jak `geometry()` dla osi
przedniej `_zf`). Szybę ewentualnie obniżyć/przyciąć na wysokości ~1,0,
żeby wyglądała jak niska szyba roadstera, a nie dach z dziurą. Potem
ponownie wygenerować `models/period_cars/kabriolet/body.obj`
(`prepare_period_cars.py`) i obejrzeć w goglach. Szyba to geometria tylko
wizualna: kolizja kabiny kabrioletu zostaje wyłączona jak teraz
(`stunt_car.gd`, `cs.disabled`). Zwróć uwagę, czy szyba nie zasłania
widoku z fotela (`eye_h = 1.10` dla kabrioletu w `car_styles_tune.py`).

# 2. Manekiny crash-test - kandydaci (do wyboru przez użytkownika)

Licencja zgodna z repo GPL: CC0 albo CC-BY (wpis do `models/CREDITS.md`).
Nie bierz modeli bez licencji, NC ani z Fab/CGTrader na licencji
standardowej (nie wolno ich redystrybuować w publicznym repo).

| Model | Licencja | Tris | Rig | Uwagi |
|---|---|---|---|---|
| Crash Test Dummy mark1, Panckuha, blendswap.com/blend/19677 | CC0 | ~1,8 tys. | Rigify (humanoid) | .blend 2.7x; najlepszy kandydat: CC0, rig do pozy siedzącej, rozsądna liczba trójkątów |
| Crash Test Dummy, NexiCide, sketchfab ...54020fb0 | CC-BY 4.0 | 264 | brak (Blockbench, kanciasty) | dobry na boty z daleka / LOD |
| Low-poly test dummy, HipDaMaster, sketchfab ...2f0d22a3 | CC-BY 4.0 | 596 | tak (wg opisu) | manekin ogólny, bez oznaczeń crash-test |
| Crash-test dummy, ART_LOLL, sketchfab ...6864f249 | CC-BY 4.0 | 12,5 tys. | nie podano | ładny, za ciężki dla botów na Queście bez decymacji |
| Rigged Crash Test Dummy, friskdreemurr66669, sketchfab ...e2852d83 | CC-BY 4.0 | 68,7 tys. | tak | za ciężki |
| Lowpoly Dummy Character, Umplix, opengameart | CC0 | nie podano | tak, 10 animacji (bez siedzenia) | FBX |
| Quaternius Universal Animation Library | CC0 | - | humanoid rig | są animacje siedzenia; można przenieść pozę na manekina z rigiem humanoidalnym |

Wydajność: manekin w każdym aucie bota to dodatkowa siatka na auto. Jeśli
rig ma służyć tylko do jednej pozy siedzącej, wypiecz pozę w statyczną
siatkę (bez Skeleton3D w grze), jeden materiał, ~1-2 tys. tris dla gracza
i bliskich botów, a dla dalekich botów wariant ~300 tris albo nic
(wizualizacja daleko może się upraszczać, fizyka nie).

Szczegóły i linki są w odpowiedzi wątku w chmurze dla użytkownika.
