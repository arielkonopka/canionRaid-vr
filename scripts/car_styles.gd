class_name CarStyles

## Modele aut z epoki: wymiary i fizyka (dane, bez logiki).
## Wygenerowane przez tools/car_styles_tune.py z symulacji tools/car_sim.py -
## nie edytuj ręcznie; wyniki manewrów w docs/car_styles_sim.md.
## Układ jak w StuntCar: przód = -Z, mocowania kół na y = 0, com_offset
## względem punktu odniesienia. inertia = (X pochylenie, Y odchylenie, Z przechył).
## Mnożniki zawieszenia działają na zestaw z SUSPENSION_PRESETS (już skalowany masą).

const STYLES := {
	"sedan": {
		"label": "Sedan z lat 70.",
		"size": Vector3(1.78, 1.39, 4.56),
		"mounts": [Vector3(-0.820, 0.0, -1.320), Vector3(0.820, 0.0, -1.320),
				Vector3(-0.820, 0.0, 1.250), Vector3(0.820, 0.0, 1.250)],
		"wheel_radius": 0.33, "rest_length": 0.45,
		"mass": 1150.0, "com_offset": Vector3(0.0, -0.120, -0.030),
		"inertia": Vector3(1750.0, 1950.0, 480.0),
		"body_bottom": -0.400, "cd": 0.36, "area": 2.1,
		"engine": "petrol", "power_kw": 90, "drive": "rwd",
		"suspension": "sport", "final_mult": 1.0,
		"arb_front_mult": 1.0, "arb_rear_mult": 1.0,
		"spring_mult": 1.0, "damper_mult": 1.0,
		"brake_front": 1900.0, "brake_rear": 1050.0,
		"bot_weight": [25, 25],   # wąwóz, autostrada
	},
	"kombi": {
		"label": "Kombi",
		"size": Vector3(1.78, 1.45, 4.62),
		"mounts": [Vector3(-0.820, 0.0, -1.320), Vector3(0.820, 0.0, -1.320),
				Vector3(-0.820, 0.0, 1.250), Vector3(0.820, 0.0, 1.250)],
		"wheel_radius": 0.33, "rest_length": 0.45,
		"mass": 1230.0, "com_offset": Vector3(0.0, -0.069, 0.030),
		"inertia": Vector3(1931.0, 2134.0, 531.0),
		"body_bottom": -0.369, "cd": 0.38, "area": 2.15,
		"engine": "petrol", "power_kw": 90, "drive": "rwd",
		"suspension": "soft", "final_mult": 0.95,
		"arb_front_mult": 0.92, "arb_rear_mult": 0.93,
		"spring_mult": 1.15, "damper_mult": 1.07,
		"brake_front": 2140.0, "brake_rear": 810.0,
		"bot_weight": [15, 20],   # wąwóz, autostrada
	},
	"hatchback": {
		"label": "Hatchback z lat 80.",
		"size": Vector3(1.62, 1.38, 3.7),
		"mounts": [Vector3(-0.700, 0.0, -1.207), Vector3(0.700, 0.0, -1.207),
				Vector3(-0.700, 0.0, 1.143), Vector3(0.700, 0.0, 1.143)],
		"wheel_radius": 0.29, "rest_length": 0.45,
		"mass": 860.0, "com_offset": Vector3(0.0, -0.147, -0.030),
		"inertia": Vector3(898.0, 993.0, 319.0),
		"body_bottom": -0.417, "cd": 0.38, "area": 1.85,
		"engine": "petrol", "power_kw": 90, "drive": "fwd",
		"suspension": "sport", "final_mult": 1.05,
		"arb_front_mult": 0.64, "arb_rear_mult": 1.11,
		"spring_mult": 1.25, "damper_mult": 1.12,
		"brake_front": 2180.0, "brake_rear": 410.0,
		"bot_weight": [20, 15],   # wąwóz, autostrada
	},
	"klin": {
		"label": "Klin z lat 80.",
		"size": Vector3(1.72, 1.24, 4.3),
		"mounts": [Vector3(-0.740, 0.0, -1.258), Vector3(0.740, 0.0, -1.258),
				Vector3(-0.740, 0.0, 1.192), Vector3(0.740, 0.0, 1.192)],
		"wheel_radius": 0.31, "rest_length": 0.4,
		"mass": 1120.0, "com_offset": Vector3(0.0, -0.187, -0.030),
		"inertia": Vector3(1502.0, 1700.0, 412.0),
		"body_bottom": -0.427, "cd": 0.33, "area": 1.8,
		"engine": "petrol", "power_kw": 130, "drive": "rwd",
		"suspension": "stiff", "final_mult": 0.9,
		"arb_front_mult": 0.42, "arb_rear_mult": 0.49,
		"spring_mult": 1.0, "damper_mult": 1.0,
		"brake_front": 1980.0, "brake_rear": 790.0,
		"bot_weight": [10, 10],   # wąwóz, autostrada
	},
	"kabriolet": {
		"label": "Kabriolet",
		"size": Vector3(1.72, 1.3, 4.4),
		"mounts": [Vector3(-0.725, 0.0, -1.284), Vector3(0.725, 0.0, -1.284),
				Vector3(-0.725, 0.0, 1.216), Vector3(0.725, 0.0, 1.216)],
		"wheel_radius": 0.32, "rest_length": 0.44,
		"mass": 1180.0, "com_offset": Vector3(0.0, -0.165, -0.030),
		"inertia": Vector3(1663.0, 1864.0, 449.0),
		"body_bottom": -0.415, "cd": 0.38, "area": 1.95,
		"engine": "petrol", "power_kw": 90, "drive": "rwd",
		"suspension": "sport", "final_mult": 0.9,
		"arb_front_mult": 1.04, "arb_rear_mult": 1.06,
		"spring_mult": 1.05, "damper_mult": 1.02,
		"brake_front": 2080.0, "brake_rear": 790.0,
		"bot_weight": [5, 5],   # wąwóz, autostrada
	},
	"muscle": {
		"label": "Muscle z lat 70.",
		"size": Vector3(1.88, 1.32, 4.85),
		"mounts": [Vector3(-0.780, 0.0, -1.438), Vector3(0.780, 0.0, -1.438),
				Vector3(-0.780, 0.0, 1.362), Vector3(0.780, 0.0, 1.362)],
		"wheel_radius": 0.34, "rest_length": 0.45,
		"mass": 1550.0, "com_offset": Vector3(0.0, -0.147, -0.090),
		"inertia": Vector3(2622.0, 2968.0, 669.0),
		"body_bottom": -0.407, "cd": 0.42, "area": 2.05,
		"engine": "petrol", "power_kw": 180, "drive": "rwd",
		"suspension": "soft", "final_mult": 0.95,
		"arb_front_mult": 0.8, "arb_rear_mult": 0.75,
		"spring_mult": 1.25, "damper_mult": 1.12,
		"brake_front": 2220.0, "brake_rear": 810.0,
		"bot_weight": [10, 10],   # wąwóz, autostrada
	},
	"terenowka": {
		"label": "Terenówka 4x4",
		"size": Vector3(1.76, 1.85, 4.45),
		"mounts": [Vector3(-0.725, 0.0, -1.233), Vector3(0.725, 0.0, -1.233),
				Vector3(-0.725, 0.0, 1.167), Vector3(0.725, 0.0, 1.167)],
		"wheel_radius": 0.38, "rest_length": 0.55,
		"mass": 1680.0, "com_offset": Vector3(0.0, -0.122, -0.030),
		"inertia": Vector3(2613.0, 2722.0, 896.0),
		"body_bottom": -0.442, "cd": 0.5, "area": 2.6,
		"engine": "diesel", "power_kw": 90, "drive": "awd",
		"suspension": "soft", "final_mult": 1.0,
		"arb_front_mult": 1.36, "arb_rear_mult": 1.56,
		"spring_mult": 1.0, "damper_mult": 1.0,
		"brake_front": 2700.0, "brake_rear": 700.0,
		"bot_weight": [10, 5],   # wąwóz, autostrada
	},
	"furgon": {
		"label": "Furgon",
		"size": Vector3(1.8, 1.98, 4.55),
		"mounts": [Vector3(-0.780, 0.0, -1.335), Vector3(0.780, 0.0, -1.335),
				Vector3(-0.780, 0.0, 1.265), Vector3(0.780, 0.0, 1.265)],
		"wheel_radius": 0.33, "rest_length": 0.5,
		"mass": 1480.0, "com_offset": Vector3(0.0, -0.007, -0.030),
		"inertia": Vector3(2440.0, 2508.0, 867.0),
		"body_bottom": -0.527, "cd": 0.42, "area": 3.2,
		"engine": "diesel", "power_kw": 90, "drive": "rwd",
		"suspension": "soft", "final_mult": 1.0,
		"arb_front_mult": 0.76, "arb_rear_mult": 1.08,
		"spring_mult": 1.25, "damper_mult": 1.12,
		"brake_front": 2320.0, "brake_rear": 630.0,
		"bot_weight": [5, 10],   # wąwóz, autostrada
	},
}
