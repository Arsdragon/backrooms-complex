shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
// Концовка «небо → лес»: земля с высоты. Вдали — сплошной полог (снимок крон tex/fx_canopy в двух масштабах),
// пятна пород, поляны, каменистые склоны в горах. Около места падения стоят объёмные кроны — там под ними
// тёмный подлесок.

uniform sampler2D canopy : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float trees_r = 430.0;            // радиус зоны объёмных крон
uniform float lake_y = -1000.0;
uniform vec2 lake_c = vec2(900.0, -1500.0);

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// форма озера — та же, что в endings.gd (_lake_d)
float lake_d(vec2 p) {
	float d = length(vec2(p.x - lake_c.x, (p.y - lake_c.y) * 1.6)) / 520.0;
	return d + 0.16 * sin(p.x * 0.0113 + 1.3) * sin(p.y * 0.0127 + 0.4) + 0.07 * sin(p.x * 0.031 + 2.0) * sin(p.y * 0.027 + 0.9);
}

void fragment() {
	vec2 p = wpos.xz;
	float r = length(p);
	vec3 macro = texture(noise_tex, p / 2600.0).rgb;
	vec3 macro2 = texture(noise_tex, p / 640.0 + 0.3).rgb;
	// полог в двух масштабах и под углом — без видимого повтора тайла
	vec3 a = texture(canopy, p / 48.0).rgb;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	vec3 b = texture(canopy, rot * p / 61.0 + 0.5).rgb;
	mat2 rot2 = mat2(vec2(-0.28, 0.96), vec2(-0.96, -0.28));
	vec3 c = texture(canopy, rot2 * p / 83.0 + 0.21).rgb;
	vec3 can = mix(a, b, smoothstep(0.35, 0.65, macro2.r));
	can = mix(can, c, smoothstep(0.4, 0.6, macro.r) * 0.6);
	// вдали узор тайла сливается в средний тон с пятнами пород
	float far_k = smoothstep(250.0, 2000.0, length(wpos - CAMERA_POSITION_WORLD));
	can = mix(can, vec3(0.12, 0.16, 0.075) * (0.7 + 0.6 * macro2.g), far_k * 0.72);
	// тон пород: от тёмных ельников к светлым лиственным
	vec3 tone = mix(vec3(0.62, 0.78, 0.7), vec3(1.08, 1.0, 0.82), smoothstep(0.3, 0.75, macro.g));
	can *= tone * (0.8 + 0.35 * macro2.b);
	// поляны и вырубки
	float clearing = smoothstep(0.8, 0.84, macro2.g * 0.7 + macro.b * 0.45);
	vec3 meadow = mix(vec3(0.07, 0.1, 0.035), vec3(0.11, 0.13, 0.05), macro2.r);
	vec3 col = mix(can * 0.58, meadow, clearing * 0.8);
	// склоны и горы: камень, редкий лес
	float slope = 1.0 - clamp(normalize(wnrm).y, 0.0, 1.0);
	vec3 rock = mix(vec3(0.3, 0.29, 0.26), vec3(0.42, 0.4, 0.36), macro2.g);
	col = mix(col, rock, smoothstep(0.25, 0.45, slope + (wpos.y - 220.0) / 900.0) * 0.8);
	// у объёмных крон — тёмный подлесок
	col = mix(can * 0.22 + vec3(0.008, 0.012, 0.004), col, smoothstep(trees_r - 70.0, trees_r + 10.0, r));
	// озеро: тёмная гладь отражает небо, у берега — полоса камыша и отмели
	float ld = lake_d(p);
	float water = smoothstep(1.0, 0.985, ld);
	col = mix(col, vec3(0.1, 0.11, 0.06), smoothstep(1.03, 1.0, ld) * (1.0 - water));
	ALBEDO = mix(col, vec3(0.012, 0.022, 0.026), water);
	ROUGHNESS = mix(0.95, 0.05, water);
	SPECULAR = mix(0.2, 0.6, water);
}
