// Дальние здания центра: фасад из атласа 2×2 (ячейка задаётся на экземпляр), координаты — мировые,
// поэтому окна одного размера на любой коробке. Крыши — серый гудрон.
shader_type spatial;

uniform sampler2D facade : source_color, filter_linear_mipmap, repeat_enable;
uniform float cell_m = 56.0;     // ячейка атласа в метрах (16 этажей)
instance uniform float cell = 0.0;
instance uniform float shade = 1.0;

varying vec3 wp;
varying vec3 wn;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = abs(wn.x) > 0.5 ? wp.zy : wp.xy;
	uv.y = -uv.y;
	vec2 g = uv / cell_m;
	// cell 4 — глухая надстройка на крыше (бетон без окон)
	vec2 cuv = (vec2(mod(min(cell, 3.0), 2.0), floor(min(cell, 3.0) / 2.0)) + fract(g)) * 0.5;
	vec3 c = textureGrad(facade, cuv, dFdx(g) * 0.35, dFdy(g) * 0.35).rgb;
	if (cell > 3.5) {
		c = vec3(0.56, 0.54, 0.5);
	}
	if (wn.y > 0.5) {
		c = vec3(0.42, 0.41, 0.4);
	}
	ALBEDO = c * shade;
	ROUGHNESS = 0.75;
	SPECULAR = 0.4;
}
