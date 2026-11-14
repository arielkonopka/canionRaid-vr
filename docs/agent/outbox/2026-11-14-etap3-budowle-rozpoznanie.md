# Etap 3 (budowle): co umie dziś autostrada, prośba o zlecenie

Od: agent lokalny (2026-11-14). Etap 2 (przekroje 2a-2e) jest zrobiony
i scalony (PR #94-#100). Według zatwierdzonej kolejności następne są
budowle (b0 kodu odcinka). Niżej rozpoznanie kodu, jak przy etapie 2.

## Stan dziś

- **Autostrada jest płaska.** `HighwayGenerator` daje `pitch` 0
  i `ROAD_Y` 1 m, a teren to płaszczyzna (komentarz w generatorze).
  Podjazd górski, zjazd z serpentynami i estakada nad doliną wymagają
  pochylenia jezdni i terenu pod nią:
  - nasyp do y = 0 dziś liczy się z wysokości próbki, więc nasyp przy
    podjeździe "rośnie" sam;
  - teren i horyzont się nie podniosą. Góra dookoła to dekoracja albo
    zmiana `ground.gdshader` / siatki ziemi (1200 m, jedzie za autem).
- **Tunel jest gotowy, ale tylko w wąwozie.** `StuntTrack._build_tunnel`
  (wiercona rura, jarzeniówki jako emisja w shaderze, wersja
  dwururowa `twin`) bierze się z meta `tunnel_len`. Autostrada go nie
  wywołuje.
  - Dwie jezdnie autostrady to jezdnia + `_build_highway`
    (przesunięte próbki), a tunel buduje rurę wokół jednej jezdni.
  - Najtańsze: rura na każdą jezdnię (jak `twin`) albo jedna szeroka
    dla obu (14,8 + 2 x 11,25 m to dużo jak na wierconą).
  - Pas rozdziału i barierki w tunelu trzeba wyłączyć.
- **Wiadukt nad autostradą już jest** (`_build_overpass`, meta
  `overpass`, pomost 6,5 m nad jezdnią). "Wiadukt kolejowy z pociągiem"
  = ten pomost + tory + pociąg (MultiMesh / kilka brył, ruch
  kinematyczny jak auta z naprzeciwka, bez fizyki).
- **Most nad rzeką** = płaski odcinek na filarach. Dziś pod jezdnią jest
  nasyp do terenu, więc potrzebne są: brak nasypu na odcinku, pas wody
  pod spodem (jest `ocean.gdshader` - morze w biomie nadmorskim)
  i balustrady zamiast barier energochłonnych. Bez pochylenia, więc
  tanio.
- **Miasto liniowe (b0 = 7) z rondem** to etap 5 - zostawiam.

## Pytania / prośba

1. Zlecenie etapu 3 w trybie jak dotąd: Wy - czysta logika budowli
   (np. profil wysokości `height_at(d)` z kodu odcinka, długości,
   miejsca filarów, dekoracje) z testem; ja - geometria, fizyka, boty,
   rendery, bench.
2. Kolejność w etapie - moja propozycja, od najtańszego:
   1. most nad rzeką (płasko, bez nasypu, woda, balustrady);
   2. tunel (gotowa rura z wąwozu, dwie nitki);
   3. wiadukt kolejowy z pociągiem;
   4. podjazd / zjazd (pochylenie, nasyp, pas dla wolnych z etapu 2,
      sekcja 1);
   5. estakada nad doliną (wysoko - teren w dół, filary).
3. Pochylenie autostrady: czy jest zgoda na zmianę płaskiego założenia
   generatora? Dotyka fizyki aut (rampa skoczni jest już pochylona, więc
   silnik to zniesie) i botów (`_calm_speed` nie zna nachylenia).

Gogle odłączone - bench etapu 2 (strefa robót) przy następnym
podłączeniu.
