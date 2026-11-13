shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, blend_mix, depth_draw_never, fog_disabled;
// Концовка «океан»: поверхность воды снизу. Окно Снелла: внутри конуса ~48,6° от вертикали видно небо
// (преломлённое, с солнцем и бликами волн), снаружи — полное внутреннее отражение тёмной толщи.
// Свет от поверхности гаснет в толще по расстоянию (прозрачность) — за ней точный цвет толщи (небо сцены).

uniform sampler2D wave_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 sun_air = vec3(0.0, 1.0, 0.0);   // направление на солнце над водой
uniform float wave_amp = 0.16;
uniform float fog_k = 0.07;                  // ослабление света в воде, 1/м
uniform float sky_gain = 2.6;                  // яркость неба в окне (камера под водой «пересвечена»)

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hgt(vec2 p) {
	float t = TIME;
	float a = texture(wave_tex, p * 0.045 + vec2(t * 0.012, t * 0.007)).r;
	float b = texture(wave_tex, p * 0.11 - vec2(t * 0.019, -t * 0.013)).r;
	float c = texture(wave_tex, p * 0.31 + vec2(-t * 0.03, t * 0.026)).r;
	return a * 0.55 + b * 0.32 + c * 0.13;
}

vec3 sky_air(vec3 r) {
	// небо над водой: у горизонта белёсое, в зените голубое; солнце и ореол
	vec3 zen = vec3(0.32, 0.55, 0.85);
	vec3 hor = vec3(0.85, 0.92, 0.95);
	vec3 col = mix(hor, zen, smoothstep(0.0, 0.7, r.y));
	float s = max(dot(r, normalize(sun_air)), 0.0);
	col += vec3(1.0, 0.95, 0.85) * (pow(s, 900.0) * 40.0 + pow(s, 60.0) * 2.0 + pow(s, 8.0) * 0.35);
	return col;
}

void fragment() {
	vec2 p = wpos.xz;
	float e = 0.12;
	float h0 = hgt(p);
	float hx = hgt(p + vec2(e, 0.0));
	float hz = hgt(p + vec2(0.0, e));
	vec3 n = normalize(vec3(-(hx - h0) / e * wave_amp, 1.0, -(hz - h0) / e * wave_amp));
	vec3 v = normalize(wpos - CAMERA_POSITION_WORLD);   // от камеры вверх
	vec3 r = refract(v, -n, 1.333);
	vec3 refl = reflect(v, -n);
	// отражённая толща: темно, чуть светлее у самой кромки окна
	vec3 tir = vec3(0.006, 0.035, 0.045) + vec3(0.01, 0.04, 0.04) * smoothstep(-0.2, 0.3, refl.y + 0.6);
	vec3 col = tir;
	if (dot(r, r) > 0.001) {
		float cos_t = clamp(r.y, 0.0, 1.0);
		float R = 0.02 + 0.98 * pow(1.0 - cos_t, 5.0);
		col = mix(sky_air(normalize(r)) * sky_gain, tir, R);
	}
	// рябь бликов: мелкие светлые прожилки (каустика поверхности)
	float caus = smoothstep(0.62, 0.9, hgt(p * 1.7 + 3.1)) * 0.25;
	col += vec3(0.4, 0.7, 0.7) * caus * smoothstep(0.55, 0.8, v.y);
	// по дороге к камере вода съедает красное быстрее синего, а рассеяние размывает окно в толщу
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	ALBEDO = col * exp(-dist * vec3(0.09, 0.022, 0.018));
	ALPHA = exp(-dist * fog_k);
}
