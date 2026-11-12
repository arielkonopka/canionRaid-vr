extends Node

## Ustawienia wybierane na ekranie tytułowym. Autoload "GameSettings".
## Zapisywane w user://settings.cfg, więc przy następnym uruchomieniu
## gracz zastaje swój ostatni wybór.
##
## Nowa opcja = nowa zmienna + wpis w OPTIONS (z "group" z GROUPS) + jej
## użycie (apply_to_car() albo scena jazdy). Ekran tytułowy buduje menu sam.

const PATH := "user://settings.cfg"
## Wersja formatu ustawień. 2: "endless" przestało znaczyć "domyślna trasa
## bez końca" (teraz to estakady; domyślny jest wąwóz) - stare zapisy
## przestawiamy na wąwóz, reszta ustawień zostaje.
const SETTINGS_VERSION := 10

const TRANSMISSIONS := {
	"auto": "Automat",
	"manual": "Manual",
}

var transmission: String = "auto"
var suspension: String = "sport"
var abs_enabled: bool = true
var tcs_enabled: bool = true
var esp_enabled: bool = true
## Ograniczenie skrętu z prędkością (StuntCar.steer_assist) - jawna pomoc.
var steer_assist: Variant = true   # true / false / "grip" (wg przyczepności)
var engine_type: String = "petrol"
var engine_power: int = 180          # kW
## Układ napędu: "rwd" tył, "fwd" przód, "awd" 4x4 (StuntCar.drive_layout).
var drive_layout: String = "rwd"
## Model auta gracza: "concept" (Khronos Car Concept, CC BY 4.0) albo
## "sedan" (własny z lat 70., z wgnieceniami). Boty zawsze sedany.
var body_model: String = "sedan"
## Masa nadwozia [kg] (bez napędu: diesel +50, elektryk +200).
var body_mass: int = 0              # 0 = fabryczna masa modelu
## Spojler: "none", "small", "large" (StuntCar.SPOILERS).
var spoiler: String = "none"
## Wytrzymałość auta: 1 = zgodna z fizyką, wyżej mnożnik (jawna pomoc,
## użytkownik 2026-11-09) - StuntCar.durability.
var durability: int = 1
## Tempo gry [%] (użytkownik 2026-11-10: "czas gry powinien płynąć nieco
## szybciej" -> "cała gra szybciej"): Engine.time_scale w scenie jazdy.
## Fizyka ta sama, cały świat biegnie szybciej - jawna opcja, 100% = realnie.
var game_speed: int = 110
## Rekuperacja elektryka (StuntCar.REGEN_LEVELS): "off", "weak", "normal", "strong".
var regen: String = "normal"
## Opływowość nadwozia (StuntCar.AERO): "classic", "modern", "sport", "record".
var aero: String = "classic"
## Szał drogowy botów: o ile km/h przekraczają ograniczenie (0 = bez
## limitu), najkrótszy szał [s], ile sekund przepisowej jazdy gracza go
## gasi, strategia: "block" (wyprzedza, zajeżdża, hamuje przed graczem),
## "ram" (dojeżdża od tyłu i stuka), "mixed" (na zmianę).
var rage_overspeed: int = 50
var rage_time: int = 10
var rage_calm: int = 6
var rage_strategy: String = "mixed"
## Posiłki: szał jednego bota zaraża boty w promieniu 400 m.
var rage_reinforce: bool = true
## Szansa [%], że wyprzedzony (nie potrącony) bot wpadnie w furię.
var rage_overtake: int = 25
## Opony: "all_season" całoroczne (domyślnie), "summer" letnie, "winter"
## zimowe (StuntCar.TIRE_COMPOUNDS).
var tires: String = "all_season"
## Elektryk: "central" jeden silnik, "hub" silnik w każdym kole (zawsze 4x4).
var motor_layout: String = "central"
var paint: String = "harvest_gold"
## Układ sterowania w goglach: na którym spuście gaz (hamulec na drugim),
## którym drążkiem kierownica, pod którym gripem ręczny.
var gas_hand: String = "right"
## Drążek kierownicy; drugi drążek (góra/dół) zmienia biegi.
var steer_stick: String = "right"
## Wykładnik krzywej drążka kierownicy: 1 = liniowo, większy = łagodniej w środku.
var stick_expo: float = 1.6
## Czułość drążka kierownicy w procentach (gogle i pad; klawiatura bez zmian).
var stick_sensitivity: int = 100
## Przezroczystość kabiny i maski w widoku z kokpitu, w procentach.
var cockpit_alpha: int = 60
## Rozdzielczość obrazu w goglach [% zalecanej przez gogle]. Quest 3 ma
## ekrany ostrzejsze niż zalecany obraz (użytkownik: "gogle mogą wyciągnąć
## wyższą rozdzielczość"); koszt rośnie z kwadratem.
var xr_resolution: int = 110
## Foweacja: 0 wył., 1 słaba, 2 średnia, 3 mocna (zawsze dynamiczna -
## mocniej tylko, gdy gogle nie nadążają).
var xr_foveation: int = 2
var wheel_range: int = 180          # [°] obrót kierownicy w powietrzu na pełny skręt
var weather: String = "variable"    # pogoda na autostradzie (WeatherPlan) / "dry"
var vibration: float = 0.5          # siła wibracji kontrolerów (0 = wył.)
var road_texture: bool = false      # lekka faktura drogi w drążkach
var shadows: String = "full"
## Rodzaj trasy (menu "Trasa"): "canyon" wąwóz bez końca albo "autostrada"
## (tryb Autostrada, użytkownik 2026-11-09, docs/AUTOSTRADA.md). "endless"
## (estakady) i "demo" (pokazowa z metą) zostały w kodzie dla testów
## (endless_test, drive_test) - nie ma ich w menu.
var track_mode: String = "autostrada"
## Dźwigi (życia) na trasie bez końca; 0 = bez limitu.
var cranes: int = 3
## Progi mocy silnika na trasie bez końca: start na pierwszym, każdy
## warsztat (co 10 odcinków) pozwala przejść na następny.
const POWER_TIERS := [90, 130, 180, 250, 350, 500, 700, 1000]
## Najwyższy próg tylko dla elektryka z silnikiem w każdym kole (4 × 250 kW,
## użytkownik: "wariant 1"). Inne napędy dostają w jego miejsce 700 kW.
const HUB_ONLY_KW := 1000
const MAX_KW_OTHERS := 700
## Rekord trasy pokazowej [s], 0 = brak. Zapisywany razem z ustawieniami.
var best_time: float = 0.0
## Rekord trasy bez końca [m].
var best_distance: float = 0.0
## false = nic nie jest zapisywane na dysk. Ustawiają to testy, żeby nie
## nadpisywać ustawień i rekordów gracza.
var persist := true
## Radio (grupa "Radio" - w menu tytułowym i w pauzie, użytkownik
## 2026-11-09: "ustawienia radia w ustawieniach gry"): włączone przy
## starcie jazdy, stacja (indeks w RadioStations.STATIONS - nazwy
## uzupełnia _ready), głośność (indeks PauseMenu.VOLUME_STEPS), stacja
## online Jamendo (jawna opcja, domyślnie wył.).
var radio_on := false
var radio_station := 0
## Wartość radio_station dla stacji online (Jamendo).
const STATION_ONLINE := -1
var radio_volume := 5
var radio_online := false

