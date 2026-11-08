extends SceneTree
## Zjazdy: stacja co 5 odcinków, warsztat co 10 (11., 21.), znak zjazdu
## co najmniej 800 m przed zjazdem.
##   godot --headless --xr-mode off -s res://tests/service_test.gd </dev/null
var et: EndlessTrack
var f := 0
func _initialize() -> void:
	et = EndlessTrack.new()
	et.seed_value = 777
	root.add_child(et)
func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var sign_d := {}
	var d := 10.0
	var found := 0
	while d < 16000.0 and found < 5:
		et.update_progress(d)
		for c in et._chunks:
			for s in c._samples:
				var m: Dictionary = s["meta"]
				if m.has("service_ahead"):
					sign_d[c.name] = float(s["dist"])
				if m.has("service") and not s.has("_seen"):
					s["_seen"] = true
					found += 1
					var sec: int = et.section_at(float(s["dist"]))
					print("%s: odcinek %d, zjazd na %.0f m, znak %.0f m wcześniej" % [
						m["service"]["kind"], sec, s["dist"], float(s["dist"]) - sign_d.get(c.name, -9999.0)])
		d += 400.0
	return true
