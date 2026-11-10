Status: nowe
Od: wątek w chmurze "Dodaj kontrolki wspomagań na zegarach" / użytkownik
Decyzje użytkownika: kontrolki wspomagań na prędkościomierzu jako
trójkąty (jak znak ostrzegawczy) ze skrótem trzyliterowym, wyskalowane
i rozłożone tak, żeby nie nachodziły na siebie; **zgaszona = system
włączony**. Otwarte: miganie przy ingerencji i skrót "SKR" (propozycja
wątku, patrz niżej).

# Kontrolki wspomagań na prędkościomierzu

> **Ponowienie 2026-11-10:** użytkownik prosi o rozmowę z Tobą w tej
> sprawie. Ten plik leżał tylko na gałęzi PR #34 (nie w `main`), więc
> mogłeś go nie zauważyć. Gałąź `claude/project-thread-146jdo` ma już
> scalony aktualny `main` (bez konfliktów). Proszę: zmień `Status`,
> a wynik testów, uwagi (czytelność na Queście, miganie, skrót "SKR",
> zgodność z autami z epoki - czy zestaw zegarów `Gauges` jest u nich
> ten sam) dopisz w sekcji odpowiedzi na końcu tego pliku albo w
> `outbox/`. Jeśli testy przejdą, PR #34 zostanie scalony z chmury.

Słowa użytkownika (2026-11-09): "wspomagania powinny się pojawiać jako
kontrolki na desce, np. na głównym zegarze, kontrolki mogą być trójkątami,
jak znak ostrzegający przed czymś i skrótem trzyliterowym, oczywiście
odpowiednio wyskalowane i rozłożone na prędkościomierzu tak, by nie
nachodziły na siebie. zgaszona oznacza, że system jest włączony."

## Co jest w PR (gałąź `claude/project-thread-146jdo`)

- `scripts/gauges.gd`: `ASSIST_LAMPS` - ABS, TCS, ESP, SKR (ograniczenie
  skrętu) na łuku o promieniu 29 mm wokół osi prędkościomierza, kąty
  168°/127°/53°/12° (dwie po lewej, dwie po prawej, przerwa u góry).
  Trójkąt 18 mm: świecący obrys 1,1 mm + czarne wnętrze + skrót (Label3D
  font 42, piksel 0,0001 → ~4 mm). Kolory: świeci bursztynowo, zgaszona
  ciemnoszara (widać zarys, jak nieświecąca kontrolka).
  Napis "km/h" przesunięty wyżej (0,467 r), między górne kontrolki.
- Logika `Gauges.lamp_lit`: wyłączony system świeci stale; włączony jest
  zgaszony; **włączony i ingerujący miga 2 Hz** (jak ESP w prawdziwym
  aucie - zastępuje dawne "[ABS]" na desce). SKR nie ma stanu ingerencji.
  Materiał zmienia się tylko przy zmianie stanu.
- `scripts/stunt_car.gd`: `gauges.set_assist(...)` co klatkę; z
  `dash_label` zniknęły "ABS off"/"[ABS]"/"SKRĘT off" - zostaje tryb
  i bieg.
- `tests/gauges_test.gd` (nowy): logika świecenia + układ: trójkąty nie
  nachodzą na siebie, na liczby skali, "km/h", piastę ani LCD, i nie
  sięgają kresek (odstęp ≥ 1 mm; rozmiary napisów szacowane).

Kodu nie uruchamiano (brak Godota w chmurze).

## Prośba

1. Uruchom `tests/gauges_test.gd`, `tests/drive_test.gd` (zmiana dotyka
   `stunt_car.gd`) i `tests/assist_test.gd`; popraw błędy parsowania,
   jeśli są.
2. Zrzut ekranu kokpitu (`tests/screenshot.gd`) z jednym systemem
   wyłączonym - sprawdź, czy trójkąty nie wchodzą na liczby (szacunek
   rozmiaru Label3D w teście może być zbyt optymistyczny).
3. Na Queście: czy skróty są czytelne z fotela (~0,7 m - ok. 6 px na
   wysokość litery). Jeśli nie, można powiększyć `LAMP_SIDE` do ~0,02
   i font, ale wtedy `LAMP_RING`/kąty trzeba przesunąć (test policzy).
4. Wpisz wynik i ustalenia do HANDOVER.md (zegary, deska, sekcja
   sterowania "stan widać na desce").
