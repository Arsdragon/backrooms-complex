// Попиксельный свет Комплекса по сетке клеток слоя (данные — src/world/light_grid.gd).
// Клетка 2.4 м, лампы — в центрах клеток. Видимость лампы из точки — луч по рёбрам клеток
// (стены, двери, арки, окна, ступени и наклоны пола, перепады потолка), поэтому свет честно режется проёмами.
// Длинный светильник светит вниз (косинус излучателя) и проверяется несколькими точками вдоль трубок —
// мягкая полутень у проёмов. Отражённый свет — из запечённого по клеткам cell_light, билинейно и только
// между клетками, которые видят друг друга (через стену не просачивается).
// Перед #include шейдер должен объявить g_flick_a, g_flick_b, g_power.

global uniform sampler2D g_cells;     // RGBA8: r — рёбра/флаги, g — потолок (дм), b — пол (дм+128), a — пандус (0..8)
global uniform sampler2D g_lamps;     // RGBAH: r — высота лампы над floor_y, g — сила, b — вид, a — группа мигания
global uniform sampler2D g_bounce;    // RGBAH: отражённый свет клетки (ровный, мигающий, красный, группа/8)
global uniform vec4 g_grid;           // x — floor_y слоя, y — 1: сетка включена, z — сила отражённого света, w — сила бликов
global uniform vec4 g_ldim;           // Сущность рядом: xyz — где, w — сила (лампы гаснут и дрожат каждая по-своему)
global uniform float g_ltime;         // время для дрожи ламп

const float GC = 2.4;
const float GNf = 384.0;
const float G_LIGHT_R = 7.5;
const float G_LIGHT_A = 6.0;
const float G_LIGHT_K = 0.62;
const vec3 G_WARM = vec3(1.0, 0.98, 0.91);
const vec3 G_RED = vec3(0.8, 0.07, 0.04);
const vec3 G_GREEN = vec3(0.35, 1.0, 0.55);

ivec2 g_wrap(ivec2 c) {
	return c - ivec2(floor(vec2(c) / GNf)) * 384;
}

vec4 g_cell(ivec2 c) {
	return texelFetch(g_cells, g_wrap(c), 0);
}

int g_bits(vec4 t) {
	return int(t.r * 255.0 + 0.5);
}

// Пол клетки (м от floor_y слоя) у «задней» стороны; у ям — дно на 7 м ниже
float g_floor(vec4 t) {
	if ((g_bits(t) & 128) != 0) return -7.0;
	return (t.b * 255.0 - 128.0) * 0.1;
}

// Пол в точке xz (мир) клетки c: у пандуса и лестницы — наклон к соседу по направлению (как LayerData.floor_off_cell)
float g_floor_at(vec4 t, ivec2 c, vec2 pxz) {
	float base = g_floor(t);
	int r = int(t.a * 255.0 + 0.5);
	if (r == 0) return base;
	int rd = (r - 1) % 4;
	ivec2 o = rd == 0 ? ivec2(1, 0) : (rd == 1 ? ivec2(0, 1) : (rd == 2 ? ivec2(-1, 0) : ivec2(0, -1)));
	float far = g_floor(g_cell(c + o));
	vec2 l = clamp((pxz - vec2(c) * GC) / GC, 0.0, 1.0);
	float tt = rd == 0 ? l.x : (rd == 1 ? l.y : (rd == 2 ? 1.0 - l.x : 1.0 - l.y));
	return mix(base, far, tt);
}

// Потолок клетки (м от floor_y); 0 — шахта/небо: «бесконечно высоко»
float g_ceil(vec4 t) {
	float h = t.g * 255.0 * 0.1;
	return h < 0.05 ? 99.0 : h;
}

float g_flick_of(int g) {
	if (g < 4) return g_flick_a[clamp(g, 0, 3)];
	return g_flick_b[clamp(g - 4, 0, 3)];
}

