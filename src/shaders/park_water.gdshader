// Вода фонтана: тёмная, с бегущей рябью; отражает небо (радиус неба) почти как зеркало.
shader_type spatial;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 deep : source_color = vec3(0.09, 0.15, 0.14);
uniform float ripple = 0.35;

varying vec3 wp;

float hgt(vec2 p) {
	return texture(noise_tex, p * 0.9 + TIME * vec2(0.05, 0.03)).b + texture(noise_tex, p * 1.7 - TIME * vec2(0.04, 0.06)).b * 0.6;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz;
	float e = 0.02;
	float h0 = hgt(p);
	vec3 nw = normalize(vec3(-(hgt(p + vec2(e, 0.0)) - h0) / e * ripple * 0.02, 1.0, -(hgt(p + vec2(0.0, e)) - h0) / e * ripple * 0.02));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ALBEDO = deep;
	ROUGHNESS = 0.06;
	SPECULAR = 0.55;
}
