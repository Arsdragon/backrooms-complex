// Кора стволов и ветвей парка (и ствол пальмы): качается вместе с кроной. Цвет вершины: r — затенение, a — вес изгиба.
shader_type spatial;
render_mode world_vertex_coords;

#include "res://src/shaders/park_wind.gdshaderinc"

uniform sampler2D bark_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float sway = 0.3;
instance uniform float hue_shift = 0.0;

varying float v_ao;

void vertex() {
	vec3 org = MODEL_MATRIX[3].xyz;
	float sc = length(MODEL_MATRIX[1].xyz);
	VERTEX += park_sway(org, COLOR.a, sway * sc, TIME);
	v_ao = COLOR.r;
}

void fragment() {
	vec3 c = texture(bark_tex, UV).rgb * tint * (1.0 + hue_shift * 0.08);
	ALBEDO = c * mix(0.45, 1.0, v_ao);
	ROUGHNESS = 0.93;
	SPECULAR = 0.25;
}
