// Wnętrze rury tunelu: beton (jak concrete.gdshader) oświetlony pasem
// jarzeniówek BEZ prawdziwych świateł - plan wydajności G1
// (docs/PERF_PLAN.md). Dziś OmniLight3D co 80 m oświetla jedną wielką
// siatkę tunelu, więc każdy piksel liczy wszystkie światła naraz.
//
// Dlaczego wystarczy stała: lampy leżą gęsto (co 2 m, użytkownik) na
// szczycie rury, więc działają jak źródło liniowe. Dla źródła liniowego na
// ścianie walca natężenie na wewnętrznej ścianie jest STAŁE: punkt
// ściany odległy o kąt środkowy Δ od lampy widzi ją z odległości
// 2R·sin(Δ/2) pod kątem padania, którego cos = sin(Δ/2), a natężenie od
// linii ~ cos/odległość = 1/(2R) - niezależnie od Δ. Względem jezdni pod
// lampą (wysokość H = R·(1 + TUNNEL_YC), natężenie ~ 1/H) ściana dostaje
// H/(2R) = (1 + TUNNEL_YC)/2 ≈ 0,675.
//
// Słońce i niebo: bez cieni (dalej niż 80 m od kamery) oświetlałyby wnętrze
// - AO z AO_LIGHT_AFFECT przyciemnia je w rurze.
//
// Siatka: tylko ściany rury (ściany czołowe wylotów zostają na betonie,
// bo patrzą na zewnątrz i świeci na nie słońce).
shader_type spatial;

uniform vec3 base : source_color = vec3(0.62, 0.61, 0.58);
uniform vec3 lamp_color : source_color = vec3(0.85, 0.95, 1.0);
// Jasność jarzeniówek na jezdni pod lampą (ta sama co w road.gdshader).
uniform float lamp_energy = 0.9;
// TUNNEL_YC ze StuntTrack - środek koła rury nad jezdnią (ułamek promienia).
uniform float tunnel_yc = 0.35;
// Ile słońca i nieba zostaje w rurze (0 = nic).
uniform float daylight = 0.1;

varying vec3 wpos;

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
	// Jeden szum zamiast trzech jak w concrete.gdshader - w półmroku
	// tunelu drobnych zacieków i tak nie widać (G2 zastąpi go teksturą).
	float n = vnoise(wpos * 0.7);
	vec3 col = base * (0.8 + 0.3 * n);
	ALBEDO = col;
	ROUGHNESS = 0.9;
	EMISSION = col * lamp_color * lamp_energy * (1.0 + tunnel_yc) * 0.5;
	AO = daylight;
	AO_LIGHT_AFFECT = 1.0 - daylight;
}
