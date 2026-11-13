// Тело шейдера предметов, людей-копий и Сущности (prop.gdshader — с отсечением задних граней,
// prop_ds.gdshader — двусторонний вариант для открытых моделей Poly Haven).
// В Комплексе свет попиксельный по сетке ламп (как у архитектуры: нормали, тени от стен, блики, углы);
// вне Комплекса (галерея) — по instance uniform light_level (замер в точке предмета).

uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nmap : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : filter_linear_mipmap_anisotropic, repeat_enable;   // R — AO, G — шероховатость, B — металл
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
uniform float powered = 0.0;         // 1 — свечение от сети: гаснет при отключении питания
uniform float mold = 0.0;            // пятна чёрной плесени
uniform float alpha_cut = 0.0;       // >0 — вырезать по альфе текстуры
uniform float alpha_from_r = 0.0;    // 1 — маска выреза из яркости текстуры (решётки *_opacity)
uniform float emit_mask = 0.0;       // 1 — свечение только там, где текстура яркая (окна)
uniform float fog_mul = 1.0;
uniform float bump = 0.0;            // сила карты нормалей (0 — нет)
uniform float has_arm = 0.0;         // 1 — есть ARM-карта модели
uniform float gloss = 14.0;          // блеск без ARM-карты
uniform float spec = 0.05;           // сила бликов без ARM-карты
// Дополнения для моделей Poly Haven и сгенерированной геометрии (по умолчанию ничего не меняют):
uniform float nmap_gl = 0.0;         // 1 — карта нормалей OpenGL (*_nor_gl: зелёный «вверх по картинке») — y меняет знак
uniform float metal_k = 1.0;         // множитель металла из ARM.b (у материала без металла — 0)
uniform sampler2D emit_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float has_emit_tex = 0.0;    // 1 — свечение по карте emit_tex (лампочки вентилятора, светильников)
uniform float box_uv = 0.0;          // 1 — UV по объектным метрам (кубическая проекция): одна плотность текселей
                                     //     у ящиков/цилиндров любого размера; размер плитки — world_scale
uniform float albedo_cap = 1.0;      // <1 — мягкий потолок альбедо: белое не «светится» и сохраняет оттенки
uniform float face_smear = 0.0;      // >0 — «смазанное лицо» копии: текстура головы протянута вниз-вбок и дрожит
uniform float wash = 0.0;            // >0 — копия: цвета одежды те же, но выцветшие и «застиранные» пятнами
uniform float near_cut = 0.0;        // >0 — ближе этого (м) к камере растворяется точками (не режется ближней плоскостью)

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

#include "res://src/shaders/grid_light.gdshaderinc"

varying vec3 wpos;
varying vec3 wnorm;
varying vec3 lpos;
varying vec3 opos;    // объектные координаты в метрах (с масштабом узла) — для box_uv
varying vec3 onorm;

