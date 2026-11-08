// Skała z tekstur (użytkownik dodał katalog textures/): ściany wąwozu -
// "cavern walls", góry nad tunelami - "ocean rock", zielone części (mech
// na zboczach w cieniu) - "mossy rock" (fragment atlasu przerobiony na
// powtarzalny: textures/derived/moss_*). Która skała - ustawia materiał
// (StuntTrack._rock_material).
//
// Siatki ścian nie mają sensownych UV, więc mapowanie trójpłaszczyznowe
// w układzie świata: trzy rzuty (z osi X, Y, Z) mieszane wagą z normalnej.
// Rzut o znikomej wadze pomijamy (Quest: mniej odczytów tekstur).
// Normalne z map łączone metodą "whiteout" (Golus), mapy w konwencji
// OpenGL - jak w Godocie.
shader_type spatial;

uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float rock_scale = 0.16;          // powtórzeń na metr (1/rozmiar kafla)
uniform sampler2D moss_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float moss_scale = 0.4;
// Tekstura mchu jest oliwkowo-brązowa i ginęła na brązowej skale w cieniu -
// lekkie podbicie zieleni, żeby "zielone części" zostały zielone.
uniform vec3 moss_tint = vec3(0.9, 1.25, 0.7);
uniform float rock_roughness = 0.9;
uniform float normal_dist = 40.0;         // [m] dalej bez map normalnych (Quest)

// Zbocza "północne" porasta mech. "Północ" to kierunek przeciwny do słońca
// w poziomie (słońce w scenach stoi na południowym wschodzie) - strona
// stale w cieniu. Trasa biegnie głównie na -Z, więc ściany patrzą na
// wschód i zachód; przy północy = -Z mchu prawie nie było widać.
uniform vec2 north_dir = vec2(-0.57, -0.82);
uniform float moss_amount = 1.0;          // 0 = bez mchu

varying vec3 wpos;
varying vec3 wnorm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec3 tri_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(6.0));
	return w / (w.x + w.y + w.z);
}

// Kolor i normalna (świat) z trzech rzutów.
// with_normal = false: tylko kolor (daleko od oka - rzeźby i tak nie widać,
// a to połowa odczytów tekstur).
void triplanar(sampler2D alb, sampler2D nrm, vec3 p, vec3 n, vec3 w, bool with_normal,
		out vec3 col, out vec3 nw) {
	col = vec3(0.0);
	vec3 acc = vec3(0.0);
	if (w.x > 0.02) {
		vec2 uv = p.zy;
		col += texture(alb, uv).rgb * w.x;
		if (with_normal) {
			vec3 t = texture(nrm, uv).xyz * 2.0 - 1.0;
			t = vec3(t.xy + n.zy, abs(t.z) * n.x);
			acc += t.zyx * w.x;
		}
	}
	if (w.y > 0.02) {
		vec2 uv = p.xz;
		col += texture(alb, uv).rgb * w.y;
		if (with_normal) {
			vec3 t = texture(nrm, uv).xyz * 2.0 - 1.0;
			t = vec3(t.xy + n.xz, abs(t.z) * n.y);
			acc += t.xzy * w.y;
		}
	}
	if (w.z > 0.02) {
		vec2 uv = p.xy;
		col += texture(alb, uv).rgb * w.z;
		if (with_normal) {
			vec3 t = texture(nrm, uv).xyz * 2.0 - 1.0;
			t = vec3(t.xy + n.xy, abs(t.z) * n.z);
			acc += t.xyz * w.z;
		}
	}
	float ws = (w.x > 0.02 ? w.x : 0.0) + (w.y > 0.02 ? w.y : 0.0) + (w.z > 0.02 ? w.z : 0.0);
	col /= max(ws, 0.001);
	nw = with_normal ? normalize(acc + n * 0.001) : n;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnorm);
	vec3 w = tri_weights(n);
	// Mapy normalnych tylko blisko (VERTEX w układzie kamery).
	bool near = length(VERTEX) < normal_dist;
	vec3 col;
	vec3 nw;
	triplanar(rock_albedo, rock_normal, wpos * rock_scale, n, w, near, col, nw);

	// Mech: strona w cieniu, plamy szumu, gęściej nisko (wilgoć spływa).
	vec2 hn = n.xz / max(length(n.xz), 0.001);
	float north = smoothstep(0.1, 0.55, dot(hn, north_dir)) * (1.0 - smoothstep(0.5, 0.9, n.y));
	float moss_a = 0.0;
	if (north * moss_amount > 0.0) {
		float along = wpos.x + wpos.z;
		float m = vnoise(vec2(along, wpos.y) * 0.35) * 0.7 + vnoise(vec2(along, wpos.y) * 2.5) * 0.3;
		m += clamp(1.0 - (wpos.y - 6.0) / 25.0, 0.0, 1.0) * 0.15;
		moss_a = smoothstep(0.32, 0.46, m) * north * moss_amount;
	}
	if (moss_a > 0.01) {
		vec3 mc;
		vec3 mn;
		triplanar(moss_albedo, moss_normal, wpos * moss_scale, n, w, near, mc, mn);
		col = mix(col, mc * moss_tint, moss_a);
		nw = normalize(mix(nw, mn, moss_a));
	}
	ALBEDO = col;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ROUGHNESS = rock_roughness;
}