## Grupy menu (podmenu na ekranie tytułowym), w kolejności wyświetlania.
const GROUPS: Array[Dictionary] = [
	{"id": "track", "label": "Trasa"},
	{"id": "car", "label": "Samochód"},
	{"id": "body", "label": "Nadwozie i opony"},
	{"id": "assist", "label": "Systemy wspomagania"},
	{"id": "controls", "label": "Sterowanie"},
	{"id": "look", "label": "Wygląd i widok"},
	{"id": "radio", "label": "Radio"},
	{"id": "rage", "label": "Szał drogowy botów"},
]

## Lakiery w duchu lat 70.
const PAINTS := {
	"harvest_gold": Color(0.80, 0.60, 0.18),
	"avocado": Color(0.42, 0.47, 0.18),
	"burnt_orange": Color(0.78, 0.33, 0.10),
	"sky_blue": Color(0.45, 0.66, 0.82),
	"chocolate": Color(0.30, 0.18, 0.10),
	"cream": Color(0.92, 0.88, 0.76),
	"red": Color(0.70, 0.08, 0.06),
	"black": Color(0.04, 0.04, 0.045),
}

## Opis opcji dla menu. "values" to lista możliwych wartości w kolejności
## przełączania, "names" ich nazwy na ekranie, "hints" opis pod opcją.
var OPTIONS: Array[Dictionary] = [
	{
		"key": "track_mode", "group": "track", "label": "Trasa",
		"values": ["autostrada", "canyon"],
		"names": ["Autostrada", "Wąwóz"],
		"hints": [
			"Autostrada 2+2 pasy przez setki km: łąki, pola, pustynia, góry, morze, miasta co 25 km.",
			"Wąwóz bez końca: skocznie, tunele, rozwidlenia, autostrada co kilka odcinków.",
		],
	},
	{
		"key": "weather", "group": "track", "label": "Pogoda",
		"values": ["variable", "dry"],
		"names": ["Zmienna", "Zawsze sucho"],
		"hints": [
			"Fronty deszczu, ciemne niebo przed ulewą, mokra jezdnia (autostrada).",
			"Bez deszczu i mokrej jezdni - jak dotąd.",
		],
	},
	{
		"key": "game_speed", "group": "track", "label": "Tempo gry", "live": true,
		"values": [100, 110, 120, 130],
		"names": ["100% (realne)", "110%", "120%", "130%"],
		"hints": [
			"Czas płynie jak naprawdę.",
			"Domyślnie: cały świat o 10% szybciej - fizyka ta sama, wszystko dzieje się żwawiej.",
			"Wszystko o 20% szybciej - auto, boty, ruch, skoki.",
			"Wszystko o 30% szybciej - jak w filmie puszczonym szybciej.",
		],
	},
	{
		"key": "cranes", "group": "track", "label": "Życia (auta)",
		"values": [3, 5, 0],
		"names": ["3", "5", "bez limitu"],
		"hints": [
			"Auto na dachu, rozbite albo spadnięte wybucha - kolejne auto stoi na miejscu wypadku.",
			"Więcej szans.",
			"Trening: aut nigdy nie zabraknie.",
		],
	},
	{
		"key": "engine_type", "group": "car", "label": "Napęd",
		"values": ["petrol", "diesel", "electric"],
		"names": ["Benzyna", "Diesel", "Elektryk"],
		"hints": [
			"Moment rośnie z obrotami, pełna moc dopiero wysoko - kręć silnik.",
			"Dużo momentu nisko, szybko kończą się obroty, mocno hamuje silnikiem.",
			"Pełny moment od zera, jeden bieg, puszczony gaz odzyskuje energię.",
		],
	},
	{
		"key": "engine_power", "group": "car", "label": "Moc maksymalna",
		"values": [90, 130, 180, 250, 350, 500, 700, 1000],
		"names": ["90 kW (122 KM)", "130 kW (177 KM)", "180 kW (245 KM)",
				"250 kW (340 KM)", "350 kW (476 KM)", "500 kW (680 KM)",
				"700 kW (952 KM)", "1000 kW (1360 KM)"],
		"hints": [
			"Spokojne auto - łatwo utrzymać przyczepność.",
			"Żwawe, wybacza błędy.",
			"Sportowe - na mokrym trzeba uważać z gazem.",
			"Bardzo mocne - bez kontroli trakcji tył ucieka łatwo.",
			"Potwór - pełny gaz na niskim biegu to poślizg nawet na suchym.",
			"Hipersamochód w sedanie z lat 70. Bez 4x4 tylko kontrola trakcji ratuje.",
			"Nierealne. Dłuższe przełożenia, ponad 350 km/h, 4x4 prawie konieczne.",
			"Tylko elektryk z silnikiem w każdym kole: 4 × 250 kW. Inny napęd dostanie 700 kW.",
		],
	},
	{
		"key": "body_model", "group": "body", "label": "Model auta",
		"values": ["sedan", "concept", "kombi", "hatchback", "klin", "kabriolet", "muscle", "terenowka", "furgon"],
		"names": ["Sedan z lat 70.", "Concept", "Kombi", "Hatchback z lat 80.", "Klin z lat 80.",
				"Kabriolet", "Muscle z lat 70.", "Terenówka", "Furgon"],
		"hints": [
			"Własny sedan z epoki: winylowy dach, chrom, wgniecenia, spojlery.",
			"Futurystyczny concept car, fotel kierowcy na środku. Bez wgnieceń.",
			"Długie kombi: dłuższy rozstaw osi, spokojne w łukach. Kokpit z sedana.",
			"Krótki i lekki: zwrotny, ale nerwowy przy dużej prędkości. Kokpit z sedana.",
			"Niski klin: nisko środek masy, sztywno, mały opór. Kokpit z sedana.",
			"Bez dachu: nisko, ale dachowanie kończy się gorzej. Kokpit z sedana.",
			"Długi i ciężki przód: stabilny na prostej, w łukach trzeba uważać. Kokpit z sedana.",
			"Wysoki środek masy: w ostrym manewrze unosi koła. Kokpit z sedana.",
			"Wysoki i szeroki: duży opór powietrza, łatwo go przechylić. Kokpit z sedana.",
		],
	},
	{
		"key": "body_mass", "group": "body", "label": "Masa",
		"values": [0, 950, 1150, 1500, 2000, 2500],
		"names": ["Fabryczna", "950 kg", "1150 kg", "1500 kg", "2000 kg", "2500 kg"],
		"hints": [
			"Tyle, ile waży wybrany model auta (sedan 1150 kg).",
			"Lekkie jak wyczynówka: żwawe, ale łatwo traci przyczepność i fruwa na garbach.",
			"Tyle, ile sedan z epoki.",
			"Cięższe: spokojniejsze, dłużej hamuje.",
			"Jak duży SUV: stabilne, ale wolniej przyspiesza i hamuje.",
			"Czołg: bot się od ciebie odbija, ty od niego nie. Zawieszenie wzmocnione.",
		],
	},
	{
		"key": "spoiler", "group": "body", "label": "Spojler",
		"values": ["none", "small", "large"],
		"names": ["Brak", "Lotka", "Skrzydło"],
		"hints": [
			"Bez docisku - przy dużej prędkości auto lekkie w zakrętach.",
			"Mały docisk: ok. 70 kg przy 200 km/h na tylną oś, trochę więcej oporu.",
			"Duży docisk: ok. 170 kg przy 200 km/h, ok. 480 kg przy 300 km/h; większy opór.",
		],
	},
	{
		"key": "radio_on", "group": "radio", "label": "Radio przy starcie",
		"values": [false, true], "names": ["Wył.", "Wł."],
		"hints": ["Jazda w ciszy - radio włączysz w pauzie.", "Radio gra od startu jazdy."],
	},
	{
		"key": "radio_station", "group": "radio", "label": "Stacja",
		"values": [0], "names": ["-"],
		"hints": ["Stacja, od której radio zaczyna."],
	},
	{
		"key": "radio_volume", "group": "radio", "label": "Głośność",
		"values": [0, 1, 2, 3, 4, 5, 6, 7, 8], "names": ["1", "2", "3", "4", "5", "6", "7", "8", "9"],
		"hints": ["Cicho - silnik ważniejszy.", "", "", "", "", "Domyślnie: nie zagłusza silnika.", "", "", "Najgłośniej."],
	},
	{
		"key": "radio_online", "group": "radio", "label": "Radio online (Jamendo)",
		"values": [false, true], "names": ["Wył.", "Wł."],
		"hints": ["Tylko muzyka z gry (offline).",
				"Dodatkowa stacja z muzyką z Jamendo (internet, utwory w pamięci)."],
	},
	{
		"key": "aero", "group": "body", "label": "Opływowość",
		"values": ["classic", "modern", "sport", "record"],
		"names": ["Sedan z epoki", "Współczesna", "Sportowa", "Rekordowa"],
		"hints": [
			"Cd 0,36, duże czoło (pomiar: 130 kW 213 km/h, 700 kW 378 km/h).",
			"Cd 0,29 jak dzisiejsze auta: 130 kW 229 km/h, 700 kW 393 km/h.",
			"Cd 0,30, niskie i wąskie czoło: 130 kW 232 km/h.",
			"Cd 0,22, jak auta do bicia rekordów: 130 kW 264 km/h, 700 kW 398 km/h. Przy 350 kW prędkość ogranicza najwyższy bieg (~285).",
		],
	},
	{
		"key": "durability", "group": "body", "label": "Wytrzymałość",
		"values": [1, 2, 3, 5, 10],
		"names": ["x1 (realna)", "x2", "x3", "x5", "x10"],
		"hints": [
			"Jak prawdziwe auto: uderzenie przy dużej prędkości kończy jazdę.",
			"Auto znosi dwa razy więcej, zanim silnik, hamulce i zawieszenie odmówią.",
			"Trzy razy mocniejsze - wybacza kilka poważnych stłuczek.",
			"Pięć razy mocniejsze - wgniecenia widać, ale auto jedzie dalej.",
			"Prawie niezniszczalne. Wgniecenia nadal widać.",
		],
	},
	{
		"key": "tires", "group": "body", "label": "Opony",
		"values": ["all_season", "summer", "winter"],
		"names": ["Całoroczne", "Letnie", "Zimowe"],
		"hints": [
			"Kompromis: na suchym trochę słabsze od letnich, na mokrym i lodzie lepsze.",
			"Najlepsze na suchym, na lodzie jak łyżwy.",
			"Najlepsze na lodzie, na suchym miękkie i wyraźnie słabsze.",
		],
	},
	{
		"key": "drive_layout", "group": "car", "label": "Napędzane koła",
		"values": ["rwd", "fwd", "awd"],
		"names": ["Tył", "Przód", "4x4"],
		"hints": [
			"Klasycznie, tylne koła z szperą - tył ucieka przy gazie w zakręcie.",
			"Przednie koła ciągną: stabilnie, przy gazie w zakręcie auto wynosi przodem na zewnątrz; mocne auto buksuje przy ruszaniu (ciężar przechodzi na tył).",
			"Wszystkie koła: 40% przód, 60% tył, wiskoza między osiami. Ciężej o poślizg.",
		],
	},
	{
		"key": "motor_layout", "group": "car", "label": "Silnik elektryczny",
		"values": ["central", "hub"],
		"names": ["Jeden centralny", "W każdym kole"],
		"hints": [
			"Jeden silnik, napęd przez dyferencjał (koła wg opcji Napędzane koła).",
			"Cztery silniki po 1/4 mocy, zawsze 4x4, każde koło niezależnie. Tylko elektryk.",
		],
	},
	{
		"key": "regen", "group": "car", "label": "Rekuperacja",
		"values": ["off", "weak", "normal", "strong"],
		"names": ["Wył.", "Słaba", "Normalna", "Mocna"],
		"hints": [
			"Puszczony gaz: elektryk toczy się swobodnie, bez odzysku energii.",
			"Lekkie hamowanie silnikiem, trochę energii wraca do baterii.",
			"Jak w typowym elektryku: wyraźne hamowanie i odzysk energii.",
			"Jazda jednym pedałem: mocne hamowanie po puszczeniu gazu, najwięcej odzysku.",
		],
	},
	{
		"key": "transmission", "group": "car", "label": "Skrzynia biegów",
		"values": ["auto", "manual"],
		"names": ["Automat", "Manual"],
		"hints": [
			"Automat zmienia biegi sam, hamulec na postoju = wsteczny.",
			"Biegi zmieniasz sam, ogranicznik obrotów nie wybacza.",
		],
	},
	{
		"key": "suspension", "group": "body", "label": "Zawieszenie",
		"values": ["soft", "sport", "stiff"],
		"names": ["Miękkie", "Sportowe", "Twarde"],
		"hints": [
			"Duże przechyły, łagodne lądowania, auto pływa w zakrętach.",
			"Kompromis: pewne w zakrętach, lądowania do zniesienia.",
			"Ostre w zakrętach, ale twarde lądowania podbijają auto.",
		],
	},
	{
		"key": "paint", "group": "look", "label": "Lakier",
		"values": ["harvest_gold", "avocado", "burnt_orange", "sky_blue",
				"chocolate", "cream", "red", "black"],
		"names": ["Złoty", "Awokado", "Pomarańcz", "Błękit",
				"Czekolada", "Kremowy", "Czerwony", "Czarny"],
		"hints": [
			"Złoto żniw - najbardziej lata 70. kolor, jaki istnieje.",
			"Zieleń awokado, jak lodówka u babci.",
			"Palony pomarańcz.",
			"Pastelowy błękit.",
			"Brąz z metalikiem.",
			"Kremowy, elegancko.",
			"Klasyczna czerwień.",
			"Czarny jak winylowy dach.",
		],
	},
	{
		"key": "abs_enabled", "group": "assist", "label": "ABS",
		"values": [true, false], "names": ["Wł.", "Wył."],
		"hints": [
			"Koła nie blokują się przy hamowaniu, auto da się skręcać.",
			"Mocne hamowanie blokuje koła - auto jedzie prosto jak sanki.",
		],
	},
	{
		"key": "tcs_enabled", "group": "assist", "label": "Kontrola trakcji",
		"values": [true, false], "names": ["Wł.", "Wył."],
		"hints": [
			"Odcina moc, gdy tylne koła buksują.",
			"Pełna moc zawsze - gaz w zakręcie może obrócić auto.",
		],
	},
	{
		"key": "esp_enabled", "group": "assist", "label": "ESP",
		"values": [true, false], "names": ["Wł.", "Wył."],
		"hints": [
			"Przyhamowuje pojedyncze koła, gdy auto zaczyna się obracać.",
			"Poślizg łapiesz sam, kontrą i gazem.",
		],
	},
	{
		"key": "steer_assist", "group": "assist", "label": "Ograniczenie skrętu",
		"values": [true, "grip", false], "names": ["Wł.", "Wg przyczepności", "Wył."],
		"hints": [
			"Im szybciej, tym mniejszy skręt kół - drążek to nie kierownica.",
			"Pełny drążek to tyle skrętu, ile opony przeniosą (z zapasem na poślizg) - przy 300 km/h drobne korekty naprawdę drobne.",
			"Pełny skręt przy każdej prędkości - jak prawdziwa kierownica.",
		],
	},
	{
		"key": "gas_hand", "group": "controls", "label": "Gaz",
		"values": ["right", "left"],
		"names": ["prawy spust", "lewy spust"],
		"hints": [
			"Gaz prawym spustem, hamulec lewym. Grip przy gazie: wsteczny (po zatrzymaniu), grip przy hamulcu: ręczny.",
			"Gaz lewym spustem, hamulec prawym. Grip przy gazie: wsteczny (po zatrzymaniu), grip przy hamulcu: ręczny.",
		],
	},
	{
		"key": "steer_stick", "group": "controls", "label": "Kierownica",
		"values": ["right", "left", "wheel"],
		"names": ["prawy drążek", "lewy drążek", "w powietrzu (dłonie)"],
		"hints": [
			"Skręcasz prawym drążkiem. Lewy drążek w górę/w dół: bieg wyżej/niżej.",
			"Skręcasz lewym drążkiem. Prawy drążek w górę/w dół: bieg wyżej/niżej.",
			"Złap kierownicę gripami i kręć jak prawdziwą (jedną albo dwiema rękami); puszczona wraca do środka. Biegi: prawy drążek, ręczny: lewy drążek w dół, wsteczny: hamulec na postoju.",
		],
	},
	{
		"key": "vibration", "group": "controls", "label": "Wibracje", "live": true,
		"values": [0.0, 0.5, 1.0],
		"names": ["Wył.", "Słabe", "Mocne"],
		"hints": [
			"Kontrolery nie wibrują.",
			"Uderzenia, lądowania, pobocze, ABS w ręce hamulca, buksowanie w ręce gazu (domyślnie).",
			"To samo, mocniej.",
		],
	},
	{
		"key": "road_texture", "group": "controls", "label": "Faktura drogi w drążkach", "live": true,
		"values": [false, true], "names": ["Wył.", "Wł."],
		"hints": ["Bez drżenia od zwykłej jezdni.", "Lekkie drżenie rosnące z prędkością - przy długiej jeździe może męczyć."],
	},
	{
		"key": "wheel_range", "group": "controls", "label": "Obrót kierownicy",
		"values": [90, 180, 270, 450],
		"names": ["±90°", "±180°", "±270°", "±450°"],
		"hints": [
			"Pełny skręt kół przy ćwierć obrotu - bardzo szybko.",
			"Pełny skręt przy pół obrotu w każdą stronę (domyślnie).",
			"Trzy czwarte obrotu - spokojniej, precyzyjniej przy dużych prędkościach.",
			"Jak w aucie z epoki bez wspomagania - dużo kręcenia.",
		],
	},
	{
		"key": "stick_expo", "group": "controls", "label": "Krzywa drążka",
		"values": [1.6, 1.0, 2.2],
		"names": ["łagodny środek", "liniowa", "bardzo łagodny środek"],
		"hints": [
			"Mały ruch = mały, precyzyjny skręt; pełne wychylenie = pełny skręt.",
			"Skręt proporcjonalny do wychylenia.",
			"Jeszcze spokojniej przy małych ruchach - dla dużych prędkości.",
		],
	},
	{
		"key": "stick_sensitivity", "group": "controls", "label": "Czułość drążka",
		"values": [50, 70, 85, 100, 120, 150],
		"names": ["50%", "70%", "85%", "100%", "120%", "150%"],
		"hints": [
			"Bardzo spokojnie - pełny skręt tylko przy dużych prędkościach przydatny.",
			"Spokojnie - łatwiej trzymać prosty tor.",
			"Lekko łagodniej niż domyślnie.",
			"Domyślnie. Środek drążka i tak jest łagodny (krzywa), pełne wychylenie = pełny skręt.",
			"Żywiej - pełny skręt przed końcem wychylenia.",
			"Bardzo żywo - dla wprawnych.",
		],
	},
	{
		"key": "xr_resolution", "group": "look", "label": "Rozdzielczość w goglach",
		"values": [100, 110, 120, 130, 140, 160, 180],
		"names": ["100%", "110%", "120%", "130%", "140%", "160%", "180%"],
		"hints": [
			"Tyle, ile zalecają gogle - najlżej.",
			"Domyślnie: najostrzej przy płynnych 72 kl./s (pomiar na Queście).",
			"Ostrzej; na granicy płynności.",
			"Środek obrazu piksel w piksel z ekranem; ok. 53 kl./s.",
			"Ostro, ale gogle nie nadążają.",
			"Najwięcej, co ekran pokaże - na Queście wyraźnie poniżej 72 kl./s, grzeje gogle.",
			"Ponad możliwości ekranu - tylko wygładzanie krawędzi, bardzo ciężko.",
		],
	},
	{
		"key": "shadows", "group": "look", "label": "Cienie", "live": true,
		"values": ["off", "near", "full"],
		"names": ["Wył.", "Bliskie", "Pełne"],
		"hints": [
			"Bez cieni słońca - najlżej dla gogli (przy 130% ok. 65 kl./s zamiast 58).",
			"Cienie tylko do 40 m, mniej dokładne - trochę lżej (ok. 60 kl./s przy 130%).",
			"Cienie do 80 m, ostre przy aucie - najciężej (ok. 58 kl./s przy 130%).",
		],
	},
	{
		"key": "xr_foveation", "group": "look", "label": "Foweacja",
		"values": [0, 1, 2, 3],
		"names": ["Wył.", "Słaba", "Średnia", "Mocna"],
		"hints": [
			"Cały obraz pełną rozdzielczością - najostrzej, najciężej.",
			"Brzegi obrazu trochę rzadziej, mocniej tylko gdy gogle nie nadążają.",
			"Domyślnie: brzegi wyraźnie rzadziej - więcej zapasu wydajności.",
			"Najlżej; brzegi obrazu widocznie rozmyte.",
		],
	},
	{
		"key": "cockpit_alpha", "group": "look", "label": "Przezroczystość kokpitu",
		"values": [0, 20, 40, 60, 80],
		"names": ["0% (pełna)", "20%", "40%", "60%", "80%"],
		"hints": [
			"Kabina pełna, jak w prawdziwym aucie - maska zasłania jezdnię przed autem.",
			"Maska i deska lekko prześwitują.",
			"Widać jezdnię przez maskę, deskę i podłogę.",
			"Domyślnie: kabina ledwo widoczna - jezdnia jak na dłoni.",
			"Prawie sama jezdnia - kabina tylko jako zarys.",
		],
	},
	{
		"key": "rage_overspeed", "group": "rage", "label": "Przekraczanie przepisów",
		"values": [20, 50, 100, 0],
		"names": ["+20 km/h", "+50 km/h", "+100 km/h", "bez limitu"],
		"hints": [
			"Bot w szale jedzie najwyżej 20 km/h ponad ograniczenie.",
			"Bot w szale jedzie najwyżej 50 km/h ponad ograniczenie.",
			"Bot w szale prawie nie patrzy na znaki.",
			"Bot w szale jedzie tak szybko, jak potrafi (tylko łuki go hamują).",
		],
	},
	{
		"key": "rage_time", "group": "rage", "label": "Szał trwa co najmniej",
		"values": [5, 10, 20, 40, 120, -1],
		"names": ["5 s", "10 s", "20 s", "40 s", "2 min", "nigdy nie mija"],
		"hints": [
			"Po tym czasie od ostatniego zderzenia przepisowa jazda zaczyna bota uspokajać.",
			"Po tym czasie od ostatniego zderzenia przepisowa jazda zaczyna bota uspokajać.",
			"Po tym czasie od ostatniego zderzenia przepisowa jazda zaczyna bota uspokajać.",
			"Po tym czasie od ostatniego zderzenia przepisowa jazda zaczyna bota uspokajać.",
			"Po tym czasie od ostatniego zderzenia przepisowa jazda zaczyna bota uspokajać.",
			"Szał nie mija - bot ściga cię, dopóki nie zostanie daleko w tyle.",
		],
	},
	{
		"key": "rage_calm", "group": "rage", "label": "Uspokojenie po",
		"values": [3, 6, 12, 20, 60],
		"names": ["3 s", "6 s", "12 s", "20 s", "60 s"],
		"hints": [
			"Tyle sekund jazdy zgodnie z przepisami gasi szał (po minimalnym czasie).",
			"Tyle sekund jazdy zgodnie z przepisami gasi szał (po minimalnym czasie).",
			"Tyle sekund jazdy zgodnie z przepisami gasi szał (po minimalnym czasie).",
			"Tyle sekund jazdy zgodnie z przepisami gasi szał (po minimalnym czasie).",
			"Tyle sekund jazdy zgodnie z przepisami gasi szał (po minimalnym czasie).",
		],
	},
	{
		"key": "rage_strategy", "group": "rage", "label": "Strategia",
		"values": ["mixed", "block", "ram", "pit", "zigzag", "ambush", "pincer"],
		"names": ["Wszystkie na zmianę", "Zajeżdżanie drogi", "Stukanie w tył",
				"Spychanie z boku", "Zygzak", "Zasadzka", "Kleszcze"],
		"hints": [
			"Co kilka sekund inna sztuczka - nie wiesz, co zrobi.",
			"Wyprzedza, zajeżdża drogę i gwałtownie hamuje przed tobą.",
			"Gwałtownie podjeżdża od tyłu i stuka w zderzak.",
			"Podjeżdża równolegle i uderza w tylny bok, żeby cię obrócić.",
			"Jedzie przed tobą od krawędzi do krawędzi - nie wyprzedzisz.",
			"Wyprzedza, staje na poboczu i wyjeżdża ci przed maskę.",
			"Dwa boty w szale biorą cię z obu boków. Sam bot spycha z boku.",
		],
	},
	{
		"key": "rage_overtake", "group": "rage", "label": "Furia po wyprzedzeniu",
		"values": [0, 10, 25, 50],
		"names": ["Wył.", "10%", "25%", "50%"],
		"hints": [
			"Bot wpada w szał tylko po stłuczce.",
			"Czasem wyprzedzony bot się wścieka - posiłki wzywa dopiero po kontakcie.",
			"Co czwarty wyprzedzony bot się wścieka - posiłki dopiero po kontakcie.",
			"Co drugi wyprzedzony bot się wścieka - posiłki dopiero po kontakcie.",
		],
	},
	{
		"key": "rage_reinforce", "group": "rage", "label": "Posiłki",
		"values": [true, false], "names": ["Wł.", "Wył."],
		"hints": [
			"Szał jednego bota zaraża wszystkie boty w promieniu 400 m.",
			"Każdy bot wściekły tylko za siebie.",
		],
	}
]


