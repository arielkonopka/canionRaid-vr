extends GazeFollow
class_name PauseMenu

## Menu pauzy = menu ustawień gry (użytkownik 2026-11-09: "menu pauzy
## będzie menu głównym, gdzie zmiana samochodu zresetuje grę, ale najpierw
## uprzedzić gracza"; "ustawienia radia w ustawieniach gry").
##
## Te same grupy i opcje co na ekranie tytułowym (GameSettings.GROUPS /
## OPTIONS). Zmiany zapisują się od razu; radio, wspomagania, sterowanie,
## wygląd i szał botów działają od razu (sygnał setting_changed -> xr_main).
## Trasa, samochód i nadwozie (RESTART_GROUPS) wymagają nowej jazdy: przy
## powrocie do jazdy pytanie - A/spust: zacznij od nowa, B: cofnij zmiany.
##
## Pauza zatrzymuje drzewo sceny; ten węzeł, radio i XROrigin działają dalej
## (PROCESS_MODE_ALWAYS). Drążek: góra/dół wybór, w bok zmiana wartości /
## wejście do grupy; A albo spust zatwierdza, B wraca.

signal resumed
signal quit_requested
signal restart_requested
signal setting_changed(key: String)

const RESTART_GROUPS := ["track", "car", "body"]
const VOLUME_STEPS := [-30.0, -24.0, -18.0, -14.0, -10.0, -8.0, -6.0, -3.0, 0.0]

var radio: CarRadio
var hands: Array = []          # XRController3D (drążki)
var xr := false
var label: Label3D
var selected := 0
var _group := ""
var _entries: Array = []
var _snapshot := {}
var _confirm := false
var _stick_ready := false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "PauseMenu"
	distance = 1.5
	label = Label3D.new()
	label.name = "PauseLabel"
	label.font_size = 56
	label.pixel_size = 0.0012
	label.outline_size = 16
	label.modulate = Color(0.9, 0.95, 1.0)
	label.no_depth_test = true
	label.render_priority = 6
	add_child(label)
	visible = false


func _gs() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null("GameSettings")


func open() -> void:
	_snapshot = _restart_values()
	_confirm = false
	_group = ""
	selected = 0
	_stick_ready = false
	_build()
	snap()
	visible = true


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


## Wartości opcji wymagających nowej jazdy (do porównania przy powrocie).
func _restart_values() -> Dictionary:
	var gs := _gs()
	var out := {}
	if gs == null:
		return out
	for opt in gs.OPTIONS:
		# "live": działa od razu, bez nowej jazdy (np. tempo gry).
		if opt["group"] in RESTART_GROUPS and not opt.get("live", false):
			out[opt["key"]] = gs.get(opt["key"])
	return out


func _build() -> void:
	_entries.clear()
	var gs := _gs()
	if _group == "":
		_entries.append({"type": "resume"})
		if gs:
			for g in gs.GROUPS:
				_entries.append({"type": "group", "id": g["id"], "label": g["label"]})
		_entries.append({"type": "quit"})
	else:
		for opt in gs.OPTIONS:
			if opt["group"] == _group:
				_entries.append({"type": "option", "opt": opt})
		_entries.append({"type": "back"})
	selected = clampi(selected, 0, _entries.size() - 1)
	refresh()


func _value_index(opt: Dictionary) -> int:
	return maxi(opt["values"].find(_gs().get(opt["key"])), 0)


## Indeks wpisu (testy): "resume", "quit", "back", grupa po id, opcja po kluczu.
func find_entry(what: String) -> int:
	for i in range(_entries.size()):
		var e: Dictionary = _entries[i]
		if e["type"] == what or e.get("id", "") == what \
				or (e["type"] == "option" and e["opt"]["key"] == what):
			return i
	return -1


func refresh() -> void:
	var lines := PackedStringArray()
	if _confirm:
		lines.append("ZMIANY AUTA / TRASY")
		lines.append("")
		lines.append("Nowe ustawienia samochodu albo trasy")
		lines.append("zaczną jazdę od nowa.")
		lines.append("")
		lines.append("A / spust: zacznij od nowa")
		lines.append("B: cofnij zmiany i wróć do jazdy")
		label.text = "\n".join(lines)
		return
	var gs := _gs()
	var title := "PAUZA"
	if _group != "":
		for g in gs.GROUPS:
			if g["id"] == _group:
				title = "- %s -" % g["label"]
	lines.append(title)
	if _group in RESTART_GROUPS:
		lines.append("(zmiana zacznie jazdę od nowa)")
	lines.append("")
	for i in range(_entries.size()):
		var t := _entry_text(_entries[i])
		lines.append(("> " + t + " <") if i == selected else t)
	lines.append("")
	var e: Dictionary = _entries[selected]
	if e["type"] == "option":
		var opt: Dictionary = e["opt"]
		var hints: Array = opt["hints"]
		var vi := _value_index(opt)
		if vi < hints.size() and str(hints[vi]) != "":
			lines.append(str(hints[vi]))
	elif e["type"] == "group" and e["id"] == "radio" and radio:
		lines.append("Teraz: " + radio.station_name() + ("" if radio.is_on else " (wył.)"))
	lines.append("drążek: wybór i zmiana   A/spust: zatwierdź   B: wstecz" if xr \
			else "strzałki: wybór i zmiana   Enter: zatwierdź   Esc: wstecz")
	label.text = "\n".join(lines)


