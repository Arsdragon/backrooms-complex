shader_type sky;
// Концовка «небо»: летний полдень. Небо светлеет к горизонту, солнце с ореолом, слой кучевых облаков
// (поле облаков из tex/fx_cloudmap проецируется на плоскость над камерой — облака уходят в перспективу).

uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 zenith = vec3(0.17, 0.33, 0.62);
uniform vec3 horizon = vec3(0.66, 0.74, 0.82);
uniform vec3 ground = vec3(0.34, 0.4, 0.42);
uniform float cloud_h = 1300.0;           // высота основания облаков над камерой, м
uniform float cloud_tile = 15000.0;       // размер тайла поля облаков, м
uniform float coverage = 0.68;

void sky() {
	vec3 d = EYEDIR;
	vec3 sun = normalize(LIGHT0_DIRECTION);
	float up = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(horizon, zenith, pow(up, 0.55));
	// ниже горизонта — дымка над далёкими холмами (почти не видна: её закрывает земля)
	col = mix(col, ground, smoothstep(0.0, -0.25, d.y));
	float sd = max(dot(d, sun), 0.0);
	vec3 sun_col = vec3(1.0, 0.96, 0.88);
	col += sun_col * (pow(sd, 8.0) * 0.18 + pow(sd, 64.0) * 0.35);
	if (d.y > 0.004) {
		vec2 p = d.xz / d.y * cloud_h;
		vec2 uv = p / cloud_tile + vec2(0.37, 0.61);
		// облако: крупная форма + несколько октав «размывающей» детали по краю — кромка рваная и мягкая,
		// без вырезанного силуэта; к горизонту (мелкие в кадре) детали меньше
		// крупная форма — с размытого мипа (мягкая кромка в сотни метров), детали — с резких
		float c = texture(cloud_tex, uv, 3.5).r * 1.25;
		float c2 = texture(cloud_tex, uv * 2.7 + vec2(0.2, 0.7), 2.0).r;
		float c3 = texture(cloud_tex, uv * 7.3 + vec2(0.61, 0.13)).r;
		float c4 = texture(cloud_tex, uv * 17.0 + vec2(0.33, 0.87)).r;
		float shape = c * 0.78 + c2 * 0.28;
		float ero = (c3 - 0.5) * 0.22 + (c4 - 0.5) * 0.12;
		float dens = smoothstep(1.0 - coverage - 0.08, 1.62 - coverage, shape + ero * smoothstep(0.02, 0.25, d.y));
		dens *= dens * (3.0 - 2.0 * dens);
		// края тоньше и светлее, середина — серое основание; к солнцу светится только тонкий край
		float thick = smoothstep(0.15, 0.9, dens);
		vec3 base = vec3(0.58, 0.61, 0.66) * (0.9 + 0.2 * c3);
		vec3 lit = vec3(0.9, 0.9, 0.88);
		vec3 cc = mix(lit, base, thick * 0.8);
		cc += sun_col * pow(sd, 8.0) * (1.0 - thick) * 0.22;
		float fade = smoothstep(0.01, 0.2, d.y);
		cc = mix(horizon * 1.05, cc, fade);
		col = mix(col, cc, dens * mix(0.35, 0.95, fade));
	}
	if (AT_CUBEMAP_PASS) {
		COLOR = col;
	} else {
		col += sun_col * smoothstep(0.99955, 0.9998, sd) * 30.0;
		COLOR = col;
	}
}
