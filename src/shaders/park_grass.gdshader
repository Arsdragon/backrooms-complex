// Травинки газона вокруг камеры: сетка экземпляров MultiMesh «переезжает» за камерой (каждый экземпляр берёт
// ближайшую к камере копию своей клетки), высота — из карты рельефа, на дорожках/площади/песке травы нет,
// к краю радиуса трава редеет и уходит в текстуру газона. Цвет совпадает с газоном под травинкой.
shader_type spatial;
render_mode cull_disabled, world_vertex_coords;

#include "res://src/shaders/park_wind.gdshaderinc"
#include "res://src/shaders/park_ground.gdshaderinc"

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform vec4 height_rect = vec4(-96.5, -96.5, 193.0, 193.0);
uniform float tile = 14.0;
uniform vec2 fade = vec2(4.5, 6.5);
uniform vec3 green : source_color = vec3(0.31, 0.40, 0.14);
uniform vec3 dry : source_color = vec3(0.52, 0.46, 0.24);
uniform float bend_amp = 0.045;
uniform float bare_kill = 1.0;
// прямоугольники без травы (park_ground.gd: cut_grass): xy — центр (мир x, z), zw — полуразмеры (< 0 — пусто);
// cut_rot — поворот каждого по Y (как rotation.y узла)
uniform vec4 cut_rect[4];
uniform vec4 cut_rot = vec4(0.0);

varying vec3 v_col;
varying float v_t;

float hash1(float n) {
	return fract(sin(n * 12.9898 + 4.1414) * 43758.5453);
}

void vertex() {
	vec3 inst = MODEL_MATRIX[3].xyz;
	vec2 cam = CAMERA_POSITION_WORLD.xz;
	vec2 wp = inst.xz + tile * round((cam - inst.xz) / tile);
	vec4 m = park_mask_at(wp);
	float hgt = textureLod(height_tex, (wp - height_rect.xy) / height_rect.zw, 0.0).r;
	float r1 = hash1(float(INSTANCE_ID));
	float r2 = hash1(float(INSTANCE_ID) * 1.618 + 7.0);
	float fv = 1.0 - smoothstep(fade.x, fade.y, distance(wp, cam));
	// у края асфальта ниже, на асфальте/бетоне/песке нет; к бордюру площади и брусу песочницы трава подходит
	// вплотную и местами нависает (рваная граница по шуму)
	float n_e = textureLod(macro_tex, wp / 1.7 + vec2(0.5, 0.2), 0.0).b - 0.5;
	float edge = smoothstep(0.0, 0.45, m.r) * smoothstep(-0.06, 0.1, m.g + n_e * 0.14) * smoothstep(0.16, 0.3, m.a + n_e * 0.12);
	for (int i = 0; i < 4; i++) {
		vec4 cr = cut_rect[i];
		if (cr.z > 0.0) {
			vec2 d = wp - cr.xy;
			float ca = cos(cut_rot[i]);
			float sa = sin(cut_rot[i]);
			vec2 l = vec2(ca * d.x - sa * d.y, sa * d.x + ca * d.y);
			edge *= smoothstep(0.0, 0.06, max(abs(l.x) - cr.z, abs(l.y) - cr.w));
		}
	}
	edge *= 1.0 - step(66.0, max(abs(wp.x), abs(wp.y)));   // за парком тротуар и улица
	float n1 = textureLod(macro_tex, wp / 9.0, 0.0).b;
	float bare = smoothstep(0.3, 0.72, m.b + (n1 - 0.5) * 0.55) * bare_kill;
	float hk = edge * (1.0 - bare) * mix(0.55, 1.0, fv);
	// у провала травы нет (кромка — голая сырая земля)
	hk *= smoothstep(0.12, 0.3, park_hole_d(wp));
	if (r2 > fv || hk < 0.04) {
		hk = 0.0;
	}
	vec3 local = VERTEX - inst;
	local *= vec3(1.0, hk, 1.0) * step(0.001, hk);
	// ветер: кончики гнутся по ветру, порывы бегут по газону
	float g = park_gust(wp, TIME);
	float bend = UV.y * UV.y;
	vec2 wv = wind_dir * (g * 0.8 + sin(TIME * 2.3 + r1 * 6.28 + dot(wp, vec2(0.9, 0.5))) * 0.3) * wind;
	local.xz += wv * bend_amp * bend * hk;
	local.y -= dot(wv, wv) * bend_amp * 0.25 * bend * hk;
	VERTEX = vec3(wp.x, hgt, wp.y) + local;
	float dr = park_dryness(wp, m);
	v_col = mix(green, dry, clamp(dr + (COLOR.a - 0.5) * 0.3, 0.0, 1.0)) * COLOR.rgb;
	v_t = UV.y;
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.75));
}

void fragment() {
	ALBEDO = v_col * mix(0.55, 1.1, v_t);
	ROUGHNESS = 0.82;
	SPECULAR = 0.3;
	BACKLIGHT = v_col * 0.4;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
