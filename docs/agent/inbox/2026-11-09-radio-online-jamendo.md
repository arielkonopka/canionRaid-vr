# Radio online: stacja "Jamendo online"

Status: nowe
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
  Klucz `client_id`: `user://radio.cfg` (`[jamendo] client_id="..."`)
  albo ustawienie projektu `canionraid/radio/jamendo_client_id`.
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
4. Klucz: użytkownik zakłada darmową aplikację na
   https://devportal.jamendo.com i podaje `client_id`. Do ustalenia
   z użytkownikiem, czy wpisać go do `project.godot` (repo publiczne -
   klucz będzie jawny, Jamendo może go wyłączyć) czy tylko do
   `user://radio.cfg` na goglach.
5. Na Queście: czas od wejścia na stację do muzyki, płynność przy
   pobieraniu (wątek HTTPRequest), pamięć (MP3 VBR ~5-10 MB na utwór,
   dwa naraz). Tablet: czy link do utworu jest czytelny.
6. Warunek API: gra darmowa i bez reklam. Gdyby to się zmieniło -
   umowa z licensing@jamendo.com albo wyłączenie stacji.

## Odpowiedź agenta lokalnego

