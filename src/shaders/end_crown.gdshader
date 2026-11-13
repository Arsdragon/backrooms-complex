shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// Концовка «небо → лес»: кроны деревьев (MultiMesh). COLOR.r — запечённое затенение кроны (низ и впадины темнее),
// INSTANCE_CUSTOM.rgb — тон дерева. Листва — трипланарный шум, рваный край силуэта (отсечение по маске листьев).

uniform sampler2D leaf_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 lp;
varying vec3 tint;

void vertex() {
	lp = VERTEX;
	tint = INSTANCE_CUSTOM.rgb;
}

vec3 tw(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / (w.x + w.y + w.z);
}

vec4 tri_leaf(vec3 p, vec3 w) {
	return texture(leaf_tex, p.yz) * w.x + texture(leaf_tex, p.xz) * w.y + texture(leaf_tex, p.xy) * w.z;
}

vec3 tri_noise(vec3 p, vec3 w) {
	return texture(noise_tex, p.yz).rgb * w.x + texture(noise_tex, p.xz).rgb * w.y + texture(noise_tex, p.xy).rgb * w.z;
}

void fragment() {
	vec3 w = tw(normalize(lp));
	vec4 lf = tri_leaf(lp * 0.9, w);
	vec4 lf2 = tri_leaf(lp * 2.3 + 0.37, w);
	vec3 nz = tri_noise(lp * 1.7, w);
	float leaf = clamp((lf.g * 0.6 + lf2.g * 0.4 - 0.25) * 3.0, 0.0, 1.0);
	// рваный силуэт: на скользящих углах — дыры по маске листьев (шире, чем раньше: край не гладкий «помпон»)
	float edge = 1.0 - abs(dot(NORMAL, VIEW));
	if (lf2.a < smoothstep(0.4, 0.92, edge) * 0.95) {
		discard;
	}
	// кучки листвы мельче кроны: светлые верхушки ветвей, тёмные провалы между ними — сверху крона читается
	// комковатой массой, а не гладким шаром
	float clumps = tri_leaf(lp * 1.5 + 0.11, w).a;
	float clumps2 = tri_leaf(lp * 3.6 + 0.53, w).a;
	float ao = COLOR.r * mix(0.32, 1.1, clumps * 0.55 + clumps2 * 0.45);
	// своя для каждого дерева доля «просвета» по шуму: соседние кроны не одинаковые
	float var_k = 0.82 + 0.36 * fract(tint.r * 97.0 + tint.g * 61.0);
	ALBEDO = tint * ao * (0.45 + 0.65 * leaf) * var_k;
	ROUGHNESS = 0.85;
	SPECULAR = 0.06;
	BACKLIGHT = tint * 0.15 * ao;
	// листья «шершавят» освещение: и крупно, и мелко
	vec3 nz2 = tri_noise(lp * 4.3 + 0.7, w);
	NORMAL = normalize(NORMAL + (nz - 0.5) * 0.8 + (nz2 - 0.5) * 0.7);
}
