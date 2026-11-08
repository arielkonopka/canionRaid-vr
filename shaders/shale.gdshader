// Łupek: skała osadowa z mułu odkładanego przez miliony lat na dnie
// spokojnego morza. Cienkie, poziome warstwy (laminacja) w odcieniach
// szaroniebieskich, ciemnoszarych i rdzawych; co kilkadziesiąt cm
// wyraźniejsza szczelina, po której skała łupie się na płyty.
// Warstwy w układzie świata (wysokość), więc ciągną się przez cały wąwóz.
shader_type spatial;

uniform vec3 shale_a : source_color = vec3(0.36, 0.38, 0.40);
uniform vec3 shale_b : source_color = vec3(0.24, 0.25, 0.27);
uniform vec3 rust : source_color = vec3(0.46, 0.33, 0.22);
uniform vec3 gravel : source_color = vec3(0.45, 0.43, 0.39);
// Zbocza północne porasta mech i bluszcz (prośba użytkownika). "Północ" to
// kierunek przeciwny do słońca w poziomie (słońce w scenach stoi na
// południowym wschodzie: światło biegnie w (-0,37, -0,53) po x, z) - to
// strona stale w cieniu. Trasa biegnie głównie na -Z, więc ściany patrzą
// na wschód i zachód; przy północy = -Z mchu prawie nie było widać.
uniform vec2 north_dir = vec2(-0.57, -0.82);
uniform vec3 moss : source_color = vec3(0.33, 0.50, 0.15);
uniform vec3 ivy : source_color = vec3(0.14, 0.36, 0.10);

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

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Warstwy lekko falują w poziomie (osady nie były idealnie płaskie).
	float wave = vnoise(wpos.xz * 0.01) * 3.0 + vnoise(wpos.xz * 0.08) * 0.4;
	float y = wpos.y + wave;
	// Pakiety warstw ~0,8-2 m: kolor pakietu z szumu po numerze warstwy.
	float bed = floor(y / 1.3);
	float tone = hash(vec2(bed, 3.7));
	vec3 col = mix(shale_a, shale_b, tone);
	col = mix(col, rust, step(0.82, hash(vec2(bed, 9.1))) * 0.7);
	// Laminacja: drobne, ciemniejsze linie co kilka cm.
	float lam = smoothstep(0.85, 1.0, fract(y * 6.0 + vnoise(wpos.xz * 0.5) * 0.3));
	col *= 1.0 - 0.18 * lam;
	// Szczeliny między pakietami - głębokie, ciemne.
	float split = smoothstep(0.93, 1.0, fract(y / 1.3));
	col *= 1.0 - 0.45 * split;
	// Ziarno i plamy wietrzenia.
	col *= 0.85 + 0.3 * vnoise(vec2(wpos.x + wpos.z, wpos.y) * 2.0);
	// Poziome półki i dno: rumosz (łupek kruszy się na płaskie płytki).
	float flat_ = smoothstep(0.6, 0.85, wnorm.y);
	col = mix(col, gravel * (0.8 + 0.3 * vnoise(wpos.xz * 3.0)), flat_);
	// Północ: ile ściana patrzy na -Z (w poziomie), z miękkim przejściem.
	vec2 hn = wnorm.xz / max(length(wnorm.xz), 0.001);
	float north = smoothstep(0.1, 0.55, dot(hn, north_dir)) * (1.0 - smoothstep(0.5, 0.9, wnorm.y));
	if (north > 0.0) {
		float along = wpos.x + wpos.z;
		// Mech: plamy, gęściej w szczelinach i nisko (wilgoć spływa w dół).
		float m = vnoise(vec2(along, wpos.y) * 0.35) * 0.7 + vnoise(vec2(along, wpos.y) * 2.5) * 0.3;
		m += split * 0.35 + clamp(1.0 - (wpos.y - 6.0) / 25.0, 0.0, 1.0) * 0.15;
		float moss_a = smoothstep(0.38, 0.56, m) * north;
		vec3 mc = moss * (0.75 + 0.5 * vnoise(vec2(along, wpos.y) * 9.0));
		col = mix(col, mc, moss_a);
		// Bluszcz: pędy zwisające pionowo z góry (szum rozciągnięty w pionie),
		// z drobnym ziarnem liści.
		float strand = vnoise(vec2(along * 1.6, wpos.y * 0.06));
		float leaves = vnoise(vec2(along, wpos.y) * 14.0);
		float ivy_a = smoothstep(0.58, 0.68, strand) * smoothstep(0.3, 0.55, leaves) * north;
		col = mix(col, ivy * (0.7 + 0.6 * leaves), ivy_a);
	}
	ALBEDO = col;
	ROUGHNESS = 0.92;
}
