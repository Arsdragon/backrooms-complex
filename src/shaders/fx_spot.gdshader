shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_back, fog_disabled;
// Картинка проектора на стене: умножает то, что уже нарисовано (обои со своим светом), на 1 + k —
// рисунок обоев и пятна сохраняются, края кадра мягкие, к углам темнее (виньетка объектива).
// Гаснет при отключении питания, вдали тонет в тумане.

uniform vec3 tint : source_color = vec3(0.9, 0.95, 1.0);
uniform float gain = 2.6;

global uniform float g_power;
global uniform vec4 g_fog;
global uniform vec4 g_dim;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 c = UV - 0.5;
	vec2 q = abs(c) * 2.0;
	float m = (1.0 - smoothstep(0.86, 1.0, q.x)) * (1.0 - smoothstep(0.84, 1.0, q.y));
	m *= 1.0 - 0.35 * dot(c, c) * 4.0;
	float dimk = 1.0 - g_dim.w * smoothstep(14.0, 2.0, distance(wpos, g_dim.xyz)) * 0.8;
	float k = gain * m * g_power * dimk * exp(-length(VERTEX) * g_fog.a);
	ALBEDO = vec3(1.0) + tint * k;
}
