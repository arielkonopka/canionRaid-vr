extends Node
class_name EnvAudio

## Akustyka otoczenia dla dźwięków auta (prośba użytkownika: auto ma brzmieć
## inaczej w wąwozie, w tunelu i w deszczu). Osobna szyna "Env" z pogłosem
## i echem; CarAudio i klaksony botów grają na niej.
##   WĄWÓZ  - krótkie echo od ścian: lewa ściana w lewym kanale, prawa
##            w prawym, opóźnienie = droga tam i z powrotem (343 m/s),
##            ściszone z odległością; lekki, otwarty pogłos.
##   TUNEL  - gęsty, długi pogłos, echo ze sprzężeniem (trzepotanie między
##            ścianami), mało tłumienia - beton.
##   DESZCZ - pogłos bardziej stłumiony (mokre powietrze i szum deszczu
##            gaszą górę pasma); syk opon na mokrym jest w CarAudio.
## Odległości ścian mierzy scena jazdy promieniami (set_walls).

const BUS := "Env"
const RATE := 2.5                    # 1/s - płynność przejść

var _bus := -1
var _rev: AudioEffectReverb
var _echo: AudioEffectDelay
var _tunnel := 0.0
var _tunnel_t := 0.0
var _rain := 0.0
var _rain_t := 0.0
var _wl := 30.0
var _wr := 30.0
var _wl_t := 30.0
var _wr_t := 30.0


## Szyna "Env" (tworzona raz na całą grę - AudioServer jest globalny).
static func ensure_bus() -> int:
	var i := AudioServer.get_bus_index(BUS)
	if i >= 0:
		return i
	AudioServer.add_bus()
	i = AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, BUS)
	AudioServer.set_bus_send(i, "Master")
	var echo := AudioEffectDelay.new()
	echo.dry = 1.0
	echo.tap1_active = true
	echo.tap2_active = true
	echo.feedback_active = false
	AudioServer.add_bus_effect(i, echo)
	var rev := AudioEffectReverb.new()
	rev.dry = 1.0
	AudioServer.add_bus_effect(i, rev)
	return i


func _ready() -> void:
	_bus = ensure_bus()
	_echo = AudioServer.get_bus_effect(_bus, 0) as AudioEffectDelay
	_rev = AudioServer.get_bus_effect(_bus, 1) as AudioEffectReverb
	_apply()


func set_env(in_tunnel: bool, rain: float) -> void:
	_tunnel_t = 1.0 if in_tunnel else 0.0
	_rain_t = clampf(rain / 2.0, 0.0, 1.0)


## Odległość ścian [m] po lewej i prawej (INF/duża = brak ściany).
func set_walls(left: float, right: float) -> void:
	_wl_t = minf(left, 60.0)
	_wr_t = minf(right, 60.0)


func _process(delta: float) -> void:
	var k := minf(RATE * delta, 1.0)
	_tunnel = lerpf(_tunnel, _tunnel_t, k)
	_rain = lerpf(_rain, _rain_t, k)
	_wl = lerpf(_wl, _wl_t, k)
	_wr = lerpf(_wr, _wr_t, k)
	_apply()


func _apply() -> void:
	if _echo == null or _rev == null:
		return
	# Echo: opóźnienie tam i z powrotem; głośność spada z drogą.
	var t := _tunnel
	for side in [0, 1]:
		var d := _wl if side == 0 else _wr
		var ms := clampf(2.0 * d / 343.0 * 1000.0, 8.0, 350.0)
		var db := lerpf(-9.0, -40.0, clampf((d - 3.0) / 45.0, 0.0, 1.0))
		db = lerpf(db, -8.0, t)
		if side == 0:
			_echo.tap1_delay_ms = ms
			_echo.tap1_level_db = db
			_echo.tap1_pan = -0.8
		else:
			_echo.tap2_delay_ms = ms
			_echo.tap2_level_db = db
			_echo.tap2_pan = 0.8
	# Tunel: trzepoczące echo między ścianami.
	_echo.feedback_active = t > 0.05
	_echo.feedback_delay_ms = clampf(2.0 * (_wl + _wr) * 0.5 / 343.0 * 1000.0, 15.0, 120.0)
	_echo.feedback_level_db = lerpf(-30.0, -7.0, t)
	_echo.feedback_lowpass = 4000.0
	# Pogłos: wąwóz otwarty u góry (krótko, mało), tunel zamknięty (długo).
	_rev.room_size = lerpf(0.35, 0.85, t)
	_rev.damping = lerpf(0.45, 0.25, t) + 0.35 * _rain
	_rev.spread = 0.8
	_rev.predelay_msec = lerpf(30.0, 15.0, t)
	_rev.predelay_feedback = lerpf(0.2, 0.5, t)
	_rev.hipass = 0.1
	_rev.wet = lerpf(0.08, 0.32, t) * (1.0 - 0.3 * _rain)
	_rev.dry = 1.0
