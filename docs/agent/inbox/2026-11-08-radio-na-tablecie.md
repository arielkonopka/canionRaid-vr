# Radio na tablecie: ścieżka dźwiękowa bez zmartwień

Status: nowe
Od: wątek w chmurze "Oceń darmowe radio jako ścieżkę dźwiękową", na prośbę
użytkownika (2026-11-08, "dodaj do kolejki prac")
Decyzje użytkownika: chce darmowej muzyki w radiu auta (tablet na desce,
patrz HANDOVER "Na tablecie: radio"), o którą nie musi się troszczyć.
Zlecił dodanie do kolejki wariantu rekomendowanego poniżej.
Otwarte: czy gra zostanie darmowa (od tego zależy stacja Jamendo, krok 5);
wybór konkretnych utworów.

## Ustalenia z oceny (sprawdzone 2026-11-08)

- **Jamendo API** - darmowe tylko niekomercyjnie (reklamy i programy
  partnerskie też są "komercyjne"), pkt 3.3
  https://devportal.jamendo.com/api_terms_of_use . Wymaga podpisu artysty
  i Jamendo oraz linku do strony każdego utworu (pkt 4.1). Zakaz
  przechowywania utworów do grania offline. Każdy utwór ma własną licencję
  CC (często NC/ND). Komercyjnie: umowa z licensing@jamendo.com i licencja
  od ok. 89 EUR/utwór. `client_id` w publicznym repo GPL będzie jawny.
- **Bandcamp** - brak publicznego API do odtwarzania. Odpada.
- **SomaFM** - regulamin (wrzesień 2026) zakazuje użycia strumieni
  w aplikacjach i grach. Odpada.
- **Muzyka dołączona do gry** - wybrane utwory CC0 / CC-BY / CC-BY-SA
  (Free Music Archive, ccMixter, Internet Archive, OpenGameArt). Działa
  offline, bezpieczne w sklepie Meta, zgodne z GPL jako osobne zasoby.
  **Bez NC i ND** (NC kłóci się z GPL i ewentualną sprzedażą; ND
  utrudnia obróbkę dźwięku). Utwory wybiera użytkownik albo agent
  z listą do akceptacji - nie pobieraj niczego bez zgody użytkownika
  (CLAUDE.md).

## Pierwsza wersja (do zrobienia)

1. **Stacje**: 2-3 stacje (np. synthwave, rock, nocna) po 5-8 utworów,
   Ogg Vorbis ~96 kb/s, razem ~40-60 MB. Katalog np. `audio/radio/<stacja>/`
   + plik opisu stacji (tytuł, wykonawca, licencja, URL źródła).
2. **Sterowanie**: przełączanie stacji przyciskiem (kierownica/kontroler),
   głośność, wyłączenie. Między utworami / przy zmianie stacji krótki szum
   eteru (generowany, jak deszcz w `xr_main.gd`).
3. **Brzmienie**: osobna szyna "Radio" z korektorem w stylu głośników
   samochodowych (obcięty dół i góra) i lekkim pogłosem kabiny. **Nie**
   przez szynę "Env" (`EnvAudio`), żeby tunel i wąwóz nie dodawały echa
   do muzyki. Radio ma nie zagłuszać silnika i klaksonów botów
   (proponowane ~-14 dB poniżej silnika na gazie, do odsłuchu).
4. **Atrybucja**: na tablecie tytuł, wykonawca i licencja obecnego utworu;
   `CREDITS.md` w repo z pełną listą (wymóg CC-BY).
5. **Później, tylko jeśli gra zostaje darmowa i bez reklam**: stacja
   "Jamendo online", domyślnie wyłączona. Pobieranie całego utworu przez
   `HTTPRequest` i odtwarzanie z pamięci przez
   `AudioStreamOggVorbis.load_from_buffer` / `AudioStreamMP3.load_from_buffer`
   (Godot 4.3+), bez zapisu na dysk. Podpis + link przy każdym utworze,
   filtr licencji w zapytaniu API. Wymaga uprawnienia INTERNET w eksporcie
   Androida i wzmianki o sieci w polityce prywatności. Brak sieci = cicha
   zmiana na stację lokalną.

## Do sprawdzenia na Queście

- Koszt dekodowania Ogg przy pełnej fizyce (oczekiwany drobny).
- Rozmiar APK po dodaniu muzyki.

Opcja na przyszłość (niezlecona): radio generowane proceduralnie
(syntezator synthwave na `AudioStreamGenerator`, jak silnik), reagujące
na prędkość lub szał botów. Zero licencji, więcej pracy.

## Odpowiedź agenta lokalnego

