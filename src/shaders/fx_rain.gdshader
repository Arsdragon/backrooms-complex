shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
// Капли дождя (частицы): тонкая вертикальная черта, повёрнутая к камере вокруг вертикали.
// Освещена лампами сетки в точке капли (считается в вершинах — дёшево), мигает и гаснет вместе со светом,
// вдали тонет в тумане; сами по себе капли почти прозрачны — видны там, где на них падает свет.

uniform float opacity = 0.38;
uniform vec3 water : source_color = vec3(0.62, 0.66, 0.68);

instance uniform vec4 light_level = vec4(0.8, 0.0, 0.0, 0.0);

global uniform vec4 g_flick_a;
global uniform vec4 g_flick_b;
global uniform float g_power;
global uniform vec4 g_fog;
global uniform vec4 g_dim;
global uniform float g_ambient;

#include "res://src/shaders/grid_light.gdshaderinc"

varying vec3 lit;
varying float fogk;

void vertex() {
	// вертикальный «билборд»: x — поперёк взгляда, y — вверх, центр — в точке частицы
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 side = normalize(cross(up, INV_VIEW_MATRIX[2].xyz));
	vec3 fwd = normalize(cross(side, up));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(side, 0.0), vec4(up, 0.0), vec4(fwd, 0.0), MODEL_MATRIX[3]);
	vec3 wp = MODEL_MATRIX[3].xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 L = vec3(0.0);
	vec3 S = vec3(0.0);
	if (g_grid.y > 0.5) {
		vec3 p = wp - vec3(0.0, g_grid.x, 0.0);
		g_direct(p, vec3(0.0, 1.0, 0.0), normalize(cam - wp), 0, 20.0, 0.0, L, S);
		L += g_bounce_at(p) * g_grid.z;
	} else {
		L = vec3(1.0, 0.965, 0.84) * light_level.r * g_power;
	}
	L += vec3(g_ambient);
	float dimk = 1.0 - g_dim.w * smoothstep(14.0, 2.0, distance(wp, g_dim.xyz)) * 0.7;
	lit = L * dimk;
	fogk = exp(-distance(wp, cam) * g_fog.a);
}

void fragment() {
	// мягкий край поперёк черты и затухание к концам
	float across = smoothstep(1.0, 0.25, abs(UV.x - 0.5) * 2.0);
	float along = smoothstep(0.0, 0.35, UV.y) * smoothstep(1.0, 0.6, UV.y);
	float bright = dot(lit, vec3(0.33));
	vec3 col = water * lit;
	ALBEDO = mix(g_fog.rgb, col, fogk);
	ALPHA = clamp(opacity * across * along * (0.35 + 0.65 * clamp(bright, 0.0, 1.5)) * fogk, 0.0, 1.0);
}
