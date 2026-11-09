shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;
// Предметы, люди-копии, Сущность внутри Комплекса. Свет — из instance uniform (замер в точке предмета).

uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 color : source_color = vec3(1.0);
uniform float tex_mix = 1.0;
uniform vec2 uv_scale = vec2(1.0);
uniform float world_uv = 0.0;        // 1 — текстура по мировым координатам (обои/ковёр на предмете)
uniform vec2 world_scale = vec2(0.8, 0.8);
uniform float wet = 0.0;             // мокрый блеск (Сущность, плесень)
uniform float smear = 0.0;           // «смазанность» копии: колыхание вершин и выцветание
uniform float pale = 0.0;            // копия бледнеет до белёсой массы
uniform float emit = 0.0;            // светится сам
uniform vec3 emit_color : source_color = vec3(1.0, 0.95, 0.8);
uniform float mold = 0.0;            // пятна чёрной плесени
uniform float alpha_cut = 0.0;       // >0 — вырезать по альфе текстуры
uniform float emit_mask = 0.0;       // 1 — свечение только там, где текстура яркая (окна)
uniform float fog_mul = 1.0;

instance uniform vec4 light_level = vec4(0.8, 0.0, 0.0, 0.0);

global uniform vec4 g_flick_a;
global uniform vec4 g_flick_b;
global uniform float g_power;
global uniform vec4 g_dim;
global uniform vec4 g_null;
global uniform vec4 g_fog;
global uniform float g_ambient;
global uniform float g_time;
global uniform vec4 g_cam_light;

varying vec3 wpos;
varying vec3 wnorm;
varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
	if (smear > 0.0) {
		float s1 = sin(VERTEX.y * 9.0 + VERTEX.x * 3.0 + g_time * 0.35);
		float s2 = sin(VERTEX.y * 23.0 - VERTEX.z * 5.0 + g_time * 0.21);
		VERTEX += NORMAL * (s1 * 0.012 + s2 * 0.006) * smear;
		VERTEX.y -= max(0.0, s1) * 0.01 * smear;
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float flick(int g) {
	if (g < 4) return g_flick_a[g];
	return g_flick_b[g - 4];
}

void fragment() {
	vec3 base = color;
	vec2 uv = UV * uv_scale;
	if (world_uv > 0.5) {
		vec3 an = abs(wnorm);
		if (an.y > an.x && an.y > an.z) uv = wpos.xz / world_scale;
		else if (an.x > an.z) uv = vec2(wpos.z, wpos.y) / world_scale;
		else uv = vec2(wpos.x, wpos.y) / world_scale;
	}
	vec4 tx = texture(tex, uv);
	if (alpha_cut > 0.0 && tx.a < alpha_cut) discard;
	base *= mix(vec3(1.0), tx.rgb, tex_mix);
	if (pale > 0.0) {
		float lum = dot(base, vec3(0.3, 0.59, 0.11));
		base = mix(base, vec3(0.86, 0.83, 0.76) * (0.75 + lum * 0.4), pale);
	}
	if (mold > 0.0) {
		vec3 n = texture(noise_tex, wpos.xy * 0.9 + wpos.zx * 0.7).rgb;
		float m = smoothstep(0.55 - mold * 0.35, 0.62 - mold * 0.3, n.b * 0.6 + n.r * 0.4);
		base = mix(base, vec3(0.025, 0.028, 0.022), m);
	}

	int g = int(light_level.a * 8.0 + 0.5);
	vec3 warm = vec3(1.0, 0.965, 0.84);
	vec3 fc = (g == 7) ? vec3(0.35, 1.0, 0.55) : warm;
	float shade = 0.5 + 0.5 * clamp(wnorm.y * 0.8 + 0.35, 0.0, 1.0);
	vec3 L = ((warm * light_level.r + fc * light_level.g * flick(g)) * g_power + vec3(0.8, 0.07, 0.04) * light_level.b) * shade;

	float dd = distance(wpos, g_dim.xyz);
	float dimf = g_dim.w * smoothstep(14.0, 2.0, dd);
	L *= 1.0 - dimf * (0.55 + 0.45 * (0.5 + 0.5 * sin(g_time * 41.0)));

	float nd = distance(wpos, g_null.xyz);
	L += vec3(0.35, 1.0, 0.55) * g_null.w * smoothstep(9.0, 0.5, nd) * 0.35;
	float cd = distance(wpos, g_cam_light.xyz);
	L += vec3(1.0, 0.97, 0.9) * g_cam_light.w / (1.0 + cd * cd * 0.5);
	L += vec3(g_ambient);

	vec3 col = base * L;
	if (wet > 0.0) {
		vec3 V = normalize(-VERTEX);
		vec3 N = normalize(NORMAL);
		float rim = pow(1.0 - clamp(dot(N, V), 0.0, 1.0), 3.0);
		float top = pow(clamp(wnorm.y, 0.0, 1.0), 4.0);
		float li = dot(L, vec3(0.33));
		col += vec3(0.75, 0.75, 0.7) * (rim * 0.35 + top * 0.25) * wet * li;
	}
	if (emit > 0.0) {
		col += emit_color * emit * (1.0 - dimf * 0.8) * mix(1.0, tx.r * tx.r * 1.6, emit_mask);
	}
	float dist = length(VERTEX);
	float f = 1.0 - exp(-dist * g_fog.a);
	col = mix(col, g_fog.rgb, clamp(f * fog_mul, 0.0, 1.0));
	ALBEDO = col;
}
