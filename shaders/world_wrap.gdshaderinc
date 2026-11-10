// Szum okresowy dla shaderów liczonych z pozycji w świecie, odporny na
// przesuwanie początku świata (scripts/world_origin.gd).
//
// Dziś ground/concrete/rock/shale/ocean liczą wzory z wpos (float32)
// i hash(sin(dot(p, ...)) * 43758) - przy setkach km w świecie sin dużych
// argumentów rozsypuje się w szum, a po przesunięciu świata wzór by
// "przeskoczył". Zamiast tego:
//   vec2 p = wpos.xz + world_origin_wrap.xz;   // < ~WRAP + kilka km
//   float n = pvnoise(p, 50.0);               // oczko 50 m, okres WRAP
// Oczko (cell) musi dzielić WRAP (6000 m: 0,5 / 0,6667 / 1 / 2 / 3,333 / 5 /
// 10 / 50 / 83,33 / 100 / 250 / 1000 ...), wtedy wzór jest ciągły przy
// przesunięciu o dowolną wielokrotność QUANTUM.
//
// Wymaga w project.godot:
//   [shader_globals]
//   world_origin_wrap={ "type": "vec3", "value": Vector3(0, 0, 0) }
// (WorldOrigin ustawia go po każdym przesunięciu).

global uniform vec3 world_origin_wrap;

const float WORLD_WRAP = 6000.0;

// Hash całkowitych współrzędnych oczka (małe liczby - sin trzyma precyzję).
float wrap_hash(vec2 i) {
	return fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
}

// Szum wartości z okresem WORLD_WRAP; cell = rozmiar oczka [m].
float pvnoise(vec2 p, float cell) {
	float n = floor(WORLD_WRAP / cell + 0.5);   // oczek na okres
	vec2 q = p / cell;
	vec2 i = floor(q);
	vec2 f = fract(q);
	vec2 i0 = mod(i, n);
	vec2 i1 = mod(i + 1.0, n);
	float a = wrap_hash(i0);
	float b = wrap_hash(vec2(i1.x, i0.y));
	float c = wrap_hash(vec2(i0.x, i1.y));
	float d = wrap_hash(i1);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Pozycja do wzorów: wpos (lokalna) + offset modulo okres.
vec2 world_xz(vec3 wpos) {
	return wpos.xz + world_origin_wrap.xz;
}
