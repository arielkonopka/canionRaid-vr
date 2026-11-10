// Tańsza wersja shaders/rock.gdshader (plan wydajności G3, prośba agenta
// lokalnego z raportu 2026-11-09): te same uniformy, więc wystarczy podmienić
// shader w StuntTrack._rock_material i zmierzyć na goglach.
//
// Różnice względem rock.gdshader:
// 1. Mapowanie dwupłaszczyznowe (biplanar, I. Quilez) zamiast trzech rzutów:
//    z trzech osi bierzemy tylko dwie o największym |n| (główną i środkową).
//    Trzecia ma przy wagach |n|^k i tak znikomy udział. Odczytów skały:
//    2 albedo + 2 normalne (było do 3 + 3). Bo wybór osi zmienia się
//    skokowo między pikselami, mipmapy liczymy z pochodnych pozycji
//    (textureGrad) - inaczej na granicy wyboru osi widać szwy.
//    Wagi: w = clamp((|n| - 1/√3) / (1 - 1/√3))^blend_pow. Ciągłość:
//    oś środkowa zamienia się z najmniejszą, gdy ich |n| są równe (= y);
//    wtedy największa x >= y i x² + 2y² = 1, więc y <= 1/√3 - waga
//    zamienianej osi jest już zerem i szwu nie ma. Zamiana głównej
//    ze środkową nic nie zmienia (obie są brane).
// 2. Mech bez osobnej mapy normalnych: tylko albedo (2 odczyty, było
//    do 6), a pod mchem normalna skały wygładzona w stronę geometrycznej
//    (mech jest miękki - rzeźbę skały zasłania). moss_normal zostaje
//    jako uniform tylko dla zgodności z _rock_material - nie jest czytany.
// 3. normal_dist domyślnie 25 m (było 40) - mapa normalnych tylko blisko.
//
// Razem w najgorszym miejscu (blisko, w mchu): 6 odczytów zamiast 12.
// Daleko: 2 (skała) + 2 (mech) zamiast do 6.
shader_type spatial;

uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float rock_scale = 0.16;          // powtórzeń na metr (1/rozmiar kafla)
uniform sampler2D moss_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float moss_scale = 0.4;
uniform vec3 moss_tint = vec3(0.9, 1.25, 0.7);
uniform float rock_roughness = 0.9;
uniform float normal_dist = 25.0;         // [m] dalej bez map normalnych (Quest)
uniform vec2 north_dir = vec2(-0.57, -0.82);
uniform float moss_amount = 1.0;          // 0 = bez mchu
// Ostrość przejścia między rzutami: potęga przemapowanych wag (1 jak
// u Quileza; większa = ostrzejsze przejście, mniej rozmycia na skosach).
uniform float blend_pow = 1.0;
// Ile rzeźby skały zostaje pod pełnym mchem (0 = gładko, 1 = jak skała).
uniform float moss_relief = 0.35;

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

// Rzut na płaszczyznę prostopadłą do osi `axis` - te same UV co
// w rock.gdshader (X: zy, Y: xz, Z: xy), żeby wygląd się zgadzał.
vec2 proj(vec3 v, int axis) {
	if (axis == 0) {
		return v.zy;
	}
	if (axis == 1) {
		return v.xz;
	}
	return v.xy;
}

float comp(vec3 v, int axis) {
	if (axis == 0) {
		return v.x;
	}
	if (axis == 1) {
		return v.y;
	}
	return v.z;
}

// Mapy normalnych importowane jako "normal map" (RG) - Z z X i Y.
vec3 nrm_tap(sampler2D nrm, vec2 uv, vec2 gx, vec2 gy) {
	vec2 xy = textureGrad(nrm, uv, gx, gy).rg * 2.0 - 1.0;
	return vec3(xy, sqrt(max(1.0 - dot(xy, xy), 0.0)));
}

// Normalna "whiteout" (Golus) dla rzutu wzdłuż osi `axis`, w świecie -
// przepisane z rock.gdshader.
vec3 whiteout(vec3 t, vec3 n, int axis) {
	if (axis == 0) {
		t = vec3(t.xy + n.zy, abs(t.z) * n.x);
		return t.zyx;
	}
	if (axis == 1) {
		t = vec3(t.xy + n.xz, abs(t.z) * n.y);
		return t.xzy;
	}
	t = vec3(t.xy + n.xy, abs(t.z) * n.z);
	return t.xyz;
}

void axes(vec3 an, out int ma, out int me) {
	// Główna (największe |n|) i środkowa oś.
	if (an.x >= an.y && an.x >= an.z) {
		ma = 0;
		me = an.y >= an.z ? 1 : 2;
	} else if (an.y >= an.z) {
		ma = 1;
		me = an.x >= an.z ? 0 : 2;
	} else {
		ma = 2;
		me = an.x >= an.y ? 0 : 1;
	}
}

vec2 weights(vec3 an, int ma, int me) {
	vec2 w = vec2(comp(an, ma), comp(an, me));
	w = clamp((w - 0.5773) / (1.0 - 0.5773), 0.0, 1.0);
	w = pow(w, vec2(blend_pow));
	w.x = max(w.x, 1e-3);    // dokładna przekątna: obie wagi 0
	return w / max(w.x + w.y, 1e-4);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnorm);
	vec3 an = abs(n);
	int ma;
	int me;
	axes(an, ma, me);
	vec2 w = weights(an, ma, me);
	bool near = length(VERTEX) < normal_dist;

	// --- skała ---
	vec3 p = wpos * rock_scale;
	vec3 dpx = dFdx(p);
	vec3 dpy = dFdy(p);
	vec2 uv0 = proj(p, ma);
	vec2 uv1 = proj(p, me);
	vec2 gx0 = proj(dpx, ma);
	vec2 gy0 = proj(dpy, ma);
	vec2 gx1 = proj(dpx, me);
	vec2 gy1 = proj(dpy, me);
	vec3 col = textureGrad(rock_albedo, uv0, gx0, gy0).rgb * w.x
			+ textureGrad(rock_albedo, uv1, gx1, gy1).rgb * w.y;
	vec3 nw = n;
	if (near) {
		vec3 acc = whiteout(nrm_tap(rock_normal, uv0, gx0, gy0), n, ma) * w.x
				+ whiteout(nrm_tap(rock_normal, uv1, gx1, gy1), n, me) * w.y;
		nw = normalize(acc + n * 0.001);
	}

	// --- mech: strona w cieniu, plamy szumu, gęściej nisko ---
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
		vec3 q = wpos * moss_scale;
		vec3 dqx = dFdx(q);
		vec3 dqy = dFdy(q);
		vec3 mc = textureGrad(moss_albedo, proj(q, ma), proj(dqx, ma), proj(dqy, ma)).rgb * w.x
				+ textureGrad(moss_albedo, proj(q, me), proj(dqx, me), proj(dqy, me)).rgb * w.y;
		col = mix(col, mc * moss_tint, moss_a);
		// Mech wygładza rzeźbę skały (bez własnej mapy normalnych).
		nw = normalize(mix(nw, n, moss_a * (1.0 - moss_relief)));
	}
	ALBEDO = col;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ROUGHNESS = rock_roughness;
}
