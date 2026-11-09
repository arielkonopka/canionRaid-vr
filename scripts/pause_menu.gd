extends GazeFollow
class_name PauseMenu

## Menu pauzy w jeździe (lewy przycisk menu; na PC Esc). Ustalone
## z użytkownikiem (2026-11-09): radio sterowane z pauzy - żaden przycisk
## w jeździe się nie zmienia. Pauza zatrzymuje drzewo sceny (fizyka, boty),
## a ten węzeł, radio i XROrigin (śledzenie głowy i kontrolerów) działają
## dalej (PROCESS_MODE_ALWAYS) - zamrożony obraz w goglach męczyłby.
## Wybór drążkiem (góra/dół), zmiana wartości drążkiem w bok, A zatwierdza.

signal resumed
signal quit_requested

const ITEMS := ["resume", "radio", "station", "volume", "quit"]
const VOLUME_STEPS := [-30.0, -24.0, -18.0, -14.0, -10.0, -8.0, -6.0, -3.0, 0.0]

var radio: CarRadio
var hands: Array = []          # XRController3D (drążki)
var xr := false
var label: Label3D
var selected := 0
var _stick_ready := false
## Głośność radia na całą sesję (scena jazdy ładuje się od nowa).
static var volume_index := 5


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "PauseMenu"
	distance = 1.5
	label = Label3D.new()
	label.name = "PauseLabel"
	label.font_size = 60
	label.pixel_size = 0.0012
	label.outline_size = 16
	label.modulate = Color(0.9, 0.95, 1.0)
	label.no_depth_test = true
	label.render_priority = 6
	add_child(label)
	visible = false


func open() -> void:
	selected = 0
	_stick_ready = false
	snap()
	visible = true
	refresh()


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func refresh() -> void:
	var lines := PackedStringArray(["PAUZA", ""])
	for i in range(ITEMS.size()):
		var t := _item_text(ITEMS[i])
		lines.append(("> " + t + " <") if i == selected else t)
	lines.append("")
	lines.append("drążek: wybór i zmiana   A: zatwierdź" if xr else "strzałki: wybór i zmiana   Enter: zatwierdź")
	label.text = "\n".join(lines)


func _item_text(id: String) -> String:
	match id:
		"resume":
			return "Wróć do jazdy"
		"radio":
			return "Radio: " + ("włączone" if radio and radio.is_on else "wyłączone")
		"station":
			var n := "-"
			if radio and radio.catalog and radio.catalog.station_count() > 0:
				n = radio.catalog.stations[maxi(radio.station, 0)]["name"]
			return "Stacja:  < %s >" % n
		"volume":
			return "Głośność radia:  < %d / %d >" % [volume_index + 1, VOLUME_STEPS.size()]
		"quit":
			return "Wyjdź do menu głównego"
	return id


func move(dir: int) -> void:
	selected = wrapi(selected + dir, 0, ITEMS.size())
	refresh()


## Drążek w bok / strzałki: zmiana wartości.
func change(dir: int) -> void:
	match ITEMS[selected]:
		"radio":
			if radio:
				radio.toggle()
		"station":
			if radio:
				radio.next_station(dir)
		"volume":
			volume_index = clampi(volume_index + dir, 0, VOLUME_STEPS.size() - 1)
			apply_volume()
	refresh()


func accept() -> void:
	match ITEMS[selected]:
		"resume":
			resumed.emit()
		"quit":
			quit_requested.emit()
		"radio":
			change(1)
		"station":
			change(1)
		"volume":
			change(1)


func apply_volume() -> void:
	if radio:
		radio.set_volume_db(VOLUME_STEPS[volume_index])


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
		resumed.emit()
	else:
		return
	get_viewport().set_input_as_handled()
