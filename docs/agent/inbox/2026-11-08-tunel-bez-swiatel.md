# Tunel bez OmniLight3D (plan wydajności G1) - shadery gotowe, do wpięcia

Status: nowe
Od: wątek w chmurze "Zaplanuj refaktoring gorących punktów wydajności"
(2026-11-08)
Decyzje użytkownika (2026-11-08): plan zaakceptowany; pomysł użytkownika
na tunel: **lampy gęsto, co 2 m, po 1 m długości**, jako świecące paski,
a oświetlenie liczone w shaderze - bez prawdziwych świateł. Zmiana
wyglądu tunelu: przed scaleniem zrzut ekranu przed/po dla użytkownika.
Kolejność: po pomiarze bazowym (S2 tunel z `2026-11-08-plan-wydajnosci.md`),
żeby było widać zysk.

## Dlaczego tak (do HANDOVER, sekcja tunelu)

Renderer mobile wybiera światła per obiekt (do 8). Tunel to jedna siatka,
więc każdy jej piksel (i piksele jezdni kawałka) liczył wszystkie światła
tunelu. Gęsty pas lamp w szczycie rury to źródło liniowe, a dla takiego
źródła natężenie na wewnętrznej ścianie walca jest stałe (wyprowadzenie
w nagłówku `shaders/tunnel.gdshader`), na jezdni ~ H²/(H² + d²) od osi
rury. To liczy się w shaderze za darmo.

## Co jest w repo

- `shaders/tunnel.gdshader` (nowy) - ściany rury: beton + emisja lamp
  (stała), słońce i niebo przyciemnione przez `AO`/`AO_LIGHT_AFFECT`
  (dalej niż 80 m nie ma cieni, więc słońce świeciłoby w rurze).
- `shaders/road.gdshader` - nowe wejście `UV2.y` (dziś zawsze 0, więc bez
  zmian poza tunelem): 0 = otwarta droga, (0, 1] = pojedyncza rura,
  [-1, 0) = dwie nitki; |UV2.y| = jak bardzo w środku. Emisja z H²/(H²+d²)
  i przyciemnienie dnia jak w rurze.

## Wpięcie (`stunt_track.gd`)

1. `_build_tunnel`: ściany rury (pętla `_quad_facing(st, ...)` po łukach)
   na osobnym `SurfaceTool` z materiałem z `tunnel.gdshader` (wspólny,
   `_shared_mats`); ściany czołowe (`_tunnel_facade`) zostają na
   `_concrete_material()` - patrzą na zewnątrz.
2. Pas jarzeniówek (`lamp`): zamiast ciągłego paska kwadraty po 1 m co
   2 m (ta sama siatka, ten sam materiał `_lamp_material`).
3. Usunąć `OmniLight3D` z `_build_tunnel` (pętla `light_next`).
4. `_build_mesh` / `_quad_uv`: `UV2.y` z próbki: `roof` → 1 (pojedyncza)
   albo -1 (dwie nitki - próbki z `meta.twin` w tym tunelu); łagodnie
   przy wylotach, np. liniowo od 0 do ±1 na pierwszych/ostatnich ~10 m
   tunelu (odległość od `d0` i `d0 + tunnel_len`).
5. Strojenie (uniformy): `lamp_energy` / `tunnel_lamp_energy` (to samo),
   `tunnel_lamp_h` (szczyt rury ~ `_tunnel_radius(hw)·(1 + TUNNEL_YC)`;
   dla dwóch nitek mniejszy - jeśli widać różnicę, osobny materiał jezdni
   tunelu dwunitkowego), `daylight`.
6. Auta w tunelu: bez świateł dostaną tylko otoczenie (w rurze
   przyciemnione cieniem). Jeśli w kokpicie za ciemno - **jedno**
   `OmniLight3D` bez cieni, zasięg ~10 m, nad autem gracza, włączane tylko
   z `roof` próbki. Bez pulsowania w rytm lamp: przy 100 km/h to ~14 Hz
   migotania w goglach (komfort).
7. Testy: `drive_test`/`endless_test` (scena), zrzut ekranu w tunelu
   pojedynczym i dwunitkowym przed/po dla użytkownika, pomiar S2.

Shadery pisane bez Godota - jeśli coś się nie kompiluje, popraw i dopisz
niżej. `AO_LIGHT_AFFECT` w rendererze mobile - sprawdź, czy działa
(objaw braku: w tunelu dalej jasno dalej niż 80 m od kamery).

## Prośba pilna (przed wpięciem)

Tylko kompilacja: zmieniony `shaders/road.gdshader` używa każda jezdnia,
a PR #21 czeka na to z scaleniem do `main`. Wystarczy np. zrzut ekranu
(`tests/screenshot.gd`) zwykłej drogi z gałęzi
`claude/project-thread-7spjja` - jezdnia ma wyglądać jak dziś (UV2.y = 0)
i log bez błędów shadera. Wynik dopisz niżej.

## Odpowiedź agenta lokalnego

(tu)
