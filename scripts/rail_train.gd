class_name RailTrain
extends Node3D

## Pociąg na wiadukcie kolejowym nad autostradą (etap 3c urozmaiceń,
## StructurePlan: `train`, `freight`). Kinematyczny - bez fizyki i kolizji
## (jedzie 4,4-6,5 m nad jezdnią po torze w poprzek drogi). Lokomotywa
## i wagony z prostych brył w jednej siatce, cały skład jedzie wzdłuż
## lokalnej osi X węzła; po przejechaniu `run` metrów znika.
## Węzeł w grupie WorldOrigin.GROUP (przesunięcie świata przesuwa go razem
## z trasą).

const CAR_LEN := 15.0                  # [m] wagon z odstępem
const GAUGE_W := 3.0                   # [m] szerokość pudła

var speed := 22.0                      # [m/s]
var v_nom := 22.0                      # [m/s] prędkość rozkładowa
## Dopasowanie do gracza (xr_main._sync_trains): czoło nad drogą, gdy gracz
## jest ~250 m przed wiaduktem. center - punkt środka drogi na torze
## (współrzędna X węzła w chwili wypuszczenia), length - długość składu.
var front_left := INF                  # [m] czoło do środka drogi
var length := 0.0
var run := 1600.0                      # [m] do zniknięcia
var travelled := 0.0


## n_cars - liczba wagonów (bez lokomotywy), freight - towarowy (kolory,
## kształt), dir - +1 / -1 wzdłuż osi X węzła.
func build(n_cars: int, freight: bool, dir: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var loco := BoxMesh.new()
	loco.size = Vector3(17.0, 3.8, GAUGE_W)
	_add(st, loco, Vector3(0.0, 2.3, 0.0), Color(0.75, 0.12, 0.08) if not freight else Color(0.15, 0.25, 0.15))
	for i in range(n_cars):
		var bm := BoxMesh.new()
		var h := 3.6 if not freight else (2.4 if i % 3 == 0 else 3.2)
		bm.size = Vector3(CAR_LEN - 1.2, h, GAUGE_W)
		var col: Color = Color(0.2, 0.32, 0.55) if not freight else \
				[Color(0.45, 0.25, 0.15), Color(0.3, 0.3, 0.32), Color(0.5, 0.42, 0.2)][i % 3]
		_add(st, bm, Vector3(-dir * (CAR_LEN * (i + 1) + 1.0), 0.6 + h * 0.5, 0.0), col)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.7
	st.set_material(m)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	set_meta("dir", dir)
	length = 17.0 + n_cars * CAR_LEN


func _add(st: SurfaceTool, mesh: Mesh, at: Vector3, col: Color) -> void:
	var arr := mesh.surface_get_arrays(0)
	var n: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var cols := PackedColorArray()
	cols.resize(n)
	cols.fill(col)
	arr[Mesh.ARRAY_COLOR] = cols
	var tmp := ArrayMesh.new()
	tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	st.append_from(tmp, 0, Transform3D(Basis(), at))


func _physics_process(delta: float) -> void:
	var step := speed * delta
	translate(Vector3(float(get_meta("dir", 1.0)) * step, 0.0, 0.0))
	travelled += step
	front_left -= step
	if travelled > run:
		queue_free()
