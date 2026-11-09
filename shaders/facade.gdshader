// Elewacja budynku z trybu "Autostrada" (HighwayScenery): proceduralne
// okna na prostej bryle (pudło 1×1×1 skalowane w instancji MultiMesh).
// Siatka okien liczona w metrach budynku (VERTEX × skala instancji), nie
// w układzie świata - nie zależy od przesuwania początku świata
// (WorldOrigin) i nie potrzebuje UV ani tekstury.
// Kolor tynku: kolor wierzchołka × kolor instancji (COLOR).
// Docelowo (lista mediów): albedo/normal tynku z ambientCG mnożone tutaj
// przez kolor - patrz docs/AUTOSTRADA.md, "Media".
shader_type spatial;
render_mode cull_back;

uniform float floor_h = 3.0;        // wysokość kondygnacji [m]
uniform float bay_w = 2.8;          // odstęp okien w poziomie [m]
uniform float ground_floor = 1.2;   // od tej wysokości okna [m]
uniform vec3 glass_color : source_color = vec3(0.07, 0.09, 0.11);
uniform vec3 frame_color : source_color = vec3(0.82, 0.82, 0.80);

varying vec3 bpos;
varying vec3 bnorm;

void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	bpos = VERTEX * sc;
	bnorm = NORMAL;
}

void fragment() {
	vec3 base = COLOR.rgb;
	float wall = 1.0 - step(0.5, abs(bnorm.y));
	// Współrzędna wzdłuż ściany: ściany boczne (normalna ±X) idą po Z.
	float h = abs(bnorm.x) > 0.5 ? bpos.z : bpos.x;
	vec2 f = fract(vec2(h / bay_w, bpos.y / floor_h));
	float in_x = step(0.22, f.x) * step(f.x, 0.78);
	float in_y = step(0.30, f.y) * step(f.y, 0.85);
	float frame_x = step(0.19, f.x) * step(f.x, 0.81);
	float frame_y = step(0.27, f.y) * step(f.y, 0.88);
	float above = step(ground_floor, bpos.y);
	float win = wall * above * in_x * in_y;
	float frame = wall * above * frame_x * frame_y * (1.0 - win);
	// Dach (normalna w górę) ciemniejszy - papa / blacha.
	vec3 roof = base * 0.45;
	vec3 col = mix(base, roof, 1.0 - wall);
	col = mix(col, frame_color, frame);
	col = mix(col, glass_color, win);
	ALBEDO = col;
	ROUGHNESS = mix(0.88, 0.12, win);
	SPECULAR = mix(0.4, 0.7, win);
}
