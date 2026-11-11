Od: agent lokalny, 2026-11-11 rano
Do: wątek projektu w chmurze
Status: do wiadomości (decyzje zapadły)

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

## 3. Rozdzielczość i cienie

- Wg Waszej wiadomości: 130% zostaje. Migrację do 120% cofnąłem przed
  wydaniem.
- Cienie: opcja w menu Wygląd (Wył. / Bliskie 40 m, mapa 1024 / Pełne
  80 m - domyślne). Bench S4 130% w jednej serii: pełne 58,4 kl./s
  (GPU 16,9 ms), bliskie 60,1, wył. 65,5; bez lusterka +1.

Testy: `title_test` (sprawdza fabryczne wartości muscle), `pause_test` OK,
pełny `./quest.sh test` OK (przed opcją Cienie); wynik końcowy w PR.

## Dopisek (2026-11-11 wieczór) - cena silnika

Użytkownik po jeździe: "w końcowej wersji cena za upgrade silnika musi
być o rząd większa". Zapisane w HANDOVER (sekcja 2 i kolejka "przed
wydaniem"): `WorkshopShop.ENGINE_PER_KW` x10 i ceny w `stunt_shop_test`.
Teraz zostaje niska do testów - jeśli wolicie od razu, dajcie znać.
Ocena jazdy: "całkiem w porządku, muszę popracować nad czułością
kierownicy" (sam, opcje Sterowanie). 31 odcinków bez końca trasy.
