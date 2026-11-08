# Instrukcje dla agenta - Stunt Track VR

## Zacznij od HANDOVER.md

Przed jakąkolwiek pracą przeczytaj cały `HANDOVER.md`. Jest tam stan
projektu, środowisko, pułapki, decyzje projektowe i następne kroki.
Nie zakładaj, że pamiętasz wcześniejsze sesje.

## Utrzymuj HANDOVER.md

`HANDOVER.md` ma być zawsze **kompletną instrukcją** dla agenta, który
nie zna tej ani żadnej wcześniejszej sesji. Po przeczytaniu samego tego
pliku (i kodu) musi dać się kontynuować pracę bez pytania użytkownika
o rzeczy, które już ustalono.

Aktualizuj go **w trakcie pracy, nie tylko na końcu**: po każdej
zakończonej zmianie, decyzji, odkrytej pułapce albo nowym ustaleniu
z użytkownikiem. Sesja może się urwać w dowolnym momencie.

Przy każdej aktualizacji:
- zmień datę "Ostatnia aktualizacja";
- popraw sekcje, które przestały być prawdziwe (stan, struktura plików,
  jak to działa, wynik testów). Dokument opisuje stan **obecny**, nie
  historię zmian, z wyjątkiem sekcji "Historia sesji";
- dopisz krótki wpis w "Historia sesji" (data, co zrobione, co
  naprawione i dlaczego);
- zaktualizuj "Następne kroki" i "Otwarte pytania", a odpowiedzi
  użytkownika przenieś do odpowiednich sekcji jako ustalenia;
- nowe preferencje użytkownika wpisz do sekcji 2;
- nowe pułapki środowiska albo silnika wpisz razem z objawem, bo po
  objawie następny agent je rozpozna;
- usuwaj informacje nieaktualne, zamiast je zostawiać obok nowych.

Nie wpisuj tego, co łatwo wyczytać z kodu linijka po linijce. Wpisuj
to, czego z kodu nie widać: dlaczego coś jest zrobione tak, a nie
inaczej, co już próbowano, co nie działa i co ustalono z użytkownikiem.

## Stałe zasady

- Rozmawiaj z użytkownikiem po polsku.
- To własna gra w gatunku stunt racerów, nie port ani kopia istniejącej
  gry. Nie odtwarzaj cudzych tras, nazw, aut ani wyglądu.
- Korzystaj z pakietów zainstalowanych w systemie. Nie pobieraj niczego
  bez zgody użytkownika.
- Godota z linii poleceń uruchamiaj zawsze z `--xr-mode off` i
  `</dev/null`. Szczegóły w HANDOVER.md, sekcja 3.
- Fizyka auta jest realistyczna z wyboru użytkownika. Nie dodawaj
  ukrytych ułatwień; pomoce dla gracza tylko jawne i wyłączalne.
- Po zmianach w fizyce, torze albo scenie uruchom
  `tests/drive_test.gd` (najlepiej dla każdego zawieszenia i obu skrzyń),
  a po zmianach w menu `tests/title_test.gd`. Wynik wpisz do HANDOVER.md.
