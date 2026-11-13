shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;
// Концовка «космос»: Земля с высоты ~1000 км (масштаб — километры). Сфера меша чуть больше планеты, точная
// поверхность — пересечение луча со сферой (лимб идеально круглый). Суша — tex/fx_earth (альфа — мягкая маска суши,
// берег, море и шельф рисуются здесь), облака (tex/fx_earth_clouds) с тенями, блик солнца на воде,
// мягкий терминатор и воздушная дымка (однократное
// рассеяние Рэлея и Ми — те же формулы, что в end_atmo.gdshader).

uniform sampler2D earth_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cloud_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 center = vec3(0.0, -7000.0, 0.0);
uniform float radius = 6000.0;
uniform float atmo = 80.0;                     // толщина атмосферы, км
uniform vec3 sun = vec3(-0.85, 0.42, 0.31);    // направление на солнце (мир)
uniform float sun_power = 22.0;
uniform float cloud_shift = 0.0;               // дрейф облаков (доля оборота)
uniform float knee = 0.78;                     // сжатие ярких: x / (1 + x / knee)

const vec3 B_R = vec3(5.8e-3, 13.5e-3, 33.1e-3);
const float B_M = 21e-3;
const float H_R = 8.0;
const float H_M = 1.2;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 ray_sphere(vec3 ro, vec3 rd, float r) {
	float b = dot(ro, rd);
	float c = dot(ro, ro) - r * r;
	float d = b * b - c;
	if (d < 0.0) {
		return vec2(1e9, -1e9);
	}
	d = sqrt(d);
	return vec2(-b - d, -b + d);
}

// оптическая толщина от точки p до верха атмосферы в сторону солнца
vec2 light_depth(vec3 p, vec3 l) {
	float t1 = ray_sphere(p, l, radius + atmo).y;
	float st = t1 / 4.0;
	vec2 od = vec2(0.0);
	for (int i = 0; i < 4; i++) {
		float h = length(p + l * (st * (float(i) + 0.5))) - radius;
		od += exp(-max(h, 0.0) / vec2(H_R, H_M)) * st;
	}
	return od;
}

// однократное рассеяние на отрезке [t0, t1] луча; возвращает свет и пропускание
vec3 scatter(vec3 ro, vec3 rd, float t0, float t1, vec3 l, out vec3 trans) {
	float st = (t1 - t0) / 8.0;
	vec2 od_v = vec2(0.0);
	vec3 sum_r = vec3(0.0);
	vec3 sum_m = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		vec3 p = ro + rd * (t0 + st * (float(i) + 0.5));
		float h = length(p) - radius;
		vec2 dens = exp(-max(h, 0.0) / vec2(H_R, H_M)) * st;
		od_v += dens;
		vec2 od_l = light_depth(p, l);
		vec3 tau = B_R * (od_v.x + od_l.x) + B_M * 1.1 * (od_v.y + od_l.y);
		vec3 att = exp(-tau);
		sum_r += dens.x * att;
		sum_m += dens.y * att;
	}
	trans = exp(-(B_R * od_v.x + B_M * 1.1 * od_v.y));
	float mu = dot(rd, l);
	float pr = 3.0 / (16.0 * PI) * (1.0 + mu * mu);
	float g = 0.76;
	float pm = 3.0 / (8.0 * PI) * ((1.0 - g * g) * (1.0 + mu * mu)) / ((2.0 + g * g) * pow(1.0 + g * g - 2.0 * g * mu, 1.5));
	return sun_power * (sum_r * B_R * pr + sum_m * B_M * pm);
}

// бикубическая выборка (B-сплайн, 4 билинейных чтения): при сильном увеличении карта не «кубится»
vec4 sample_grad(sampler2D tx, vec2 uv) {
	// шов долготы ±180°: производные берём от непрерывного варианта координаты
	vec2 uv2 = vec2(fract(uv.x + 0.5) - 0.5, uv.y);
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	vec2 dx2 = dFdx(uv2);
	vec2 dy2 = dFdy(uv2);
	if (abs(dx.x) > abs(dx2.x)) { dx.x = dx2.x; }
	if (abs(dy.x) > abs(dy2.x)) { dy.x = dy2.x; }
	vec2 sz = vec2(textureSize(tx, 0));
	vec2 st = uv * sz - 0.5;
	vec2 i = floor(st);
	vec2 f = st - i;
	vec2 w0 = (1.0 - f) * (1.0 - f) * (1.0 - f) / 6.0;
	vec2 w1 = (3.0 * f * f * f - 6.0 * f * f + 4.0) / 6.0;
	vec2 w2 = (-3.0 * f * f * f + 3.0 * f * f + 3.0 * f + 1.0) / 6.0;
	vec2 w3 = f * f * f / 6.0;
	vec2 g0 = w0 + w1;
	vec2 g1 = w2 + w3;
	vec2 p0 = (i - 1.0 + w1 / g0 + 0.5) / sz;
	vec2 p1 = (i + 1.0 + w3 / g1 + 0.5) / sz;
	return g0.y * (g0.x * textureGrad(tx, vec2(p0.x, p0.y), dx, dy) + g1.x * textureGrad(tx, vec2(p1.x, p0.y), dx, dy))
		+ g1.y * (g0.x * textureGrad(tx, vec2(p0.x, p1.y), dx, dy) + g1.x * textureGrad(tx, vec2(p1.x, p1.y), dx, dy));
}

