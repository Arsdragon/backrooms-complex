shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled, fog_disabled;
// Концовка «космос»: тонкая голубая кромка атмосферы над лимбом (там, где луч не упирается в Землю).
// Однократное рассеяние Рэлея и Ми — те же формулы, что в end_earth.gdshader; над диском планеты — ноль
// (дымку над поверхностью считает шейдер Земли). Ярче всего на солнечной стороне.

uniform vec3 center = vec3(0.0, -7000.0, 0.0);
uniform float radius = 6000.0;
uniform float atmo = 80.0;
uniform vec3 sun = vec3(-0.85, 0.42, 0.31);
uniform float sun_power = 22.0;

const vec3 B_R = vec3(5.8e-3, 13.5e-3, 33.1e-3);
const float B_M = 21e-3;
const float H_R = 8.0;
const float H_M = 1.2;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 ray_sphere(vec3 ro, vec3 rd, float r) {
	float b = dot(ro, rd);
	float c = dot(ro, ro) - r * r;
	float d = b * b - c;
	if (d < 0.0) {
		return vec2(1e9, -1e9);
	}
	d = sqrt(d);
	return vec2(-b - d, -b + d);
}

vec2 light_depth(vec3 p, vec3 l) {
	float t1 = ray_sphere(p, l, radius + atmo).y;
	float st = t1 / 4.0;
	vec2 od = vec2(0.0);
	for (int i = 0; i < 4; i++) {
		float h = length(p + l * (st * (float(i) + 0.5))) - radius;
		od += exp(-max(h, 0.0) / vec2(H_R, H_M)) * st;
	}
	return od;
}

void fragment() {
	vec3 ro = CAMERA_POSITION_WORLD - center;
	vec3 rd = normalize(wpos - CAMERA_POSITION_WORLD);
	vec2 pl = ray_sphere(ro, rd, radius);
	vec2 ta = ray_sphere(ro, rd, radius + atmo);
	if (ta.x > ta.y || (pl.x < pl.y && pl.x > 0.0)) {
		discard;
	}
	vec3 l = normalize(sun);
	float t0 = max(ta.x, 0.0);
	float st = (ta.y - t0) / 12.0;
	vec2 od_v = vec2(0.0);
	vec3 sum_r = vec3(0.0);
	vec3 sum_m = vec3(0.0);
	for (int i = 0; i < 12; i++) {
		vec3 p = ro + rd * (t0 + st * (float(i) + 0.5));
		float h = length(p) - radius;
		vec2 dens = exp(-max(h, 0.0) / vec2(H_R, H_M)) * st;
		od_v += dens;
		// тень Земли: точка за планетой от солнца не освещена
		vec2 sh = ray_sphere(p, l, radius);
		if (sh.x < sh.y && sh.x > 0.0) {
			continue;
		}
		vec2 od_l = light_depth(p, l);
		vec3 att = exp(-(B_R * (od_v.x + od_l.x) + B_M * 1.1 * (od_v.y + od_l.y)));
		sum_r += dens.x * att;
		sum_m += dens.y * att;
	}
	float mu = dot(rd, l);
	float pr = 3.0 / (16.0 * PI) * (1.0 + mu * mu);
	float g = 0.76;
	float pm = 3.0 / (8.0 * PI) * ((1.0 - g * g) * (1.0 + mu * mu)) / ((2.0 + g * g) * pow(1.0 + g * g - 2.0 * g * mu, 1.5));
	ALBEDO = sun_power * 0.4 * (sum_r * B_R * pr + sum_m * B_M * pm);
}