// Проходит ли луч через ребро вида e на высоте y (fe — пол у ребра, u — место вдоль ребра 0..GC)
bool g_edge_open(int e, float y, float fe, float u) {
	if (e == 0) return true;
	if (e == 1) return false;
	if (e == 2) return abs(u - GC * 0.5) < 0.55 && y < fe + 2.1;
	if (e == 3) return y < fe + 2.25;
	return y > fe + 0.9 && y < fe + 2.2;
}

// Видимость точки l из точки p (обе в координатах слоя: y от floor_y). 1 — видно, 0 — закрыто.
float g_trace(vec3 p, vec3 l) {
	vec2 a = p.xz / GC;
	vec2 b = l.xz / GC;
	ivec2 c = ivec2(floor(a));
	ivec2 cb = ivec2(floor(b));
	vec2 d = b - a;
	ivec2 st = ivec2(d.x >= 0.0 ? 1 : -1, d.y >= 0.0 ? 1 : -1);
	vec2 ad = abs(d);
	vec2 inv = vec2(ad.x > 1e-6 ? 1.0 / ad.x : 1e9, ad.y > 1e-6 ? 1.0 / ad.y : 1e9);
	vec2 fr = a - vec2(c);
	vec2 tmax = vec2(d.x >= 0.0 ? 1.0 - fr.x : fr.x, d.y >= 0.0 ? 1.0 - fr.y : fr.y) * inv;
	vec4 cur = g_cell(c);
	for (int i = 0; i < 9; i++) {
		if (c == cb) return 1.0;
		bool xs = tmax.x < tmax.y;
		float t = xs ? tmax.x : tmax.y;
		if (t > 1.0) return 1.0;
		ivec2 nc = xs ? ivec2(c.x + st.x, c.y) : ivec2(c.x, c.y + st.y);
		if (xs) {
			tmax.x += inv.x;
		} else {
			tmax.y += inv.y;
		}
		vec4 nxt = g_cell(nc);
		int bn = g_bits(nxt);
		if ((bn & 64) != 0) return 0.0;
		vec3 q = mix(p, l, t);
		float fe = max(g_floor_at(cur, c, q.xz), g_floor_at(nxt, nc, q.xz));
		float ce = min(g_ceil(cur), g_ceil(nxt));
		if (q.y < fe - 0.03 || q.y > ce + 0.03) return 0.0;
		int owner = xs ? (st.x > 0 ? g_bits(cur) : bn) : (st.y > 0 ? g_bits(cur) : bn);
		int e = xs ? (owner & 7) : ((owner >> 3) & 7);
		float u = xs ? (q.z - float(c.y) * GC) : (q.x - float(c.x) * GC);
		if (!g_edge_open(e, q.y, fe, u)) return 0.0;
		c = nc;
		cur = nxt;
	}
	return 1.0;
}