func _ready() -> void:
	_fill_radio_stations()
	load_settings()


## Nazwy stacji z katalogu radia (lista zależy od plików muzyki).
func _fill_radio_stations() -> void:
	var st: Array = preload("res://scripts/radio_stations.gd").STATIONS
	for opt in OPTIONS:
		if opt["key"] == "radio_station":
			# Ostatnia pozycja: stacja online (użytkownik 2026-11-10: "w menu,
			# gdy Jamendo jest włączone, nie ma stacji Jamendo"). Wartość
			# STATION_ONLINE (-1), nie indeks - zapisany wybór nie zmieni
			# znaczenia, gdy dojdzie stacja offline.
			opt["values"] = range(st.size()) + [STATION_ONLINE]
			opt["names"] = st.map(func(x): return str(x["name"])) + ["Jamendo online"]
			var hints := []
			for x in st:
				hints.append("Stacja, od której radio zaczyna.")
			hints.append("Muzyka z internetu (Jamendo) - gra, gdy \"Radio online (Jamendo)\" jest Wł.; inaczej pierwsza stacja z gry.")
			opt["hints"] = hints


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for opt in OPTIONS:
		var key: String = opt["key"]
		var v = cfg.get_value("car", key, get(key))
		# Wartość spoza listy (np. stary plik) - zostaje domyślna.
		if opt["values"].has(v):
			set(key, v)
	var version: int = cfg.get_value("meta", "version", 1)
	if version < 10:
		# Do v9 Jamendo w menu Stacja było indeksem za stacjami offline
		# (2026-11-10, kilka godzin) - teraz STATION_ONLINE.
		var st_n: int = preload("res://scripts/radio_stations.gd").STATIONS.size()
		if int(cfg.get_value("car", "radio_station", 0)) == st_n:
			radio_station = STATION_ONLINE
	if version < 7:
		# Użytkownik po jeździe: "sedan najfajniejszy" - domyślny znowu sedan.
		body_model = "sedan"
	if version < 9:
		# Użytkownik 2026-11-09 (przed snem): "cała trasa jest na
		# autostradzie" - autostrada domyślna. Zapisany "canyon" był dotąd
		# tylko domyślną wartością (wyboru trasy nie było w menu), więc
		# jednorazowo przestawiamy; wąwóz dalej do wyboru w menu.
		if track_mode == "canyon":
			track_mode = "autostrada"
	if version < 8:
		# Do v7 gogle same zmniejszały obraz (dynamiczna rozdzielczość Meta,
		# log VrApi SF=0.50 przy 160%) - zapisane 130-160% nie było prawdą.
		# Bez niej (2026-11-09) uczciwy pomiar: 100% 10 ms GPU, 130% 15,8 ms
		# (53 kl./s) - start od 110%, wyżej gracz podnosi sam.
		xr_resolution = mini(xr_resolution, 110)
	if version < 5:
		# 160% bez dynamicznej rozdzielczości dawało na Queście ~8 kl./s
		# (2026-11-08) - z powrotem 130% i średnia foweacja.
		xr_resolution = mini(xr_resolution, 130)
		xr_foveation = maxi(xr_foveation, 2)
	if version < 3:
		# Nowy układ (użytkownik): kierownica prawym, biegi lewym drążkiem.
		steer_stick = "right"
	best_time = cfg.get_value("records", "best_time", 0.0)
	best_distance = cfg.get_value("records", "best_distance", 0.0)
	# Dawny zapis (przed grupą "Radio" w OPTIONS).
	if cfg.has_section_key("radio", "online") and not cfg.has_section_key("car", "radio_online"):
		radio_online = bool(cfg.get_value("radio", "online", false))


