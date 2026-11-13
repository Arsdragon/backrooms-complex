// Небо над Сан-Хосе в жаркий июльский день: белёсый зенит, у горизонта тёплая дымка смога,
// маленькое горячее солнце с ореолом в дымке, редкие кучевые облака и перистые полосы.
shader_type sky;

uniform vec3 zenith : source_color = vec3(0.40, 0.56, 0.80);
uniform vec3 horizon : source_color = vec3(0.80, 0.82, 0.82);
uniform vec3 haze : source_color = vec3(0.86, 0.81, 0.70);
uniform vec3 below : source_color = vec3(0.60, 0.57, 0.50);
uniform sampler2D clouds : filter_linear_mipmap, repeat_enable;
uniform float cover = 0.6;          // порог облачности (больше — меньше облаков)
uniform float cloud_scale = 0.12;
uniform float sun_glow = 0.7;
uniform float brightness = 1.0;
uniform vec2 drift = vec2(0.0012, 0.0005);

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	float hu = max(h, 0.0);
	vec3 col = mix(horizon, zenith, pow(smoothstep(0.0, 1.0, hu), 0.6));
	col = mix(col, haze, exp(-hu * 8.0) * 0.92);
	vec3 sd = LIGHT0_DIRECTION;
	float cs = max(dot(d, sd), 0.0);
	vec3 sun_c = LIGHT0_COLOR * LIGHT0_ENERGY;
	// ореол в дымке: яркое ядро ~1° и мягкое светлое пятно, без широкого «прожектора» (засветку и смаз
	// в объективе рисует камера)
	// угол до солнца через 1 - cos (без acos): t2 ≈ θ²; ореол — мягкие «хвосты» (как рассеяние в дымке), не диск
	float t2 = 2.0 * (1.0 - cs);
	float aur = 0.3 / (1.0 + t2 / 0.00005) + 0.05 / (1.0 + t2 / 0.0028) + pow(cs, 6.0) * 0.03;
	col += sun_c * aur * sun_glow;
	// сам диск ~0,5° — очень горячий (в кадре — маленькое белое ядро)
	float disc = smoothstep(0.99996, 0.999982, cs);
	col += sun_c * disc * 60.0;
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.1) * cloud_scale + drift * TIME;
		vec4 c = texture(clouds, uv);
		vec4 c2 = texture(clouds, uv * 2.1 + vec2(0.37, 0.11));
		float dens = c.r + (c2.g - 0.5) * 0.16;
		float cu = smoothstep(cover, cover + 0.22, dens);
		// подсветка: облако светлее со стороны солнца, днище серее
		vec4 cl = texture(clouds, uv + sd.xz * 0.015);
		float dl = cl.r + (c2.g - 0.5) * 0.16;
		float lit = clamp(0.62 + (dens - dl) * 7.0 - (1.0 - smoothstep(cover, cover + 0.35, dens)) * -0.2, 0.0, 1.0);
		// у солнца светится только тонкий край облака (рассеяние вперёд), плотная середина — серая: облако
		// рядом с солнцем не выбивается в белый «второй диск»
		float thin = 1.0 - smoothstep(cover + 0.04, cover + 0.3, dens);
		vec3 ccol = mix(vec3(0.7, 0.71, 0.73), vec3(0.97, 0.96, 0.93), lit) * (1.0 - pow(cs, 24.0) * 0.18 * (1.0 - thin))
			+ sun_c * pow(cs, 10.0) * 0.16 * thin;
		float ci = smoothstep(0.62, 0.9, texture(clouds, uv * 0.35 + vec2(0.2, 0.6)).b) * 0.16;
		float fadeh = smoothstep(0.015, 0.2, h);
		ccol = mix(haze, ccol, smoothstep(0.0, 0.25, h));
		col = mix(col, vec3(1.0, 0.99, 0.96), ci * fadeh * (1.0 - cu));
		col = mix(col, ccol, cu * fadeh * 0.92);
	} else {
		col = mix(haze, below, smoothstep(0.0, -0.2, h));
	}
	COLOR = col * brightness;
}
