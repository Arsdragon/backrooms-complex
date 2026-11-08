shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;
// Стоячая вода на полу Комплекса: тёмная, с бликами ламп и рябью

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
global uniform vec4 g_flick_a;
global uniform vec4 g_flick_b;
global uniform vec4 g_fog;
global uniform vec4 g_dim;
global uniform float g_ambient;
global uniform float g_time;

varying vec3 wpos;
varying vec4 lc;

float flick(int g) {
	if (g < 4) return g_flick_a[g];
	return g_flick_b[g - 4];
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lc = COLOR;
}

void fragment() {
	vec2 uv = wpos.xz * 0.33;
	float n1 = texture(noise_tex, uv + vec2(g_time * 0.021, g_time * 0.013)).r;
	float n2 = texture(noise_tex, uv * 1.9 - vec2(g_time * 0.017, g_time * 0.024)).g;
	int g = int(lc.a * 8.0 + 0.5);
	float L = lc.r * 2.0 + lc.g * 2.0 * flick(g) + lc.b * 1.2 + g_ambient;
	float dd = distance(wpos, g_dim.xyz);
	L *= 1.0 - g_dim.w * smoothstep(14.0, 2.0, dd) * 0.7;
	vec3 V = normalize(-VERTEX);
	vec3 N = normalize(NORMAL);
	float fr = pow(1.0 - clamp(dot(N, V), 0.0, 1.0), 3.0);
	float glint = smoothstep(0.62, 0.7, n1 * 0.6 + n2 * 0.5) * fr;
	vec3 col = vec3(0.025, 0.024, 0.018) * L + vec3(0.95, 0.9, 0.7) * L * (fr * 0.6 + glint * 0.9);
	float dist = length(VERTEX);
	float f = 1.0 - exp(-dist * g_fog.a);
	ALBEDO = mix(col, g_fog.rgb, clamp(f, 0.0, 1.0));
	ALPHA = clamp(0.62 + fr * 0.33, 0.0, 0.95);
}
