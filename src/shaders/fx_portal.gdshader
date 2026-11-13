shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
// Пелена Порога Async: слой светящейся дымки в проёме. Несколько слоёв на разной глубине дают параллакс —
// видно, что за рамой есть глубина. К краям проёма дымка мягко гаснет (рамка квада не видна), в середине —
// ярче и белее; волокна медленно ползут вверх и колышутся. Яркость умеренная: камера с автоусилением,
// пелена не должна клипаться в плоское белое.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float layer = 0.0;
uniform float strength = 0.2;
uniform vec3 tint : source_color = vec3(0.62, 1.0, 0.74);

global uniform vec4 g_fog;
global uniform float g_time;

void fragment() {
	vec2 uv = UV;
	vec2 c = uv - 0.5;
	float edge = smoothstep(0.5, 0.34, abs(c.x)) * smoothstep(0.5, 0.3, abs(c.y));
	float t = g_time * (0.03 + layer * 0.011);
	vec2 p = vec2(uv.x * 1.5 + layer * 0.37, uv.y * 1.05 + layer * 0.21);
	float n1 = texture(noise_tex, p * 0.6 + vec2(sin(t * 3.0 + layer) * 0.05, t)).r;
	float n2 = texture(noise_tex, p * 1.8 + vec2(-t * 0.6, t * 1.7) + n1 * 0.18).g;
	float n3 = texture(noise_tex, p * 4.1 + vec2(t * 0.9, t * 2.6)).b;
	float wisps = smoothstep(0.32, 0.88, n1 * 0.6 + n2 * 0.5 + (n3 - 0.5) * 0.15);
	vec2 cc = c * vec2(1.7, 1.15);
	float core = exp(-dot(cc, cc) * 5.5);
	float a = (0.4 * core + wisps * (0.35 + 0.65 * core)) * edge;
	a *= 0.86 + 0.14 * sin(g_time * 0.8 + layer * 1.7);
	vec3 col = mix(tint, vec3(0.9, 1.0, 0.94), core * 0.55) * a * strength;
	float f = 1.0 - exp(-length(VERTEX) * g_fog.a);
	ALBEDO = col * (1.0 - f);
}
