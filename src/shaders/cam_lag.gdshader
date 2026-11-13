shader_type canvas_item;
render_mode blend_disabled, unshaded;
// Инерция матрицы видеокамеры (ПЗС / трубка): яркие лампы оставляют короткие хвосты, когда камеру ведут,
// и всё движение чуть смазано. Работает в разрешении кадра, до объектива (объектив статичен — порядок не важен).
// cur_tex — свежий кадр 3D-мира, prev_tex — результат этого же шага в прошлом кадре (вьюпорт Copy).
// Доли заданы для 60 к/с и пересчитываются на настоящую длину кадра (frames = dt·60), поэтому хвост
// одинаковой длины во времени при любой частоте кадров и всегда гаснет (доля < 1).
//
// След — это РАЗНИЦА размытого прошлого и размытого нынешнего кадра: не резкая копия прошлого кадра (при быстром
// движении копии ложились стопкой резких контуров), а мягкое пятно, которое с каждым кадром ещё расплывается и
// гаснет. У неподвижной картинки размытое прошлое = размытому нынешнему — ореола вокруг ламп нет.
// Долгий хвост — только у выбитых в белое источников (лампа, солнце: заряд пересвета стекает медленно);
// просто светлое (край ямы на фоне неба, белая стена) тянет лишь общий слабый смаз.

uniform sampler2D cur_tex : filter_linear, repeat_disable;
uniform sampler2D prev_tex : filter_linear, repeat_disable;
uniform float smear = 0.1;    // общий смаз: доля прошлого кадра везде (за 1/60 с)
uniform float keep = 0.5;     // послесвечение: доп. доля там, где было очень светло (за 1/60 с)
uniform float frames = 1.0;   // длина кадра в шестидесятых долях секунды
uniform float blur_px = 3.5;  // радиус размытия следа, пикс кадра 480 строк

#include "res://src/shaders/cam_common.gdshaderinc"

// мягкое размытие 3×3 билинейными выборками (≈ гаусс σ ≈ r·0.8)
vec3 soft(sampler2D t, vec2 uv, vec2 r) {
	vec3 a = texture(t, uv).rgb * 0.25;
	a += (texture(t, uv + vec2(r.x, 0.0)).rgb + texture(t, uv - vec2(r.x, 0.0)).rgb
		+ texture(t, uv + vec2(0.0, r.y)).rgb + texture(t, uv - vec2(0.0, r.y)).rgb) * 0.125;
	a += (texture(t, uv + r).rgb + texture(t, uv - r).rgb
		+ texture(t, uv + vec2(r.x, -r.y)).rgb + texture(t, uv + vec2(-r.x, r.y)).rgb) * 0.0625;
	return a;
}

void fragment() {
	vec2 tex_px = 1.0 / vec2(textureSize(cur_tex, 0));
	vec2 r = tex_px * blur_px * float(textureSize(cur_tex, 0).y) / 480.0;
	vec3 c = texture(cur_tex, UV).rgb;
	vec3 pb = soft(prev_tex, UV, r);
	vec3 cb = soft(cur_tex, UV, r);
	float hp = hot_of(pb);
	// хвост тянется только от светлого к тёмному (заряд не успевает стечь); порог 1.5/255 — чтобы
	// 8-битное округление не «залипало» и след гас до нуля
	vec3 ghost = max(pb - cb - 1.5 / 255.0, vec3(0.0));
	float w = pow(clamp(smear + keep * hp, 0.0, 0.7), frames);
	vec3 o = c + ghost * w;
	// чуть-чуть симметричного смаза (и в тёмную сторону) — мягкость быстрого движения
	o = mix(o, texture(prev_tex, UV).rgb, pow(smear * 0.3, frames));
	COLOR = vec4(o, 1.0);
}
