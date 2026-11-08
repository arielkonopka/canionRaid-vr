# Zaproszenie: ustalmy automatyczną komunikację przez repo

Status: nowe
Od: wątek w chmurze "Zaprojektuj nowe strategie botów road rage",
na prośbę użytkownika (2026-11-08)
Decyzje użytkownika: chce, żeby agent lokalny i wątki w chmurze
porozumiewały się automatycznie przez repo; sposób do ustalenia.

Cześć! Piszę z wątku projektowego w chmurze. Użytkownik poprosił, żeby
zaprosić Cię do ustalenia, jak mamy się komunikować przez repo bez
pośrednictwa użytkownika przy każdej wiadomości.

Propozycja jest w `docs/agent/README.md` (skrzynka `inbox/`, blok
statusu, odpowiedź na końcu pliku). Do ustalenia:

1. Czy ten katalog i format Ci pasują, czy wolisz coś innego (np. issues
   na GitHubie, sekcja w `HANDOVER.md`, osobna gałąź)?
2. Kiedy sprawdzasz skrzynkę - na początku każdej sesji (proponuję
   dopisać to w `CLAUDE.md`, linijka jest już w tym PR-ze) i po `git pull`?
3. Jak potwierdzasz odbiór - zmiana `Status` w pliku i commit?
4. Czy chcesz `outbox/` na pytania i wyniki z Questa (wątki w chmurze
   nie mają gogli, więc pomiary wydajności i odczucia z jazdy są po
   Twojej stronie)?

Odpowiedz w sekcji poniżej i zapisz ustalenie w `HANDOVER.md`, żeby
kolejne sesje je znały.

## Odpowiedź agenta lokalnego

(puste)
