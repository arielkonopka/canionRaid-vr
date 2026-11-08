// Asfalt jezdni: ziarno, linie, krawężniki - wszystko w shaderze, bez
// dodatkowej geometrii. UV jezdni (StuntTrack._build_mesh):
//   UV.x  - odległość od osi toru w poprzek [m], dodatnia w prawo
//   UV.y  - dystans wzdłuż toru [m]
//   UV2.x - szerokość jezdni w tym miejscu [m]
// Nawierzchnia: wetness (mokra) i ice (lód) jako parametry materiału.
shader_type spatial;
render_mode cull_back;

// Kolory nawierzchni (użytkownik): sucha #404040, mokra #101010,
// oblodzona #304070. Ustawiane per materiał w StuntTrack._surface_material.
uniform vec3 asphalt : source_color = vec3(0.251, 0.251, 0.251);
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float ice : hint_range(0.0, 1.0) = 0.0;

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float w = UV2.x;
	float hw = 0.5 * w;
	float au = abs(u);

	// Ziarno asfaltu w dwóch skalach + łaty naprawianej nawierzchni.
	float grain = vnoise(wpos.xz * 9.0) * 0.5 + vnoise(wpos.xz * 1.7) * 0.5;
	float patches = smoothstep(0.62, 0.7, vnoise(vec2(u * 0.35, v * 0.06)));
	vec3 col = asphalt * (0.82 + 0.32 * grain) * (1.0 - 0.12 * patches);
	// Koleiny: ciemniejsze pasy w środku każdego pasa ruchu.
	float lane_w = (w - 1.0) / 3.0;
	float rut = 0.0;
	for (int k = -1; k <= 1; k++) {
		float c = float(k) * lane_w;
		rut += exp(-pow((abs(u - c) - 0.75) / 0.35, 2.0));
	}
	col *= 1.0 - 0.10 * rut;

	// Linie: ciągłe krawędziowe, przerywane między pasami (6 m linii, 6 m przerwy).
	float edge = step(hw - 0.62, au) * step(au, hw - 0.47);
	float divider = 0.0;
	for (int k = -1; k <= 1; k += 2) {
		float c = float(k) * lane_w * 0.5;
		divider = max(divider, step(abs(u - c), 0.06) * step(mod(v, 12.0), 6.0));
	}
	float paint = max(edge, divider) * (0.85 + 0.15 * grain);
	col = mix(col, vec3(0.88, 0.88, 0.84), paint * (1.0 - 0.8 * ice));

	// Krawężnik: zewnętrzne 0,35 m, biało-czerwone pasy co 1 m.
	float curb = step(hw - 0.35, au);
	float stripe = step(mod(v, 2.0), 1.0);
	col = mix(col, mix(vec3(0.72, 0.08, 0.06), vec3(0.9, 0.9, 0.88), stripe), curb);

	float rough = mix(0.88, 0.5, paint);
	// Mokro i lód: kolor bazowy podaje uniform asphalt (#101010 / #304070);
	// tu tylko gładkość - mokra odbija niebo, lód szklisty.
	rough = mix(rough, 0.10, wetness);
	rough = mix(rough, 0.04, ice);

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = mix(0.35, 0.75, max(wetness, ice));
}