func save_settings() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	for opt in OPTIONS:
		cfg.set_value("car", opt["key"], get(opt["key"]))
	cfg.set_value("meta", "version", SETTINGS_VERSION)
	cfg.set_value("records", "best_time", best_time)
	cfg.set_value("records", "best_distance", best_distance)
	cfg.save(PATH)


## Ograniczenie skrętu na aucie: Wł. / Wg przyczepności / Wył.
## (użytkownik 2026-11-11: przy 300 km/h oscylacje - 10% drążka zużywało
## już całą przyczepność, tests/esp_highspeed_test.gd).
func apply_steer(car: StuntCar) -> void:
	car.steer_assist = steer_assist is String or bool(steer_assist)
	car.steer_grip = steer_assist is String and steer_assist == "grip"


## Ustawia samochód zgodnie z wyborem gracza.
## Moc, jaką auto naprawdę dostanie: próg HUB_ONLY_KW tylko dla elektryka
## z silnikami w kołach, inne napędy w jego miejsce MAX_KW_OTHERS.
static func effective_power(type_name: String, hub: bool, kw: int) -> int:
	if kw > MAX_KW_OTHERS and not (type_name == "electric" and hub):
		return MAX_KW_OTHERS
	return kw


## Tempo gry w scenie jazdy. W testach bez okna zawsze 100% (wyniki testów
## są skalibrowane na czas rzeczywisty); CANION_TIME_SCALE (np. 1.3) wymusza
## tempo do sprawdzenia testem.
func apply_game_speed() -> void:
	var ts := game_speed / 100.0
	if DisplayServer.get_name() == "headless":
		ts = 1.0
	var env := OS.get_environment("CANION_TIME_SCALE")
	if env != "":
		ts = env.to_float()
	Engine.time_scale = ts


