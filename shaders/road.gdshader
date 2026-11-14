// Asfalt jezdni: ziarno, linie, krawężniki - wszystko w shaderze, bez
// dodatkowej geometrii. UV jezdni (StuntTrack._build_mesh):
//   UV.x  - odległość od osi toru w poprzek [m], dodatnia w prawo
//   UV.y  - dystans wzdłuż toru [m]
//   UV2.x - szerokość jezdni w tym miejscu [m]
//   UV2.y - tunel (plan wydajności G1): 0 = otwarta droga (domyślnie, bez
//           zmian), (0, 1] = pojedyncza rura, [-1, 0) = dwie nitki;
//           |UV2.y| = jak bardzo "w środku" (łagodnie przy wylotach).
// Nawierzchnia: wetness (mokra) i ice (lód) jako parametry materiału.
shader_type spatial;
render_mode cull_back;

// Kolory nawierzchni (użytkownik): sucha #404040, mokra #101010,
// oblodzona #304070. Ustawiane per materiał w StuntTrack._surface_material.
uniform vec3 asphalt : source_color = vec3(0.251, 0.251, 0.251);
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float ice : hint_range(0.0, 1.0) = 0.0;
// Układ pasów: 0 = wąwóz (3 pasy, krawężniki), 1 = autostrada 2+2, nasza
// jezdnia (opaska 0,75 m z lewej, pas awaryjny 3 m z prawej, bez
// krawężników), 2 = autostrada, jezdnia z naprzeciwka (lustrzanie),
// 3 = rozbieg i stół wielkiej skoczni (pasy poprzeczne).
uniform int layout = 0;

// Jarzeniówki w tunelu bez OmniLight3D (G1): pas lamp co 2 m w szczycie
// rury działa jak źródło liniowe na wysokości H nad osią rury. Na
// jezdni w odległości d w poprzek od osi: natężenie ~ cos/odległość =
// H/(H² + d²), względem miejsca pod lampą H²/(H² + d²).
uniform vec3 tunnel_lamp : source_color = vec3(0.85, 0.95, 1.0);
uniform float tunnel_lamp_energy = 0.9;
uniform float tunnel_lamp_h = 11.0;       // szczyt rury nad jezdnią [m]
uniform float tunnel_island_w = 5.0;      // TrackGenerator.ISLAND_W
uniform float tunnel_daylight = 0.1;      // ile słońca i nieba zostaje w rurze

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
	float paint = 0.0;
	float works = 0.0;
	float curb = 0.0;
	float stripe = 0.0;
	if (layout == 1 || layout == 2) {
		// Autostrada (HighwayGenerator: LANE_W 3,75, SHOULDER_L 0,75,
		// SHOULDER_R 3,0). uu od lewej krawędzi (od pasa rozdziału).
		float uu = (layout == 2 ? -u : u) + hw;
		float rut_h = 0.0;
		for (int k = 0; k < 2; k++) {
			float c = 0.75 + 3.75 * (float(k) + 0.5);
			rut_h += exp(-pow((abs(uu - c) - 0.75) / 0.35, 2.0));
		}
		col *= 1.0 - 0.10 * rut_h;
		float edge_l = step(0.6, uu) * step(uu, 0.75);
		float edge_r = step(w - 3.0, uu) * step(uu, w - 2.85);
		float div = step(abs(uu - 4.5), 0.075) * step(mod(v, 12.0), 6.0);
		// Roboty (COLOR.r, etap 2b): linia między kierunkami ciągła.
		works = layout == 1 ? COLOR.r : 0.0;
		div = max(div, step(0.5, works) * step(abs(uu - 4.5), 0.075));
		paint = max(max(edge_l, edge_r), div) * (0.85 + 0.15 * grain);
	} else if (layout == 3) {
		// Wielka skocznia: biało-czerwone pasy poprzeczne co 2 m na całej
		// szerokości - widoczna z daleka.
		curb = 0.85;
		stripe = step(mod(v, 4.0), 2.0);
	} else {
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
		paint = max(edge, divider) * (0.85 + 0.15 * grain);
		// Krawężnik: zewnętrzne 0,35 m, biało-czerwone pasy co 1 m.
		curb = step(hw - 0.35, au);
		stripe = step(mod(v, 2.0), 1.0);
	}
	// Linie tymczasowe robót żółte.
	vec3 line_col = mix(vec3(0.88, 0.88, 0.84), vec3(0.95, 0.72, 0.05), step(0.5, works));
	col = mix(col, line_col, paint * (1.0 - 0.8 * ice));
	col = mix(col, mix(vec3(0.72, 0.08, 0.06), vec3(0.9, 0.9, 0.88), stripe), curb);

	float rough = mix(0.88, 0.5, paint);
	// Mokro i lód: kolor bazowy podaje uniform asphalt (#101010 / #304070);
	// tu tylko gładkość - mokra odbija niebo, lód szklisty.
	rough = mix(rough, 0.10, wetness);
	rough = mix(rough, 0.04, ice);

	ALBEDO = col;
	ROUGHNESS = rough;

	// Tunel: światło lamp jako emisja (albedo × natężenie), słońce i niebo
	// przyciemnione przez AO (bez cieni dalej niż 80 m świeciłyby w rurze).
	float enc = clamp(abs(UV2.y), 0.0, 1.0);
	// Dwie nitki: osie rur w ±(szerokość + wyspa)/4 od osi całej jezdni.
	float lamp_x = UV2.y < 0.0 ? (w + tunnel_island_w) * 0.25 : 0.0;
	float dl = au - lamp_x;
	float h2 = tunnel_lamp_h * tunnel_lamp_h;
	EMISSION = col * tunnel_lamp * (tunnel_lamp_energy * enc * h2 / (h2 + dl * dl));
	AO = 1.0 - (1.0 - tunnel_daylight) * enc;
	AO_LIGHT_AFFECT = enc;
	SPECULAR = mix(0.35, 0.75, max(wetness, ice));
}
