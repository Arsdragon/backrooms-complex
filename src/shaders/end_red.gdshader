shader_type canvas_item;
// Красный экран смерти (src/scenes/red_screen.gd). Рисуется внутри 3D-вьюпорта красным полем со следом
// последнего кадра; плёнка (vhs.gdshader при hurt = 1) переводит яркость в красный, добавляет шум,
// строки, смаз цвета и пульсирующую виньетку — получается записанный кадр, а не плоская заливка окна.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float level = 1.0;      // общая яркость поля (после плёнки — насыщенность красного)
uniform float ghost = 0.4;      // сколько осталось от последнего кадра

void fragment() {
	vec3 s = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(s, vec3(0.299, 0.587, 0.114));
	// лёгкая неровность поля: матрица камеры «пересвечена» сверху
	float grad = 1.0 - (SCREEN_UV.y - 0.4) * 0.12;
	float v = min(level, 1.0) * (1.0 + (l - 0.35) * ghost) * grad;
	// поле розовато-красное: плёнка берёт его яркость, а в середине кадра оставляет часть исходного цвета
	COLOR = vec4(vec3(1.0, 0.42, 0.4) * max(v, 0.0), 1.0);
}
