shader_type sky;
// Концовка «океан»: толща воды во все стороны вместо неба. Сверху светлее (свет из окна Снелла),
// книзу — бездна. Туман сцены (aerial perspective) берёт цвет отсюда, поэтому всё тонет в той же воде.

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);   // направление на солнце уже под водой (преломлённое)
uniform float depth = 18.0;                    // глубина камеры, м

void sky() {
	vec3 d = EYEDIR;
	float k = exp(-depth * 0.045);             // чем глубже, тем темнее
	vec3 abyss = vec3(0.001, 0.005, 0.011);
	vec3 mid = vec3(0.004, 0.032, 0.05);
	vec3 high = vec3(0.02, 0.12, 0.155);
	vec3 col = mix(abyss, mid, smoothstep(-0.7, 0.15, d.y));
	col = mix(col, high, smoothstep(0.05, 0.95, d.y) * (0.35 + 0.65 * k));
	// вокруг преломлённого солнца толща светится сильнее (рассеяние вперёд)
	float s = max(dot(d, normalize(sun_dir)), 0.0);
	col += vec3(0.06, 0.2, 0.2) * (pow(s, 6.0) * 0.7 + pow(s, 40.0) * 1.2) * k;
	COLOR = col;
}
