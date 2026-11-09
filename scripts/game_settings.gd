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
const SETTINGS_VERSION := 8

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
var steer_assist: bool = true
var engine_type: String = "petrol"
var engine_power: int = 180          # kW
## Układ napędu: "rwd" tył, "fwd" przód, "awd" 4x4 (StuntCar.drive_layout).
var drive_layout: String = "rwd"
## Model auta gracza: "concept" (Khronos Car Concept, CC BY 4.0) albo
## "sedan" (własny z lat 70., z wgnieceniami). Boty zawsze sedany.
var body_model: String = "sedan"
## Masa nadwozia [kg] (bez napędu: diesel +50, elektryk +200).
var body_mass: int = 1150
## Spojler: "none", "small", "large" (StuntCar.SPOILERS).
var spoiler: String = "none"
## Wytrzymałość auta: 1 = zgodna z fizyką, wyżej mnożnik (jawna pomoc,
## użytkownik 2026-11-09) - StuntCar.durability.
var durability: int = 1
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
## Rodzaj trasy. W grze tylko "canyon" (wąwóz bez końca) - jedyny tryb,
## ustalone z użytkownikiem; nie ma go w menu. "endless" (estakady) i "demo"
## (pokazowa z metą) zostały w kodzie dla testów (endless_test, drive_test).
var track_mode: String = "canyon"
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

## Grupy menu (podmenu na ekranie tytułowym), w kolejności wyświetlania.
const GROUPS: Array[Dictionary] = [
	{"id": "track", "label": "Trasa"},
	{"id": "car", "label": "Samochód"},
	{"id": "body", "label": "Nadwozie i opony"},
	{"id": "assist", "label": "Systemy wspomagania"},
	{"id": "controls", "label": "Sterowanie"},
	{"id": "look", "label": "Wygląd i widok"},
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
		"values": ["sedan", "concept"],
		"names": ["Sedan z lat 70.", "Concept"],
		"hints": [
			"Własny sedan z epoki: winylowy dach, chrom, wgniecenia, spojlery.",
			"Futurystyczny concept car, fotel kierowcy na środku. Bez wgnieceń.",
		],
	},
	{
		"key": "body_mass", "group": "body", "label": "Masa",
		"values": [950, 1150, 1500, 2000, 2500],
		"names": ["950 kg", "1150 kg", "1500 kg", "2000 kg", "2500 kg"],
		"hints": [
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
		"key": "aero", "group": "body", "label": "Opływowość",
		"values": ["classic", "modern", "sport", "record"],
		"names": ["Sedan z epoki", "Współczesna", "Sportowa", "Rekordowa"],
		"hints": [
			"Cd 0,36, duże czoło: 130 kW ok. 215 km/h, ponad 300 km/h od ok. 450 kW.",
			"Cd 0,29 jak dzisiejsze auta: o kilkanaście km/h szybciej.",
			"Cd 0,30, niskie i wąskie czoło: jeszcze trochę szybciej.",
			"Cd 0,22, jak auta do bicia rekordów: najmniejszy opór, mocne auto ponad 350 km/h.",
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
		"values": [true, false], "names": ["Wł.", "Wył."],
		"hints": [
			"Im szybciej, tym mniejszy skręt kół - drążek to nie kierownica.",
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
		"values": ["right", "left"],
		"names": ["prawy drążek", "lewy drążek"],
		"hints": [
			"Skręcasz prawym drążkiem. Lewy drążek w górę/w dół: bieg wyżej/niżej.",
			"Skręcasz lewym drążkiem. Prawy drążek w górę/w dół: bieg wyżej/niżej.",
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
	load_settings()


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
	if version < 7:
		# Użytkownik po jeździe: "sedan najfajniejszy" - domyślny znowu sedan.
		body_model = "sedan"
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


## Ustawia samochód zgodnie z wyborem gracza.
## Moc, jaką auto naprawdę dostanie: próg HUB_ONLY_KW tylko dla elektryka
## z silnikami w kołach, inne napędy w jego miejsce MAX_KW_OTHERS.
static func effective_power(type_name: String, hub: bool, kw: int) -> int:
	if kw > MAX_KW_OTHERS and not (type_name == "electric" and hub):
		return MAX_KW_OTHERS
	return kw


func apply_to_car(car: StuntCar) -> void:
	car.set_body_model(body_model)
	car.drive_layout = drive_layout
	car.tires = tires
	car.hub_motors = motor_layout == "hub"
	car.apply_engine(engine_type, effective_power(engine_type, motor_layout == "hub", engine_power))
	car.automatic = transmission == "auto"
	car.apply_suspension_preset(suspension)
	car.set_body_mass(body_mass)
	car.set_spoiler(spoiler)
	car.durability = float(durability)
	car.set_aero(aero)
	car.abs_enabled = abs_enabled
	car.tcs_enabled = tcs_enabled
	car.esp_enabled = esp_enabled
	car.steer_assist = steer_assist
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


func enable_xr(viewport: Viewport) -> bool:
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized():
		apply_xr_quality()
		# W XR to kompozytor gogli decyduje o synchronizacji, nie okno pulpitu.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		viewport.use_xr = true
		return true
	return false
