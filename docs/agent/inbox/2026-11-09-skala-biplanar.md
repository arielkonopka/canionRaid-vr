# Tańsza skała: shaders/rock_biplanar.gdshader (odpowiedź na raport pomiaru)

Status: nowe
Od: wątek w chmurze "Zaplanuj refaktoring gorących punktów wydajności"
(2026-11-09), odpowiedź na `outbox/2026-11-09-pomiar-bazowy.md`
Decyzje użytkownika: plan wydajności zaakceptowany 2026-11-08; zmiana
wyglądu skały - zrzut przed/po dla użytkownika przed przełączeniem na stałe.

Dzięki za raport - dynamiczna rozdzielczość i nieskompresowane tekstury
to ważne znalezisko; poprawię `docs/PERF_PLAN.md` (sekcja 2) tak, żeby
stare liczby były oznaczone jako nieważne.

## Co jest

`shaders/rock_biplanar.gdshader` - na gałęzi `claude/project-thread-7spjja`
(PR #21), **te same uniformy** co `rock.gdshader` (z Twoim `nrm_tap` RG),
więc podmiana to jedna linia w `_rock_material`
(`load("res://shaders/rock_biplanar.gdshader")`) albo przełącznik `Bench`.

- biplanar (Quilez): dwie osie o największym |n|, `textureGrad`
  z pochodnych pozycji (bez szwów mipmap przy zmianie osi); ciągłość wag
  wyjaśniona w nagłówku;
- mech tylko albedo (bez `moss_normal`), pod mchem normalna skały
  wygładzona (`moss_relief` 0,35);
- `normal_dist` domyślnie 25 m - **ale `_rock_material` może go
  nadpisywać** (Twój A/B ustawia 0) - sprawdź, czy nie ustawia 40;
- odczyty: najgorzej 6 zamiast 12, daleko 4 zamiast do 6.

## Prośba

1. Kompilacja + zrzut wąwozu z bliska i z daleka, `rock.gdshader` vs
   `rock_biplanar.gdshader` (dla użytkownika).
2. S1 przy 110% i 130%: GPU ms obu wersji. Jeśli różnica wyglądu
   widoczna na skosach - `blend_pow` 2-4 (ostrzej).
3. Przy okazji z PR #21: kompilacja `road.gdshader` (prośba w
   `2026-11-08-tunel-bez-swiatel.md`) - PR czeka na nią ze scaleniem.

## Odpowiedź agenta lokalnego

(tu)
