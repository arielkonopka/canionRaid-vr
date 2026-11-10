extends SceneTree
## Test leniwego grafu ulic (CityGraph) - czysta logika, bez sceny.
##   godot --headless --xr-mode off -s res://tests/city_graph_test.gd -- [ziarno] [skrzyżowania] </dev/null
## To samo sprawdza tools/city_graph_sim.py (wierny odpowiednik w Pythonie,
## ten sam hash): determinizm, symetrię krawędzi, brak ślepych zaułków,
## spójność miasta z obwodnicą, ten sam łuk z obu stron, a w jeździe losowej
## (z zawrotkami): bieżąca krawędź zawsze zbudowana w całości, skręt
## przełącza bieżącą, zbudowanych naraz nie więcej niż 11, powrót na ulicę
## daje tę samą geometrię. Kod wyjścia 1 przy błędzie.

var fails := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_v := int(args[0]) if args.size() > 0 else 4242
	var junctions := int(args[1]) if args.size() > 1 else 200
	for bounded in [false, true]:
		var b := Rect2i(Vector2i(-6, -5), Vector2i(13, 11)) if bounded else Rect2i()
		_test_graph(seed_v, b)
		_test_drive(seed_v, b, junctions)
	print("city_graph_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
	quit(1 if fails > 0 else 0)


func _check(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		if fails < 30:
			print("  BŁĄD: ", what)


func _cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in range(-6, 8):
		for j in range(-5, 7):
			out.append(Vector2i(i, j))
	return out


func _test_graph(seed_v: int, b: Rect2i) -> void:
	var c := CityGraph.new(seed_v, b)
	var c2 := CityGraph.new(seed_v, b)
	var nodes: Array[Vector2i] = []
	for n in _cells():
		_check(c.node_pos(n) == c2.node_pos(n), "node_pos %s" % n)
		for d in [Vector2i(1, 0), Vector2i(0, 1)]:
			var m: Vector2i = n + d
			_check(c.has_edge(n, m) == c.has_edge(m, n), "symetria %s-%s" % [n, m])
		if c.in_bounds(n) and c.is_node(n):
			nodes.append(n)
	var deg := [0, 0, 0, 0, 0]
	for n in nodes:
		var k := c.neighbors(n).size()
		deg[k] += 1
		_check(k >= 2, "ślepy zaułek %s" % n)
	if b.size.x > 0:
		# Spójność: z pierwszego węzła da się dojechać do każdego.
		var seen := {nodes[0]: true}
		var todo: Array[Vector2i] = [nodes[0]]
		while not todo.is_empty():
			for m in c.neighbors(todo.pop_back()):
				if not seen.has(m):
					seen[m] = true
					todo.append(m)
		_check(seen.size() == nodes.size(), "spójność %d/%d" % [seen.size(), nodes.size()])
	var a := nodes[0]
	var nb: Vector2i = c.neighbors(a)[0]
	var fw := c.edge_points(a, nb)
	var bw := c.edge_points(nb, a)
	bw.reverse()
	var same := fw.size() == bw.size()
	for k in range(mini(fw.size(), bw.size())):
		same = same and fw[k].distance_to(bw[k]) < 1e-4
	_check(same, "ten sam łuk z obu stron")
	print("bounds=%s: węzłów %d, stopnie 2:%d 3:%d 4:%d" % [b, nodes.size(), deg[2], deg[3], deg[4]])


func _test_drive(seed_v: int, b: Rect2i, junctions: int) -> void:
	var c := CityGraph.new(seed_v, b)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var s := Vector2i.ZERO
	if not c.is_node(s):
		for n in _cells():
			if c.is_node(n):
				s = n
				break
	c.start(s, c.neighbors(s)[0])
	var geo := {}
	var revisits := 0
	var max_built := 0
	var frm := c.current_a
	var to := c.current_b
	for _t in range(junctions):
		var path := c.edge_points(frm, to)
		for k in range(1, path.size()):
			revisits += _record(c, c.update(path[k]), geo)
			var cur := CityGraph.edge_key(c.current_a, c.current_b)
			_check(c.built().has(cur) and float(c.built()[cur]["len"]) < 0.0,
					"bieżąca krawędź zbudowana w całości (%s)" % cur)
			max_built = maxi(max_built, c.built().size())
		var outs: Array[Vector2i] = []
		for m in c.neighbors(to):
			if m != frm:
				outs.append(m)
		if outs.is_empty():
			outs.append(frm)
		var nxt: Vector2i = frm if rng.randf() < 0.1 else outs[rng.randi_range(0, outs.size() - 1)]
		frm = to
		to = nxt
		revisits += _record(c, c.update(c.edge_points(frm, to)[3]), geo)
		_check(CityGraph.edge_key(c.current_a, c.current_b) == CityGraph.edge_key(frm, to)
				and c.current_a == frm,
				"po skręcie bieżąca %s->%s zamiast %s->%s" % [c.current_a, c.current_b, frm, to])
	print("  jazda: %d skrzyżowań, %.1f km, zbudowanych naraz maks. %d, różnych krawędzi %d, powrotów %d"
			% [junctions, c.odometer / 1000.0, max_built, geo.size(), revisits])
	_check(max_built <= 2 + CityGraph.KEEP_BEHIND + 6 + 1, "za dużo zbudowanych naraz: %d" % max_built)
	_check(revisits > 0, "jazda nie wróciła na żadną ulicę - powrót niesprawdzony")


## Pełne krawędzie z różnicy: przy powrocie ta sama geometria. Zwraca liczbę powrotów.
func _record(c: CityGraph, d: Dictionary, geo: Dictionary) -> int:
	var n := 0
	for e in d["add"]:
		if float(e["len"]) >= 0.0:
			continue
		var key: String = e["key"]
		var ea: Vector2i = e["a"]
		var eb: Vector2i = e["b"]
		# Zawsze od mniejszego węzła - porównujemy tę samą kolejność punktów.
		var lo := ea if (ea.x < eb.x or (ea.x == eb.x and ea.y < eb.y)) else eb
		var hi := eb if lo == ea else ea
		var g := c.edge_points(lo, hi)
		if geo.has(key):
			n += 1
			var old: PackedVector2Array = geo[key]
			var same := old.size() == g.size()
			for k in range(mini(old.size(), g.size())):
				same = same and old[k].is_equal_approx(g[k])
			_check(same, "ta sama geometria po powrocie %s" % key)
		geo[key] = g
	return n
