shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;
// Падающая (или бьющая вверх) вода фонтана в парке: тонкая завеса/струя. Полосы бегут вдоль UV.y
// (speed > 0 — вниз, < 0 — вверх), прозрачность пятнами, к краям сетки гаснет; блики — от солнца и неба
// (освещаемый шейдер парка). Цвет — светлая вода, не белая краска.
// sheet = 1 — перелив с края чаши: сверху сплошная прозрачная плёнка (видна бликами и по краям силуэта),
// ниже рвётся на отдельные струи разной толщины, между ними — пусто; у воды внизу — белая пена брызг.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float speed = 1.4;
uniform float opacity = 0.5;
uniform vec2 scale = vec2(8.0, 1.6);
uniform float fade_top = 0.06;
uniform float fade_bottom = 0.12;
uniform float sheet = 0.0;

void fragment() {
	vec2 uv = UV;
	float t = TIME * speed;
	float n1 = texture(noise_tex, vec2(uv.x * scale.x, uv.y * scale.y - t)).r;
	float n2 = texture(noise_tex, vec2(uv.x * scale.x * 2.3 + 0.37, uv.y * scale.y * 1.7 - t * 1.6)).g;
	float n3 = texture(noise_tex, vec2(uv.x * scale.x * 5.1 + 0.71, uv.y * scale.y * 3.3 - t * 2.4)).b;
	float streak = smoothstep(0.42, 0.85, n1 * 0.55 + n2 * 0.45 + (n3 - 0.5) * 0.25);
	float edge = smoothstep(0.0, fade_top, uv.y) * smoothstep(1.0, 1.0 - fade_bottom, uv.y);
	float a = opacity * (0.12 + 0.88 * streak);
	vec3 col = mix(vec3(0.62, 0.7, 0.72), vec3(0.9, 0.93, 0.94), streak);
	if (sheet > 0.5) {
		// струи: дорожки по окружности, у каждой своя толщина (медленно гуляет); плёнка сверху сужается в струю
		float fall = smoothstep(0.08, 0.55, uv.y);
		float cx = uv.x * scale.x + (texture(noise_tex, vec2(uv.x * 3.0, uv.y * 0.4 - t * 0.05)).g - 0.5) * 0.6;
		float lane = abs(fract(cx) - 0.5) * 2.0;
		float thick = texture(noise_tex, vec2(floor(cx) * 0.137, TIME * 0.03)).r;
		float wdt = mix(1.05, 0.12 + 0.4 * thick, fall);
		float stream = smoothstep(wdt, wdt * 0.55, lane);
		// плёнка: почти прозрачная, по краю силуэта (скользящий взгляд) — заметнее
		float fr = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 3.0);
		float film = (1.0 - fall) * (0.18 + 0.7 * fr);
		float foam = smoothstep(0.82, 1.0, uv.y) * stream;
		a = opacity * clamp(stream * (0.25 + 0.75 * streak) * fall + film + foam * 0.6, 0.0, 1.0);
		col = mix(vec3(0.6, 0.68, 0.7), vec3(0.92, 0.94, 0.95), clamp(streak * stream + foam, 0.0, 1.0));
	}
	// струи белеют от пузырьков воздуха, между ними вода почти прозрачна
	ALBEDO = col;
	ALPHA = clamp(a * edge, 0.0, 1.0);
	ROUGHNESS = 0.06;
	SPECULAR = 0.75;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4((vec3(n1, n2, n3) - 0.5) * 0.6, 0.0)).xyz);
}
