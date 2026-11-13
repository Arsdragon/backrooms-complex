shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
// Стекло моделей (циферблат часов, рамки картин, дверцы печи и микроволновки, фары, кассетники):
// почти прозрачное, пыльный налёт пятнами, френель по краям, блики ламп сетки (в Комплексе), туман.
// Вне Комплекса — по instance uniform light_level, как у предметов.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.55, 0.6, 0.58);
uniform float dirt = 0.5;            // пыль и разводы (0..1)
uniform float opacity = 0.06;        // прозрачность «в лоб» без бликов
uniform float fog_mul = 1.0;
uniform float shine = 240.0;         // показатель блика ламп (больше — меньше и резче отражение)
uniform float spec_gl = 0.55;        // сила блика

instance uniform vec4 light_level = vec4(0.8, 0.0, 0.0, 0.0);

global uniform vec4 g_flick_a;
global uniform vec4 g_flick_b;
global uniform float g_power;
global uniform vec4 g_dim;
global uniform vec4 g_fog;
global uniform float g_ambient;

#include "res://src/shaders/grid_light.gdshaderinc"

varying vec3 wpos;
varying vec3 wnorm;
varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 gn = normalize(wnorm);
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 v = normalize(cam - wpos);
	if (dot(gn, v) < 0.0) gn = -gn;
	// пыль: крупные пятна + мелкая зернь (в объектных координатах — не «плывёт» за предметом)
	vec3 nz = texture(noise_tex, lpos.xy * 2.3 + lpos.zy * 1.7).rgb;
	vec3 nz2 = texture(noise_tex, lpos.xz * 9.0 + lpos.yx * 7.0).rgb;
	float dust = clamp(nz.g * 0.7 + nz2.r * 0.3, 0.0, 1.0) * dirt;

	vec3 L;
	vec3 S = vec3(0.0);
	if (g_grid.y > 0.5) {
		vec3 p = wpos + gn * 0.04 - vec3(0.0, g_grid.x, 0.0);
		g_direct(p, gn, v, 0, shine, spec_gl, L, S);
		L += g_bounce_at(p) * g_grid.z;
	} else {
		int g = int(light_level.a * 8.0 + 0.5);
		L = vec3(1.0, 0.965, 0.84) * (light_level.r + light_level.g * g_flick_of(g)) * g_power + vec3(0.8, 0.07, 0.04) * light_level.b;
	}
	L += vec3(g_ambient);
	float dd = distance(wpos, g_dim.xyz);
	float dimk = 1.0 - g_dim.w * smoothstep(14.0, 2.0, dd) * 0.7;
	float fr = pow(1.0 - clamp(dot(gn, v), 0.0, 1.0), 4.0);
	// налёт рассеивает свет (сероватый), чистое стекло только отражает: френель и блики
	// блик мягко ограничен: на выпуклом стекле (часы) отражение лампы — пятнышко, а не белая заливка всего купола
	float sl = dot(S, vec3(0.33));
	vec3 Sc = S / (1.0 + sl * 0.6);
	vec3 col = (tint * L * (0.45 + dust * 0.6) + Sc) * dimk;
	float a = opacity + dust * 0.16 + fr * 0.35 + min(sl * 0.6, 0.45);
	float dist = length(VERTEX);
	float f = 1.0 - exp(-dist * g_fog.a);
	ALBEDO = mix(col, g_fog.rgb, clamp(f * fog_mul, 0.0, 1.0));
	ALPHA = clamp(a, 0.0, 0.85);
}
