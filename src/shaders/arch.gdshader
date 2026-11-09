shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, skip_vertex_transform;
// Архитектура Комплекса. Свет «запечён» в цвет вершин (см. chunk_builder.gd).

uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex2 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec2 scale = vec2(0.8, 0.8);     // метров на повтор текстуры
uniform float dirt = 0.5;                // доля грязного варианта
uniform float dirt_scale = 0.06;
uniform vec3 tint = vec3(1.0);
uniform float emissive = 0.0;            // светильник: светится сам
uniform float pit = 0.0;                 // стенки ям: уходят в черноту

global uniform vec4 g_flick_a;
global uniform vec4 g_flick_b;
global uniform vec4 g_dim;
global uniform vec4 g_null;
global uniform vec4 g_fog;
global uniform float g_ambient;
global uniform float g_time;
global uniform vec4 g_cam_light;   // «подсветка» камеры: xyz позиция, w сила (обычно 0)
global uniform float g_power;      // питание ламп: 1 — норма, просадка/отключение — меньше

varying vec3 wpos;
varying vec4 lc;
varying float ao;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lc = COLOR;
	ao = UV2.x;
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float flick(int g) {
	if (g < 4) return g_flick_a[g];
	return g_flick_b[g - 4];
}

void fragment() {
	vec2 uv = UV / scale;
	vec3 a = texture(tex, uv).rgb;
	vec3 b = texture(tex2, uv).rgb;
	vec3 nz = texture(noise_tex, vec2(wpos.x + wpos.z * 0.7, wpos.y * 0.5 + wpos.z * 0.3) * dirt_scale).rgb;
	float dm = smoothstep(0.62 - dirt * 0.35, 0.82 - dirt * 0.2, nz.r * 0.7 + nz.b * 0.3);
	vec3 base = mix(a, b, dm * step(0.001, dirt)) * tint;

	int g = int(lc.a * 8.0 + 0.5);
	float fv = flick(g);
	vec3 warm = vec3(1.0, 0.965, 0.84);
	vec3 L = warm * lc.r * 2.0 * g_power;
	vec3 fc = (g == 7) ? vec3(0.35, 1.0, 0.55) : warm;
	L += fc * lc.g * 2.0 * fv * (g == 7 ? 1.0 : g_power);
	L += vec3(0.8, 0.07, 0.04) * lc.b * 2.0;

	// Сущность рядом — лампы гаснут и дрожат
	float dd = distance(wpos, g_dim.xyz);
	float dimf = g_dim.w * smoothstep(14.0, 2.0, dd);
	float jitter = 0.5 + 0.5 * sin(g_time * 41.0 + floor(wpos.x * 0.4) * 3.1 + floor(wpos.z * 0.4) * 1.7);
	L *= 1.0 - dimf * (0.55 + 0.45 * jitter);

	// нулевая зона: зелёный отсвет и «электричество», ползущее по стенам
	float nd = distance(wpos, g_null.xyz);
	float nz2 = g_null.w * smoothstep(10.0, 0.5, nd);
	vec3 ncol = vec3(0.0);
	if (nz2 > 0.001) {
		vec3 n2 = texture(noise_tex, wpos.xy * 0.35 + wpos.zy * 0.35 + vec2(g_time * 0.07, -g_time * 0.05)).rgb;
		float veins = smoothstep(0.035, 0.0, abs(n2.b - 0.5)) * step(0.55, fract(g_time * 1.7 + n2.r * 3.0));
		ncol = vec3(0.4, 1.0, 0.6) * nz2 * (0.25 + veins * 2.5);
		L += ncol * 0.6;
	}

	// дополнительный источник у камеры (используется в концовках/меню)
	float cd = distance(wpos, g_cam_light.xyz);
	L += vec3(1.0, 0.97, 0.9) * g_cam_light.w / (1.0 + cd * cd * 0.5);

	L += vec3(g_ambient);
	vec3 col = base * L * ao;
	if (emissive > 0.0) {
		float on = (lc.r + lc.g * fv) * g_power;
		vec3 em = mix(vec3(0.09, 0.085, 0.08), vec3(1.0, 0.98, 0.9) * emissive, clamp(on, 0.0, 1.0));
		if (g == 7) em = mix(em, vec3(0.3, 1.0, 0.5) * emissive * 0.6, lc.g * fv);
		em = mix(em, vec3(1.0, 0.08, 0.05) * emissive * 0.8, lc.b);
		col = a * em * (1.0 - dimf * 0.8 * jitter);
	}
	if (pit > 0.0) {
		col *= clamp(ao * 1.25, 0.0, 1.0);
	}
	float dist = length(VERTEX);
	float f = 1.0 - exp(-dist * g_fog.a);
	col = mix(col, g_fog.rgb, clamp(f, 0.0, 1.0));
	ALBEDO = col;
}
