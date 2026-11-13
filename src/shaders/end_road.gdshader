shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
// Концовка «шоссе»: одна плоскость на всё — двухполосная дорога US 50 (асфальт, прерывистая жёлтая ось,
// белые края, колеи), гравийная обочина и пустыня до горизонта. Одной поверхностью — без z-fighting разметки.

uniform sampler2D asphalt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D desert_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float ax = abs(p.x);
	vec3 m1 = texture(noise_tex, p / 70.0).rgb;
	vec3 m2 = texture(noise_tex, p / 9.0 + 0.4).rgb;
	// асфальт: заплаты, светлее по середине полос, колеи темнее
	// старый выгоревший асфальт светлее свежего: в свете луны и фар читается зерно и заплаты
	vec3 asph = texture(asphalt_tex, p / 3.5).rgb * (0.82 + 0.3 * m1.r) * 1.15 + vec3(0.012);
	float wheel = exp(-pow((ax - 0.95) / 0.38, 2.0)) + exp(-pow((ax - 2.75) / 0.38, 2.0));
	asph *= 1.0 - 0.1 * wheel;
	asph = mix(asph, asph * 0.7, smoothstep(0.62, 0.7, m1.g) * 0.6);          // свежие заплаты
	// разметка: ось — жёлтые штрихи 3 м через 9 м, края — сплошные белые; краска стёрта местами
	float wear = smoothstep(0.25, 0.55, m2.b + 0.25);
	float dash = step(fract(p.y / 12.2), 0.25);
	float cl = smoothstep(0.07, 0.055, ax) * dash;
	float el = smoothstep(0.075, 0.055, abs(ax - 3.62));
	vec3 col = asph;
	col = mix(col, vec3(0.72, 0.56, 0.16), cl * wear);
	col = mix(col, vec3(0.74, 0.74, 0.7), el * wear);
	float paint = (cl + el) * wear;
	// обочина (гравий) и пустыня
	vec3 des = texture(desert_tex, p / 8.0).rgb * (0.8 + 0.35 * m1.g);
	vec3 des2 = texture(desert_tex, p / 23.0 + 0.37).rgb;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	des = mix(des, des2 * (0.8 + 0.35 * m1.g), smoothstep(30.0, 120.0, dist) * 0.6);
	vec3 gravel = mix(des, vec3(0.34, 0.32, 0.29) * (0.8 + 0.4 * m2.r), 0.65);
	float road = smoothstep(4.0, 3.9, ax);
	float shoulder = smoothstep(5.8, 4.6, ax + (m2.g - 0.5) * 0.8);
	vec3 ground = mix(des * 0.85, gravel, shoulder);
	col = mix(ground, col, road);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, mix(0.68, 0.5, paint), road);
	SPECULAR = mix(0.3, mix(0.5, 0.8, paint), road);
}
