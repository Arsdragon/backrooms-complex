shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
// Луч проектора в пыльном воздухе. Сетка — только оболочка (усечённая пирамида без торцов, рисуются дальние грани —
// видно и изнутри луча); яркость считается по лучу зрения: ближайшая точка оси луча, сечение — мягкий
// прямоугольник кадра (rx, ry растут от объектива к экрану), плотность падает к экрану. Пыль — медленный шум
// и редкие искорки. Гаснет при отключении питания, тонет в тумане.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 beam_color : source_color = vec3(0.75, 0.8, 0.9);
uniform float strength = 0.07;
uniform vec3 axis_a = vec3(0.0, 0.83, -0.18);   // объектив (локально)
uniform vec3 axis_b = vec3(0.0, 1.55, -4.0);    // центр картинки на стене (локально)
uniform vec2 r_a = vec2(0.03, 0.022);           // полуразмеры сечения у объектива
uniform vec2 r_b = vec2(0.85, 0.575);           // полуразмеры картинки

global uniform float g_power;
global uniform vec4 g_fog;
global uniform vec4 g_dim;
global uniform float g_time;

varying vec3 wpos;
varying vec3 wn;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	// только дальние (от камеры) грани оболочки: нормали наружу; каждый пиксель луча — один раз
	if (dot(wn, cam - wpos) > 0.0) discard;
	vec3 pa = (MODEL_MATRIX * vec4(axis_a, 1.0)).xyz;
	vec3 pb = (MODEL_MATRIX * vec4(axis_b, 1.0)).xyz;
	vec3 rd = normalize(wpos - cam);
	vec3 ab = pb - pa;
	vec3 w0 = cam - pa;
	float bb = dot(rd, ab);
	float cc = dot(ab, ab);
	float dd = dot(rd, w0);
	float ee = dot(ab, w0);
	float den = max(cc - bb * bb, 1e-5);
	float s = clamp((ee - bb * dd) / den, 0.0, 1.0);
	// не дальше стены: точка на луче зрения не за фрагментом оболочки
	float tr = clamp(dot((pa + ab * s) - cam, rd), 0.0, length(wpos - cam) + 0.5);
	vec3 P = pa + ab * s;
	vec3 Q = cam + rd * tr;
	vec3 dv = Q - P;
	// оси сечения: локальный x узла и перпендикуляр к оси в вертикальной плоскости
	vec3 ax = normalize(ab);
	vec3 bx = normalize(MODEL_MATRIX[0].xyz);
	vec3 by = normalize(cross(ax, bx));
	vec2 r = mix(r_a, r_b, s);
	vec2 q = vec2(dot(dv, bx), dot(dv, by)) / r;
	float edge = max(abs(q.x), abs(q.y));
	float shape = 1.0 - smoothstep(0.55, 1.08, edge);
	shape *= exp(-0.6 * dot(q, q));
	// ближе к объективу плотнее; у самой стены луч растворяется в пятне
	float along = mix(0.8, 0.3, sqrt(s)) * smoothstep(1.0, 0.94, s) * smoothstep(0.0, 0.08, s);
	// пыль: медленные клубы и редкие искорки в свете
	float t = g_time;
	float n1 = texture(noise_tex, Q.xz * 0.45 + Q.y * 0.2 + vec2(t * 0.011, -t * 0.007)).r;
	float n2 = texture(noise_tex, Q.zy * 0.8 - vec2(t * 0.017, t * 0.009)).g;
	float dust = 0.55 + 0.7 * n1 * n2;
	float sp = texture(noise_tex, Q.xy * 7.0 + Q.z * 3.1 + vec2(t * 0.03, t * 0.021)).b;
	dust += smoothstep(0.86, 0.95, sp) * 2.5 * shape;
	float dimk = 1.0 - g_dim.w * smoothstep(14.0, 2.0, distance(Q, g_dim.xyz)) * 0.8;
	float fog = exp(-length(Q - cam) * g_fog.a);
	float I = strength * shape * along * dust * g_power * dimk * fog;
	ALBEDO = beam_color * I;
}
