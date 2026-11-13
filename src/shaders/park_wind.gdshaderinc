// Ветер растительности парка: бегущие по парку порывы + медленное раскачивание.
// wind — сила (парк гасит её, когда «что-то не так»), wind_dir — направление (единичный вектор по XZ).
uniform float wind = 1.0;
uniform vec2 wind_dir = vec2(0.82, 0.57);

// Порыв в точке wp (0..~1.4): волны вдоль направления ветра, сдвигаются со временем
float park_gust(vec2 wp, float t) {
	float s = dot(wp, wind_dir);
	float c = dot(wp, vec2(-wind_dir.y, wind_dir.x));
	float g = sin(s * 0.043 - t * 0.83 + sin(c * 0.03) * 1.5) * 0.45
		+ sin(s * 0.11 - t * 1.73 + c * 0.05) * 0.22
		+ sin(s * 0.27 - t * 3.1 + c * 0.13) * 0.08;
	return clamp(g + 0.55, 0.0, 1.4);
}

// Смещение кроны/ствола на высоте с весом w (0 у земли, 1 у верхушки): org — корень дерева, ph — фаза
vec3 park_sway(vec3 org, float w, float amp, float t) {
	float ph = dot(org.xz, vec2(0.37, 0.71));
	vec2 side = vec2(-wind_dir.y, wind_dir.x);
	float g = park_gust(org.xz, t);
	vec2 o = wind_dir * (g * 0.7 + sin(t * 0.9 + ph) * 0.22 * (0.4 + g)) + side * sin(t * 0.61 + ph * 1.7) * 0.14 * (0.3 + g);
	o *= amp * w * wind;
	return vec3(o.x, -dot(o, o) * 0.12, o.y);
}
