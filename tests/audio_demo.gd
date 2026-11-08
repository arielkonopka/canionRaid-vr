extends SceneTree
## Renderuje próbki dźwięku auta do plików WAV - do odsłuchu bez gogli.
##   godot --headless --xr-mode off -s res://tests/audio_demo.gd -- KATALOG </dev/null
## Dla każdego napędu (benzyna, diesel, elektryk) ~12 s:
##   wolne obroty → gaz do odcinki → zmiana biegu → jazda 120 km/h →
##   pisk opon → twarde lądowanie → zwolnienie.
## Synteza ta sama co w grze (CarAudio._synth), parametry podawane ręcznie.

const SCRIPT_STEPS := [
	# [czas trwania s, obroty od, obroty do, gaz, prędkość m/s, poślizg, łupnięcie]
	[1.5, 850.0, 850.0, 0.0, 0.0, 0.0, 0.0],
	[2.0, 850.0, 6800.0, 1.0, 12.0, 0.0, 0.0],
	[0.25, 6800.0, 4300.0, 0.0, 15.0, 0.0, 0.0],
	[2.0, 4300.0, 6500.0, 1.0, 30.0, 0.0, 0.0],
	[2.0, 5200.0, 5200.0, 0.4, 33.0, 0.0, 0.0],
	[1.5, 5000.0, 4500.0, 0.2, 30.0, 2.5, 0.0],
	[0.1, 4500.0, 4500.0, 0.0, 28.0, 0.0, 1.0],
	[2.5, 4500.0, 1200.0, 0.0, 28.0, 0.0, 0.0],
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "."
	for e in ["petrol", "diesel", "electric"]:
		var car := StuntCar.new()
		car.engine_type = e
		car.electric = e == "electric"
		var audio := CarAudio.new()
		audio.car = car
		var data := PackedByteArray()
		for st in SCRIPT_STEPS:
			var frames := int(st[0] * CarAudio.MIX_RATE)
			var chunk := 512
			var done := 0
			while done < frames:
				var n := mini(chunk, frames - done)
				var t := float(done) / maxf(frames, 1)
				var rpm_scale := 0.68 if e == "diesel" else (2.2 if e == "electric" else 1.0)
				audio._rpm = lerpf(st[1], st[2], t) * rpm_scale
				audio._load = st[3]
				audio._speed = st[4]
				audio._slip = st[5]
				if st[6] > 0.0 and done == 0:
					audio.thud(st[6])
				var buf := PackedVector2Array()
				buf.resize(n)
				audio._synth(buf, n)
				for v in buf:
					var s16 := int(clampf(v.x, -1.0, 1.0) * 32000.0)
					data.append(s16 & 0xFF)
					data.append((s16 >> 8) & 0xFF)
				done += n
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = int(CarAudio.MIX_RATE)
		wav.stereo = false
		wav.data = data
		var path := "%s/silnik_%s.wav" % [out, e]
		wav.save_to_wav(path)
		print("zapisano ", path, " (", data.size() / 2 / int(CarAudio.MIX_RATE), " s)")
		audio.free()
		car.free()
	quit()
