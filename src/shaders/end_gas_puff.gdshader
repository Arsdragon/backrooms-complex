shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Концовка Async: клубы газа из решётки (частицы, атлас 2×2 tex/fx_smoke). Спрайт всегда лицом к камере.
// Мягкие края у всех поверхностей: по глубине сцены (стол, люди) и по расстоянию до стен/потолка/пола комнаты
// в мировых координатах — у стены, видной вскользь, обычные «мягкие частицы» не спасают, край выходит прямой.

uniform sampler2D smoke_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
// серее белого: камера считает почти белое лампой и раздувает в ореол
uniform vec3 tint : source_color = vec3(0.8, 0.81, 0.8);
uniform vec3 room_min = vec3(-1.5, 0.0, -14.0);
uniform vec3 room_max = vec3(1.5, 2.8, 0.0);
uniform float soft = 0.6;                 // мягкость у поверхностей сцены, м
uniform float wall_soft = 0.55;           // мягкость у стен комнаты, м
uniform float opacity = 0.6;

varying vec3 wp;

void vertex() {
	// как billboard «для частиц» у StandardMaterial: лицом к камере, поворот спрайта — INSTANCE_CUSTOM.x
	mat4 mw = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	float a = INSTANCE_CUSTOM.x;
	mw = mw * mat4(vec4(cos(a), -sin(a), 0.0, 0.0), vec4(sin(a), cos(a), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	mw = mw * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mw;
	wp = (mw * vec4(VERTEX, 1.0)).xyz;
	// кадр атласа 2×2 по фазе жизни (без зацикливания)
	float fr = clamp(floor(INSTANCE_CUSTOM.z * 4.0), 0.0, 3.0);
	UV = UV * 0.5 + vec2(mod(fr, 2.0), floor(fr / 2.0)) * 0.5;
}

void fragment() {
	vec4 t = texture(smoke_tex, UV);
	// плотность клуба — мягче и прозрачнее карты (кромка «тает», середина не плотнее густого тумана)
	float al = pow(t.a, 1.6) * COLOR.a * opacity;
	// глубина сцены за спрайтом
	float dz = texture(depth_tex, SCREEN_UV).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, dz, 1.0);
	vp.xyz /= vp.w;
	al *= clamp((VERTEX.z - vp.z) / soft, 0.0, 1.0);
	// стены, пол и потолок комнаты
	vec3 dmin = wp - room_min;
	vec3 dmax = room_max - wp;
	float dw = min(min(min(dmin.x, dmax.x), min(dmin.z, dmax.z)), min(dmin.y, dmax.y));
	al *= smoothstep(0.0, wall_soft, dw);
	// у самого объектива растворяется
	al *= smoothstep(0.25, 1.3, -VERTEX.z);
	ALBEDO = tint * COLOR.rgb * t.rgb;
	ALPHA = clamp(al, 0.0, 1.0);
}
