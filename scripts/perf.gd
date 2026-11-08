class_name Perf

## Lekkie liczniki czasu na goglach: ile ms na sekundę zjada każda część
## gry. Zbierane przez Perf.add(...), wypisywane i zerowane co 5 s przez
## xr_main._log_perf ("PERF+" w logu: ./quest.sh log).

static var _acc := {}


static func add(key: String, t0_usec: int) -> void:
	_acc[key] = _acc.get(key, 0) + (Time.get_ticks_usec() - t0_usec)


## "klucz ms/s ..." posortowane od największego, i zerowanie.
static func dump(seconds: float) -> String:
	var keys: Array = _acc.keys()
	keys.sort_custom(func(a, b): return _acc[a] > _acc[b])
	var parts := PackedStringArray()
	for k in keys:
		parts.append("%s %.0f" % [k, _acc[k] / 1000.0 / seconds])
	_acc.clear()
	return " ".join(parts)
