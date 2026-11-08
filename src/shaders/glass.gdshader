shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
// Грязное стекло окон

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
global uniform vec4 g_fog;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = texture(noise_tex, wpos.xy * 0.2 + wpos.zy * 0.2).rgb;
	float l = COLOR.r * 2.0 + 0.04;
	ALBEDO = vec3(0.55, 0.6, 0.58) * l + n.r * 0.03;
	ALPHA = 0.08 + n.g * 0.12;
}