func _entry_text(e: Dictionary) -> String:
	match e["type"]:
		"resume":
			return "Wróć do jazdy"
		"quit":
			return "Wyjdź do menu głównego"
		"group":
			return e["label"] + "   >"
		"back":
			return "<   Wróć"
		"option":
			var opt: Dictionary = e["opt"]
			return "%s:  < %s >" % [opt["label"], opt["names"][_value_index(opt)]]
	return ""


func move(dir: int) -> void:
	if _confirm:
		return
	selected = wrapi(selected + dir, 0, _entries.size())
	refresh()


## Drążek w bok / strzałki: zmiana wartości albo wejście/wyjście z grupy.
func change(dir: int) -> void:
	if _confirm:
		return
	var e: Dictionary = _entries[selected]
	match e["type"]:
		"option":
			var opt: Dictionary = e["opt"]
			var values: Array = opt["values"]
			var gs := _gs()
			gs.set_option(opt["key"], values[wrapi(_value_index(opt) + dir, 0, values.size())])
			gs.save_settings()
			setting_changed.emit(opt["key"])
			refresh()
		"group":
			if dir > 0:
				enter_group(e["id"])
		"back":
			if dir < 0:
				enter_group("")


func enter_group(group_id: String) -> void:
	var prev := _group
	_group = group_id
	selected = 0
	_build()
	if group_id == "":
		for i in range(_entries.size()):
			if _entries[i].get("id", "") == prev:
				selected = i
		refresh()


func accept() -> void:
	if _confirm:
		restart_requested.emit()
		return
	var e: Dictionary = _entries[selected]
	match e["type"]:
		"resume":
			try_resume()
		"quit":
			quit_requested.emit()
		"group":
			enter_group(e["id"])
		"back":
			enter_group("")
		"option":
			change(1)


## B / Esc: z pytania - cofnij zmiany i jedź dalej; z grupy - wyżej; z menu
## głównego pauzy - powrót do jazdy.
func cancel() -> void:
	if _confirm:
		var gs := _gs()
		for k in _snapshot:
			gs.set(k, _snapshot[k])
		gs.save_settings()
		_confirm = false
		resumed.emit()
		return
	if _group != "":
		enter_group("")
	else:
		try_resume()


## Powrót do jazdy: jeśli zmieniono auto/trasę - najpierw pytanie.
func try_resume() -> void:
	if _restart_values() != _snapshot:
		_confirm = true
		refresh()
		return
	resumed.emit()


## Głośność radia z ustawień.
func apply_volume() -> void:
	var gs := _gs()
	if radio and gs:
		radio.set_volume_db(VOLUME_STEPS[clampi(gs.radio_volume, 0, VOLUME_STEPS.size() - 1)])


func _process(delta: float) -> void:
	super._process(delta)
	if not visible or not xr:
		return
	var v := Vector2.ZERO
	for h in hands:
		v += (h as XRController3D).get_vector2("primary")
	if v.length() < 0.3:
		_stick_ready = true
	elif _stick_ready and v.length() > 0.7:
		_stick_ready = false
		if absf(v.y) >= absf(v.x):
			move(-1 if v.y > 0.0 else 1)
		else:
			change(1 if v.x > 0.0 else -1)


## Klawiatura na PC (Esc otwiera w xr_main; tu - bo scena jazdy w pauzie
## nie dostaje wejścia).
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_up"):
		move(-1)
	elif event.is_action_pressed("ui_down"):
		move(1)
	elif event.is_action_pressed("ui_left"):
		change(-1)
	elif event.is_action_pressed("ui_right"):
		change(1)
	elif event.is_action_pressed("ui_accept"):
		accept()
	elif event.is_action_pressed("ui_cancel"):
		cancel()
	else:
		return
	get_viewport().set_input_as_handled()
