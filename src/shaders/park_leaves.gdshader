// Листва парка: карточки с кластерами листьев, «сферические» нормали кроны, просвечивание на солнце,
// качание ветром. Цвет вершины: r — затенение внутри кроны, g — случайное число карточки,
// b — «сухость» (жёлтые/бурые листья), a — вес изгиба (0 у земли, 1 у верхушки).
shader_type spatial;
render_mode cull_disabled, world_vertex_coords;

#include "res://src/shaders/park_wind.gdshaderinc"

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
// сухие листья — оливково-бурые, не лимонные (иначе на солнце карточки выцветают в кремовые пятна)
uniform vec3 dry_tint : source_color = vec3(1.12, 0.95, 0.58);
uniform float alpha_cut = 0.5;
uniform float sway = 0.3;          // изгиб кроны у верхушки, м
uniform float flutter = 0.035;     // дрожь листьев, м
uniform float translucency = 0.55;
uniform float ao_min = 0.42;
// насколько альфа «густеет» на дальних мип-уровнях (1 — как у листвы: крона вдали не редеет)
uniform float mip_fill = 1.0;
// предел мип-уровня для альфы: у веера пальмы сегменты с просветами на дальних мипах сливаются в гладкий
// круглый «лист кувшинки»; с пределом силуэт вдали остаётся рваным, «гребёнкой»
uniform float alpha_max_lod = 16.0;
instance uniform float hue_shift = 0.0;   // −1..1: темнее/зеленее … светлее/суше

varying float v_ao;
varying float v_dry;
varying float v_rnd;

void vertex() {
	vec3 org = MODEL_MATRIX[3].xyz;
	float sc = length(MODEL_MATRIX[1].xyz);
	float w = COLOR.a;
	VERTEX += park_sway(org, w, sway * sc, TIME);
	float fr = COLOR.g * 6.2832;
	float g = park_gust(VERTEX.xz, TIME);
	VERTEX += vec3(sin(TIME * 3.3 + fr), sin(TIME * 2.4 + fr * 1.3) * 0.5, cos(TIME * 2.9 + fr * 0.7)) * flutter * wind * (0.35 + g) * min(w * 2.0, 1.0);
	v_ao = COLOR.r;
	v_dry = COLOR.b;
	v_rnd = COLOR.g;
}

void fragment() {
	vec4 t = texture(leaf_tex, UV);
	// карточка «ребром» к камере тает (листья по краю кластера осыпаются), а не рисуется тёмной щепкой
	vec3 gn = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	float facing = abs(dot(gn, normalize(VIEW)));
	// альфа на дальних мип-уровнях не тает — иначе крона вдали редеет
	float lod = textureQueryLod(leaf_tex, UV).x;
	float ta = lod > alpha_max_lod ? textureLod(leaf_tex, UV, alpha_max_lod).a : t.a;
	ALPHA = ta * (1.0 + clamp(lod, 0.0, alpha_max_lod) * 0.3 * mip_fill) * smoothstep(0.06, 0.32, facing);
	// (alpha to coverage в Forward+ не сглаживает: предпроход глубины отсекает по порогу — край всё равно ступенчатый;
	// «лесенку» прячет плёнка)
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	vec3 c = t.rgb * tint;
	float dry = clamp(v_dry + max(hue_shift, 0.0) * 0.25 + (v_rnd - 0.5) * 0.14, 0.0, 1.0);
	c = mix(c, c * dry_tint, dry);
	c *= 1.0 + min(hue_shift, 0.0) * 0.2 + (v_rnd - 0.5) * 0.16;
	float ao = mix(ao_min, 1.0, v_ao);
	ALBEDO = c * ao;
	// обе стороны карточки освещаются как наружная поверхность кроны
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	// изнутри кроны (снизу, против солнца) «наружная» нормаль смотрит от камеры: N·V < 0, Френель там равен 1 —
	// солнце и небо отражались белым, листья выцветали в кремовые пятна. Блик — только на видимой стороне
	ROUGHNESS = 0.72;
	SPECULAR = 0.3 * smoothstep(0.05, 0.45, dot(NORMAL, VIEW));
	// свет сквозь лист проходит толщу хлорофилла: цвет «в квадрате» (насыщенный жёлто-зелёный, яркость как у
	// зелёного канала), а не тот же цвет — иначе контровые карточки выбеливаются до кремового
	vec3 trans = c * c / max(c.g, 0.02);
	BACKLIGHT = trans * translucency * (0.4 + 0.6 * ao);
}
