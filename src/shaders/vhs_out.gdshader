shader_type canvas_item;
// Вывод записанного кадра (480/600/720 строк) на экран: масштабирование Catmull-Rom (5 билинейных выборок).
// Мягко, как оцифровка кассеты, но без «мыла» билинейного растяжения и без ступенек.

vec3 catmull_rom(sampler2D tex, vec2 uv, vec2 size) {
	vec2 sp = uv * size;
	vec2 tp = floor(sp - 0.5) + 0.5;
	vec2 f = sp - tp;
	vec2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
	vec2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
	vec2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
	vec2 w3 = f * f * (-0.5 + 0.5 * f);
	vec2 w12 = w1 + w2;
	vec2 o12 = w2 / w12;
	vec2 p0 = (tp - 1.0) / size;
	vec2 p3 = (tp + 2.0) / size;
	vec2 p12 = (tp + o12) / size;
	vec3 r = texture(tex, vec2(p12.x, p0.y)).rgb * (w12.x * w0.y);
	r += texture(tex, vec2(p0.x, p12.y)).rgb * (w0.x * w12.y);
	r += texture(tex, p12).rgb * (w12.x * w12.y);
	r += texture(tex, vec2(p3.x, p12.y)).rgb * (w3.x * w12.y);
	r += texture(tex, vec2(p12.x, p3.y)).rgb * (w12.x * w3.y);
	float ws = w12.x * w0.y + w0.x * w12.y + w12.x * w12.y + w3.x * w12.y + w12.x * w3.y;
	return r / ws;
}

void fragment() {
	vec2 size = 1.0 / TEXTURE_PIXEL_SIZE;
	COLOR = vec4(clamp(catmull_rom(TEXTURE, UV, size), 0.0, 1.0), 1.0);
}
