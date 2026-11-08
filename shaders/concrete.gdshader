// Beton filarów i płyty jezdni: plamy, zacieki i drobne ziarno w układzie
// świata (bez UV), więc działa na każdej bryle.
shader_type spatial;

uniform vec3 base : source_color = vec3(0.62, 0.61, 0.58);

varying vec3 wpos;
varying vec3 wnorm;

float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = vnoise(wpos * 3.0) * 0.5 + vnoise(wpos * 0.7) * 0.5;
	// Zacieki: pionowe smugi, ciemniejsze u dołu.
	float streak = vnoise(vec3(wpos.x * 4.0, wpos.y * 0.15, wpos.z * 4.0));
	vec3 col = base * (0.8 + 0.3 * n) * (1.0 - 0.15 * smoothstep(0.5, 0.9, streak));
	ALBEDO = col;
	ROUGHNESS = 0.9;
}