void vertex() {
	lpos = VERTEX;
	opos = VERTEX * vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	onorm = NORMAL;
	if (smear > 0.0) {
		float s1 = sin(VERTEX.y * 9.0 + VERTEX.x * 3.0 + g_time * 0.35);
		float s2 = sin(VERTEX.y * 23.0 - VERTEX.z * 5.0 + g_time * 0.21);
		VERTEX += NORMAL * (s1 * 0.012 + s2 * 0.006) * smear;
		VERTEX.y -= max(0.0, s1) * 0.01 * smear;
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	if (near_cut > 0.0) {
		float hn = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
		if (length(VERTEX) < near_cut * (0.55 + 0.45 * hn)) discard;
	}
	vec3 base = color;
	vec2 uv = UV * uv_scale;
	vec3 gn = normalize(wnorm);
	if (!FRONT_FACING) gn = -gn;
	if (world_uv > 0.5) {
		vec3 an = abs(gn);
		if (an.y > an.x && an.y > an.z) uv = wpos.xz / world_scale;
		else if (an.x > an.z) uv = vec2(wpos.z, -wpos.y) / world_scale;
		else uv = vec2(wpos.x, -wpos.y) / world_scale;
	} else if (box_uv > 0.5) {
		vec3 an = abs(onorm);
		if (an.y > an.x && an.y > an.z) uv = opos.xz / world_scale;
		else if (an.x > an.z) uv = vec2(opos.z, -opos.y) / world_scale;
		else uv = vec2(opos.x, -opos.y) / world_scale;
	}
	vec4 tx = texture(tex, uv);
	if (face_smear > 0.0) {
		// размытие по 7 точкам вдоль «мазка» (вниз и чуть вбок) с медленно плывущим сдвигом:
		// черты лица расплываются, а голова остаётся своей формы
		vec2 jit = (texture(noise_tex, uv * 3.0 + vec2(g_time * 0.015, g_time * 0.007)).rg - 0.5) * 0.025 * face_smear;
		vec2 dir = vec2(0.005, 0.015) * face_smear;
		vec4 acc = vec4(0.0);
		for (int i = -3; i <= 3; i++) {
			acc += texture(tex, uv + jit + dir * float(i));
		}
		tx = vec4(acc.rgb / 7.0, tx.a);
	}
	float cut_a = alpha_from_r > 0.5 ? dot(tx.rgb, vec3(0.33)) : tx.a;
	if (alpha_cut > 0.0 && cut_a < alpha_cut) discard;
	base *= mix(vec3(1.0), tx.rgb, tex_mix);
	if (pale > 0.0) {
		float lum = dot(base, vec3(0.3, 0.59, 0.11));
		base = mix(base, vec3(0.86, 0.83, 0.76) * (0.75 + lum * 0.4), pale);
	}
	if (wash > 0.0) {
		// выцветшая копия: насыщенность и контраст ниже, оттенок к тёплому серому; пятнами сильнее (как застирано)
		float lw = dot(base, vec3(0.3, 0.59, 0.11));
		vec3 nw = texture(noise_tex, lpos.xy * 1.3 + lpos.zx * 0.9).rgb;
		float blot = smoothstep(0.38, 0.78, nw.g * 0.7 + nw.r * 0.3);
		vec3 dull = vec3(lw) * vec3(1.0, 0.97, 0.9) * 0.9 + vec3(0.045, 0.042, 0.036);
		base = mix(base, dull, clamp(wash * (0.4 + 0.45 * blot), 0.0, 1.0));
	}
	if (mold > 0.0) {
		vec3 nm = texture(noise_tex, lpos.xy * 0.9 + lpos.zx * 0.7).rgb;
		float m = smoothstep(0.55 - mold * 0.35, 0.62 - mold * 0.3, nm.b * 0.6 + nm.r * 0.4);
		base = mix(base, vec3(0.025, 0.028, 0.022), m);
	}
	if (albedo_cap < 0.999) {
		// мягкое колено: до 0.7·cap без изменений, 1.0 → cap
		float mx = max(max(base.r, base.g), base.b);
		float kn = albedo_cap * 0.7;
		if (mx > kn) base *= (kn + (mx - kn) * (albedo_cap - kn) / (1.0 - kn)) / mx;
	}

	vec3 n = gn;
	if (bump > 0.0) {
		vec2 tnx = texture(nmap, uv).xy * 2.0 - 1.0;
		if (nmap_gl > 0.5) tnx.y = -tnx.y;
		n = g_perturb(gn, wpos, uv, tnx, bump);
	}
	float tex_ao = 1.0;
	float gl = gloss;
	float sp = spec;
	float met = 0.0;
	if (has_arm > 0.5) {
		vec3 arm = texture(arm_tex, uv).rgb;
		tex_ao = mix(1.0, arm.r, 0.85);
		float rough = clamp(arm.g, 0.05, 1.0);
		met = arm.b * metal_k;
		gl = mix(160.0, 3.0, sqrt(rough));
		sp = mix(0.04, 0.35, met) * (1.0 - rough * 0.7);
	}
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 v = normalize(cam - wpos);

	vec3 L = vec3(0.0);
	vec3 S = vec3(0.0);
	float occ = 1.0;
	if (g_grid.y > 0.5) {
		vec3 p = wpos + gn * 0.04 - vec3(0.0, g_grid.x, 0.0);
		g_direct(p, n, v, 0, gl, (sp + wet * 0.3) * g_grid.w, L, S);
		L += g_bounce_at(p) * g_grid.z * (0.8 + 0.2 * gn.y);
		// у пола и стен темнее: предмет «стоит», а не висит
		vec4 cl = g_cell(ivec2(floor(p.xz / GC)));
		float fl = g_floor(cl);
		occ = mix(1.0, g_ao(p, vec3(0.0, 1.0, 0.0)), 0.55) * (1.0 - 0.38 * exp(-max(p.y - fl, 0.0) / 0.22));
	} else {
		int g = int(light_level.a * 8.0 + 0.5);
		vec3 warm = vec3(1.0, 0.965, 0.84);
		vec3 fc = (g == 7) ? vec3(0.35, 1.0, 0.55) : warm;
		float shade = 0.5 + 0.5 * clamp(gn.y * 0.8 + 0.35, 0.0, 1.0);
		L = ((warm * light_level.r + fc * light_level.g * g_flick_of(g)) * g_power + vec3(0.8, 0.07, 0.04) * light_level.b) * shade;
	}

	float dd = distance(wpos, g_dim.xyz);
	float dimf = g_dim.w * smoothstep(14.0, 2.0, dd);
	// в Комплексе лампы у Сущности гаснут по одной уже в g_direct/g_bounce_at; здесь — только вне сетки
	if (g_grid.y < 0.5) {
		float dimk = 1.0 - dimf * (0.55 + 0.45 * (0.5 + 0.5 * sin(g_time * 41.0)));
		L *= dimk;
		S *= dimk;
	}

	float nd = distance(wpos, g_null.xyz);
	L += vec3(0.35, 1.0, 0.55) * g_null.w * smoothstep(9.0, 0.5, nd) * 0.35;
	float cd = distance(wpos, g_cam_light.xyz);
	L += vec3(1.0, 0.97, 0.9) * g_cam_light.w / (1.0 + cd * cd * 0.5);
	L += vec3(g_ambient);

	if (met > 0.0) {
		// металл: блик окрашен цветом металла, рассеянного меньше
		S *= mix(vec3(1.0), base * 1.5 + 0.1, met);
		base *= 1.0 - 0.35 * met;
	}
	vec3 col = (base * L + S) * occ * tex_ao;
	if (wet > 0.0) {
		float rim = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 3.0);
		float li = dot(L, vec3(0.33));
		col += vec3(0.75, 0.75, 0.7) * rim * 0.3 * wet * li;
	}
	if (emit > 0.0) {
		float pw = mix(1.0, g_power, powered);
		vec3 em = emit_color * emit * pw * (1.0 - dimf * 0.8) * mix(1.0, tx.r * tx.r * 1.6, emit_mask);
		if (has_emit_tex > 0.5) em *= texture(emit_tex, uv).rgb;
		col += em;
	}
	float dist = length(VERTEX);
	float f = 1.0 - exp(-dist * g_fog.a);
	col = mix(col, g_fog.rgb, clamp(f * fog_mul, 0.0, 1.0));
	ALBEDO = col;
}
