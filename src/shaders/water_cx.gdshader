shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;
// Стоячая вода на полу Комплекса: мутная тёмная толща, в ней — отражение комнаты (экранные отражения по буферу
// глубины: жёлтые стены, светильники), слегка дрожащее от ряби; там, где отражение не нашлось (край кадра) —
// отражённый свет клеток. По Френелю: под ногами — тёмная муть, к дали — зеркало.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
global uniform vec4 g_flick_a;
global uniform vec4 g_flick_b;
global uniform float g_power;
global uniform vec4 g_fog;
global uniform vec4 g_dim;
global uniform float g_ambient;
global uniform float g_time;

#include "res://src/shaders/grid_light.gdshaderinc"

varying vec3 wpos;

vec3 view_at(vec2 suv, mat4 inv_proj) {
	float d = textureLod(depth_tex, suv, 0.0).r;
	vec4 v = inv_proj * vec4(suv * 2.0 - 1.0, d, 1.0);
	return v.xyz / v.w;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// рябь: две медленные волны шума дают наклон нормали
	vec2 uv = wpos.xz * 0.22;
	vec2 o1 = vec2(g_time * 0.011, g_time * 0.007);
	vec2 o2 = vec2(-g_time * 0.009, g_time * 0.012);
	float e = 0.015;
	float h0 = texture(noise_tex, uv + o1).r + texture(noise_tex, uv * 1.7 + o2).g * 0.5;
	float hx = texture(noise_tex, uv + o1 + vec2(e, 0.0)).r + texture(noise_tex, (uv + vec2(e, 0.0)) * 1.7 + o2).g * 0.5;
	float hz = texture(noise_tex, uv + o1 + vec2(0.0, e)).r + texture(noise_tex, (uv + vec2(0.0, e)) * 1.7 + o2).g * 0.5;
	vec3 n = normalize(vec3(-(hx - h0) * 0.1, 1.0, -(hz - h0) * 0.1));
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 v = normalize(cam - wpos);
	// стоячая вода с плёнкой — зеркальнее чистой: даже под ногами заметно отражение потолка
	float fr = 0.3 + 0.7 * pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 4.0);

	vec3 L = vec3(0.0);
	vec3 S = vec3(0.0);
	vec3 fallback = vec3(0.0);
	if (g_grid.y > 0.5) {
		vec3 p = wpos + vec3(0.0, 0.04, 0.0) - vec3(0.0, g_grid.x, 0.0);
		g_direct(p, n, v, 0, 160.0, 0.08, L, S);
		vec3 B = g_bounce_at(p);
		L += B * g_grid.z;
		// зеркальный потолок (то, что экранное отражение не видит — он над кадром): луч до плоскости потолка,
		// там — освещённые плиты и, если попали в светильник, его светящийся рассеиватель
		vec3 rw = reflect(-v, n);
		vec4 c0 = g_cell(ivec2(floor(p.xz / GC)));
		float ce = g_ceil(c0);
		fallback = B * 0.35;
		if (rw.y > 0.03 && ce < 90.0) {
			float tc = (ce - p.y) / rw.y;
			vec3 hp = p + rw * tc;
			ivec2 hc = ivec2(floor(hp.xz / GC));
			vec3 ceil_col = vec3(0.78, 0.77, 0.72) * (g_bounce_at(hp - vec3(0.0, 0.1, 0.0)) * 0.9 + vec3(g_ambient));
			vec4 lm = texelFetch(g_lamps, g_wrap(hc), 0);
			vec2 lo = hp.xz - (vec2(hc) + 0.5) * GC;
			int kind = int(lm.b + 0.5);
			if (lm.g > 0.0 && kind <= 1 && abs(lm.r - ce) < 0.3 && abs(lo.x) < 0.29 && abs(lo.y) < 0.59) {
				float fv = kind == 1 ? g_flick_of(int(lm.a + 0.5)) : 1.0;
				ceil_col = G_WARM * 4.5 * fv * g_power;
			}
			fallback = mix(ceil_col, fallback, smoothstep(6.0, 18.0, tc));
		}
	}
	L += vec3(g_ambient);

	// экранное отражение: луч в пространстве вида по отражённому направлению, шаги растут, затем уточнение
	vec3 nv = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 rv = reflect(normalize(VERTEX), nv);
	vec3 refl = fallback;
	float hit = 0.0;
	if (rv.z < 0.2) {
		vec3 pos = VERTEX;
		float stp = 0.12;
		vec3 prev = pos;
		for (int i = 0; i < 28; i++) {
			prev = pos;
			pos += rv * stp;
			stp *= 1.18;
			vec4 cp = PROJECTION_MATRIX * vec4(pos, 1.0);
			vec2 suv = cp.xy / cp.w * 0.5 + 0.5;
			if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0 || cp.w <= 0.0) break;
			float sz = view_at(suv, INV_PROJECTION_MATRIX).z;
			if (pos.z < sz && sz - pos.z < max(0.6, stp * 2.0)) {
				// уточнение между prev и pos
				vec3 a = prev;
				vec3 b = pos;
				for (int k = 0; k < 5; k++) {
					vec3 m = (a + b) * 0.5;
					vec4 cm = PROJECTION_MATRIX * vec4(m, 1.0);
					vec2 mu = cm.xy / cm.w * 0.5 + 0.5;
					if (m.z < view_at(mu, INV_PROJECTION_MATRIX).z) b = m; else a = m;
				}
				vec4 cb = PROJECTION_MATRIX * vec4(b, 1.0);
				vec2 bu = cb.xy / cb.w * 0.5 + 0.5;
				vec2 edge = smoothstep(0.0, 0.08, bu) * smoothstep(1.0, 0.92, bu);
				hit = edge.x * edge.y * (1.0 - float(i) / 28.0);
				refl = mix(fallback, textureLod(screen_tex, bu, 0.5).rgb, hit);
				break;
			}
		}
	}

	float dd = distance(wpos, g_dim.xyz);
	float dimk = 1.0 - g_dim.w * smoothstep(14.0, 2.0, dd) * 0.5;
	// мутная толща (тёмная, чуть тёплая) + отражение комнаты по Френелю + блики ламп
	vec3 murk = vec3(0.035, 0.032, 0.022) * L;
	vec3 col = mix(murk, refl * 0.92, clamp(fr * 1.15, 0.0, 1.0)) + S * (1.0 - hit * 0.7);
	col *= dimk;
	float dist = length(VERTEX);
	float f = 1.0 - exp(-dist * g_fog.a);
	ALBEDO = mix(col, g_fog.rgb, clamp(f, 0.0, 1.0));
	ALPHA = clamp(0.82 + fr * 0.16, 0.0, 0.98);
}
