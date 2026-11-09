# Radio na tablecie: ścieżka dźwiękowa bez zmartwień

Status: zrobione (do odsłuchu w goglach)
Od: wątek w chmurze "Oceń darmowe radio jako ścieżkę dźwiękową", na prośbę
użytkownika (2026-11-08, "dodaj do kolejki prac")
Decyzje użytkownika: chce darmowej muzyki w radiu auta (tablet na desce,
patrz HANDOVER "Na tablecie: radio"), o którą nie musi się troszczyć.
Zlecił dodanie do kolejki wariantu rekomendowanego poniżej.
Użytkownik (2026-11-08): "to co możesz weź na siebie, żeby odciążyć
agenta" - część bez Godota zrobiła chmura (sekcja niżej).
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

## Zrobione w chmurze (bez Godota - testu nie uruchomiono!)

- `scripts/radio_catalog.gd` (`RadioCatalog`) - czysta logika: filtr
  licencji (CC0/PD/CC-BY/CC-BY-SA, bez NC/ND), odrzucanie złych wpisów
  z opisem w `errors`, zawijanie stacji, tasowanie bez powtórki pod rząd,
  losowe wejście w środek utworu, napis na tablet, sekcja do CREDITS.md.
- `scripts/radio_stations.gd` (`RadioStations.STATIONS`) - lista stacji,
  na razie pusta. GDScript zamiast JSON, bo `export_filter="all_resources"`
  nie wrzuca .json do APK.
- `scripts/car_radio.gd` (`CarRadio`, Node) - szyna "Radio" (górno-
  i dolnoprzepustowy 140 Hz / 8 kHz, mały pogłos kabiny, wysyłka na
  Master), szum eteru generowany w kodzie, `toggle()`, `next_station(dir)`,
  `skip()`, `set_volume_db()`, sygnał `now_playing(text)`. Bez stacji lub
  plików nie sypie się, tylko podaje komunikat.
  `AudioStreamPlayer` (nie 3D) - do decyzji, czy dźwięk ma iść z tabletu.
- `tests/radio_test.gd` - test headless tych modułów.
- `audio/radio/README.md` - gdzie kłaść pliki.
- `scripts/radio_stations.gd` - 3 stacje: Fala 84 (synthwave), Radio
  Szuter (rock/drive), Nocna Zmiana (spokojne); `CREDITS.md`;
  `tools/fetch_radio.py` (pobieranie + konwersja, `--check` zgodności).

## Zostaje dla agenta lokalnego

1. Uruchomić `tests/radio_test.gd` (chmura nie ma Godota), poprawić
   ewentualne błędy składni, dodać pliki `.uid`, wynik do HANDOVER.md.
2. Wpiąć `CarRadio` w scenę jazdy (`xr_main.gd`): przycisk na
   kontrolerze/kierownicy, napis `now_playing` na tablecie.
3. Odsłuch na Queście: głośność `VOLUME_DB` względem silnika, brzmienie
   szyny, ewentualnie `AudioStreamPlayer3D` przy tablecie.
4. Muzyka: lista 15 utworów na 3 stacje jest już w `radio_stations.gd`
   i `CREDITS.md` (licencje sprawdzone na stronach 2026-11-08; użytkownik
   dał "zielone światło" na dobór i pobranie). Chmura nie ma dostępu do
   opengameart.org, więc pobranie po Twojej stronie:
   `python3 tools/fetch_radio.py` (ffmpeg -> Ogg 96 kb/s, wyrównana
   głośność). Ok. 30-50 MB. Do decyzji z użytkownikiem: commit plików do
   repo (licencje na to pozwalają) czy `.gitignore` jak `textures/`.
   Jeśli wzorzec pliku na stronie nie pasuje, popraw tabelę w skrypcie.
   Opcjonalnie do ręcznego pobrania z itch.io (CC-BY 4.0, zip):
   "Neon Night" (Fatal Exit, amadan-interactive.itch.io) i
   "Racing Music Pack" (Monsieur Fred, monsieur-fred.itch.io).

## Do sprawdzenia na Queście

- Koszt dekodowania Ogg przy pełnej fizyce (oczekiwany drobny).
- Rozmiar APK po dodaniu muzyki.

Opcja na przyszłość (niezlecona): radio generowane proceduralnie
(syntezator synthwave na `AudioStreamGenerator`, jak silnik), reagujące
na prędkość lub szał botów. Zero licencji, więcej pracy.

## Odpowiedź agenta lokalnego


2026-11-09 - zrobione:
1. `radio_test` się wywracał: `set_power` przed `_ready` trafiał na pusty
   `_player`. `CarRadio._setup()` tworzy teraz odtwarzacze przy pierwszym
   użyciu, a `_static.play()` jest wołane tylko w drzewie sceny. Test
   przechodzi i jest w `./quest.sh test`.
2. Radio jest wpięte w scenę jazdy przez **menu pauzy**: użytkownik
   wybrał, żeby nie zmieniać żadnego przycisku w jeździe. Menu zawiera:
   radio wł./wył., stację i głośność (9 stopni). "Co gra" jest na
   napisie nad radiem na desce sedana. Szczegóły w `HANDOVER.md`.
3. Odsłuch na Queście jeszcze przed nami.
4. Muzyka: wszystkie 15 utworów pobrane. Wzorce w `fetch_radio.py`
   poprawione: OpenGameArt dopisuje do nazw numer wersji, np.
   `into_the_night_0.mp3`. Licencje zgadzają się ze stronami. Pliki są
   **w repo** (decyzja użytkownika), razem 24 MB.
