extends Node3D

## Ekran tytułowy z podmenu: grupy opcji (GameSettings.GROUPS), w każdej
## opcje z GameSettings.OPTIONS, na dole START.
##
## Menu to napisy Label3D zawieszone w przestrzeni przed graczem, za nimi
## widać tor i auto (z lakierem na żywo). Działa tak samo w goglach i na płasko:
##   góra / dół      - wybór wiersza   (strzałki, d-pad, drążek)
##   lewo / prawo    - zmiana wartości opcji
##   Enter / A / spust - wejście do grupy, "Wróć", START
##   Esc / B         - wyjście z grupy (w menu głównym Esc zamyka grę na PC)
## Bez wskaźnika laserowego: przy kilku wierszach drążek jest szybszy.

const RACE_SCENE := "res://scenes/main.tscn"
const MENU_DISTANCE := 2.6
const MAX_ROWS := 8                  # najwięcej wierszy na ekranie (z "Wróć"/START)
const COLOR_NORMAL := Color(0.92, 0.94, 0.97)
const COLOR_SELECTED := Color(1.0, 0.75, 0.2)
const COLOR_DIM := Color(0.7, 0.74, 0.8)

@onready var origin: XROrigin3D = $XROrigin3D
@onready var camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var left_hand: XRController3D = $XROrigin3D/LeftHand
@onready var right_hand: XRController3D = $XROrigin3D/RightHand
@onready var car: StuntCar = $Car
## Tło: wąwóz, jedyny tryb gry (ustalone z użytkownikiem). Stały seed -
## zawsze ten sam, ładny początek trasy.
const TITLE_SEED := 2026
var track: EndlessTrack

var _xr := false
var _menu: Node3D
var _heading: Label3D
var _rows: Array[Label3D] = []
var _hint: Label3D
var _controls: Label3D
var _stick_ready := true

## Bieżąca grupa ("" = menu główne) i widoczne wiersze. Każdy wiersz to
## słownik {"type": "group" | "option" | "back" | "start", ...}.
var _group := ""
var _entries: Array[Dictionary] = []
var _selected := 0
var _driver: BotDriver
var _progress_t := 0.0


func _ready() -> void:
	_xr = GameSettings.enable_xr(get_viewport())
	if _xr:
		right_hand.button_pressed.connect(_on_xr_button)
		left_hand.button_pressed.connect(_on_xr_button)
	else:
		camera.current = true

	var demo: StuntTrack = $Track
	track = EndlessTrack.new()
	track.name = "Canyon"
	track.seed_value = TITLE_SEED
	track.road_material = demo.road_material
	track.pillar_material = demo.pillar_material
	track.canyon = true
	demo.queue_free()
	add_child(track)

	# Tło menu: gracz siedzi w aucie, które samo jedzie wąwozem przepisowo
	# (sterownik bota) - prośba użytkownika; wcześniej stał przy aucie,
	# a w przestrzeni "local" oczy wypadały na poziomie jezdni (widok spod
	# spodu). Auto ma ustawienia gracza (lakier, napęd) na żywo.
	_place_car(30.0)
	_driver = BotDriver.new()
	_driver.name = "Driver"
	_driver.car = car
	_driver.track = track
	_driver.dist = 30.0
	car.add_child(_driver)
	_follow_car()

	_build_menu()
	enter_group("")
	if _xr:
		XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, false)


## Auto na trasie w odległości `d`, w ruchu (prawy pas, 50 km/h).
func _place_car(d: float) -> void:
	var xf := track.transform_at_distance(d)
	var lane := (float(track.samples_from(d, 1.0)[0]["width"]) - 1.0) / 3.0
	car.place(Transform3D(xf.basis, xf.origin + xf.basis.x * lane + xf.basis.y * 0.9))
	car._settle_t = 0.0
	var v := 50.0 / 3.6
	car.linear_velocity = -xf.basis.z * v
	for w in car.wheels:
		w.omega = v / car.wheel_radius
	if _driver:
		_driver.dist = d


## Kamera (w goglach: punkt odniesienia głowy) w fotelu kierowcy, jak w grze.
func _follow_car() -> void:
	origin.global_transform = car.get_global_transform_interpolated() * car.seat.transform
	car.set_cockpit_transparency(GameSettings.cockpit_alpha / 100.0)


