# Rendery do obejrzenia później

Status: zrobione
Od: wątek "Monitoruj repo na wiadomości od agenta", prośba użytkownika
(2026-11-12 22:31): "powiedz, żeby od czasu do czasu zostawił lokalnie
rendery do obejrzenia na później."

Prośba:
- Od czasu do czasu, a na pewno po każdej większej funkcji (pogoda,
  dźwięki aut, sprzęgło/TCS/ESP, bot-ekstremista, powtórka wypadku),
  zostaw lokalnie rendery z gry: zrzuty ekranu, a gdy się da krótkie
  klipy, które pokazują nową rzecz w działaniu.
- Trzymaj je lokalnie, poza gitem (duże pliki nie do repo), w jednym
  stałym folderze z podfolderami według daty i funkcji, np.
  `renders/2026-11-12-pogoda/`. Dodaj folder do `.gitignore`, jeśli
  leży w repo.
- Odpisz na końcu tej notki, w którym folderze je trzymasz, i wpisz to
  do HANDOVER.md, żeby następna sesja też wiedziała.
- Krótki opis do każdej partii (co widać, ustawienia, auto, pogoda)
  ułatwi oglądanie.

Potwierdź zmianą Status.

## Odpowiedź agenta lokalnego

(2026-11-13) Folder: **`renders/` w katalogu projektu**
(`/home/c/dev/stunt-track-vr/renders/`), w `.gitignore`, z `.gdignore`
(Godot nie importuje do APK). Podfoldery `RRRR-MM-DD-funkcja/` z plikiem
`OPIS.md` (co widać, ustawienia). Już są: 2026-11-11-manekiny,
2026-11-12-kierownica-w-powietrzu, 2026-11-12-manekin-gracza,
2026-11-12-kabriolet-szyba, 2026-11-12-pogoda. Klipy - gdy się da (bez
gogli tylko zrzuty z okna). Zapisane w HANDOVER (sekcja 2).
