shader_type sky;
// Концовка «шоссе»: ночное небо пустыни Невады. Почти чёрное, у горизонта светлее (свечение воздуха),
// впереди над дорогой — слабое тёплое зарево далёкого городка. Звёзды — только редкие яркие (их и берёт камера).

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 glow_dir = vec3(0.0, 0.0, -1.0);
uniform float star_gain = 1.0;

float hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

// звёзды одного слоя: в каждой ячейке — одна звезда в случайной точке
vec3 stars(vec3 d, float scale, float keep, float bright) {
	vec3 q = d * scale;
	vec3 id = floor(q);
	vec3 f = fract(q);
	float h = hash3(id);
	if (h > keep) {
		return vec3(0.0);
	}
	vec3 c = vec3(hash3(id + 1.7), hash3(id + 3.1), hash3(id + 5.3)) * 0.6 + 0.2;
	float r = length(f - c);
	float mag = pow(hash3(id + 9.7), 5.0);
	float s = exp(-r * r / 0.012) * (0.08 + mag * 1.6) * bright;
	vec3 tint = mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.86, 0.68), hash3(id + 11.0));
	return tint * s;
}

void sky() {
	vec3 d = EYEDIR;
	float up = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(vec3(0.013, 0.016, 0.028), vec3(0.002, 0.003, 0.008), smoothstep(0.0, 0.45, up));
	// зарево за горизонтом впереди
	vec2 hz = normalize(d.xz + vec2(1e-5));
	float g = pow(max(dot(hz, normalize(glow_dir.xz)), 0.0), 10.0) * exp(-up * 14.0);
	col += vec3(0.045, 0.03, 0.016) * g;
	col = mix(col, vec3(0.006, 0.006, 0.008), smoothstep(0.0, -0.08, d.y));
	if (!AT_CUBEMAP_PASS && d.y > -0.02) {
		// Млечный Путь: широкая полоса по большому кругу, рваная шумом
		vec3 mw_n = normalize(vec3(0.62, 0.35, -0.7));
		float band = exp(-pow(dot(d, mw_n) / 0.2, 2.0));
		vec2 suv = vec2(atan(d.x, d.z) / 6.2831, d.y * 0.5);
		float n1 = texture(noise_tex, suv * 3.0).r;
		float n2 = texture(noise_tex, suv * 9.0 + 0.3).g;
		float mw = band * smoothstep(0.35, 0.85, n1 * 0.7 + n2 * 0.4) * smoothstep(0.0, 0.25, up);
		// Млечный Путь бытовая камера почти не берёт — едва заметная полоса
		col += vec3(0.022, 0.024, 0.03) * mw * 0.25;
		float ext = smoothstep(0.02, 0.3, d.y);            // у горизонта звёзды гаснут в дымке
		// только самые яркие звёзды: редкие, мягкие (оптика и плёнка размывают точку), большинство — на пределе
		vec3 st = stars(d, 120.0, 0.012, 0.9) + stars(d, 200.0, 0.006, 0.3);
		col += st * ext * star_gain;
	}
	COLOR = col;
}
