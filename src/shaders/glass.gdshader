shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
// Грязное стекло окон: тусклый налёт, освещённый лампами по сетке, блик ламп, туман.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
global uniform vec4 g_flick_a;
global uniform vec4 g_flick_b;
global uniform float g_power;
global uniform vec4 g_fog;
global uniform vec4 g_dim;
global uniform float g_ambient;

#include "res://src/shaders/grid_light.gdshaderinc"

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 nz = texture(noise_tex, wpos.xy * 0.2 + wpos.zy * 0.2).rgb;
	vec3 gn = normalize(wnorm);
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 v = normalize(cam - wpos);
	if (dot(gn, v) < 0.0) gn = -gn;
	vec3 L = vec3(0.35);
	vec3 S = vec3(0.0);
	if (g_grid.y > 0.5) {
		vec3 p = wpos + gn * 0.12 - vec3(0.0, g_grid.x, 0.0);
		g_direct(p, gn, v, 0, 48.0, 0.1, L, S);
		L += g_bounce_at(p) * g_grid.z;
	}
	L += vec3(g_ambient);
	float dd = distance(wpos, g_dim.xyz);
	float dimk = 1.0 - g_dim.w * smoothstep(14.0, 2.0, dd) * 0.7;
	float fr = pow(1.0 - clamp(dot(gn, v), 0.0, 1.0), 4.0);
	vec3 col = (vec3(0.55, 0.6, 0.58) * L * (0.6 + nz.r * 0.5) + S) * dimk;
	float dist = length(VERTEX);
	float f = 1.0 - exp(-dist * g_fog.a);
	ALBEDO = mix(col, g_fog.rgb, clamp(f, 0.0, 1.0));
	ALPHA = clamp(0.07 + nz.g * 0.1 + fr * 0.25 + dot(S, vec3(0.33)) * 0.5, 0.0, 0.8);
}
