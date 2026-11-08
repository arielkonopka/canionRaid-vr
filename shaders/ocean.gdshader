// Morze za obniżoną ścianą wąwozu: płaska płaszczyzna, fale tylko
// w normalnych (dwie warstwy szumu przesuwane w czasie) - tanio na Queście.
// Pod kątem jaśniej (odbicie nieba, Fresnel), z góry ciemny granat.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 deep : source_color = vec3(0.03, 0.12, 0.22);
uniform vec3 shallow : source_color = vec3(0.10, 0.30, 0.40);
uniform vec3 sky : source_color = vec3(0.62, 0.72, 0.82);

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float waves(vec2 p) {
	return vnoise(p * 0.08 + vec2(TIME * 0.05, TIME * 0.03)) * 0.6
			+ vnoise(p * 0.31 - vec2(TIME * 0.11, -TIME * 0.07)) * 0.3
			+ vnoise(p * 1.2 + vec2(TIME * 0.2, 0.0)) * 0.1;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float e = 0.6;
	float h0 = waves(p);
	float hx = waves(p + vec2(e, 0.0));
	float hz = waves(p + vec2(0.0, e));
	vec3 nw = normalize(vec3((h0 - hx) * 2.5, 1.0, (h0 - hz) * 2.5));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 col = mix(deep, shallow, h0 * 0.6);
	ALBEDO = mix(col, sky, fres * 0.7);
	ROUGHNESS = 0.12;
	SPECULAR = 0.6;
}
