extends RefCounted
class_name RadioStations

## Lista stacji radia na tablecie - dane dla RadioCatalog.
## Pliki muzyki leżą w res://audio/radio/<stacja>/ (Ogg Vorbis ~96 kb/s).
## Dozwolone licencje: CC0, domena publiczna, CC-BY, CC-BY-SA - bez NC i ND
## (filtr w RadioCatalog.license_ok odrzuci resztę i zapisze w logu).
## Utwory wybiera użytkownik; nic nie pobieramy bez jego zgody (CLAUDE.md).
## Po każdej zmianie listy odśwież CREDITS.md (RadioCatalog.credits_markdown).
##
## Przykład wpisu:
##   {"id": "fala", "name": "Fala 84", "tracks": [
##       {"file": "fala/nocny_przejazd.ogg", "title": "Nocny przejazd",
##        "artist": "Ktoś", "license": "CC-BY-4.0",
##        "source": "https://freemusicarchive.org/..."},
##   ]},

const STATIONS := [
]
