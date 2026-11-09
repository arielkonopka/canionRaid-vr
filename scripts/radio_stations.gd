extends RefCounted
class_name RadioStations

## Lista stacji radia na tablecie - dane dla RadioCatalog.
## Pliki muzyki leżą w res://audio/radio/<stacja>/ (Ogg Vorbis ~96 kb/s),
## pobiera je i konwertuje tools/fetch_radio.py (tabela źródeł tamże -
## przy zmianie listy popraw oba pliki; skrypt sprawdza zgodność).
## Dozwolone licencje: CC0, domena publiczna, CC-BY, CC-BY-SA - bez NC i ND
## (filtr w RadioCatalog.license_ok odrzuci resztę i zapisze w logu).
## Licencje sprawdzone na stronach źródłowych 2026-11-08 (wątek w chmurze,
## zgoda użytkownika na dobór muzyki).
## Po każdej zmianie listy odśwież CREDITS.md (RadioCatalog.credits_markdown).
## "credit" - opcjonalny dodatkowy tekst, o który prosi autor.

const OGA := "https://opengameart.org"
const CCM := "https://ccmixter.org/files"

const STATIONS := [
	{"id": "fala84", "name": "Fala 84", "tracks": [
		{"file": "fala84/midnight_drive.ogg", "title": "Midnight Drive",
			"artist": "congusbongus", "license": "CC0",
			"source": OGA + "/content/midnight-drive"},
		{"file": "fala84/into_the_night.ogg", "title": "Into the Night",
			"artist": "Bogart VGM", "license": "CC-BY-4.0",
			"source": OGA + "/content/synthwave-to-drive-at-oceanside",
			"credit": "https://www.facebook.com/BogartVGM/"},
		{"file": "fala84/moonlight.ogg", "title": "Moonlight",
			"artist": "Bogart VGM", "license": "CC-BY-4.0",
			"source": OGA + "/content/synthwave-to-drive-at-oceanside",
			"credit": "https://www.facebook.com/BogartVGM/"},
		{"file": "fala84/sunrise.ogg", "title": "Sunrise",
			"artist": "Bogart VGM", "license": "CC-BY-4.0",
			"source": OGA + "/content/synthwave-to-drive-at-oceanside",
			"credit": "https://www.facebook.com/BogartVGM/"},
		{"file": "fala84/the_cruise.ogg", "title": "The Cruise",
			"artist": "Bogart VGM", "license": "CC-BY-4.0",
			"source": OGA + "/content/synthwave-to-drive-at-oceanside",
			"credit": "https://www.facebook.com/BogartVGM/"},
		{"file": "fala84/synthwave_type.ogg", "title": "synthwave_type",
			"artist": "G_P", "license": "CC0",
			"source": OGA + "/content/synthwavetype"},
	]},
	{"id": "szuter", "name": "Radio Szuter", "tracks": [
		{"file": "szuter/into_the_winds.ogg", "title": "Into The Winds",
			"artist": "Human Antagonist", "license": "CC-BY-SA-4.0",
			"source": OGA + "/node/74545",
			"credit": "soundcloud.com/humanantagonist"},
		{"file": "szuter/on_the_road.ogg", "title": "On The Road",
			"artist": "Marcelo Fernández", "license": "CC-BY-4.0",
			"source": OGA + "/node/117857",
			"credit": "http://www.marcelofernandezmusic.com"},
		{"file": "szuter/techno_drive.ogg", "title": "Techno DRIVE!!! (v2.5)",
			"artist": "Centurion_of_war", "license": "CC-BY-4.0",
			"source": OGA + "/content/techno-drive"},
		{"file": "szuter/jump_higher_run_faster.ogg", "title": "Jump Higher Run Faster",
			"artist": "bart", "license": "CC-BY-3.0",
			"source": OGA + "/node/3942",
			"credit": "http://opengameart.org"},
		{"file": "szuter/alt_rock_song.ogg", "title": "Alt Rock Song",
			"artist": "Joe Reynolds - Professorlamp", "license": "CC-BY-3.0",
			"source": OGA + "/node/18237",
			"credit": "jrtheories.webs.com"},
	]},
	{"id": "nocna", "name": "Nocna Zmiana", "tracks": [
		{"file": "nocna/calm_track.ogg", "title": "Calm Track",
			"artist": "pmiller", "license": "CC0",
			"source": OGA + "/node/98635"},
		{"file": "nocna/contemplation.ogg", "title": "Contemplation",
			"artist": "Joth", "license": "CC0",
			"source": OGA + "/node/85636"},
		{"file": "nocna/calm_ambient_1.ogg", "title": "Calm Ambient 1 (Synthwave 4k)",
			"artist": "The Cynic Project", "license": "CC0",
			"source": OGA + "/node/97098",
			"credit": "cynicmusic.com / pixelsphere.org"},
		{"file": "nocna/chill_jungle_ambient.ogg", "title": "Chill Jungle Ambient",
			"artist": "Tausdei", "license": "CC-BY-3.0",
			"source": OGA + "/node/123092"},
	]},
	# Psytrance - użytkownik lubi go do auta (2026-11-09, lista zaakceptowana).
	# ccMixter: licencje z API i ze stron utworów (CC-BY 3.0), 2026-11-09.
	{"id": "psy", "name": "Psy Wąwóz", "tracks": [
		{"file": "psy/amigos.ogg", "title": "Amigos",
			"artist": "F_Fact", "license": "CC-BY-3.0",
			"source": CCM + "/F_Fact/52032"},
		{"file": "psy/end_of_days.ogg", "title": "End of Days",
			"artist": "F_Fact", "license": "CC-BY-3.0",
			"source": CCM + "/F_Fact/43533"},
		{"file": "psy/the_beach.ogg", "title": "The Beach (Original Mix)",
			"artist": "Astral", "license": "CC-BY-3.0",
			"source": CCM + "/Astral/50472"},
		{"file": "psy/psycho_freak.ogg", "title": "Psycho Freak (Final Edit)",
			"artist": "Psykick", "license": "CC-BY-3.0",
			"source": CCM + "/Psykick/37264"},
		{"file": "psy/trance_dance.ogg", "title": "Trance Dance",
			"artist": "Psykick", "license": "CC-BY-3.0",
			"source": CCM + "/Psykick/40201"},
		{"file": "psy/tempest.ogg", "title": "Tempest",
			"artist": "Psykick", "license": "CC-BY-3.0",
			"source": CCM + "/Psykick/53063"},
		{"file": "psy/shiva.ogg", "title": "Shiva",
			"artist": "chandubaba", "license": "CC-BY-3.0",
			"source": CCM + "/chandubaba/52311"},
		{"file": "psy/psytrance_for_a_game.ogg", "title": "psytrance for a game",
			"artist": "Kris Klavenes (klavo85)", "license": "CC-BY-4.0",
			"source": OGA + "/content/psytrance-for-a-game-by-kris-klavenes"},
	]},
]