void fragment() {
	vec3 ro = CAMERA_POSITION_WORLD - center;
	vec3 rd = normalize((INV_VIEW_MATRIX * vec4(-VIEW, 0.0)).xyz);
	vec2 hit = ray_sphere(ro, rd, radius);
	if (hit.x > hit.y || hit.x < 0.0) {
		discard;
	}
	// ближний корень без вычитания близких больших чисел: t = c / (-b + sqrt(d))
	float lro = length(ro);
	float cc = (lro - radius) * (lro + radius);
	float bb = dot(ro, rd);
	hit.x = cc / (-bb + sqrt(max(bb * bb - cc, 0.0)));
	vec3 p = ro + rd * hit.x;
	vec3 n = normalize(p);
	vec3 l = normalize(sun);
	// координаты на карте: нормаль в системе планеты (вращение задаёт узел)
	vec3 no = normalize(transpose(mat3(MODEL_MATRIX)) * n);
	float lat = asin(clamp(no.y, -1.0, 1.0));
	float lon = atan(no.x, no.z);
	vec2 uv = vec2(lon / TAU + 0.5, 0.5 - lat / PI);
	vec4 e = sample_grad(earth_tex, uv);
	// берег: порог мягкой маски суши + мелкий шум — линия чёткая и неровная при любом увеличении
	// фрактальный берег: заливы, мысы и островки нескольких масштабов поверх гладкой маски материков
	float cn = (texture(noise_tex, uv * vec2(260.0, 130.0) + 0.5).b - 0.5) * 0.5
		+ (texture(noise_tex, uv * vec2(900.0, 450.0)).r - 0.5) * 0.3
		+ (texture(noise_tex, uv * vec2(2900.0, 1450.0)).g - 0.5) * 0.16;
	// ширина перехода — по производной всей суммы (с мелким шумом): берег сглажен на пиксель, без «лесенки»
	float lv = e.a + cn * 0.5 * smoothstep(0.02, 0.2, e.a) * smoothstep(0.98, 0.8, e.a);
	float aw = max(fwidth(lv) * 0.7, 0.002);
	float land = smoothstep(0.5 - aw, 0.5 + aw, lv);
	float water = 1.0 - land;
	// море: глубокое тёмно-синее, у берегов — светлее шельф (размытая маска с мелкого мипа)
	float shelf = textureLod(earth_tex, uv, 3.5).a;
	vec3 sea = mix(vec3(0.002, 0.006, 0.02), vec3(0.005, 0.018, 0.034), smoothstep(0.02, 0.45, shelf));
	// мелкий рельеф и пашни: рябь яркости суши в нескольких масштабах (карта сама по себе гладкая)
	float d1 = texture(noise_tex, uv * vec2(1600.0, 800.0)).g;
	float d2 = texture(noise_tex, uv * vec2(5200.0, 2600.0)).b;
	float d3 = texture(noise_tex, uv * vec2(420.0, 210.0) + 0.21).r;
	vec3 lc = e.rgb * (0.74 + 0.36 * d1) * (0.88 + 0.24 * d2) * (0.9 + 0.2 * d3);
	// с орбиты цвета суши приглушены (дымка, рассеяние): чуть меньше насыщенности, не больше
	lc = max(mix(vec3(dot(lc, vec3(0.3, 0.55, 0.15))), lc, 0.9), 0.0);
	// мелкий рельеф: складки гор и долины из «гребневого» шума, освещённые солнцем сбоку (терминатор далеко,
	// но солнце невысоко — склоны читаются)
	vec3 lo_r = normalize(transpose(mat3(MODEL_MATRIX)) * normalize(sun));
	vec3 east = normalize(vec3(no.z, 0.0, -no.x) + vec3(1e-5, 0.0, 0.0));
	vec3 north = cross(no, east);
	vec2 sl = vec2(dot(lo_r, east), dot(lo_r, north));
	vec2 ruv = uv * vec2(900.0, 450.0);
	float eps = 0.003;
	float h0 = 1.0 - abs(texture(noise_tex, ruv).g * 2.0 - 1.0);
	float hx = 1.0 - abs(texture(noise_tex, ruv + vec2(eps, 0.0)).g * 2.0 - 1.0);
	float hy = 1.0 - abs(texture(noise_tex, ruv - vec2(0.0, eps)).g * 2.0 - 1.0);
	vec2 ruv2 = uv * vec2(2600.0, 1300.0) + 0.37;
	float g0 = texture(noise_tex, ruv2).r;
	float gx = texture(noise_tex, ruv2 + vec2(eps, 0.0)).r;
	float gy = texture(noise_tex, ruv2 - vec2(0.0, eps)).r;
	vec2 grad = vec2(hx - h0, hy - h0) * 1.0 + vec2(gx - g0, gy - g0) * 0.6;
	lc *= 1.0 + clamp(dot(grad, sl) * 9.0, -0.3, 0.3);
	vec3 alb = mix(sea, lc, land);
	// облака: карта + мелкая рябь (кучёвка), тени облаков смещены от солнца
	vec2 cuv = uv + vec2(cloud_shift, 0.0);
	float cb = sample_grad(cloud_tex, cuv).r;
	float cd = texture(noise_tex, uv * vec2(140.0, 70.0)).r * 0.6 + texture(noise_tex, uv * vec2(420.0, 210.0)).g * 0.4;
	// плотность облака — мягко: тонкие края полупрозрачны, рябь мелкой текстуры по всей массе
	float cloud = clamp(smoothstep(0.08, 0.72, cb) * (0.78 + 0.4 * cd), 0.0, 1.0);
	// мелкая структура: край облака рвётся на клочья и волокна (сдвиг координат — крупным шумом), плотные
	// середины остаются. Без этого облака — гладкие круглые пятна увеличенной карты
	vec2 wv = vec2(texture(noise_tex, uv * vec2(300.0, 150.0) + 0.61).g, texture(noise_tex, uv * vec2(300.0, 150.0) + 0.17).b) - 0.5;
	float er = texture(noise_tex, uv * vec2(1300.0, 650.0) + wv * 0.35).r * 0.6 + texture(noise_tex, uv * vec2(3900.0, 1950.0) + wv * 0.8).g * 0.4;
	cloud *= smoothstep(0.12, 0.62, cloud + (er - 0.5) * 1.1);
	// днём над сушей — поля мелкой кучёвки (летняя конвекция) клочьями, над морем её нет
	float cu_f = texture(noise_tex, uv * vec2(60.0, 30.0) + 0.3).b;
	float cu = smoothstep(0.7, 0.92, texture(noise_tex, uv * vec2(6400.0, 3200.0) + wv * 0.6).r * 0.6 + er * 0.25 + cu_f * 0.35);
	cloud = max(cloud, cu * land * smoothstep(0.55, 0.75, cu_f) * 0.45);
	vec3 lo = normalize(transpose(mat3(MODEL_MATRIX)) * l);
	vec2 sh_off = vec2(lo.x, -lo.y) * 0.0012;
	float cs = sample_grad(cloud_tex, cuv + sh_off).r;
	float shadow = 1.0 - smoothstep(0.12, 0.7, cs) * 0.55;
	// свет: солнце сквозь атмосферу (на закате — красноватое), мягкий терминатор
	float ndl = dot(n, l);
	vec3 sun_t = exp(-(B_R * light_depth(p, l).x + B_M * 1.1 * light_depth(p, l).y));
	float diff = smoothstep(-0.03, 0.12, ndl) * max(ndl, 0.0) + smoothstep(-0.03, 0.05, ndl) * 0.03;
	vec3 ground = alb * diff * shadow;
	// блик на воде
	vec3 v = -rd;
	vec3 h = normalize(l + v);
	// солнечная дорожка на море: волны дают широкое серебристое пятно с ярким ядром (Бекманн), Френель
	float nh = max(dot(n, h), 1e-3);
	float th2 = (1.0 - nh * nh) / (nh * nh);
	float fres = 0.02 + 0.98 * pow(1.0 - max(dot(v, h), 0.0), 5.0);
	float spec = (exp(-th2 / 0.012) * 0.07 + exp(-th2 / 0.0014) * 0.28) * min(fres / 0.04, 3.0);
	ground += vec3(1.0, 0.96, 0.88) * spec * water * (1.0 - cloud) * smoothstep(0.0, 0.08, ndl);
	// облака: толстые ярче, тонкие сероватые (сквозь них видно тёмное море)
	vec3 cloud_col = vec3(0.93) * (0.8 + 0.2 * smoothstep(0.3, 0.9, cb)) * (diff * 1.05 + 0.01);
	vec3 surf = mix(ground, cloud_col, cloud) * sun_t * sun_power * 0.24;
	// дымка между камерой и поверхностью
	vec2 ta = ray_sphere(ro, rd, radius + atmo);
	vec3 trans;
	vec3 ins = scatter(ro, rd, max(ta.x, 0.0), hit.x, l, trans);
	// «колено» матрицы: яркое (облака у освещённого лимба, дымка) мягко сжато ниже белого — рисунок облаков
	// виден, а камера не принимает Землю за лампу (почти белое она раздувает в ореол и смаз)
	vec3 col = surf * trans + ins * 0.15;
	float lum = dot(col, vec3(0.3, 0.55, 0.15));
	ALBEDO = col / (1.0 + lum / knee);
}