## Masa wybranego modelu (opcja Masa = "Fabryczna").
func factory_mass() -> float:
	var st: Dictionary = CarStyles.STYLES.get(body_model, CarStyles.STYLES["sedan"])
	return float(st["mass"])


## Zmiana opcji z menu (główne i pauza - jedno miejsce). Wybór modelu auta
## ustawia jego fabryczny silnik, moc, napęd, zawieszenie i masę
## (użytkownik 2026-11-11); potem każdą z nich można zmienić.
func set_option(key: String, value: Variant) -> void:
	set(key, value)
	if key == "body_model" and CarStyles.STYLES.has(value):
		var st: Dictionary = CarStyles.STYLES[value]
		engine_type = st["engine"]
		engine_power = int(st["power_kw"])
		drive_layout = st["drive"]
		suspension = st["suspension"]
		body_mass = 0


func apply_to_car(car: StuntCar) -> void:
	# Modele z epoki (CarStyles): bryła, rozstawy, rozkład masy, zawieszenie,
	# hamulce, opór. Silnik, napęd i masa z menu - wybór modelu ustawia je
	# na fabryczne (set_option), gracz może je potem zmienić.
	if body_model != "concept" and CarStyles.STYLES.has(body_model):
		car.set_body_model("sedan")
		car.apply_style(body_model)
	else:
		car.apply_style("sedan")
		car.set_body_model(body_model)
	car.drive_layout = drive_layout
	car.tires = tires
	car.hub_motors = motor_layout == "hub"
	car.regen_level = regen
	car.apply_engine(engine_type, effective_power(engine_type, motor_layout == "hub", engine_power))
	car.automatic = transmission == "auto"
	car.apply_suspension_preset(suspension)
	car.set_body_mass(body_mass if body_mass > 0 else factory_mass())
	car.set_spoiler(spoiler)
	car.durability = float(durability)
	car.set_aero(aero)
	car.abs_enabled = abs_enabled
	car.tcs_enabled = tcs_enabled
	car.esp_enabled = esp_enabled
	apply_steer(car)
	car.set_paint(PAINTS[paint])


