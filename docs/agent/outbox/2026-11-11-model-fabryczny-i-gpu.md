Od: agent lokalny, 2026-11-11 rano
Do: wątek projektu w chmurze
Status: do decyzji (użytkownik woli dziś rozmawiać przez chmurę)

# Odpowiedzi użytkownika z sekcji 9 HANDOVER i co z nimi zrobiłem

Użytkownik odpowiedział w terminalu "na wszystko tak" na trzy pytania.
Poprosił też, żeby takie rzeczy konsultować najpierw z chmurą - od teraz
pytania będą trafiać tutaj.

## 1. Model auta ustawia fabryczny silnik i masę - zrobione (gałąź boty-szal-tekstury)

- Zmiana modelu w menu (główne i pauza, wspólne `GameSettings.set_option`)
  ustawia z `CarStyles`: silnik, moc, napęd kół, zawieszenie, masę.
  Potem gracz może każdą z tych opcji zmienić.
- Nowa wartość opcji Masa: "Fabryczna" (0 = masa modelu). Domyślnie dla
  nowych graczy. Zapisane ustawienia użytkownika (elektryk 1000 kW,
  2500 kg) nie zmieniają się przy wczytaniu, tylko przy zmianie modelu.
- Silnik elektryczny i Rekuperacja przy zmianie modelu zostają bez zmian -
  użytkownik (2026-11-11): benzyna i diesel nic nie odzyskają, hybrydy
  nie ma. Menu już podpowiada przy tych opcjach "Dotyczy tylko elektryka".
  Rozstrzygnięte.

## 2. Kokpit sedana we wszystkich modelach - zostaje

## 3. Rozdzielczość: zejście do 110-120% i oszczędności GPU

- Migracja ustawień v11 obcina zapisane 130% do 120%. Przy 130% gogle
  miały ~60 kl./s (GPU 15,6 ms), przy 110% 72 kl./s. 120% jeszcze nie
  było mierzone.
- Na goglach do zmierzenia: bench S4 przy 130% bez cieni, bez lusterka,
  oraz przy 120%. Gogle są dziś odłączone od komputera. Pomiar zrobię po
  podłączeniu kabla. Cel: wrócić do 120-130% przy 72 kl./s.
- Cienie: użytkownik wybrał opcję w menu. Zrobione: Wygląd -> Cienie
  (Wył. / Bliskie 40 m, jedna mapa / Pełne 80 m, dwie mapy - domyślne,
  jak dotąd), działa od razu, także z pauzy.

Testy: `title_test` (sprawdza fabryczne wartości muscle), `pause_test` OK,
pełny zestaw w toku - wynik dopiszę w PR #58.
