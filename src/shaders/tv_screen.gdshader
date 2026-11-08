shader_type spatial;
render_mode unshaded, cull_back;
// Экран кинескопа: канал из SubViewport, строки, мерцание, «снег» (channel_static = 1)

uniform sampler2D screen : source_color, filter_linear;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float channel_static = 0.0;
uniform float bright = 1.6;
global uniform vec4 g_fog;
global uniform vec4 g_dim;
global uniform float g_time;
varying vec3 wpos;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV;
	vec2 c = uv - 0.5;
	uv = 0.5 + c * (1.0 + dot(c, c) * 0.18);
	float line = floor(uv.y * 144.0);
	uv.x += (hash(vec2(line, floor(g_time * 20.0))) - 0.5) * 0.004;
	vec3 col = texture(screen, uv).rgb;
	float sn = hash(uv * vec2(192.0, 144.0) + floor(g_time * 30.0));
	col = mix(col, vec3(sn), channel_static);
	col += (sn - 0.5) * 0.06;
	col *= 0.85 + 0.15 * sin(uv.y * 144.0 * 3.14159);
	col *= 0.93 + 0.07 * sin(g_time * 60.0);
	float edge = smoothstep(0.5, 0.42, max(abs(c.x), abs(c.y)));
	col *= edge;
	float dd = distance(wpos, g_dim.xyz);
	col *= 1.0 - g_dim.w * smoothstep(14.0, 2.0, dd) * 0.8;
	col *= bright;
	float dist = length(VERTEX);
	float f = 1.0 - exp(-dist * g_fog.a);
	ALBEDO = mix(col, g_fog.rgb, clamp(f, 0.0, 1.0));
}
