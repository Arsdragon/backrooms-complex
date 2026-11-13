shader_type canvas_item;
render_mode blend_disabled, unshaded;
// Экспонометр автоириса: вьюпорт 16×12, каждая точка — клетка кадра.
// R — средняя яркость клетки (0..1), G — доля пересвета (лампы, выбитое в белое). main.gd читает его асинхронно.

uniform sampler2D src : filter_linear, repeat_disable;
uniform vec2 cells = vec2(16.0, 12.0);

#include "res://src/shaders/cam_common.gdshaderinc"

void fragment() {
	vec2 cell = 1.0 / cells;
	vec2 base = UV - cell * 0.5;
	float l = 0.0;
	float h = 0.0;
	for (int y = 0; y < 4; y++) {
		for (int x = 0; x < 4; x++) {
			vec3 c = texture(src, base + (vec2(float(x), float(y)) + 0.5) * 0.25 * cell).rgb;
			l += dot(c, vec3(0.299, 0.587, 0.114));
			// лампы — целиком; светлое небо — наполовину (ирис прикрывается, как раньше, а ореола у неба нет)
			h += max(hot_of(c), 0.5 * bright_of(c));
		}
	}
	COLOR = vec4(l / 16.0, h / 16.0, 0.0, 1.0);
}
