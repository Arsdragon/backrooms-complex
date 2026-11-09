shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;
// Пятна, лужи, плесень, следы шин, травяные проплешины — плоские наклейки

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 0.5);
uniform float radial = 0.0;     // 1 — круглое рваное пятно из шума
uniform float stripes = 0.0;    // 1 — следы шин
uniform float tex_color = 0.0;  // 1 — цвет из текстуры
uniform float sheen = 0.0;      // мокрый блеск

instance uniform vec4 light_level = vec4(0.8, 0.0, 0.0, 0.0);
instance uniform float seed = 0.0;

global uniform vec4 g_flick_a;
global uniform vec4 g_flick_b;
global uniform float g_power;
global uniform vec4 g_fog;
global uniform float g_ambient;
global uniform vec4 g_dim;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float flick(int g) {
	if (g < 4) return g_flick_a[g];
	return g_flick_b[g - 4];
}

void fragment() {
	float a = 1.0;
	vec3 c = tint.rgb;
	if (radial > 0.5) {
		float r = length(UV - 0.5) * 2.0;
		float n = texture(noise_tex, UV * 0.6 + vec2(seed * 0.37, seed * 0.71)).r;
		float n2 = texture(noise_tex, UV * 1.7 + vec2(seed * 0.13, seed * 0.29)).g;
		a = smoothstep(1.0, 0.62, r + (n - 0.5) * 0.9 + (n2 - 0.5) * 0.25);
	} else if (stripes > 0.5) {
		float s = abs(fract(UV.x * 2.0) - 0.5);
		float n = texture(noise_tex, UV * vec2(0.3, 2.0) + seed).r;
		a = smoothstep(0.32, 0.22, s) * (0.4 + n * 0.6) * smoothstep(0.0, 0.2, UV.y) * smoothstep(1.0, 0.6, UV.y);
	} else {
		vec4 t = texture(tex, UV);
		a = t.a;
		if (tex_color > 0.5) c *= t.rgb;
	}
	int g = int(light_level.a * 8.0 + 0.5);
	vec3 L = vec3(1.0, 0.965, 0.84) * (light_level.r + light_level.g * flick(g)) * g_power + vec3(0.8, 0.07, 0.04) * light_level.b + vec3(g_ambient);
	float dd = distance(wpos, g_dim.xyz);
	L *= 1.0 - g_dim.w * smoothstep(14.0, 2.0, dd) * 0.7;
	vec3 col = c * L;
	if (sheen > 0.0) {
		vec3 V = normalize(-VERTEX);
		float fr = pow(1.0 - clamp(dot(normalize(NORMAL), V), 0.0, 1.0), 4.0);
		col += vec3(0.6, 0.58, 0.5) * fr * sheen * dot(L, vec3(0.33));
	}
	float dist = length(VERTEX);
	float f = 1.0 - exp(-dist * g_fog.a);
	ALBEDO = mix(col, g_fog.rgb, clamp(f, 0.0, 1.0));
	ALPHA = a * tint.a;
}
