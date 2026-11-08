shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
// Открытый океан: те же волны, что и в коде (endings.gd: _wave_h)

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
varying float h;

float wave(vec2 p, float t) {
	return sin(p.x * 0.08 + t * 0.9) * 0.6 + sin(p.y * 0.11 + t * 1.3) * 0.45 + sin((p.x + p.y) * 0.21 + t * 1.9) * 0.2;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	h = wave(w.xz, t);
	VERTEX.y += h;
	float e = 0.5;
	float hx = wave(w.xz + vec2(e, 0.0), t) - h;
	float hz = wave(w.xz + vec2(0.0, e), t) - h;
	NORMAL = normalize(vec3(-hx / e, 1.0, -hz / e));
}

void fragment() {
	vec3 n = texture(noise_tex, UV * 40.0 + TIME * 0.01).rgb;
	ALBEDO = mix(vec3(0.03, 0.09, 0.11), vec3(0.12, 0.2, 0.22), clamp(h * 0.4 + 0.4, 0.0, 1.0)) + n.r * 0.02;
	ROUGHNESS = 0.12 + n.g * 0.1;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	float foam = smoothstep(0.78, 0.95, h * 0.6 + n.b * 0.5);
	ALBEDO = mix(ALBEDO, vec3(0.75, 0.78, 0.78), foam * 0.5);
}