// Видимость длинного светильника (0.6×1.2 м вдоль z): сначала концы трубок; если они расходятся (полутень) —
// ещё четыре точки по площади лампы со сдвигом от точки поверхности (размытая ступенька вместо резкой).
float g_vis_tube(vec3 p, vec3 lp) {
	// светит вся площадь рассеивателя 0.6×1.2 м (плюс рассеянный свет от потолка вокруг) — точки по всей площади
	float a = g_trace(p, lp + vec3(0.27, -0.03, 0.57));
	float b = g_trace(p, lp + vec3(-0.27, -0.03, -0.57));
	if (a == b) {
		float c2 = g_trace(p, lp + vec3(-0.27, -0.03, 0.57));
		if (c2 == a) return a;
		b = 0.5 * (b + c2);
	}
	float j = fract(sin(dot(floor(p.xz * 40.0) + floor(p.y * 40.0) * 0.37, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	float s = a + b;
	s += g_trace(p, lp + vec3(0.27, -0.03, -0.57));
	s += g_trace(p, lp + vec3(-0.25, -0.03, 0.28 + j * 0.2));
	s += g_trace(p, lp + vec3(0.25, -0.03, 0.0 + j * 0.2));
	s += g_trace(p, lp + vec3(-0.25, -0.03, -0.28 + j * 0.2));
	s += g_trace(p, lp + vec3(0.0, -0.03, 0.42 - j * 0.2));
	s += g_trace(p, lp + vec3(0.0, -0.03, -0.42 - j * 0.2));
	return s / 8.0;
}

// Прямой свет ламп и блики. p — точка в координатах слоя (уже сдвинута по нормали на несколько см),
// n — мировая нормаль (с картой нормалей), v — к камере, mode: 0 — стены/пол/предметы, 1 — потолок
// (светильник светит вниз: потолок у лампы освещён слабо и рассеянно, основной свет потолка — отражённый).
// shin — показатель блеска, spec_k — сила бликов. Результат: o_diff — освещённость, o_spec — блики (уже цвет).
void g_direct(vec3 p, vec3 n, vec3 v, int mode, float shin, float spec_k, out vec3 o_diff, out vec3 o_spec) {
	o_diff = vec3(0.0);
	o_spec = vec3(0.0);
	ivec2 c0 = ivec2(floor(p.xz / GC));
	for (int dz = -3; dz <= 3; dz++) {
		for (int dx = -3; dx <= 3; dx++) {
			ivec2 lc = c0 + ivec2(dx, dz);
			vec4 lm = texelFetch(g_lamps, g_wrap(lc), 0);
			if (lm.g <= 0.0) continue;
			vec3 lp = vec3((float(lc.x) + 0.5) * GC, lm.r, (float(lc.y) + 0.5) * GC);
			vec3 dv = lp - p;
			float d = length(dv);
			if (d > G_LIGHT_R) continue;
			int kind = int(lm.b + 0.5);
			bool down = kind <= 2 || kind == 6;
			vec3 l = dv / max(d, 1e-3);
			float w = 1.0 - (d / G_LIGHT_R) * (d / G_LIGHT_R);
			w *= w;
			float fall;
			float lam;
			if (mode == 1) {
				float dc = max(d, 0.7);
				fall = 0.3 / (1.0 + dc * dc * 1.2) + 0.07 * G_LIGHT_A / (G_LIGHT_A + dc * dc);
				lam = 1.0;
				if (kind == 6) fall *= 0.12;
			} else {
				fall = G_LIGHT_A / (G_LIGHT_A + d * d);
				lam = 0.22 + 0.78 * max(0.0, dot(n, l));
				// излучатель: светильник и прожектор светят вниз (на полу «перевёртыша» — вверх), лампочка — во все стороны
				if (down) {
					float dn = lm.r > 1.0 ? l.y : -l.y;
					fall *= kind == 6 ? 0.08 + 0.92 * clamp(dn * 1.3, 0.0, 1.0) : 0.3 + 0.7 * clamp(dn * 1.15, 0.0, 1.0);
				}
			}
			fall *= w;
			float vis = kind <= 1 ? g_vis_tube(p, lp) : g_trace(p, lp + vec3(0.0, -0.03, 0.0));
			if (vis <= 0.0) continue;
			vec3 lcol;
			if (kind == 2) {
				lcol = G_RED;
			} else if (kind == 3) {
				lcol = G_GREEN * g_flick_of(7);
			} else if (kind == 1 || kind == 5) {
				lcol = G_WARM * g_flick_of(int(lm.a + 0.5)) * g_power;
			} else {
				lcol = G_WARM * g_power;
			}
			// Сущность рядом: каждая лампа гаснет и дрожит сама по себе (а не квадратами по полу)
			if (g_ldim.w > 0.0) {
				float dd = distance(lp + vec3(0.0, g_grid.x, 0.0), g_ldim.xyz);
				float df = g_ldim.w * smoothstep(14.0, 2.0, dd);
				float jit = 0.5 + 0.5 * sin(g_ltime * 41.0 + float(lc.x) * 3.1 + float(lc.y) * 1.7);
				lcol *= 1.0 - df * (0.55 + 0.45 * jit);
			}
			lcol *= lm.g * vis * G_LIGHT_K;
			o_diff += lcol * fall * lam;
			if (spec_k > 0.0 && mode == 0) {
				vec3 h = normalize(l + v);
				float nh = max(dot(n, h), 0.0);
				float s = pow(nh, shin) * (shin + 8.0) * 0.045;
				o_spec += lcol * s * w * G_LIGHT_A / (G_LIGHT_A + d * d) * max(dot(n, l), 0.0);
			}
		}
	}
	o_spec *= spec_k;
}

// Сколько отражённого света проходит между соседними клетками a и b (по ребру): стена/окно — 0, дверь — 0.4
float g_link(ivec2 a, vec4 ta, ivec2 b, vec4 tb) {
	if ((g_bits(tb) & 64) != 0) return 0.0;
	int e;
	if (b.x == a.x + 1) e = g_bits(ta) & 7;
	else if (b.x == a.x - 1) e = g_bits(tb) & 7;
	else if (b.y == a.y + 1) e = (g_bits(ta) >> 3) & 7;
	else e = (g_bits(tb) >> 3) & 7;
	if (e == 0 || e == 3) return 1.0;
	if (e == 2) return 0.4;
	return 0.0;
}

// Отражённый свет: билинейно по центрам клеток, но только из клеток, связанных с клеткой точки
vec3 g_bounce_at(vec3 p) {
	vec2 f = p.xz / GC - 0.5;
	ivec2 b0 = ivec2(floor(f));
	vec2 t = f - vec2(b0);
	ivec2 cp = ivec2(floor(p.xz / GC));
	ivec2 cc[4];
	vec4 ct[4];
	for (int k = 0; k < 4; k++) {
		cc[k] = b0 + ivec2(k & 1, k >> 1);
		ct[k] = g_cell(cc[k]);
	}
	int me = 0;
	for (int k = 0; k < 4; k++) {
		if (cc[k] == cp) me = k;
	}
	vec3 acc = vec3(0.0);
	float ws = 0.0;
	for (int k = 0; k < 4; k++) {
		ivec2 o = ivec2(k & 1, k >> 1);
		float w = (o.x == 1 ? t.x : 1.0 - t.x) * (o.y == 1 ? t.y : 1.0 - t.y);
		if ((g_bits(ct[k]) & 64) != 0) continue;
		float link = 1.0;
		if (k != me) {
			ivec2 dd = cc[k] - cc[me];
			if (dd.x != 0 && dd.y != 0) {
				// по диагонали — через любую из двух соседних клеток
				int m1 = me ^ 1;
				int m2 = me ^ 2;
				float l1 = g_link(cc[me], ct[me], cc[m1], ct[m1]) * g_link(cc[m1], ct[m1], cc[k], ct[k]);
				float l2 = g_link(cc[me], ct[me], cc[m2], ct[m2]) * g_link(cc[m2], ct[m2], cc[k], ct[k]);
				link = max(l1, l2);
			} else {
				link = g_link(cc[me], ct[me], cc[k], ct[k]);
			}
		}
		w *= link;
		if (w <= 0.0) continue;
		vec4 bl = texelFetch(g_bounce, g_wrap(cc[k]), 0);
		int grp = int(bl.a * 8.0 + 0.5);
		vec3 L = G_WARM * (bl.r + bl.g * g_flick_of(grp)) * g_power + G_RED * bl.b;
		if (grp == 7) L = G_WARM * bl.r * g_power + G_GREEN * bl.g * g_flick_of(7) + G_RED * bl.b;
		acc += L * w;
		ws += w;
	}
	vec3 r = ws > 0.0 ? acc / ws : vec3(0.0);
	if (g_ldim.w > 0.0) {
		r *= 1.0 - g_ldim.w * smoothstep(14.0, 2.0, distance(p + vec3(0.0, g_grid.x, 0.0), g_ldim.xyz)) * 0.6;
	}
	return r;
}

// Затенение углов: близость к стенам клетки, к полу и потолку. p — точка слоя (сдвинута по нормали),
// n — геометрическая нормаль (стена, на которой лежит точка, сама себя не затеняет).
float g_ao(vec3 p, vec3 n) {
	ivec2 c = ivec2(floor(p.xz / GC));
	vec4 me = g_cell(c);
	vec2 lp = p.xz - vec2(c) * GC;
	int bm = g_bits(me);
	int bw = g_bits(g_cell(c + ivec2(-1, 0)));
	int bn = g_bits(g_cell(c + ivec2(0, -1)));
	int e_e = bm & 7;
	int e_s = (bm >> 3) & 7;
	int e_w = bw & 7;
	int e_n = (bn >> 3) & 7;
	float ao = 1.0;
	float fl = g_floor_at(me, c, p.xz);
	float ce = g_ceil(me);
	float de = GC - lp.x - 0.1;
	float dw = lp.x - 0.1;
	float ds = GC - lp.y - 0.1;
	float dn = lp.y - 0.1;
	bool door_x = abs(lp.y - GC * 0.5) < 0.55 && p.y < fl + 2.1;
	bool door_z = abs(lp.x - GC * 0.5) < 0.55 && p.y < fl + 2.1;
	bool arch_low = p.y < fl + 2.25;
	if (n.x > -0.5 && (e_e == 1 || e_e == 4 || (e_e == 2 && !door_x) || (e_e == 3 && !arch_low))) ao *= 1.0 - 0.4 * exp(-max(de, 0.0) / 0.3);
	if (n.x < 0.5 && (e_w == 1 || e_w == 4 || (e_w == 2 && !door_x) || (e_w == 3 && !arch_low))) ao *= 1.0 - 0.4 * exp(-max(dw, 0.0) / 0.3);
	if (n.z > -0.5 && (e_s == 1 || e_s == 4 || (e_s == 2 && !door_z) || (e_s == 3 && !arch_low))) ao *= 1.0 - 0.4 * exp(-max(ds, 0.0) / 0.3);
	if (n.z < 0.5 && (e_n == 1 || e_n == 4 || (e_n == 2 && !door_z) || (e_n == 3 && !arch_low))) ao *= 1.0 - 0.4 * exp(-max(dn, 0.0) / 0.3);
	if (n.y < 0.5) ao *= 1.0 - 0.42 * exp(-max(p.y - fl, 0.0) / 0.26);
	if (n.y > -0.5 && ce < 90.0) ao *= 1.0 - 0.32 * exp(-max(ce - p.y, 0.0) / 0.2);
	return ao;
}

// Нормаль из карты нормалей без касательных: кокасательный базис по производным (Schüler).
// tnx — xy из карты (−1..1), z восстанавливается. Соглашение карт: x — вдоль +u, y — вдоль +v (вниз по картинке).
vec3 g_perturb(vec3 n, vec3 p, vec2 uv, vec2 tnx, float k) {
	vec3 dp1 = dFdx(p);
	vec3 dp2 = dFdy(p);
	vec2 du1 = dFdx(uv);
	vec2 du2 = dFdy(uv);
	vec3 dp2perp = cross(dp2, n);
	vec3 dp1perp = cross(n, dp1);
	vec3 T = dp2perp * du1.x + dp1perp * du2.x;
	vec3 B = dp2perp * du1.y + dp1perp * du2.y;
	float invmax = inversesqrt(max(max(dot(T, T), dot(B, B)), 1e-20));
	vec2 xy = tnx * k;
	float z = sqrt(max(1.0 - dot(tnx, tnx), 0.0));
	return normalize(T * invmax * xy.x + B * invmax * xy.y + n * max(z, 0.2));
}
