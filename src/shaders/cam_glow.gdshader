shader_type canvas_item;
render_mode blend_disabled, unshaded;
// Ореол вокруг ламп (для camera.gdshader). Два маленьких вьюпорта:
//   mode 0 (Glow1, 1/4 кадра): выделить яркое и уменьшить — среднее блока 4×4 (4 билинейные выборки по 2×2),
//                              поэтому мелкие лампы не мерцают при движении камеры;
//   mode 1 (Glow2, 1/8 кадра): широкое гауссово размытие Glow1 (16 билинейных выборок = блок 8×8).

uniform sampler2D src : filter_linear, repeat_disable;
uniform vec2 src_px = vec2(0.0015625, 0.0020833);  // размер текселя источника в UV
uniform int mode = 0;
uniform float threshold = 0.82;                    // с какой яркости начинается свечение
uniform float hot_boost = 3.0;                     // как в camera.gdshader: выбитое в 1.0 на самом деле ярче
uniform vec3 sun_src = vec3(0.0);                  // солнце в кадре мира: xy — UV, z — 0..1 (нет / в кадре), main.gd

#include "res://src/shaders/cam_common.gdshaderinc"

// «энергия» яркого места: выбитые в белое источники (лампы, солнце) — в разы сильнее, просто светлое
// (дымка неба, белый газ, белая ткань) — едва-едва: рассеяние в объективе от них слабое и широкое,
// без «пузыря» в каждом просвете листвы (вьюпорты ореола в HDR — значения больше 1 сохраняются)
vec3 bright(vec3 c, vec2 uv) {
	float w = smoothstep(threshold, 1.0, max(c.r, max(c.g, c.b)));
	// диск солнца после тонмаппинга не белее дымки вокруг (AgX), но это настоящий источник: светлое
	// в пределах диска — «горячее» (закрыто листвой — тёмное, и ореола со смазом нет)
	float hot = max(hot_of(c), sun_hot(c, uv, sun_src, src_px.y / src_px.x));
	return c * w * w * (0.08 + 0.92 * hot) * (1.0 + hot * hot * hot_boost);
}

void fragment() {
	vec3 acc = vec3(0.0);
	if (mode == 0) {
		acc += bright(texture(src, UV + vec2(-1.0, -1.0) * src_px).rgb, UV);
		acc += bright(texture(src, UV + vec2(1.0, -1.0) * src_px).rgb, UV);
		acc += bright(texture(src, UV + vec2(-1.0, 1.0) * src_px).rgb, UV);
		acc += bright(texture(src, UV + vec2(1.0, 1.0) * src_px).rgb, UV);
		acc *= 0.25;
	} else {
		float ws = 0.0;
		for (int y = 0; y < 4; y++) {
			for (int x = 0; x < 4; x++) {
				vec2 o = vec2(float(x) * 2.0 - 3.0, float(y) * 2.0 - 3.0);
				float w = exp(-dot(o, o) / (2.0 * 2.6 * 2.6));
				acc += texture(src, UV + o * src_px).rgb * w;
				ws += w;
			}
		}
		acc /= ws;
	}
	COLOR = vec4(acc, 1.0);
}