func _physics_process(delta: float) -> void:
	if _driver == null:
		return
	# Trasa dobudowuje się przed autem; auto obrócone, wywrócone albo
	# zjechane z trasy wraca na prawy pas trochę dalej.
	_progress_t -= delta
	if _progress_t <= 0.0:
		_progress_t = 0.5
		track.update_progress(_driver.dist)
		var below: float = (track.transform_at_distance(_driver.dist).origin - car.global_position).y
		if _driver.flipped_time > 2.0 or below > 4.0 or _driver._reverse_t > 0.0:
			_place_car(_driver.dist + 25.0)
	# Ziemia jedzie za autem (siatka 4 km).
	var gm := get_node_or_null("GroundMesh") as Node3D
	if gm:
		var p := car.global_position
		gm.global_position = Vector3(snappedf(p.x, 50.0), 0.0, snappedf(p.z, 50.0))


func _build_menu() -> void:
	# Menu podąża za wzrokiem (GazeFollow), środek wierszy na wysokości oczu.
	var gf := GazeFollow.new()
	gf.name = "Menu"
	gf.camera = camera
	gf.distance = MENU_DISTANCE
	# Nad deską rozdzielczą (menu na tle zegarów było nieczytelne).
	gf.height = 0.25
	gf.height_rate = 30.0
	_menu = gf
	origin.add_child(_menu)

	# Wysokość całego menu musi się zmieścić w wygodnym polu widzenia gogli
	# (ok. ±25° w pionie na 2,6 m to ±1,2 m).
	var title := _label("CANION RAID VR", 130, Vector3(0.0, 0.88, 0.0), COLOR_NORMAL)
	title.outline_size = 24
	_heading = _label("", 44, Vector3(0.0, 0.72, 0.0), COLOR_DIM)
	var y := 0.52
	for i in range(MAX_ROWS):
		_rows.append(_label("", 60, Vector3(0.0, y, 0.0), COLOR_NORMAL))
		y -= 0.125
	_hint = _label("", 38, Vector3(0.0, y - 0.06, 0.0), COLOR_DIM)
	_controls = _label("", 34, Vector3(0.0, y - 0.24, 0.0), COLOR_DIM)


