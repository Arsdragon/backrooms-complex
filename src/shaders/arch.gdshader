shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, skip_vertex_transform;
// Архитектура Комплекса. Свет попиксельный по сетке ламп слоя (grid_light.gdshaderinc): тени от стен и проёмов,
// мягкие полутени длинных светильников, отражённый свет по клеткам, затенение углов, карты нормалей и блики.
// Цвет вершин: у светильников — вид лампы (r ровный, g мигающий, b красный, a группа); UV2.x — «глубина»
// (тьма в ямах, шахтах и провалах; у обычных поверхностей 1).

uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex2 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nmap : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D grime_tex : filter_linear_mipmap, repeat_enable;   // крупные маски износа (по миру)
uniform vec2 scale = vec2(0.8, 0.8);     // метров на повтор текстуры
uniform float dirt = 0.5;                // доля грязного варианта
uniform float dirt_scale = 0.06;
uniform vec3 tint = vec3(1.0);
uniform float emissive = 0.0;            // светильник: светится сам (рассеиватель — по альфе текстуры)
uniform float pit = 0.0;                 // стенки ям: уходят в черноту
uniform float bump = 0.0;                // сила карты нормалей (0 — без карты)
uniform float gloss = 16.0;              // блеск (показатель Блинна — Фонга)
uniform float spec = 0.0;                // сила бликов от ламп
uniform float wet_spec = 0.0;            // доп. блик на грязных (мокрых) пятнах
uniform int grime_mode = 0;              // 0 — нет, 1 — стена (подтёки, потёки, сырость снизу), 2 — потолок (кольца протечек), 3 — ковёр (сырость, вытоптанное)
uniform float grime = 0.0;               // сила износа
uniform vec2 grime_span = vec2(4.8, 3.2);
uniform float anchor_floor = 0.0;        // 1 — картинка стены привязана к полу (низ картинки = пол; высота повтора = scale.y)
uniform float grout = 0.0;               // 1 — плитка 15 см: швы матовые (блик только на глазури)
uniform float tile_var = 0.0;            // потолок: разброс тона плит 0.6 м и редкие пожелтевшие плиты
uniform float spec_tint = 0.0;           // 1 — блик окрашен цветом поверхности (ворс ковра, а не серая плёнка)
uniform float detile = 0.0;              // пол: подмешать ту же текстуру со сдвигом пятнами по миру — повтор не виден решёткой
uniform float lens_flat = 0.0;           // погасший светильник: рассеиватель — ровный светлый пластик, а не тёмная «решётка»
uniform float hole_depth = 0.0;          // вынутая плита потолка: глубина «полости» над ней (интерьерная проекция)
uniform vec2 hole_size = vec2(0.6, 1.2);

global uniform vec4 g_flick_a;
global uniform vec4 g_flick_b;
global uniform vec4 g_dim;
global uniform vec4 g_null;
global uniform vec4 g_fog;
global uniform float g_ambient;
global uniform float g_time;
global uniform vec4 g_cam_light;
global uniform float g_power;

#include "res://src/shaders/grid_light.gdshaderinc"

varying vec3 wpos;
varying vec3 wnorm;
varying vec4 lc;
varying float ao;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	lc = COLOR;
	ao = UV2.x;
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash12(vec2 q) {
	q = fract(q * vec2(123.34, 456.21));
	q += dot(q, q + 45.32);
	return fract(q.x * q.y);
}

