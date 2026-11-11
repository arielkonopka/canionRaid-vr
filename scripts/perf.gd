class_name Perf

## Lekkie liczniki czasu na goglach: ile ms na sekundę zjada każda część
## gry i najdłuższe pojedyncze wywołanie (szarpnięcia). Zbierane przez
## Perf.add(...), wypisywane i zerowane co 5 s przez xr_main._log_perf
## ("PERF+ ms/s" w logu: ./quest.sh log). Znaczniki zdarzeń (Perf.mark)
## przypisują najdłuższą klatkę do tego, co się w niej działo (plan
## wydajności, etap 0).

static var _acc := {}
static var _max := {}
static var _events := PackedStringArray()


static func add(key: String, t0_usec: int) -> void:
	var dt := Time.get_ticks_usec() - t0_usec
	_acc[key] = _acc.get(key, 0) + dt
	if dt > _max.get(key, 0):
		_max[key] = dt


## Licznik zdarzeń (np. kopie próbek) - w "PERF+" jako "klucz Nx/s"
## (suma jak czas: dump dzieli przez sekundy; maks nieistotny).
static var _cnt := {}
static func count(key: String, n := 1) -> void:
	_cnt[key] = _cnt.get(key, 0) + n


## Znacznik zdarzenia w bieżącej klatce (bot_spawn, chunk_build, ...).
static func mark(event: String) -> void:
	if not event in _events:
		_events.append(event)


## Zdarzenia zebrane od ostatniego wywołania (= w poprzedniej klatce).
static func take_events() -> PackedStringArray:
	var e := _events
	_events = PackedStringArray()
	return e


## "klucz suma/maks ..." posortowane od największej sumy [ms/s, ms], i zerowanie.
static func dump(seconds: float) -> String:
	var keys: Array = _acc.keys()
	keys.sort_custom(func(a, b): return _acc[a] > _acc[b])
	var parts := PackedStringArray()
	for k in keys:
		parts.append("%s %.0f/%.1f" % [k, _acc[k] / 1000.0 / seconds, _max.get(k, 0) / 1000.0])
	for k in _cnt:
		parts.append("%s %.0fx/s" % [k, _cnt[k] / seconds])
	_acc.clear()
	_max.clear()
	_cnt.clear()
	return " ".join(parts)
