// Дальние планы парка: кольца-полосы с силуэтами деревьев, крыш и холмов (альфа), без собственных теней.
shader_type spatial;
render_mode cull_disabled, shadows_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float alpha_cut = 0.5;
uniform float lift = 0.0;     // подсветка (дальние слои светлее и площе)

void fragment() {
	// по кругу текстура повторяется вручную (fract), производные — от непрерывных UV: без шва и без
	// «перетекания» низа полосы на её верх, как было бы при repeat по вертикали
	vec2 uvw = vec2(fract(UV.x), UV.y);
	vec4 t = textureGrad(tex, uvw, dFdx(UV), dFdy(UV));
	float lod = textureQueryLod(tex, UV).x;
	ALPHA = t.a * (1.0 + max(lod, 0.0) * 0.25);
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ALBEDO = t.rgb * tint;
	EMISSION = t.rgb * tint * lift;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
