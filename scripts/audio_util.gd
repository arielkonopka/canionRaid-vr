class_name AudioUtil

## Dźwięki generowane w kodzie: jeden zapis AudioStreamWAV zamiast pięciu
## kopii (przegląd chmury D2). Próbki to surowe wartości całkowite:
## 16 bitów -32768..32767, 8 bitów ze znakiem -128..127 (Godot czyta
## 8 bitów ze znakiem - "128 + x" bez znaku dawało trzask na końcu sygnału).


static func wav(samples: PackedInt32Array, rate: int, bits := 16, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	if bits == 16:
		data.resize(samples.size() * 2)
		for i in range(samples.size()):
			data.encode_s16(i * 2, clampi(samples[i], -32768, 32767))
	else:
		data.resize(samples.size())
		for i in range(samples.size()):
			data[i] = clampi(samples[i], -128, 127) & 0xFF
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS if bits == 16 else AudioStreamWAV.FORMAT_8_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = samples.size()
	return w
