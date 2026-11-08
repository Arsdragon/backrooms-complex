shader_type canvas_item;
// Плёнка VHS / бытовая видеокамера начала 90-х.
// TEXTURE — кадр из 3D-вьюпорта (480 строк). Всё считается в «строках» исходного кадра.

uniform float intensity = 1.0;      // общая сила эффекта (настройка)
uniform float gain = 1.0;           // автоусиление камеры в темноте (шум растёт)
uniform float interference = 0.0;   // помехи: нулевая зона, Сущность рядом (0..1)
uniform float tracking = 0.0;       // срыв трекинга (вспышка 0..1)
uniform float stopfx = 0.0;         // «стоп/перемотка»: 0..1
uniform float desat = 0.0;          // доп. обесцвечивание
uniform float bw = 0.0;             // 1 — чёрно-белая камера наблюдения
uniform vec2 src_size = vec2(640.0, 480.0);
uniform float time_offset = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	float a = hash(vec2(i, 1.7));
	float b = hash(vec2(i + 1.0, 1.7));
	return mix(a, b, f * f * (3.0 - 2.0 * f));
}

vec3 rgb2yiq(vec3 c) {
	return vec3(dot(c, vec3(0.299, 0.587, 0.114)),
				dot(c, vec3(0.596, -0.274, -0.322)),
				dot(c, vec3(0.211, -0.523, 0.312)));
}

vec3 yiq2rgb(vec3 c) {
	return vec3(c.x + 0.956 * c.y + 0.621 * c.z,
				c.x - 0.272 * c.y - 0.647 * c.z,
				c.x - 1.106 * c.y + 1.703 * c.z);
}

void fragment() {
	float t = TIME + time_offset;
	vec2 uv = UV;
	float k = intensity;
	float line = floor(uv.y * src_size.y);
	float px = 1.0 / src_size.x;

	// --- геометрические искажения строк ---
	float wob = (noise1(line * 0.11 + t * 9.0) - 0.5) * 0.9 * px * k;
	// медленное «плавание» кадра
	wob += (noise1(t * 0.7) - 0.5) * 0.6 * px * k;
	// полоса срыва трекинга, ползущая по кадру
	float band_pos = fract(t * 0.045);
	float band = smoothstep(0.035, 0.0, abs(uv.y - band_pos)) * (0.15 + tracking * 1.5 + interference * 0.8) * k;
	wob += band * (hash(vec2(line, floor(t * 30.0))) - 0.5) * 18.0 * px;
	// помехи: рваные строки
	float tear = step(1.0 - interference * 0.25 - tracking * 0.4, hash(vec2(floor(line / 3.0), floor(t * 24.0))));
	wob += tear * (hash(vec2(line, t)) - 0.5) * 40.0 * px * (interference + tracking);
	// шум переключения головок внизу кадра
	float head = smoothstep(src_size.y - 7.0, src_size.y - 1.0, line);
	wob += head * (hash(vec2(line, floor(t * 60.0))) * 14.0 + 5.0) * px * k;
	// вертикальный рывок при сильных помехах
	float vjump = step(0.985 - interference * 0.06, hash(vec2(floor(t * 8.0), 3.1))) * (interference + tracking) * 0.04;
	uv.y = fract(uv.y + vjump);
	uv.x += wob;

	// --- яркость (Y) резче, цвет (IQ) размыт и сдвинут ---
	vec3 c0 = texture(TEXTURE, uv).rgb;
	vec3 cl = texture(TEXTURE, uv - vec2(px * 1.2, 0.0)).rgb;
	vec3 cr = texture(TEXTURE, uv + vec2(px * 1.2, 0.0)).rgb;
	float Y = rgb2yiq(c0).x * 0.5 + rgb2yiq(cl).x * 0.25 + rgb2yiq(cr).x * 0.25;
	float Yblur = 0.0;
	vec2 IQ = vec2(0.0);
	float cs = 2.0 + 1.5 * k;
	for (int i = -3; i <= 3; i++) {
		vec2 o = vec2(float(i) * px * cs, 0.0);
		vec3 s = rgb2yiq(texture(TEXTURE, uv + o + vec2(px * 2.5 * k, 0.0)).rgb);
		IQ += s.yz;
		Yblur += rgb2yiq(texture(TEXTURE, uv + o * 0.6).rgb).x;
	}
	IQ /= 7.0;
	Yblur /= 7.0;
	// «окантовка» резкости бытовых камер
	Y += (Y - Yblur) * 0.55 * k;

	// --- автоусиление и шум ---
	float g = gain;
	Y *= g;
	IQ *= mix(1.0, g, 0.6);
	float grain = (hash(uv * src_size + vec2(fract(t * 13.0) * 100.0, fract(t * 7.0) * 50.0)) - 0.5);
	float noise_amt = (0.035 + 0.05 * max(g - 1.0, 0.0) + interference * 0.25) * k;
	Y += grain * noise_amt;
	// цветной «снег» пятнами
	vec2 blot = vec2(hash(floor(uv * src_size / vec2(6.0, 2.0)) + floor(t * 20.0)), hash(floor(uv * src_size / vec2(5.0, 2.0)) + floor(t * 20.0) + 7.0)) - 0.5;
	IQ += blot * (0.03 + 0.04 * max(g - 1.0, 0.0) + interference * 0.15) * k;
	// выпадения ленты — белые чёрточки
	float drop = step(0.9993 - interference * 0.004 - tracking * 0.01, hash(vec2(floor(uv.x * 40.0), line + floor(t * 15.0) * 17.0)));
	Y += drop * 0.7 * k;
	// полоса трекинга светлее и шумнее
	Y += band * 0.35 * (hash(vec2(uv.x * 50.0, line + t)) - 0.3);

	// --- цвет плёнки ---
	IQ *= (1.0 - desat) * (1.0 - 0.06 * k);
	vec3 col = yiq2rgb(vec3(Y, IQ));
	// поднятые чёрные, мягкое «выгорание» светов
	col = max(col, vec3(0.0));
	col = col / (1.0 + col * 0.12);
	col = mix(col, vec3(0.035, 0.03, 0.04) + col * 0.95, 0.6 * k);
	// интерлейс / строки
	float sl = 0.94 + 0.06 * sin(uv.y * src_size.y * 3.14159);
	col *= mix(1.0, sl, 0.8 * k);
	// виньетка объектива
	vec2 vc = UV - 0.5;
	float vig = 1.0 - dot(vc, vc) * 0.55 * k;
	col *= vig;
	// камера наблюдения
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum) * vec3(0.92, 1.0, 0.95), bw);

	// --- «стоп»: синий экран и полосы ---
	if (stopfx > 0.0) {
		float sn = hash(vec2(uv.x * 300.0, line + floor(t * 40.0)));
		vec3 st = mix(vec3(sn * 0.6), vec3(0.05, 0.08, 0.55), smoothstep(0.6, 1.0, stopfx));
		col = mix(col, st, stopfx);
	}
	// жёсткий «снег» при максимальных помехах
	float snow = smoothstep(0.75, 1.0, interference);
	col = mix(col, vec3(hash(uv * src_size + t * 60.0)), snow * 0.85);
	COLOR = vec4(col, 1.0);
}
