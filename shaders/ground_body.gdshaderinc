// Wspólna treść ground.gdshader i ground_river.gdshader (etap 3a).
uniform vec3 grass_a : source_color = vec3(0.27, 0.40, 0.18);
uniform vec3 grass_b : source_color = vec3(0.42, 0.47, 0.22);
uniform vec3 dirt : source_color = vec3(0.42, 0.36, 0.25);
uniform vec3 b_grass_a : source_color = vec3(0.27, 0.40, 0.18);
uniform vec3 b_grass_b : source_color = vec3(0.42, 0.47, 0.22);
uniform vec3 b_dirt : source_color = vec3(0.42, 0.36, 0.25);
uniform float biome_t = 0.0;
// Pola uprawne: pasy upraw (0 = brak).
uniform float stripes_a = 0.0;
uniform float stripes_b = 0.0;

varying vec3 wpos;
// Rzeka pod mostem (tylko wariant ground_river.gdshader).
uniform vec2 river_c = vec2(0.0, 0.0);
uniform vec2 river_t = vec2(0.0, 1.0);
uniform float river_hw = 0.0;
uniform float river_reach = 700.0;

vec3 palette(vec2 p, vec3 ga, vec3 gb, vec3 dr, float stripes) {
	// Oczka dzielą WORLD_WRAP (6000 m): 250, 50, 3,333, 0,6667.
	float big = pvnoise(p, 250.0) * 0.6 + pvnoise(p, 50.0) * 0.4;
	float small = pvnoise(p, 3.3333333) * 0.5 + pvnoise(p, 0.6666667) * 0.5;
	vec3 col = mix(ga, gb, big);
	if (stripes > 0.0) {
		// Pasy pól ~40 m szerokości w kratkach ~250 m, różne odcienie.
		float field = pvnoise(p, 250.0);
		float band = step(0.5, fract(p.x / 40.0 + field * 3.0));
		col = mix(col, mix(ga, dr, 0.5 + 0.5 * field), band * stripes * 0.6);
	}
	col *= 0.85 + 0.25 * small;
	col = mix(col, dr, smoothstep(0.72, 0.8, pvnoise(p + vec2(583.0, 0.0), 83.333333)) * 0.7);
	return col;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
#ifdef RIVER_HOLE
	// Dziura na rzekę pod mostem (etap 3a): pas wzdłuż osi drogi w ±river_hw
	// od środka rzeki, w poprzek do river_reach. discard tylko w tym
	// wariancie (wyłącza wczesny test głębi - na Queście tylko przy moście).
	vec2 rv = wpos.xz - river_c;
	if (abs(dot(rv, river_t)) < river_hw && abs(dot(rv, vec2(-river_t.y, river_t.x))) < river_reach) {
		discard;
	}
#endif
	vec2 p = world_xz(wpos);
	vec3 col = palette(p, grass_a, grass_b, dirt, stripes_a);
	if (biome_t > 0.001) {
		col = mix(col, palette(p, b_grass_a, b_grass_b, b_dirt, stripes_b), biome_t);
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
