Status: nowe
Od: wątek w chmurze "Popraw trakcję przy przyspieszaniu"
Decyzje użytkownika: prośba (2026-11-09) "przejrzyj źródła i poszukaj
nieścisłości, że coś wybierasz w menu, a to nie ma przełożenia na grę".
Punkt 1 ustalony (karta decyzji). Pozostałe to propozycje poprawek;
w punkcie 4 rekomendacja, użytkownik może zdecydować inaczej.

# Menu a gra: niespójności (przegląd `boty-szal-tekstury` @ 7e0b954)

Sprawdzone wszystkie 30 opcji z `GameSettings.OPTIONS`: gdzie trafiają
do gry (`apply_to_car`, `xr_main`, `bot_driver`) i czy coś je później
nadpisuje. Działają zgodnie z opisem: dźwigi, napęd, model, masa,
opony, napędzane koła, skrzynia, zawieszenie, lakier, ABS/TCS/ESP,
ograniczenie skrętu (przełączane w jeździe są zapisywane), sterowanie
(ręka gazu, drążek, krzywa, czułość), rozdzielczość, foweacja,
przezroczystość kokpitu, wszystkie opcje szału botów.

## 1. Moc w trasie bez końca - USTALONE
Osobny plik: `2026-11-09-moc-z-menu-w-trasie.md`.

## 2. Podpowiedzi "nie ma znaczenia" nigdy się nie pokazują (title.gd)
`_hint_for`: warunki dla `motor_layout` ("Dotyczy tylko elektryka...")
i `drive_layout` ("Silniki w kołach to zawsze 4x4...") są wewnątrz
gałęzi `match` dla `"engine_type", "engine_power"`, więc `opt["key"]`
nigdy nie jest tam `motor_layout` ani `drive_layout` - martwy kod.
Gracz z benzyną może przełączać "Silnik elektryczny" bez informacji, że
to nic nie zmienia. Poprawka: przenieść oba warunki do osobnych
gałęzi `"motor_layout":` i `"drive_layout":`.

## 3. Podpowiedź automatu kłamie w goglach
Hint skrzyni "auto": "hamulec na postoju = wsteczny". W goglach
`xr_main._read_drive_input` ustawia `car.dedicated_reverse = true`
i wsteczny jest pod gripem ręki z gazem; hamulec na postoju nic nie
włącza. Poprawka: w goglach hint "wsteczny: grip ręki z gazem (na
postoju)", na płasko jak teraz.

## 4. Spojler w concept carze: działa fizycznie, nie widać go
`set_body_model("concept")` chowa bryły spojlerów, ale `SPOILERS[spoiler]`
nadal liczy docisk i opór w `_physics_step`. Gracz z conceptem i "duży"
ma niewidzialne skrzydło (~480 kg docisku przy 300 km/h).
Rekomendacja: spojler tylko w sedanie - w conceptcie fizyka jak "none",
w menu hint "Tylko sedan" (alternatywa: zrobić bryły na concepcie).

## 5. "Silnik w kołach" zostaje w ukryciu po zmianie napędu
`apply_to_car` ustawia `car.hub_motors = motor_layout == "hub"` także
dla benzyny/diesla. Fizycznie nic to nie daje (`_hub()` wymaga
elektryka), ale gdy taki gracz wybierze w warsztacie elektryka, dostaje
4 silniki w kołach (4x4), choć w menu ma np. napęd na tył - a warsztat
pokazuje zwykłego "Elektryk N kW". Poprawka: w warsztacie
`car.hub_motors = opt.get("hub", false) or (car.engine_type == "electric"
and car.hub_motors)` - silniki w kołach tylko z ostatniego progu albo
gdy auto już je ma.

## Testy
`title_test` (2, 3, 4), `endless_test` z warsztatem (1, 5). Wynik do
HANDOVER i odpowiedź tutaj.
