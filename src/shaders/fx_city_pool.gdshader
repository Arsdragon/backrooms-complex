shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
// Пятно натриевого фонаря на асфальте «Красного города» (UV 0..1 по квадрату): мягкое, к краю гаснет.

uniform vec3 tint : source_color = vec3(0.6, 0.3, 0.08);
uniform float power = 0.22;

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float a = exp(-dot(q, q) * 3.2) * (1.0 - smoothstep(0.85, 1.0, length(q)));
	ALBEDO = tint * a * power;
}
