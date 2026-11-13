shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Концовка «океан»: столбы света от поверхности. MultiMesh из квадов: начало луча — у поверхности,
// ось — направление преломлённых солнечных лучей; квад всегда развёрнут к камере вокруг своей оси.
// INSTANCE_CUSTOM: x — ширина, y — длина, z — фаза мерцания, w — яркость.

uniform vec3 axis = vec3(0.0, -1.0, 0.0);
uniform vec3 color : source_color = vec3(0.45, 0.85, 0.8);
uniform float intensity = 0.12;
uniform float fog_k = 0.07;

varying float v_along;
varying float v_across;
varying float v_fade;

void vertex() {
	vec3 a = normalize(axis);
	vec3 top = MODEL_MATRIX[3].xyz;
	float w = INSTANCE_CUSTOM.x;
	float len = INSTANCE_CUSTOM.y;
	float along = VERTEX.y + 0.5;                 // 0 у поверхности → 1 в глубине
	vec3 mid = top + a * len * 0.5;
	vec3 to_cam = CAMERA_POSITION_WORLD - mid;
	vec3 side = normalize(cross(a, to_cam));
	vec3 wp = top + a * (len * along) + side * VERTEX.x * w;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
	v_along = along;
	v_across = VERTEX.x * 2.0;
	// камера близко к оси — луч гаснет (иначе он режет кадр плоской лентой)
	vec3 rel = CAMERA_POSITION_WORLD - top;
	float d_axis = length(rel - a * dot(rel, a));
	float d_cam = length(CAMERA_POSITION_WORLD - (top + a * clamp(dot(rel, a), 0.0, len)));
	float flick = 0.6 + 0.4 * sin(TIME * (0.7 + INSTANCE_CUSTOM.z * 0.5) + INSTANCE_CUSTOM.z * 6.283)
		* sin(TIME * 0.31 + INSTANCE_CUSTOM.z * 17.0);
	v_fade = smoothstep(0.8, 2.6, d_axis) * exp(-d_cam * fog_k) * flick * INSTANCE_CUSTOM.w;
}

void fragment() {
	float across = exp(-v_across * v_across * 3.2);
	float along = smoothstep(0.0, 0.06, v_along) * exp(-v_along * 2.4);
	ALBEDO = color * intensity * across * along * v_fade;
}
