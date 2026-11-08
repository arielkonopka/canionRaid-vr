shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// Krople deszczu na przedniej szybie. Siatka to płaski czworokąt w układzie
// szyby (x w prawo, y w górę szyby, metry), więc VERTEX.xy = punkt na szybie.
// Krople przybywają z czasem od ostatniego przetarcia danego miejsca.
// Bez stanu na piksel: chwilę przetarcia liczymy z fazy cyklu wycieraczek
// (kąt ramienia = sweep * sin(PI * faza), faza 0..1 w czasie c_dur).

uniform float now = 0.0;          // czas gry [s] (podawany ze skryptu)
uniform float c_start = -1e6;     // początek bieżącego/ostatniego cyklu
uniform float c_prev = -1e6;      // początek poprzedniego cyklu
uniform float c_dur = 1.1;        // czas jednego cyklu (w górę i w dół)
uniform float sweep = 1.7;        // kąt wychylenia ramienia [rad]
uniform float arm_len = 0.66;
uniform vec2 pivot0 = vec2(-0.62, -0.33);
uniform vec2 pivot1 = vec2(0.0, -0.33);
uniform float rate = 0.0;         // tempo przybywania kropli [1/s], 0 = nie pada
uniform float opacity = 0.32;

varying vec2 g;

void vertex() {
	g = VERTEX.xy;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float last_wipe(vec2 p, vec2 pivot) {
	vec2 rel = p - pivot;
	float r = length(rel);
	if (r > arm_len || r < 0.04) {
		return -1e6;
	}
	float a = atan(rel.y, rel.x);
	if (a < 0.0 || a > sweep) {
		return -1e6;
	}
	float p1 = asin(a / sweep) / PI;            // 0..0.5: przejście w górę
	float up = c_start + p1 * c_dur;
	float down = c_start + (1.0 - p1) * c_dur;
	if (now >= down) {
		return down;
	}
	if (now >= up) {
		return up;
	}
	return c_prev + (1.0 - p1) * c_dur;
}

void fragment() {
	float since = now - max(last_wipe(g, pivot0), last_wipe(g, pivot1));
	float cover = 1.0 - exp(-since * rate);
	float cell = 0.016;
	vec2 id = floor(g / cell);
	float h1 = hash(id);
	vec2 c = (id + 0.2 + 0.6 * vec2(hash(id + 7.3), hash(id + 3.1))) * cell;
	float rad = cell * (0.07 + 0.16 * hash(id + 11.7));
	float d = length(g - c) / rad;
	float drop = (1.0 - smoothstep(0.7, 1.0, d)) * step(h1, cover);
	// Kropla jak soczewka: jaśniejszy brzeg i odblask u góry.
	float rim = smoothstep(0.45, 0.9, d);
	ALBEDO = mix(vec3(0.55, 0.6, 0.65), vec3(0.95), rim * 0.6);
	ALPHA = drop * opacity * (0.55 + 0.45 * rim);
}
