// Trawa: zmienność koloru w kilku skalach (płaty, kępy), w układzie świata,
// więc ziemia może jechać za autem bez "pływania" wzoru.
shader_type spatial;

uniform vec3 grass_a : source_color = vec3(0.27, 0.40, 0.18);
uniform vec3 grass_b : source_color = vec3(0.42, 0.47, 0.22);
uniform vec3 dirt : source_color = vec3(0.42, 0.36, 0.25);

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
	vec2 p = wpos.xz;
	float big = vnoise(p * 0.004) * 0.6 + vnoise(p * 0.02) * 0.4;
	float small = vnoise(p * 0.3) * 0.5 + vnoise(p * 1.5) * 0.5;
	vec3 col = mix(grass_a, grass_b, big);
	col *= 0.85 + 0.25 * small;
	col = mix(col, dirt, smoothstep(0.72, 0.8, vnoise(p * 0.012 + 7.0)) * 0.7);
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
