shader_type sky;
// Концовка «космос»: чёрное небо, звёзды (камера с автоэкспозицией видит их только когда в кадре мало Земли —
// star_gain задаёт сцена) и солнце с ореолом.

uniform float star_gain = 1.0;

float hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

vec3 stars(vec3 d, float scale, float keep, float bright) {
	vec3 q = d * scale;
	vec3 id = floor(q);
	vec3 f = fract(q);
	if (hash3(id) > keep) {
		return vec3(0.0);
	}
	vec3 c = vec3(hash3(id + 1.7), hash3(id + 3.1), hash3(id + 5.3)) * 0.6 + 0.2;
	float s = smoothstep(0.32, 0.0, length(f - c)) * (0.2 + pow(hash3(id + 9.7), 3.0) * 2.5) * bright;
	return mix(vec3(0.78, 0.84, 1.0), vec3(1.0, 0.88, 0.72), hash3(id + 11.0)) * s;
}

void sky() {
	vec3 d = EYEDIR;
	vec3 col = vec3(0.0);
	if (!AT_CUBEMAP_PASS) {
		col += (stars(d, 300.0, 0.03, 1.0) + stars(d, 620.0, 0.025, 0.45)) * star_gain;
	}
	if (LIGHT0_ENABLED) {
		float sd = dot(d, normalize(LIGHT0_DIRECTION));
		col += vec3(1.0, 0.97, 0.92) * smoothstep(0.99985, 0.99992, sd) * 60.0;
		col += vec3(1.0, 0.92, 0.8) * (pow(max(sd, 0.0), 900.0) * 1.5 + pow(max(sd, 0.0), 60.0) * 0.08);
	}
	COLOR = col;
}
