Status: nowe
Od: wątek w chmurze "Popraw trakcję przy przyspieszaniu"
Decyzje użytkownika: zgłoszenie "auto rozpędza się wolniej przez zbyt słabą
trakcję". Zmiana poniżej to poprawka fizyki (bez ukrytych ułatwień), do
sprawdzenia testami; scalenie po potwierdzeniu wyników.

# Trakcja przy przyspieszaniu: analiza i poprawka sprzęgła

## Co sprawdzone (w chmurze, bez Godota)

Przepisałem wzdłużną część modelu (`_tire_forces` z relaksacją
i tłumieniem przy niskiej prędkości, MF C=1,4, load sensitivity, koło
z odbitą bezwładnością silnika, TCS, skrzynia, sprzęgło, opór) do
skryptu 1D z quasi-statycznym przenoszeniem masy (h_cg ≈ 0,58 m,
L = 2,57 m, 50/50). Kalibracja: 180 kW benzyna tył, całoroczne,
0-100 = 5,75 s (engine_test: 5,7 s).

Wnioski:
- **Trakcja nie jest za słaba.** μ = 1,1 · 0,94 (całoroczne) ≈ 1,03,
  z load sensitivity na tylnym kole ≈ 1,0. Napęd na tył przy 50/50
  daje fizyczną granicę ~0,6 g, model jedzie 5,9 m/s² w 1. biegu,
  czyli 97-98% tej granicy. Od 250 kW w górę 0-100 stoi na ~5,1 s
  (ograniczenie przyczepnością) - tak jest w prawdziwych autach.
- TCS (proporcjonalny, cel 0,09) trzyma poślizg ~0,15-0,18 (ρ ≈ 1,5),
  MF daje tam 97-98% szczytu. Strata 2-3%. Wyłączony TCS: koła buksują,
  0-100 o ~1 s gorzej (ogon MF ~80%) - to też realistyczne.
- **Prawdziwa strata była w sprzęgle.** Sprzęgło zamykało się, gdy
  obroty liczone z kół doszły do `clutch_engage_rpm` (1300), niezależnie
  od obrotów silnika. Przy ruszaniu silnik stał na `launch_rpm` 3800,
  przy ~12 km/h skakał na 1300 obr. i auto ciągnęło z ~63% momentu
  zamiast ~96%. Fizycznie sprzęgło tarciowe zamyka się dopiero po
  zrównaniu obrotów. Przy małej mocy (start gry: 90 kW) to wygląda
  i brzmi jak "auto się dusi", co łatwo wziąć za brak trakcji.

## Zmiana (PR do `boty-szal-tekstury`)

`stunt_car.gd`, `_update_gearbox`: sprzęgło (poza elektrykiem) otwarte
poniżej `clutch_engage_rpm` jak dotąd; ze stanu ślizgania zamyka się,
gdy `wheel_rpm >= engine_rpm - CLUTCH_SYNC_RPM` (100); zamknięte zostaje
zamknięte, dopóki obroty z kół ≥ `clutch_engage_rpm`. Po zmianie biegu
w górę silnik przez ~0,1 s dobiega do obrotów skrzyni na ślizgającym się
sprzęgle (przenosi wtedy swój moment), potem się zamyka.

Symulacja 0-100 (benzyna, tył, całoroczne, TCS wł.):
| kW  | przed  | po     |
|-----|--------|--------|
| 90  | 10,66 s | 9,93 s |
| 130 | 7,48 s | 7,00 s |
| 180 | 5,75 s | 5,63 s |
| 250+ | bez zmian (ograniczenie przyczepnością) |

## Do przetestowania

1. `engine_test` (wszystkie napędy × moce) - porównać 0-100 z tabelą
   wyżej i z HANDOVER; elektryk ma zostać bez zmian.
2. `drive_test` dla każdego zawieszenia i obu skrzyń (manual też:
   ruszanie, zmiany biegów, czy nic nie szarpie, udział TCS).
3. `hill_test` (ruszanie pod górę - sprzęgło ślizga się dłużej)
   i `reverse_test`.
4. `runup_test` - rozbiegi przy 90-180 kW będą szybsze; jeśli różnica
   > ~2 km/h, zaktualizować `RUNUP_CAP` w `track_generator.gd`
   (wiersze 90/130/180 kW), żeby skoki dalej były strojone pod realne
   możliwości auta.
5. Odsłuch / jazda: przy ruszaniu obroty trzymają się ~3800 do ~37 km/h
   w 1. biegu (benzyna; diesel 2000 obr.), potem płynnie rosną - bez
   spadku do 1300.
6. `launch_test` i `grip_test` (nowy TCS z wyprzedzeniem liczy `req`
   z `_engine_torque_at_clutch()`; przy dłuższym ślizganiu sprzęgła
   moment jest wyższy - sprawdzić, czy TCS nadal trzyma poślizg ~0,10).
7. Wynik do HANDOVER (sekcja skrzyni i wyniki testów) + odpowiedź tutaj.

## Na później (nie w tym PR)

- TCS z członem całkującym, celujący w szczyt (`peak_slip_ratio`) -
  w symulacji 1-3% przy mocach ograniczonych przyczepnością. Mały zysk,
  ryzyko oscylacji z dynamiką nadwozia, więc tylko jeśli użytkownik chce.
- Więcej trakcji fizycznie: opony letnie (+6%), 4x4. Nie podnoszę
  `tire_mu` - 1,03 dla całorocznych na suchym asfalcie jest już na
  górnej granicy realizmu.
