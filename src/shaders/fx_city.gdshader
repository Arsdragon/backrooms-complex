shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, fog_disabled;
// «Красный город» за окнами перехода (props.gd red_city): ночной город, освещённый только собой.
// mode 0 — фасад: UV — метры (u вдоль стены, v вверх от земли); сетка окон по этажам и пролётам, часть окон
//          горит (красный/оранжевый/янтарный, шторы и жалюзи), тёмные окна чуть отражают зарево неба, низ
//          фасада подсвечен улицей; даль тонет в красно-бурой дымке.
// mode 1 — крыши/земля: почти чёрные, с дымкой.
// mode 2 — небо-задник: зарево у горизонта (UV.y — высота над землёй, м) и дальние силуэты кварталов
//          с редкими огнями (UV.x — метры вдоль задника).

uniform float mode = 0.0;
uniform vec3 haze_col : source_color = vec3(0.16, 0.045, 0.025);
uniform vec3 glow_col : source_color = vec3(0.55, 0.14, 0.06);
uniform float horizon = 14.0;      // высота зарева над землёй (м)
uniform float haze_near = 18.0;
uniform float haze_far = 170.0;
uniform float haze_max = 0.72;
instance uniform vec4 bld = vec4(0.0, 3.2, 3.2, 0.45);   // сид, высота этажа, ширина пролёта, доля горящих окон
instance uniform float style = 0.0;                        // 0 — окна-проёмы, 1 — ленточные окна, 2 — узкие высокие

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec3 window_col(float r, float k) {
	vec3 a = vec3(1.0, 0.13, 0.05);
	vec3 b = vec3(1.0, 0.36, 0.1);
	vec3 c = vec3(0.85, 0.45, 0.2);
	vec3 col = r < 0.55 ? a : (r < 0.85 ? b : c);
	return col * k;
}

void fragment() {
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float dist = distance(cam, wpos);
	float hz = smoothstep(haze_near, haze_far, dist) * haze_max;
	vec3 col = vec3(0.0);
	if (mode < 0.5) {
		vec2 m = UV;
		float seed = bld.x;
		float fh = bld.y;
		float bw = bld.z;
		vec2 cell = floor(vec2(m.x / bw, m.y / fh));
		vec2 f = fract(vec2(m.x / bw, m.y / fh));
		// стена: тёмный бетон, панели чуть различаются
		float pn = h21(cell * 0.37 + seed);
		col = vec3(0.016, 0.012, 0.011) * (0.8 + 0.4 * pn);
		// окно
		vec2 lo = style < 0.5 ? vec2(0.18, 0.28) : (style < 1.5 ? vec2(0.02, 0.32) : vec2(0.3, 0.16));
		vec2 hi = style < 0.5 ? vec2(0.82, 0.86) : (style < 1.5 ? vec2(0.98, 0.8) : vec2(0.7, 0.9));
		float inx = step(lo.x, f.x) * step(f.x, hi.x) * step(lo.y, f.y) * step(f.y, hi.y);
		if (cell.y < 0.5) {
			// первый этаж: витрины во всю ширину, чаще тёмные
			inx = step(0.06, f.x) * step(f.x, 0.94) * step(0.12, f.y) * step(f.y, 0.78);
		}
		float r1 = h21(cell + vec2(seed * 7.1, seed * 3.3));
		float r2 = h21(cell.yx + vec2(seed * 1.7, 9.2));
		float lit = step(r1, bld.w * (cell.y < 0.5 ? 0.5 : 1.0));
		if (inx > 0.5) {
			// тёмное стекло: отражает зарево неба, к верху окна светлее
			vec3 glass = glow_col * (0.03 + 0.03 * f.y) + vec3(0.004);
			vec3 wc = window_col(r2, 0.5 + 0.9 * h21(cell + 3.7 + seed));
			// внутри: потолок комнаты ярче, низ — темнее; шторы/жалюзи у части окон
			float inside = mix(0.55, 1.0, smoothstep(lo.y, hi.y, f.y));
			float blind = (r2 > 0.6) ? (0.55 + 0.45 * step(0.5, fract(f.y * 14.0))) : 1.0;
			float curt = (r2 < 0.25) ? mix(0.25, 1.0, smoothstep(0.0, 0.25, abs(f.x - 0.5) * 2.0 - 0.45 + 0.25)) : 1.0;
			col = mix(glass, wc * inside * blind * curt, lit);
			// переплёт
			float mull = step(abs(f.x - 0.5), 0.012) * (style < 1.5 ? 1.0 : 0.0);
			col *= 1.0 - 0.7 * mull;
		}
		// низ подсвечен улицей (натрий), верх — заревом
		col += vec3(0.5, 0.22, 0.06) * 0.05 * exp(-m.y / 4.0);
		col += glow_col * 0.012 * smoothstep(0.0, 40.0, m.y);
	} else if (mode < 1.5) {
		col = vec3(0.01, 0.008, 0.008) + glow_col * 0.01;
	} else if (mode < 2.5) {
		// небо: зарево у горизонта, выше — тёмное, облачная дымка пятнами
		float y = UV.y;
		float g = exp(-max(y - horizon, 0.0) / 18.0) * smoothstep(-20.0, horizon, y);
		col = glow_col * (0.05 + 0.3 * g) + vec3(0.006, 0.004, 0.006);
		// дальние кварталы: силуэт по x (ступенчатый шум), редкие огни
		float bx = floor(UV.x / 7.0);
		float hb = 3.0 + 22.0 * pow(h21(vec2(bx, 4.1)), 2.0) + 6.0 * h21(vec2(floor(UV.x / 23.0), 1.3));
		if (y < hb) {
			col = mix(vec3(0.03, 0.012, 0.01), glow_col * 0.12, 0.35);
			vec2 wc2 = floor(vec2(UV.x / 2.2, y / 2.6));
			vec2 wf = fract(vec2(UV.x / 2.2, y / 2.6));
			float on = step(h21(wc2 + 1.3), 0.22) * step(0.25, wf.x) * step(wf.x, 0.75) * step(0.3, wf.y) * step(wf.y, 0.8);
			col += window_col(h21(wc2 + 7.7), 0.35) * on;
		}
		hz *= 0.3;
	}
	col = mix(col, haze_col, hz);
	ALBEDO = col;
}
