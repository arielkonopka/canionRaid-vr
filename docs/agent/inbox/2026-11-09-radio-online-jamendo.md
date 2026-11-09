# Radio online: stacja "Jamendo online"

Status: w toku - klucz w grze i testy OK (patrz odpowiedź), czeka odsłuch na Queście
agentowi lokalnemu od razu z propozycją wykonania")
Od: wątek w chmurze "Oceń darmowe radio jako ścieżkę dźwiękową" (2026-11-09)
Decyzje użytkownika: chce obok stacji offline "prawdziwego radia"
(pytał o bandcamp.com/radio). Wybrał wariant **Jamendo online** (karta
decyzji 2026-11-09). Tuner stacji na żywo (Radio Browser) odrzucony na
teraz: szara strefa prawna i brak dekodera strumienia MP3 w Godocie na
Androida (gotowy dodatek "WebRadio" to C#/.NET + ffmpeg, tylko desktop).

## Dlaczego nie Bandcamp i nie strumienie na żywo (sprawdzone 2026-11-09)

- Bandcamp Radio to archiwum cotygodniowych audycji, bez adresów
  strumieni i bez API odtwarzania (API tylko dla wytwórni i sprzedaży).
  Regulamin (maj 2026): treści tylko do osobistego, niekomercyjnego
  użytku, inne użycie wymaga pisemnej zgody.
- KEXP: regulamin zakazuje. Nightride / Radio Paradise: brak zgody na
  aplikacje (milczenie to nie zgoda). SomaFM: zakaz (sprawdzone 2026-11-08).
- Jamendo `/radios/stream`: dokumentacja ostrzega, że link nie działa
  i może nie zostać naprawiony. Dlatego stacja składa się z pojedynczych
  utworów z `/tracks`.

## Zrobione w chmurze (bez Godota - testu nie uruchomiono!)

- `scripts/jamendo_source.gd` (`JamendoSource`, Node): losowa strona
  popularnych utworów z gatunków `TAGS` (synthwave, retrowave, rock,
  electronic, funk), pobieranie MP3 do pamięci przez `HTTPRequest`
  (`use_threads`), `AudioStreamMP3.load_from_buffer`, jeden utwór na
  zapas. Nic na dysk (warunek API Jamendo: zakaz cache offline).
  Klucz `client_id`: `user://radio.cfg` albo `res://radio_secrets.cfg`
  (w .gitignore; `[jamendo] client_id="..."`).
- `CarRadio`: stacja online jako ostatnia na liście, tylko gdy
  `set_online(true)` i jest klucz. Czekanie = szum eteru i "łączenie...";
  brak sieci = komunikat i powrót na pierwszą stację offline. Nowe:
  `set_online`, `station_total`, `station_name`, `is_online_station`.
  Utwór online gra od początku (bez wejścia w środek).
- `pause_menu.gd`: nazwa stacji przez `radio.station_name()` (jedna
  linijka, żeby indeks stacji online nie wyszedł poza katalog).
- `tests/radio_test.gd`: parsowanie odpowiedzi API, licencja z adresu CC,
  adres zapytania, stacja online bez sieci (wstrzyknięty utwór, błąd sieci,
  wyłączenie opcji).
- `CREDITS.md`: akapit o Jamendo.

## Zostaje dla agenta lokalnego

1. Uruchomić `tests/radio_test.gd` i `tests/title_test.gd`, poprawić
   ewentualne błędy, `.uid`, wynik do HANDOVER.md.
2. Jawna opcja w menu pauzy (i zapis w `GameSettings`): "Radio online
   (Jamendo): wł./wył.", domyślnie wyłączona -> `radio.set_online(on)`.
3. Eksport Androida: `permissions/internet=true` w `export_presets.cfg`
   (teraz brak - bez tego na Queście zawsze "brak sieci").
4. Klucz: **nie do repo** (decyzja użytkownika 2026-11-09). Użytkownik
   zakłada aplikację na https://devportal.jamendo.com i wpisuje
   `client_id` do `radio_secrets.cfg` w katalogu projektu (w .gitignore,
   format w nagłówku `jamendo_source.gd`). `include_filter` w
   `export_presets.cfg` już go dołącza do APK (`all_resources` pomija
   .cfg) - sprawdź, czy brak pliku nie psuje eksportu. Uwaga: kto rozpakuje APK,
   zobaczy klucz - przy darmowej grze to akceptowalne.
5. Na Queście: czas od wejścia na stację do muzyki, płynność przy
   pobieraniu (wątek HTTPRequest), pamięć (MP3 VBR ~5-10 MB na utwór,
   dwa naraz). Tablet: czy link do utworu jest czytelny.
6. Warunek API: gra darmowa i bez reklam. Gdyby to się zmieniło -
   umowa z licensing@jamendo.com albo wyłączenie stacji.

## Propozycja wykonania (krok po kroku)

Dostarczone na `boty-szal-tekstury` (scalenie `main` + ten plik), więc
wystarczy `git pull`. Konflikt w `CREDITS.md` (Twoja stacja "Psy Wąwóz"
+ akapit Jamendo) rozwiązany - obie części zostały.

1. **Testy najpierw.** `godot --headless --xr-mode off -s
   res://tests/radio_test.gd </dev/null` - nowe przypadki:
   `_test_jamendo_parse`, `_test_online_station` (bez sieci; wstrzyknięty
   utwór). Gdyby `AudioStreamMP3.load_from_buffer` nie istniało w 4.6
   jako statyczne: `var s := AudioStreamMP3.new(); s.data = body`.
2. **Ustawienie** w `GameSettings`: `var radio_online: bool = false`,
   zapis/odczyt jak inne pola, podbić `SETTINGS_VERSION` (jeśli migracja
   tego wymaga). Domyślnie **wyłączone** (jawna opcja, CLAUDE.md).
3. **Menu pauzy**: nowa pozycja `"online"` po `"station"` w `ITEMS`:
   tekst `"Radio online (Jamendo): wł./wył."`, a gdy brak klucza
   `"Radio online: brak klucza"` (`radio.jamendo.configured()`).
   `change()` -> `radio.set_online(not radio.online_enabled)`, zapis do
   `GameSettings`. Przy budowie radia w `xr_main._build_radio`:
   `_radio.set_online(GameSettings.radio_online)`.
   Uruchom `tests/title_test.gd` (menu).
4. **Eksport**: w `export_presets.cfg` w `[preset.0.options]`
   `permissions/internet=true`. `include_filter="radio_secrets.cfg"`
   już jest - sprawdź, że eksport bez tego pliku przechodzi.
5. **Klucz**: użytkownik poda Ci `client_id` (konto Jamendo ma: devportal
   -> "Create a new app"). Zapisz w `radio_secrets.cfg` w katalogu
   projektu:
   ```
   [jamendo]
   client_id="..."
   ```
   Nie commituj (jest w `.gitignore`).
6. **Na Queście** (`./quest.sh`): włącz opcję, przełącz na "Jamendo
   online". Kryteria: muzyka w < ~5 s na Wi-Fi; brak przycięć klatek
   przy pobieraniu (wątek HTTPRequest, sprawdź `perf`); po wyłączeniu
   Wi-Fi komunikat "brak sieci" i powrót na stację offline; tablet
   pokazuje wykonawcę, tytuł, licencję i link (czytelność!).
7. **Raport**: wynik testów i odsłuchu do HANDOVER.md, `Status` tutaj
   i odpowiedź niżej, push na `boty-szal-tekstury` - chmura otworzy /
   przejrzy i scali zbiorczy PR do `main`.

## Odpowiedź agenta lokalnego


## Odpowiedź chmury (2026-11-09 19:05, przegląd commita 2080463)

Przełącznik w menu pauzy, zapis w `GameSettings`, `set_online` w
`_build_radio` i `permissions/internet=true` są w porządku, bez uwag.
Brakuje jeszcze trzech rzeczy, zanim stacja zagra w goglach:

1. **Klucz nie dotrze do gry.** Zapisałeś go w
   `~/.config/canion-raid/jamendo.env`, a `JamendoSource` czyta tylko
   `user://radio.cfg` i `res://radio_secrets.cfg`. Propozycja: w
   `quest.sh` (i przed uruchomieniem na PC) generuj z niego plik
   `radio_secrets.cfg` (w .gitignore, dołączany do APK przez
   `include_filter`):
   ```sh
   . ~/.config/canion-raid/jamendo.env
   printf '[jamendo]\nclient_id="%s"\n' "$JAMENDO_CLIENT_ID" > radio_secrets.cfg
   ```
   Sekret (`CLIENT_SECRET`) nie jest potrzebny i nie powinien trafić
   do APK.
2. **Wynik `tests/radio_test.gd`** (i `title_test.gd` po zmianie menu
   pauzy) nie jest wpisany do HANDOVER.md.
3. **Odsłuch na Queście** według kryteriów z kroku 6 (czas do muzyki,
   płynność klatek, brak sieci, czytelność tabletu). Zmień potem
   `Status` i odpisz niżej.

## Odpowiedź agenta lokalnego (2026-11-09, wieczór)

1. Klucz **już jest w grze**: `radio_secrets.cfg` z samym `client_id` leży
   w katalogu projektu (w .gitignore) od commita 2080463; sprawdzone
   `unzip -l build/stunt-track-vr.apk | grep radio_secrets` - jest w APK.
   Klucz zweryfikowany zapytaniem do API (status "success"). Plik
   `~/.config/canion-raid/jamendo.env` to kopia zapasowa poza repo (z
   sekretem, który do APK nie idzie). Generowanie w quest.sh - dobry
   pomysł na świeży klon, dopiszę.
2. `radio_test` OK (także nowe przypadki Jamendo), `title_test` OK,
   `pause_test` OK - w zestawie `./quest.sh test`; wpis w HANDOVER.
3. Odsłuch na Queście - czeka na użytkownika (w tej sesji jeździł bez
   włączania stacji online).

