// Земля парка одним проходом: газон (два масштаба + выгоревшие пятна), голая земля под деревьями и у скамеек,
// вытоптанные края дорожек, асфальт петли и спиц, бетон площади со швами, песок детской площадки.
// Дорожки нарисованы по маске-расстоянию, поэтому края ровные и плавные, без наложения мешей.
// Провал (park_hole_r в park_ground.gdshaderinc): земля под героем расходится; изнанка земли — чёрная.
shader_type spatial;
render_mode cull_disabled;

#include "res://src/shaders/park_ground.gdshaderinc"

uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_dry_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float plaza_r = 9.0;

varying vec3 wp;

vec2 rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz;
	// провал: внутри — пусто (под ним колодец из park.gd), у кромки — осыпающаяся сырая земля
	float hd = park_hole_d(p);
	if (hd < 0.0) {
		discard;
	}
	vec4 m = park_mask_at(p);
	float n_big = texture(macro_tex, p / 37.0 + vec2(0.13, 0.71)).g;
	float n_mid = texture(macro_tex, p / 9.0).b;
	float n_fine = texture(macro_tex, p / 1.7 + vec2(0.5, 0.2)).b;

	// газон: два масштаба одной текстуры под углом — повтор не читается
	vec3 g1 = texture(grass_tex, p / 2.3).rgb;
	vec3 g2 = texture(grass_tex, rot(p, 1.1) / 6.1).rgb;
	vec3 grass = mix(g1, g2, 0.4);
	vec3 dry = mix(texture(grass_dry_tex, p / 2.7).rgb, texture(grass_dry_tex, rot(p, 2.3) / 7.3).rgb, 0.35);
	float dr = park_dryness(p, m);
	vec3 col = mix(grass, dry, dr);
	col *= 0.9 + (n_big - 0.5) * 0.3 + (n_mid - 0.5) * 0.12;
	// полосы от газонокосилки: трава, примятая в разные стороны, чуть светлее/темнее
	float stripe = smoothstep(-0.25, 0.25, sin(dot(p, vec2(0.8, 0.6)) * 3.1416 / 1.7 + (n_big - 0.5) * 0.8));
	col *= mix(0.95, 1.04, stripe) * mix(1.0, 0.98, dr);

	// голая земля: под кронами, у скамеек и урн, под качелями
	vec3 dirt = texture(dirt_tex, p / 2.6).rgb * (0.92 + (n_mid - 0.5) * 0.2);
	float dk = smoothstep(0.28, 0.68, m.b + (n_mid - 0.5) * 0.55 + (n_fine - 0.5) * 0.2);
	// вытоптанная полоса вдоль асфальта
	float wear = (1.0 - smoothstep(0.0, 0.42, m.r + (n_mid - 0.5) * 0.5)) * step(0.0, m.r);
	dk = max(dk, wear * 0.75 * smoothstep(0.3, 0.6, n_fine + 0.2));
	col = mix(col, dirt, dk);
	float rough = mix(0.95, 0.9, dk);

	// вытоптанная полоса вокруг бетонной площади (за бордюром) и песочницы (за брусом)
	float w_pl = (1.0 - smoothstep(0.0, 0.55, m.g + (n_mid - 0.5) * 0.45)) * step(0.0, m.g);
	float w_sd = (1.0 - smoothstep(0.2, 0.9, m.a + (n_mid - 0.5) * 0.5)) * step(0.2, m.a);
	col = mix(col, dirt, max(w_pl, w_sd) * 0.7 * smoothstep(0.3, 0.62, n_fine + 0.15));

	// песок детской площадки: внутри бруса край ровный (брус — меш в park.gd), снаружи — выбитый ногами
	// пятнами на траву
	float sk = 1.0 - smoothstep(-0.03, 0.03, m.a);
	float spill = (1.0 - smoothstep(0.2, 1.1, m.a)) * step(0.17, m.a) * smoothstep(0.52, 0.72, n_fine + (n_mid - 0.5) * 0.5);
	vec3 sand = texture(sand_tex, p / 1.9).rgb * (0.94 + (n_mid - 0.5) * 0.15);
	// у бруса песок в тени и сырее
	sand *= 1.0 - 0.18 * (1.0 - smoothstep(-0.35, -0.05, m.a)) * sk;
	col = mix(col, sand, max(sk, spill * 0.75));

	// асфальт: рваный край, у края светлее и крошится
	float ak = 1.0 - smoothstep(-0.012, 0.012, m.r + (n_fine - 0.5) * 0.1);
	// асфальт и бетон темнее текстур: на солнце (камера открыта по тени) иначе выбиваются в белый «снег»
	vec3 asph = texture(asphalt_tex, p / 3.7).rgb * (0.93 + (n_big - 0.5) * 0.16) * 0.86;
	asph = mix(asph, asph * 1.08 + vec3(0.02, 0.015, 0.0), (1.0 - smoothstep(-0.25, 0.0, m.r)) * 0.6);
	col = mix(col, asph, ak);
	rough = mix(rough, 0.86, ak);

	// бетонная площадь: кольцевые и радиальные швы. Край (0..−0,3 м) — бордюр-меш из park.gd, под ним граница маски
	float ck = 1.0 - smoothstep(-0.12, -0.1, m.g);
	vec3 conc = texture(concrete_tex, p / 2.9).rgb * (0.95 + (n_big - 0.5) * 0.1) * 0.8;
	float r = length(p);
	float ring = abs(fract(r / 2.25 + 0.5) - 0.5) * 2.25;
	float ang = atan(p.y, p.x);
	float rad = abs(fract(ang * 24.0 / 6.2832 + 0.5) - 0.5) * 6.2832 / 24.0 * r;
	// шов шириной ~1 см; вдали, где он тоньше пикселя, — шире и бледнее (иначе рвётся в пунктир)
	float jw = max(fwidth(r) * 0.75, 0.007);
	float joint = (1.0 - smoothstep(jw, jw * 2.2, min(ring, r > 2.0 ? rad : 1.0))) * min(1.0, 0.009 / jw);
	joint *= step(0.6, r);
	conc *= 1.0 - joint * 0.45;
	// вдоль бордюра в шве набилась грязь
	conc *= 1.0 - 0.22 * (1.0 - smoothstep(-0.55, -0.3, m.g)) * smoothstep(0.35, 0.6, n_fine + 0.1);
	// пятна: мокрое кольцо брызг у чаши, разводы от пролитого и тень-грязь вдоль швов, вытертая середина
	float wet = smoothstep(2.9, 1.8, r) * (0.3 + 0.15 * n_fine);
	float stain = smoothstep(0.6, 0.82, texture(macro_tex, p / 4.3 + vec2(0.17, 0.4)).g) * 0.16
		+ smoothstep(0.66, 0.85, texture(macro_tex, p / 1.3 + vec2(0.7, 0.1)).b) * 0.1;
	float trodden = smoothstep(7.5, 4.0, r) * 0.05;
	conc *= (1.0 - wet - stain + trodden) * (1.0 - joint * 0.12);
	col = mix(col, conc, ck);
	rough = mix(rough, 0.82, ck);

	// за парком: тротуар, бордюр, улица с двойной жёлтой осевой, тротуар, газоны перед домами
	float e = max(abs(p.x), abs(p.y));
	float along = abs(p.x) > abs(p.y) ? p.y : p.x;
	float aa = fwidth(e) + 0.004;
	float walk1 = smoothstep(66.55 - aa, 66.55 + aa, e) * (1.0 - smoothstep(68.3 - aa, 68.3 + aa, e));
	float walk2 = smoothstep(79.45 - aa, 79.45 + aa, e) * (1.0 - smoothstep(81.1 - aa, 81.1 + aa, e));
	float curb = (smoothstep(68.3 - aa, 68.3 + aa, e) - smoothstep(68.5 - aa, 68.5 + aa, e)) + (smoothstep(79.25 - aa, 79.25 + aa, e) - smoothstep(79.45 - aa, 79.45 + aa, e));
	float road = smoothstep(68.5 - aa, 68.5 + aa, e) * (1.0 - smoothstep(79.25 - aa, 79.25 + aa, e));
	if (e > 66.0) {
		vec3 sw = texture(concrete_tex, p / 2.9).rgb * 0.8;
		float sj = 1.0 - smoothstep(0.008, 0.02, abs(fract(along / 1.52 + 0.5) - 0.5) * 1.52);
		sw *= 1.0 - sj * 0.4;
		col = mix(col, sw, clamp(walk1 + walk2, 0.0, 1.0));
		col = mix(col, texture(concrete_tex, p / 1.3).rgb * 0.9, curb);
		vec3 st = texture(asphalt_tex, p / 4.3).rgb * vec3(0.78, 0.78, 0.8) * (0.95 + (n_big - 0.5) * 0.15);
		// у бордюра — тёмная полоса грязи и масла по колеям
		float gut = 1.0 - smoothstep(0.0, 0.5, min(abs(e - 68.5), abs(e - 79.25)));
		st *= 1.0 - gut * 0.18;
		float lane = abs(e - 73.875);
		float yl = (1.0 - smoothstep(0.045, 0.055 + aa, abs(lane - 0.1))) * smoothstep(0.3, 0.6, n_fine + 0.25);
		st = mix(st, vec3(0.78, 0.64, 0.24), yl * 0.85);
		col = mix(col, st, road);
		rough = mix(rough, 0.85, clamp(road + walk1 + walk2 + curb, 0.0, 1.0));
	}

	// кромка провала: дёрн оборван, под ним тёмная сырая земля
	float rim = 1.0 - smoothstep(0.0, 0.22 + n_fine * 0.12, hd);
	col = mix(col, texture(dirt_tex, p / 1.1).rgb * 0.42, rim * step(0.001, park_hole.z));

	// снизу земля — тьма (камера под поверхностью видит только черноту, а не парк «из-под пола»)
	float front = FRONT_FACING ? 1.0 : 0.0;
	ALBEDO = col * front;
	ROUGHNESS = rough;
	SPECULAR = 0.28 * front;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