void fragment() {
	vec3 gn = normalize(wnorm);
	vec3 p = wpos + gn * 0.05 - vec3(0.0, g_grid.x, 0.0);
	bool horiz = abs(gn.y) > 0.5;
	float along = abs(gn.x) > 0.5 ? wpos.z : wpos.x;
	vec2 uv = UV / scale;
	if (anchor_floor > 0.5 && !horiz && g_grid.y > 0.5) {
		ivec2 c0 = ivec2(floor(p.xz / GC));
		float fl0 = g_floor_at(g_cell(c0), c0, p.xz);
		uv.y = 1.0 - (p.y - fl0) / scale.y;
	}
	vec4 ta = texture(tex, uv);
	vec3 a = ta.rgb;
	vec3 b = texture(tex2, uv).rgb;
	float dtw = 0.0;
	vec2 uv_d = uv + vec2(0.371, 0.613);
	if (detile > 0.0 && horiz) {
		dtw = smoothstep(0.38, 0.62, texture(noise_tex, wpos.xz * 0.045).g) * detile;
		a = mix(a, texture(tex, uv_d).rgb, dtw);
		b = mix(b, texture(tex2, uv_d).rgb, dtw);
	}
	if (lens_flat > 0.0) {
		a = mix(a, vec3(0.8, 0.8, 0.78), lens_flat * ta.a);
	}
	// грязный вариант — пятнами по миру: на полу/потолке по xz, на стенах — вдоль стены и по высоте
	vec2 dq = horiz ? wpos.xz : vec2(along, wpos.y * 0.6);
	vec3 nz = texture(noise_tex, dq * dirt_scale).rgb;
	float dm = smoothstep(0.62 - dirt * 0.35, 0.82 - dirt * 0.2, nz.r * 0.7 + nz.b * 0.3) * step(0.001, dirt);
	vec3 base = mix(a, b, dm) * tint;
	if (tile_var > 0.0 && horiz) {
		// у каждой плиты 0.6 м свой тон (партии плит разные), изредка — пожелтевшая от протечки
		vec2 tid = floor(UV / 0.6);
		float h1 = hash12(tid * 0.731 + 3.17);
		float h2 = hash12(tid * 1.37 + 11.9);
		base *= 1.0 + (h1 - 0.5) * 0.08 * tile_var;
		if (h2 < 0.035 * tile_var) base *= vec3(0.93, 0.88, 0.76);
	}

	vec3 n = gn;
	if (bump > 0.0) {
		vec2 tnx = texture(nmap, uv).xy * 2.0 - 1.0;
		if (dtw > 0.0) tnx = mix(tnx, texture(nmap, uv_d).xy * 2.0 - 1.0, dtw);
		n = g_perturb(gn, wpos, uv, tnx, bump);
	}
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 v = normalize(cam - wpos);

	// вынутая плита: за проёмом — тёмная полость над потолком (стенки соседних плит, пыльный бетон, трубы во тьме)
	float hole_k = 1.0;
	if (hole_depth > 0.0) {
		float sy = gn.y < 0.0 ? 1.0 : -1.0;
		vec3 rd = -v;
		base = vec3(0.015);
		hole_k = 0.0;
		if (rd.y * sy > 0.001) {
			vec2 bmin = wpos.xz - UV * hole_size;
			vec2 bmax = bmin + hole_size;
			float tt = hole_depth / abs(rd.y);
			float tx = rd.x > 1e-4 ? (bmax.x - wpos.x) / rd.x : (rd.x < -1e-4 ? (bmin.x - wpos.x) / rd.x : 1e9);
			float tz = rd.z > 1e-4 ? (bmax.y - wpos.z) / rd.z : (rd.z < -1e-4 ? (bmin.y - wpos.z) / rd.z : 1e9);
			float t = min(tt, min(tx, tz));
			vec3 hp = wpos + rd * t;
			float hgt = abs(rd.y) * t;
			bool side = t < tt;
			vec3 hc = side ? vec3(0.42, 0.4, 0.35) : vec3(0.16, 0.15, 0.13);
			float nn = texture(noise_tex, (hp.xz + vec2(hp.y * 0.7)) * 1.7).r;
			hc *= 0.65 + 0.7 * nn;
			base = hc;
			hole_k = exp(-hgt * 6.0) * (side ? 1.0 : 0.5);
		}
	}

	// износ в мировых координатах: не повторяется на глазах, не зависит от плитки текстуры
	float wetness = dm;
	if (grime_mode > 0 && grime > 0.0 && g_grid.y > 0.5) {
		ivec2 cg = ivec2(floor(p.xz / GC));
		vec4 cl = g_cell(cg);
		float fl = g_floor_at(cl, cg, p.xz);
		float ce = min(g_ceil(cl), fl + 6.0);
		if (grime_mode == 1 && !horiz) {
			// своя фаза у каждой линии стен (и у каждой стороны), чтобы пятна не повторялись от стены к стене
			float line = abs(gn.x) > 0.5 ? floor(wpos.x / GC + 0.5) : floor(wpos.z / GC + 0.5) + 517.0;
			float ph = hash12(vec2(line, sign(gn.x + gn.z) * 3.1));
			float u = along / grime_span.x + ph;
			// пятна и потёки — от потолка, «подсос» сырости — от пола
			vec2 gr = texture(grime_tex, vec2(u, clamp((ce - p.y) / grime_span.y, 0.0, 1.0))).rg;
			float gb = texture(grime_tex, vec2(u, 1.0 - clamp((p.y - fl) / grime_span.y, 0.0, 1.0))).b;
			base *= 1.0 - gr.r * grime * vec3(0.22, 0.27, 0.40);
			base *= 1.0 - gr.g * grime * vec3(0.18, 0.22, 0.32);
			base *= 1.0 - gb * grime * vec3(0.28, 0.34, 0.46);
			wetness = max(wetness, gb * grime * 0.6);
		} else if (grime_mode == 2) {
			vec2 gm = texture(grime_tex, vec2(wpos.x + 0.3, wpos.z) / grime_span.x).rg;
			base *= 1.0 - gm.r * grime * vec3(0.32, 0.43, 0.58);
			base *= 1.0 - gm.g * grime * vec3(0.12, 0.20, 0.36);
		} else if (grime_mode == 3) {
			vec2 gm = texture(grime_tex, wpos.xz / grime_span.x).rg;
			base = mix(base, b * tint, clamp(gm.r * grime * 0.6, 0.0, 1.0));
			base *= 1.0 + 0.08 * gm.g * grime;
			wetness = max(wetness, gm.r * grime);
		}
	}
	float spec_here = spec + wet_spec * wetness;
	if (grout > 0.5) {
		vec2 q = abs(fract(uv * 8.0 + 0.5) - 0.5) * 0.15;
		float gm2 = 1.0 - smoothstep(0.0013, 0.0019, min(q.x, q.y));
		spec_here *= 1.0 - gm2 * 0.9;
	}

	int g = int(lc.a * 8.0 + 0.5);
	vec3 L = vec3(0.0);
	vec3 S = vec3(0.0);
	float occ = 1.0;
	if (g_grid.y > 0.5) {
		int mode = gn.y < -0.5 ? 1 : 0;
		g_direct(p, n, v, mode, gloss, spec_here * g_grid.w, L, S);
		L += g_bounce_at(p) * g_grid.z;
		occ = g_ao(p, gn);
	}

	// Сущность рядом: лампы гаснут и дрожат каждая сама по себе — это уже в g_direct/g_bounce_at;
	// здесь — только дрожь самого светильника (по его клетке, тем же законом)
	float dd = distance(wpos, g_dim.xyz);
	float dimf = g_dim.w * smoothstep(14.0, 2.0, dd);
	float jitter = 0.5 + 0.5 * sin(g_time * 41.0 + floor(wpos.x / GC) * 3.1 + floor(wpos.z / GC) * 1.7);

	// нулевая зона: зелёный отсвет и «электричество», ползущее по стенам (шум — в плоскости самой грани)
	float nd = distance(wpos, g_null.xyz);
	float nz2 = g_null.w * smoothstep(10.0, 0.5, nd);
	if (nz2 > 0.001) {
		vec2 vq = horiz ? wpos.xz : vec2(along, wpos.y);
		vec3 n2 = texture(noise_tex, vq * 0.22 + vec2(g_time * 0.07, -g_time * 0.05)).rgb;
		// разряды — редкими ветвящимися нитями, а не узором по всей стене
		float patch = smoothstep(0.62, 0.78, texture(noise_tex, vq * 0.06 + vec2(-g_time * 0.03, g_time * 0.02)).g);
		n2.b = mix(0.0, n2.b, patch);
		float veins = smoothstep(0.02, 0.0, abs(n2.b - 0.5)) * step(0.6, fract(g_time * 1.7 + n2.r * 3.0)) * patch;
		L += vec3(0.4, 1.0, 0.6) * nz2 * (0.1 + veins * 1.8) * 0.6;
	}

	// дополнительный источник у камеры (концовки/меню)
	float cd = distance(wpos, g_cam_light.xyz);
	L += vec3(1.0, 0.97, 0.9) * g_cam_light.w / (1.0 + cd * cd * 0.5);

	L += vec3(g_ambient);
	S = mix(S, S * base * 2.2, spec_tint);
	vec3 col = (base * L + S) * ao * occ * hole_k;
	if (emissive > 0.0) {
		// рассеиватель светится (маска — альфа текстуры), рамка освещена как потолок;
		// погасшая трубка (мигание, отключение питания) — просто освещённый снаружи пластик, в темноте тёмный
		float fv = g_flick_of(g);
		float on = clamp((lc.r + lc.g * fv) * g_power, 0.0, 1.0);
		vec3 em = vec3(1.0, 0.985, 0.93) * emissive;
		if (g == 7) {
			on = clamp(lc.g * fv, 0.0, 1.0);
			em = vec3(0.3, 1.0, 0.5) * emissive * 0.6;
		}
		if (lc.b > 0.5) {
			on = 1.0;
			em = vec3(1.0, 0.08, 0.05) * emissive * 0.8;
		}
		vec3 lit = a * em * (1.0 - dimf * 0.8 * jitter);
		// погасшая трубка: матовый светлый пластик рассеивателя, освещённый комнатой
		vec3 off_col = vec3(0.8, 0.8, 0.78) * L * ao * occ;
		vec3 lens = mix(mix(col * 0.9, off_col, 0.7), lit, on);
		col = mix(col, lens, ta.a);
	}
	if (pit > 0.0) {
		col *= clamp(ao * 1.25, 0.0, 1.0);
	}
	float dist = length(VERTEX);
	float f = 1.0 - exp(-dist * g_fog.a);
	col = mix(col, g_fog.rgb, clamp(f, 0.0, 1.0));
	ALBEDO = col;
}