func _label(text: String, size: int, pos: Vector3, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.001
	l.position = pos
	l.modulate = color
	l.outline_size = 12
	l.outline_modulate = Color(0.05, 0.06, 0.08, 0.85)
	l.double_sided = false
	l.no_depth_test = true    # menu zawsze na wierzchu, nawet gdy coś stoi bliżej
	_menu.add_child(l)
	return l


# --------------------------------------------------------------------------
# Wiersze menu
# --------------------------------------------------------------------------

## Przechodzi do grupy (podmenu); "" = menu główne.
func enter_group(group_id: String) -> void:
	var previous := _group
	_group = group_id
	_entries.clear()
	if group_id == "":
		for g in GameSettings.GROUPS:
			_entries.append({"type": "group", "id": g["id"], "label": g["label"]})
		_entries.append({"type": "start"})
		# Po wyjściu z grupy kursor zostaje na niej, nie skacze na górę.
		_selected = 0
		for i in range(_entries.size()):
			if _entries[i].get("id", "") == previous:
				_selected = i
	else:
		for opt in GameSettings.OPTIONS:
			if opt["group"] == group_id:
				_entries.append({"type": "option", "opt": opt})
		_entries.append({"type": "back"})
		_selected = 0
	_refresh()


func _value_index(opt: Dictionary) -> int:
	return maxi(opt["values"].find(GameSettings.get(opt["key"])), 0)


func _value_name(opt: Dictionary) -> String:
	if opt["key"] == "transmission" and GameSettings.engine_type == "electric":
		return "1 bieg"
	return opt["names"][_value_index(opt)]


## Skrót ustawień grupy - pokazywany pod grupą w menu głównym.
func _group_summary(group_id: String) -> String:
	var parts := PackedStringArray()
	for opt in GameSettings.OPTIONS:
		if opt["group"] == group_id:
			var v := _value_name(opt)
			if opt["values"][0] is bool:
				v = opt["label"] + " " + v
			parts.append(v)
	return ", ".join(parts)


func _group_label(group_id: String) -> String:
	for g in GameSettings.GROUPS:
		if g["id"] == group_id:
			return g["label"]
	return ""


func _refresh() -> void:
	# Auto z tła pokazuje wybrany lakier na żywo.
	car.set_paint(GameSettings.PAINTS[GameSettings.paint])
	_heading.text = "kaskaderska jazda wąwozem" if _group == "" \
			else "- " + _group_label(_group) + " -"

	for i in range(_rows.size()):
		var row := _rows[i]
		if i >= _entries.size():
			row.text = ""
			continue
		var e := _entries[i]
		var sel := i == _selected
		match e["type"]:
			"group":
				row.text = e["label"] + "   >"
			"option":
				row.text = "%s:   <  %s  >" % [e["opt"]["label"], _value_name(e["opt"])]
			"back":
				row.text = "<   Wróć"
			"start":
				row.text = ">  START  <" if sel else "START"
		row.font_size = 84 if e["type"] == "start" else 60
		row.modulate = COLOR_SELECTED if sel else COLOR_NORMAL

	_hint.text = _hint_for(_entries[_selected])
	if _group == "":
		_controls.text = "drążek: wybór     spust / A: wejdź / start" if _xr \
				else "strzałki: wybór     Enter: wejdź / start     Esc: wyjście"
	else:
		_controls.text = "drążek: wybór i zmiana     spust / A na Wróć, B: powrót" if _xr \
				else "strzałki: wybór i zmiana     Enter na Wróć, Esc: powrót"


func _hint_for(e: Dictionary) -> String:
	match e["type"]:
		"group":
			return _group_summary(e["id"])
		"option":
			var opt: Dictionary = e["opt"]
			var h: String = opt["hints"][_value_index(opt)]
			match opt["key"]:
				"transmission":
					if GameSettings.engine_type == "electric":
						h = "Elektryk ma jeden bieg - wybór skrzyni nie ma znaczenia."
				"engine_type", "engine_power":
					# Moment liczony z prawdziwej krzywej silnika, na aucie z tła.
					var kw: int = GameSettings.effective_power(GameSettings.engine_type,
							GameSettings.motor_layout == "hub", GameSettings.engine_power)
					car.apply_engine(GameSettings.engine_type, kw)
					h += "\nMaks. moment: %d Nm" % roundi(car.peak_torque())
					if kw != GameSettings.engine_power:
						h += "\nTen napęd dostanie %d kW (1000 kW tylko z silnikami w kołach)." % kw
					if opt["key"] == "motor_layout" and GameSettings.engine_type != "electric":
						h = "Dotyczy tylko elektryka - teraz wybrany jest inny napęd."
					elif opt["key"] == "drive_layout" and GameSettings.engine_type == "electric" \
							and GameSettings.motor_layout == "hub":
						h = "Silniki w kołach to zawsze 4x4 - ta opcja nie ma znaczenia."
			return h
		"back":
			return "Powrót do menu głównego."
	return ""


# --------------------------------------------------------------------------
# Wejście
# --------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		_move(-1)
	elif event.is_action_pressed("ui_down"):
		_move(1)
	elif event.is_action_pressed("ui_left"):
		_change(-1)
	elif event.is_action_pressed("ui_right"):
		_change(1)
	elif event.is_action_pressed("ui_accept"):
		_accept()
	elif event.is_action_pressed("ui_cancel"):
		_cancel()


func _on_xr_button(button: String) -> void:
	match button:
		"trigger_click", "ax_button":
			_accept()
		"by_button":
			_cancel()


func _process(_delta: float) -> void:
	if _driver:
		_follow_car()
	# Drążek: gałka w goglach albo lewa gałka pada. Jeden ruch = jeden krok,
	# kolejny dopiero po powrocie gałki do środka.
	var stick := Vector2.ZERO
	if _xr:
		stick = left_hand.get_vector2("primary") + right_hand.get_vector2("primary")
	else:
		stick = Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), -Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if stick.length() < 0.3:
		_stick_ready = true
		return
	if not _stick_ready or stick.length() < 0.7:
		return
	_stick_ready = false
	if absf(stick.y) > absf(stick.x):
		_move(-1 if stick.y > 0.0 else 1)
	else:
		_change(1 if stick.x > 0.0 else -1)


func _move(dir: int) -> void:
	_selected = wrapi(_selected + dir, 0, _entries.size())
	_refresh()


## Zmiana wartości opcji. W menu głównym "w prawo" na grupie wchodzi do niej.
func _change(dir: int) -> void:
	var e := _entries[_selected]
	match e["type"]:
		"option":
			var opt: Dictionary = e["opt"]
			var values: Array = opt["values"]
			GameSettings.set(opt["key"], values[wrapi(_value_index(opt) + dir, 0, values.size())])
			if opt["key"] == "xr_resolution" or opt["key"] == "xr_foveation":
				GameSettings.apply_xr_quality()
			_refresh()
		"group":
			if dir > 0:
				enter_group(e["id"])
		"back":
			if dir < 0:
				enter_group("")


func _accept() -> void:
	var e := _entries[_selected]
	match e["type"]:
		"group":
			enter_group(e["id"])
		"back":
			enter_group("")
		"option":
			# Enter na opcji przeskakuje na "Wróć" - mniej klikania.
			_selected = _entries.size() - 1
			_refresh()
		"start":
			GameSettings.save_settings()
			get_tree().change_scene_to_file(RACE_SCENE)


func _cancel() -> void:
	if _group != "":
		enter_group("")
	elif not _xr:
		get_tree().quit()
