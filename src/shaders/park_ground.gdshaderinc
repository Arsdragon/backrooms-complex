// Общее для земли и травы парка: маска (R — расстояние до края асфальта, м, внутри < 0; G — то же для бетонной
// площади; B — «голая земля» 0..1; A — расстояние до края песка) и макрошум газона.
uniform sampler2D park_mask : filter_linear, repeat_disable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 mask_rect = vec4(-96.0, -96.0, 192.0, 192.0);
// провал под героем в конце парка: xy — центр (мир x, z), z — радиус (0 — провала нет), w — фаза формы
uniform vec4 park_hole = vec4(0.0, 0.0, 0.0, 0.0);

vec4 park_mask_at(vec2 p) {
	return textureLod(park_mask, (p - mask_rect.xy) / mask_rect.zw, 0.0);
}

// Радиус провала по направлению a (та же формула — у стенок колодца в park.gd: Park.hole_r)
float park_hole_r(float a) {
	float w = park_hole.w;
	return park_hole.z * (1.0 + 0.13 * sin(3.0 * a + w) + 0.07 * sin(7.0 * a + w * 2.3) + 0.04 * sin(13.0 * a + w * 0.7));
}

// Расстояние до кромки провала (< 0 — внутри); без провала — большое
float park_hole_d(vec2 p) {
	if (park_hole.z <= 0.0) {
		return 1e5;
	}
	vec2 d = p - park_hole.xy;
	return length(d) - park_hole_r(atan(d.y, d.x));
}

// Насколько газон выгорел (0 — сочный, 1 — солома): пятна полива, края дорожек, тень деревьев
float park_dryness(vec2 p, vec4 m) {
	float a = textureLod(macro_tex, p / 95.0, 0.0).r;
	float b = textureLod(macro_tex, p / 31.0 + vec2(0.31, 0.17), 0.0).g;
	float d = smoothstep(0.62, 0.9, a * 0.6 + b * 0.55) * 0.7;
	d = max(d, (1.0 - smoothstep(0.0, 1.0, m.r)) * 0.3);
	d = max(d, smoothstep(0.08, 0.5, m.b) * 0.45);
	return clamp(d, 0.0, 0.9);
}
