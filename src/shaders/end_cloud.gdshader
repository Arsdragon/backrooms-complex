shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_front, shadows_disabled;
// Концовка «небо»: клок облака на высоте падения — объёмный эллипсоид (SphereMesh радиуса 1, растянутый узлом),
// а не плоский спрайт лицом к камере. Плотность — толщина эллипсоида по лучу взгляда (аналитически), край рвёт
// 3D-шум в мировых координатах: силуэт клочьями, при полёте мимо не «поворачивается» за камерой.
// Рисуются задние грани — облако видно и изнутри (пролетая сквозь, кадр белеет).

uniform vec3 sun_dir = vec3(0.5, 0.6, 0.3);             // на солнце, мир
uniform vec3 lit_col : source_color = vec3(0.8, 0.81, 0.82);   // освещённая сторона — серее белого: камера
uniform vec3 shade_col : source_color = vec3(0.47, 0.52, 0.6); // считает почти белое лампой и раздувает
uniform float density = 1.0;
instance uniform float seed = 0.0;

varying vec3 o_cam;
varying vec3 o_pos;
varying vec3 o_sun;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += vnoise(p) * a;
		p = p * 2.07 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s / 0.9375;
}

void vertex() {
	mat4 inv = inverse(MODEL_MATRIX);
	o_pos = VERTEX;
	o_cam = (inv * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	o_sun = normalize((inv * vec4(normalize(sun_dir), 0.0)).xyz);
}

void fragment() {
	vec3 rd = normalize(o_pos - o_cam);
	float b = dot(o_cam, rd);
	float c = dot(o_cam, o_cam) - 1.0;
	float h = b * b - c;
	if (h <= 0.0) {
		discard;
	}
	h = sqrt(h);
	float t0 = max(-b - h, 0.0);
	float t1 = -b + h;
	float th = max(t1 - t0, 0.0) * 0.5;                    // 0..1: доля диаметра
	vec3 pe = o_cam + rd * t0;                             // вход луча
	vec3 pm = o_cam + rd * (t0 + t1) * 0.5;
	vec3 pw = (MODEL_MATRIX * vec4(pm, 1.0)).xyz;
	float n0 = fbm(pw * 0.03 + vec3(seed * 0.21, 5.3, seed));
	float n = fbm(pw * 0.075 + vec3(seed, seed * 0.37, TIME * 0.004));
	float n2 = fbm(pw * 0.23 + vec3(3.1, seed, 1.7));
	// плотность: толща по лучу; силуэт ломает крупный шум (лопасти размером с сам клок), края рвутся мелким
	// на клочья, середина плотная, но с просветами — не гладкий эллипсоид
	float nc = n0 * 0.5 + n * 0.33 + n2 * 0.17;
	// край — изолиния «расстояния луча от центра» rho, сдвинутая шумом: лопасти и клочья по всему контуру
	// (по одной толще край остаётся ровным эллипсом — толща у края растёт слишком круто)
	float rho = sqrt(max(dot(o_cam, o_cam) - b * b, 0.0));
	float er = 0.12 + nc * 1.25;
	float a = smoothstep(er, er - 0.4, rho) * smoothstep(0.0, 0.3, th) * density;
	// свет: сторона к солнцу и верх ярче, низ — серо-синий; «кочаны» со своими тенями
	vec3 pn = normalize(pe + vec3(0.0001));
	float lit = clamp(0.45 + 0.42 * dot(pn, o_sun) + 0.3 * pn.y + (n - 0.5) * 0.9 + (n2 - 0.5) * 0.4 - th * 0.25, 0.0, 1.0);
	ALBEDO = mix(shade_col, lit_col, lit);
	ALPHA = clamp(a, 0.0, 0.92);
}
