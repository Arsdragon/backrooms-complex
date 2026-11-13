shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_front, fog_disabled;
// Ядро нулевой зоны: не предмет, а «прореха» в воздухе. Сетка — только оболочка (цилиндр, рисуются дальние
// грани — видно и изнутри); по лучу зрения считается ближайшая точка к оси столба (аналитически), плотность —
// гаусс от оси с дрожащей шириной. Внутри фон за ядром преломляется и чуть размыт (экранная текстура),
// поверх — зеленовато-белое свечение: белое лишь в тонкой сердцевине, к краю мягко уходит в зелень и в ноль
// (без плоского белого силуэта — у камеры автоусиление). Перекрытия — по буферу глубины (свой тест глубины
// выключен, иначе пол под столбом срезал бы его низ). Узел без масштаба: единицы оболочки — метры.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float y0 = 0.1;          // низ столба (локально)
uniform float height = 2.0;      // высота столба
uniform float width = 0.12;      // полуширина сердцевины (м)
uniform float glow = 0.3;        // яркость сердцевины (линейная)
uniform float bend = 0.045;       // сила преломления фона
uniform vec3 tint : source_color = vec3(0.4, 1.0, 0.58);

global uniform float g_time;
global uniform vec4 g_fog;

varying vec3 l_pos;
varying vec3 l_cam;

void vertex() {
	l_pos = VERTEX;
	l_cam = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
}

void fragment() {
	vec3 ro = l_cam;
	vec3 rd = normalize(l_pos - ro);
	// расстояние до сцены по этому лучу
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vp.xyz /= vp.w;
	float scene_d = length(vp.xyz);
	// ближайшая к оси (x = z = 0) точка луча, не дальше сцены
	vec2 d2 = rd.xz;
	float dd = max(dot(d2, d2), 1e-5);
	float tc = clamp(-dot(ro.xz, d2) / dd, 0.0, scene_d);
	vec3 pc = ro + rd * tc;
	float r = length(pc.xz);
	float h = (pc.y - y0) / height;
	float hw = smoothstep(-0.02, 0.16, h) * smoothstep(1.02, 0.72, h);
	float t = g_time;
	float ang = atan(pc.z, pc.x);
	float nA = texture(noise_tex, vec2(h * 0.7 + t * 0.045, ang * 0.16 + t * 0.021)).r;
	float nB = texture(noise_tex, vec2(h * 2.1 - t * 0.12, ang * 0.32 - t * 0.05)).g;
	float nC = texture(noise_tex, vec2(h * 5.0 + t * 0.31, ang * 0.48 + t * 0.17)).b;
	// ширина дрожит по высоте и кругу; к концам сужается — веретено, а не капсула
	float w = width * (0.7 + 0.55 * nA + 0.2 * (nC - 0.5)) * (0.45 + 0.55 * sin(clamp(h, 0.0, 1.0) * 3.14159));
	float core = exp(-(r * r) / (w * w)) * hw;
	float halo = exp(-(r * r) / (w * w * 7.0)) * hw;
	float outer = exp(-(r * r) / (w * w * 26.0)) * hw;
	// преломление: фон сдвинут от оси и по шуму, внутри — слегка размыт
	vec2 off = (vec2(nA, nB) - 0.5) * bend * (halo + outer * 0.4);
	vec3 bg = textureLod(screen_tex, SCREEN_UV + off, 0.0).rgb;
	vec3 bgb = textureLod(screen_tex, SCREEN_UV + off * 1.6, 2.5).rgb;
	bg = mix(bg, bgb, halo * 0.7);
	// мерцание: неровное, «электрическое», но без вспышек на весь кадр
	float fl = 0.82 + 0.18 * sin(t * 7.3 + nB * 6.0) * sin(t * 2.3 + nC * 3.0);
	float fil = smoothstep(0.55, 0.9, nC) * halo;     // светлые прожилки в ореоле
	vec3 white = vec3(0.86, 1.0, 0.9);
	vec3 gcol = tint * (halo * 0.12 + outer * 0.04 + fil * 0.1) + mix(tint, white, core * 0.7) * core * glow;
	gcol *= fl;
	float f = 1.0 - exp(-tc * g_fog.a);
	ALBEDO = bg * (1.0 - core * 0.35) + gcol * (1.0 - f);
	ALPHA = clamp(outer * 3.0, 0.0, 1.0);
}
