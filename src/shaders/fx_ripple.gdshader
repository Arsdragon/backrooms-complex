shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;
// Круги на воде чаши фонтана (парк): от кольца падения струи бегут волны наружу и внутрь, гаснут с расстоянием;
// сами по себе почти прозрачны — видны бликами неба и солнца на наклоне волны (нормаль по производной).

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float ring_r = 0.45;     // радиус кольца падения (доля полуразмера квада)
uniform float freq = 38.0;
uniform float speed = 2.2;
uniform float strength = 0.5;
uniform vec3 deep : source_color = vec3(0.09, 0.15, 0.14);

void fragment() {
	vec2 c = (UV - 0.5) * 2.0;
	float r = length(c);
	float n = texture(noise_tex, UV * 3.0 + TIME * vec2(0.02, 0.03)).r;
	float d = abs(r - ring_r) + (n - 0.5) * 0.04;
	float ph = d * freq - TIME * speed * 6.2832;
	float amp = exp(-d * 6.0) * smoothstep(1.0, 0.85, r);
	float w = sin(ph) * amp;
	float dw = cos(ph) * amp * freq * 0.02;
	vec2 dir = r > 1e-4 ? c / r : vec2(0.0);
	vec3 nw = normalize(vec3(-dir.x * dw * sign(r - ring_r), 1.0, -dir.y * dw * sign(r - ring_r)));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ALBEDO = deep;
	ROUGHNESS = 0.05;
	SPECULAR = 0.8;
	ALPHA = clamp(strength * (abs(w) * 0.7 + amp * 0.15), 0.0, 0.9);
}
