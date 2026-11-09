class_name Bench

## Pomiar porównawczy (plan wydajności, etap 0): powtarzalny przejazd
## (stałe ziarno, autem jedzie sterownik bota) i przełączniki A/B.
## Na Queście gra nie dostaje argumentów, więc konfiguracja z pliku
## user://bench.cfg (wgrywany przez adb run-as), na PC także z argumentu
## --bench=S1 [--perf-ab=mirror,rain] [--bench-time=75].
##
##   [bench]
##   scenario="S2"          ; S1 wąwóz, S2 tunel, S3 ulewa, S4 autostrada
##                          ; z 20 botami, S5 zdarzenia (wybuchy)
##   time=75.0
##   seed=4242
##   res=160                ; rozdzielczość w goglach [%] (0 = z ustawień)
##   ab="mirror,rain"       ; WYŁĄCZONE: mirror, rain, tunnel_lights,
##                          ; shadows, rock_simple
##
## Bez pliku i argumentów: gra jak zwykle (wszystko włączone).

static var scenario := ""
static var duration := 75.0
static var seed_value := 4242
static var resolution := 0            # [%] 0 = z ustawień gracza
static var off := PackedStringArray()
static var _loaded := false


static func load_config() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load("user://bench.cfg") == OK:
		scenario = str(cfg.get_value("bench", "scenario", ""))
		duration = float(cfg.get_value("bench", "time", duration))
		seed_value = int(cfg.get_value("bench", "seed", seed_value))
		resolution = int(cfg.get_value("bench", "res", resolution))
		_parse_off(str(cfg.get_value("bench", "ab", "")))
		# Jednorazowy: plik zostawiony w goglach po cichu przełączałby
		# każde następne uruchomienie w tryb pomiaru (wejście ignorowane).
		# Ustawienia zostają w zmiennych statycznych do końca procesu.
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://bench.cfg"))
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--bench="):
			scenario = a.substr(8)
		elif a.begins_with("--perf-ab="):
			_parse_off(a.substr(10))
		elif a.begins_with("--bench-time="):
			duration = float(a.substr(13))
	if active() or not off.is_empty():
		print("BENCH: scenariusz %s, %.0f s, ziarno %d, wyłączone: %s" % [
				scenario if scenario != "" else "-", duration, seed_value,
				",".join(off) if not off.is_empty() else "nic"])


static func _parse_off(s: String) -> void:
	for p in s.split(",", false):
		var k := p.strip_edges()
		if k != "" and not k in off:
			off.append(k)


static func active() -> bool:
	return scenario != ""


## Czy element A/B jest włączony (domyślnie wszystko).
static func on(feature: String) -> bool:
	return not feature in off
