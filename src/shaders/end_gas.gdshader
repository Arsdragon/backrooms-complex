shader_type fog;
// Концовка Async: усыпляющий газ из вентиляции (объёмный туман в FogVolume). Опускается от потолка слоем,
// клубится (3D-шум, медленно сползает вниз и вбок), гуще у решёток. Освещается лампами сцены.

uniform float fill = 0.0;                   // 0..1 — насколько газ заполнил помещение (ведёт сцена)
uniform float ceiling = 2.8;                // высота потолка (мировая)
uniform float density = 1.6;
uniform vec3 albedo : source_color = vec3(0.92, 0.93, 0.92);
uniform vec4 vent_a = vec4(0.0, 2.8, -3.5, 1.4);   // xyz — решётка, w — радиус струи
uniform vec4 vent_b = vec4(0.0, 2.8, -9.0, 1.4);

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
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}

float jet(vec3 p, vec4 v, float n) {
	// струя из решётки: расширяющийся конус вниз, гауссов профиль и рваная шумом граница — без резкого края
	// (объёмный туман считается крупными ячейками-фрокселями: резкий перепад плотности даёт «ступеньки»)
	vec3 d = p - v.xyz;
	float down = clamp(-d.y, 0.0, 3.0);
	float r = length(d.xz) / (v.w * (0.5 + down * 0.55)) + (n - 0.5) * 0.6;
	return exp(-r * r * 2.2) * smoothstep(3.0, 0.4, down) * smoothstep(-0.05, 0.35, down);
}

void fog() {
	vec3 p = WORLD_POSITION;
	float t = TIME;
	// слой газа опускается от потолка; кромка слоя рваная
	float edge = ceiling - fill * (ceiling + 0.4);
	float n = fbm(p * 0.85 + vec3(t * 0.06, t * 0.32, -t * 0.09));
	float n2 = fbm(p * 2.1 - vec3(t * 0.15, -t * 0.45, t * 0.11));
	float layer = smoothstep(edge - 0.3, edge + 0.9, p.y + (n - 0.5) * 1.4);
	float j = (jet(p, vent_a, n2) + jet(p, vent_b, n2)) * smoothstep(0.0, 0.15, fill);
	float d = max(layer * smoothstep(0.25, 0.75, n * 0.75 + n2 * 0.35 + fill * 0.2), j * 0.55 * smoothstep(0.15, 0.65, n2));
	DENSITY = d * density * smoothstep(0.0, 0.08, fill);
	ALBEDO = albedo;
}