## Włącza renderowanie do gogli, jeśli OpenXR wystartował. Zwraca true w VR.
## Wołane przez każdą scenę - po zmianie sceny viewport trzeba ustawić od nowa.
## Rozdzielczość obrazu i foweacja (brzegi obrazu liczone rzadziej;
## dynamiczna - mocniej tylko gdy gogle nie nadążają). Do logu faktyczny
## rozmiar obrazu - po nim widać, czy mnożnik zadziałał w trakcie sesji.
func apply_xr_quality() -> void:
	var xr := XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr == null or not xr.is_initialized():
		return
	xr.render_target_size_multiplier = xr_resolution / 100.0
	xr.foveation_level = xr_foveation
	xr.foveation_dynamic = xr_foveation > 0
	print("XR: rozdzielczość %d%%, obraz na oko %s, foweacja %d" % [
			xr_resolution, xr.get_render_target_size(), xr.foveation_level])


## Cienie słońca wg opcji Cienie (użytkownik 2026-11-11: opcja w menu,
## bo przy 130% gogle ogranicza GPU). Bench w A/B: "shadows" wyłącza,
## "shadows_far" wymusza bliskie (pomiar opcji bez zmiany ustawień gracza).
func apply_shadows(sun: DirectionalLight3D) -> void:
	sun.shadow_enabled = shadows != "off" and Bench.on("shadows")
	# Bench S4 130% (2026-11-11, jedna seria): pełne 58,4 kl./s (GPU 16,9 ms),
	# bliskie (40 m, jedna mapa 1024) 60,1, bez cieni 65,5 - koszt to głównie
	# sam przebieg cieni, zasięg i rozmiar mapy dają mało.
	var full_size: int = ProjectSettings.get_setting_with_override(
			"rendering/lights_and_shadows/directional_shadow/size")
	if shadows == "near" or not Bench.on("shadows_far"):
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 40.0
		RenderingServer.directional_shadow_atlas_set_size(mini(full_size, 1024), true)
	else:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = 80.0
		RenderingServer.directional_shadow_atlas_set_size(full_size, true)
	var near := shadows == "near" or not Bench.on("shadows_far")
	print("CIENIE: %s" % ("wył." if not sun.shadow_enabled else
			"%s, mapa %d" % ["bliskie" if near else "pełne", mini(full_size, 1024) if near else full_size]))


func enable_xr(viewport: Viewport) -> bool:
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized():
		apply_xr_quality()
		# W XR to kompozytor gogli decyduje o synchronizacji, nie okno pulpitu.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		viewport.use_xr = true
		return true
	return false
