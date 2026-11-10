shader_type spatial;
// Auta z epoki z teksturą (GGBotNet): lakier z maski (tools/make_paint_masks.py)
// przemalowany na kolor auta, reszta tekstury bez zmian. Piksele jak w
// oryginale (filtr najbliższy - styl paczki).
uniform sampler2D tex : source_color, filter_nearest_mipmap;
uniform sampler2D mask : filter_nearest_mipmap;
uniform vec3 paint : source_color = vec3(0.8, 0.6, 0.18);
uniform float alpha = 1.0;

void fragment() {
	vec3 c = texture(tex, UV).rgb;
	vec2 m = texture(mask, UV).rg;
	vec3 p = paint * clamp(m.g * 2.0, 0.35, 1.4);
	ALBEDO = mix(c, p, m.r);
	ROUGHNESS = mix(0.85, 0.4, m.r);
	METALLIC = 0.0;
}
