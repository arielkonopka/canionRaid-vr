# Komunikacja przez repo (propozycja)

Nad grą pracują dwa rodzaje agentów:

- **agent lokalny** - na komputerze użytkownika, pisze kod, buduje na Questa,
  prowadzi `HANDOVER.md`;
- **wątki projektu w chmurze** (claude.ai) - rozmowy projektowe
  z użytkownikiem, bez dostępu do gogli i do lokalnego builda.

Ten katalog to wspólna skrzynka. **To jest propozycja - agent lokalny
ma ją przejrzeć i ustalić z użytkownikiem ostateczny sposób** (patrz
`inbox/2026-11-08-zaproszenie-komunikacja.md`).

## Proponowane zasady

- `docs/agent/inbox/` - zlecenia i specyfikacje dla agenta lokalnego.
  Nazwa: `RRRR-MM-DD-krotki-temat.md`. Na górze pliku blok statusu:

  ```
  Status: nowe | przyjęte | w toku | zrobione | odrzucone
  Od: wątek w chmurze "<tytuł>" / użytkownik
  Decyzje użytkownika: <co ustalone, co otwarte>
  ```

- Agent lokalny po przeczytaniu zmienia `Status`, a uwagi i pytania
  dopisuje na końcu pliku w sekcji `## Odpowiedź agenta lokalnego`.
  Wynik pracy (stan, testy) trafia jak zwykle do `HANDOVER.md`;
  w pliku zlecenia wystarczy odnośnik.
- `docs/agent/outbox/` (do założenia, jeśli się przyda) - pytania
  i raporty od agenta lokalnego dla wątków w chmurze, np. wyniki
  pomiarów z Questa, których chmura nie zrobi.
- Wątki w chmurze mogą pisać kod (zgoda użytkownika 2026-11-08), ale
  najlepiej w **nowych, odizolowanych plikach** (czysta logika + testy
  headless); wpinanie w gorące pliki (`xr_main.gd`, `bot_driver.gd`,
  `stunt_track.gd`, menu) i `HANDOVER.md` zostają po stronie agenta
  lokalnego. Zmiany na osobnej gałęzi z PR-em. Wątki w chmurze mogą też
  przeglądać i scalać PR-y (zgoda użytkownika 2026-11-08). W chmurze nie
  ma Godota ani gogli - testy uruchamia agent lokalny.
- Specyfikacja to propozycja projektowa, nie rozkaz: decyzje należą do
  użytkownika, a agent lokalny może się nie zgodzić z uzasadnieniem
  (np. wydajność na Queście, fizyka).
