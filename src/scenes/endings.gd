extends Node3D
## Концовки. Случайные выходы через нулевую зону всегда смертельны: океан, небо (лес), шоссе, стена, космос.
## Выход Async: газ, люди в костюмах, изолятор под камерой наблюдения, допрос — и снова газ.
## Смерть везде одинакова: кадр краснеет (как от ран), удар — красный экран — карточка.

const Props := preload("res://src/world/props.gd")
const ParkS := preload("res://src/scenes/park.gd")
const RedScreen := preload("res://src/scenes/red_screen.gd")
const WATER := preload("res://src/shaders/water.gdshader")

var kind := "ocean"
var player: Player = null
var cam: Camera3D
var env: Environment
var t := 0.0
var _look := Vector2.ZERO
var _yaw := 0.0
var _pitch := 0.0
var _free_look := true
var _done := false
var _phase := 0
var _water_y := 0.0
var _vel := Vector3.ZERO
var _subject: Human = null
var _cctv := false
var _lines_left: Array = []
var _hurt := 0.0               # красное в кадре 0..1 (Game.main.hurt); 1 — смерть
var _hurt_rate := 0.0          # сколько прибавляется в секунду
var _stroke := 0.0
var _earth: Node3D = null
var _bubbles: GPUParticles3D = null
var _gas_on := false
var _water_sky: ShaderMaterial = null
var _sky_depth := 18.0
var _smear_mat: StandardMaterial3D = null
var _slit_mat: StandardMaterial3D = null
var _slit_base := 0.6
var _tv_mat: StandardMaterial3D = null
var _earth_mat: ShaderMaterial = null
var _space_sky: ShaderMaterial = null
var _star_gain := 1.0
var _hn: FastNoiseLite = null    # лес: холмы
var _hd: FastNoiseLite = null    # лес: мелкий рельеф
var _hm: FastNoiseLite = null    # лес: горы вдали
var _h0 := 0.0
var _lake_y := 0.0

const LAKE := Vector2(900.0, -1500.0)
const TREES_R := 430.0

const EARTH_C := Vector3(0, -7000, 0)     # высота орбиты ~1000 «км»: видно Средиземноморье целиком
const EARTH_R := 6000.0


func begin() -> void:
	Props.park_mode = true
	if Game.main != null:
		Game.main.osd.shown = true
		Game.main.osd.date_reset = true
		Game.main.burst(1.0)
		Game.main.interference = 0.0
		Game.main.gain = 1.0
	Snd.stop_all(0.1)
	Snd.play("null_burst", 0.0)
	Snd.muffle(0.0)
	# сердце — тише или громче вместе с красным
	Snd.loop("heart", "heartbeat", 0.0, 0.3)
	match kind:
		"ocean": _ocean()
		"sky": _sky()
		"highway": _highway()
		"wall": _wall()
		"space": _space()
		"async": _async()
		_: _ocean()
	# отладка: --yaw/--pitch задают начальный взгляд там, где камерой правит сама концовка
	if Cfg.has_arg("yaw"):
		_yaw = float(Cfg.arg("yaw"))
	if Cfg.has_arg("pitch"):
		_pitch = float(Cfg.arg("pitch"))


func _env_base(bg: Color) -> Environment:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = bg
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.4
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.3, 0.3, 0.32)
	we.environment = e
	add_child(we)
	env = e
	return e


func _make_cam(pos: Vector3) -> void:
	cam = Camera3D.new()
	cam.fov = Cfg.fov
	cam.near = 0.05
	cam.far = 3000.0
	add_child(cam)
	cam.position = pos
	cam.current = true


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look += (e as InputEventMouseMotion).relative


func _apply_look(dt: float) -> void:
	if not _free_look or cam == null:
		_look = Vector2.ZERO
		return
	var s := 0.0022 * Cfg.sens
	_yaw -= _look.x * s
	_pitch = clampf(_pitch - _look.y * s * (-1.0 if Cfg.invert_y else 1.0), -1.4, 1.4)
	_look = Vector2.ZERO


## Красное прибавляется само (_hurt_rate); дошло до 1 — смерть
func _hurt_tick(dt: float) -> void:
	_hurt = clampf(_hurt + _hurt_rate * dt, 0.0, 1.0)
	if Game.main != null:
		Game.main.hurt = _hurt
	Snd.loop_vol("heart", clampf((_hurt - 0.15) * 1.3, 0.0, 1.0), 0.4)
	if _hurt >= 1.0:
		_death()


## Смерть: удар, кадр целиком красный, гул — и карточка концовки
func _death(card := "") -> void:
	if _done:
		return
	_done = true
	# _hurt_tick идёт каждый кадр и записал бы в main.hurt своё (у неба 0.75, у шоссе 0.55) — смерть = полный красный
	_hurt = 1.0
	Snd.stop_all(0.05)
	Snd.play("death_hit", 2.0)
	if Game.main != null:
		Game.main.hurt = 1.0
		Game.main.hurt_flash = 1.0
		Game.main.burst(1.0)
	await get_tree().create_timer(0.3).timeout
	# красный экран — записанный кадр внутри вьюпорта: плёнка красит его, шумит и пульсирует
	add_child(RedScreen.new())
	if Game.main != null:
		Game.main.interference = minf(Game.main.interference, 0.12)
		Game.main.osd.shown = false
	Snd.muffle(0.0)
	Snd.loop("death_drone", "death_drone", 0.6, 0.5)
	await get_tree().create_timer(3.4).timeout
	Snd.stop_loop("death_drone", 1.0)
	if Game.main != null:
		Game.main.fade_to(Color(0, 0, 0, 1), 1.0)
	await get_tree().create_timer(1.1).timeout
	Snd.stop_all(0.2)
	if Game.main != null:
		Game.main.hurt = 0.0
		Game.main.stopfx = 0.0
		Game.main.bw = 0.0
		Game.main.desat = 0.0
		Game.main.interference = 0.0
		Game.main.osd.message = ""
		Game.main.osd.cam_label = ""
	Game.show_card(card if card != "" else kind)


# ======================================================================= ОКЕАН

func _ocean() -> void:
	var e := _env_base(Color(0.0, 0.035, 0.05))
	# солнце над водой и его преломлённое направление под водой (закон Снелла)
	var sun_air := Vector3(0.14, 0.86, -0.5).normalized()
	var hor := Vector2(sun_air.x, sun_air.z)
	var sin_w := hor.length() / 1.333
	var sun_w := Vector3(hor.normalized().x * sin_w, sqrt(1.0 - sin_w * sin_w), hor.normalized().y * sin_w)
	# толща воды — «небо» во все стороны: к поверхности светлее, вниз — бездна; туман берёт цвет отсюда
	var sky := Sky.new()
	_water_sky = ShaderMaterial.new()
	_water_sky.shader = load("res://src/shaders/end_water_column.gdshader")
	_water_sky.set_shader_parameter("sun_dir", sun_w)
	_water_sky.set_shader_parameter("depth", 18.0)
	sky.sky_material = _water_sky
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.05, 0.12, 0.13)
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.fog_enabled = true
	e.fog_light_color = Color(0.015, 0.07, 0.085)
	e.fog_density = 0.07
	e.fog_aerial_perspective = 1.0
	e.fog_sky_affect = 0.0
	e.glow_intensity = 0.6
	e.glow_hdr_threshold = 1.0
	var sun := DirectionalLight3D.new()
	sun.look_at_from_position(Vector3.ZERO, -sun_w, Vector3.FORWARD)
	sun.light_color = Color(0.55, 0.85, 0.85)
	sun.light_energy = 0.6
	add_child(sun)
	# поверхность снизу: окно Снелла с небом и солнцем, вокруг — полное отражение тёмной толщи
	var surf := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 600)
	pm.subdivide_width = 4
	pm.subdivide_depth = 4
	surf.mesh = pm
	var sm := ShaderMaterial.new()
	sm.shader = load("res://src/shaders/end_water_surface.gdshader")
	sm.set_shader_parameter("wave_tex", Mats.tex("water_n"))
	sm.set_shader_parameter("sun_air", sun_air)
	surf.material_override = sm
	surf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surf)
	# столбы света: от поверхности вглубь вдоль преломлённых лучей, мерцают
	var rm := ShaderMaterial.new()
	rm.shader = load("res://src/shaders/end_godray.gdshader")
	rm.set_shader_parameter("axis", -sun_w)
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = rm
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = 48
	var rr := RandomNumberGenerator.new()
	rr.seed = 1991
	for k in mm.instance_count:
		var a := rr.randf() * TAU
		var r := sqrt(rr.randf()) * 26.0 + 1.5
		# начало луча — у поверхности, со сдвигом к солнцу: на глубине ~14 м столбы стоят вокруг камеры
		var top := Vector3(cos(a) * r, -0.3, sin(a) * r) + Vector3(sun_w.x, 0, sun_w.z) / sun_w.y * 14.0
		mm.set_instance_transform(k, Transform3D(Basis(), top))
		mm.set_instance_custom_data(k, Color(rr.randf_range(0.35, 1.6), rr.randf_range(22.0, 48.0), rr.randf(), rr.randf_range(0.5, 1.0)))
	var rays := MultiMeshInstance3D.new()
	rays.multimesh = mm
	rays.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rays.custom_aabb = AABB(Vector3(-60, -70, -60), Vector3(120, 75, 120))
	add_child(rays)
	# взвесь вокруг камеры
	_make_cam(Vector3(0, -18.0, 0))
	var specks := _particles(320, 9.0, Vector3(9, 6, 9), Color(0.75, 0.92, 0.88, 0.35), 0.02, Vector3(0, 0.03, 0))
	specks.local_coords = false
	cam.add_child(specks)
	_bubbles = _bubble_fx(40, 2.6, Vector3(0.12, 0.06, 0.12), 0.01, 0.035)
	_bubbles.emitting = false
	_bubbles.one_shot = true
	_bubbles.position = Vector3(0, -0.3, -0.7)
	cam.add_child(_bubbles)
	# падение в воду: облако пузырей вокруг и снизу, уходит вверх мимо камеры
	var plunge := _bubble_fx(220, 3.2, Vector3(1.6, 1.2, 1.6), 0.008, 0.05)
	plunge.one_shot = true
	plunge.explosiveness = 0.85
	plunge.position = Vector3(0, -1.2, -0.5)
	cam.add_child(plunge)
	_pitch = 0.55
	_vel = Vector3(0, -0.6, 0)
	_hurt_rate = 0.022
	Snd.loop("under", "under_rumble", 0.8, 0.5)
	Snd.muffle(0.85, true)
	Snd.play("bubbles", -2.0)
	if Game.main != null:
		Game.main.desat = 0.3
		Game.main.subs.say(Loc.t("ui.swim"), 6.0)


## Пузыри: всплывают с покачиванием, растут к поверхности, ободок со бликом (tex/fx_bubble)
func _bubble_fx(n: int, life: float, box: Vector3, size_min: float, size_max: float) -> GPUParticles3D:
	var gp := GPUParticles3D.new()
	gp.amount = n
	gp.lifetime = life
	gp.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.1
	pm.gravity = Vector3(0, 0.9, 0)
	pm.damping_min = 0.4
	pm.damping_max = 0.9
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 1.2
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.12
	pm.scale_min = size_min / size_max
	pm.scale_max = 1.0
	var a := Gradient.new()
	a.offsets = PackedFloat32Array([0.0, 0.08, 0.75, 1.0])
	a.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	var at := GradientTexture1D.new()
	at.gradient = a
	pm.color_ramp = at
	gp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size_max, size_max)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.vertex_color_use_as_albedo = true
	qm.albedo_color = Color(0.75, 0.92, 0.92, 0.45)
	qm.albedo_texture = Mats.tex("fx_bubble")
	qm.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	qm.distance_fade_min_distance = 0.06
	qm.distance_fade_max_distance = 0.2
	q.material = qm
	gp.draw_pass_1 = q
	gp.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 12, 8))
	return gp


## Простые частицы-квадратики: взвесь в воде, пузыри
func _particles(n: int, life: float, box: Vector3, col: Color, size: float, vel: Vector3) -> GPUParticles3D:
	var gp := GPUParticles3D.new()
	gp.amount = n
	gp.lifetime = life
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.direction = vel.normalized() if vel.length() > 0.001 else Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = vel.length() * 0.6
	pm.initial_velocity_max = vel.length() * 1.2
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	gp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.albedo_color = col
	qm.albedo_texture = _dot_tex()
	q.material = qm
	gp.draw_pass_1 = q
	return gp


## Ореол яркого огня в объективе: яркое ядро и долгий мягкий спад
func _glare_tex() -> GradientTexture2D:
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.06, 0.18, 0.4, 0.7, 1.0])
	gr.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.12),
		Color(1, 1, 1, 0.03), Color(1, 1, 1, 0)])
	gt.gradient = gr
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	return gt


## Круглое мягкое пятнышко (для пузырей, взвеси, газа)
func _dot_tex() -> GradientTexture2D:
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	gt.gradient = gr
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 32
	gt.height = 32
	return gt


func _ocean_tick(dt: float) -> void:
	var up := Input.is_action_pressed("move_f") or Input.is_action_pressed("fly_up") or Cfg.has_arg("auto")
	var strength := clampf(1.15 - _hurt * 1.25, 0.0, 1.0)
	_stroke -= dt
	if up and strength > 0.05:
		_vel.y = move_toward(_vel.y, 0.9 * strength, dt * 1.2)
		_hurt_rate = 0.025
		if _stroke <= 0.0:
			_stroke = randf_range(1.0, 1.6)
			Snd.play("bubbles", -10.0, randf_range(0.9, 1.1))
			_bubbles.restart()
	else:
		_vel.y = move_toward(_vel.y, -0.5, dt * 0.7)
		_hurt_rate = 0.02
	# у поверхности свет близко, но воздух кончается быстрее — не дотянуться
	if cam.position.y > -6.0:
		_hurt_rate += 0.035
	cam.position += _vel * dt
	cam.position.y = minf(cam.position.y, -2.2)
	cam.rotation = Vector3(_pitch + sin(t * 0.8) * 0.04, _yaw, sin(t * 0.6) * 0.05 + _hurt * 0.15 * sin(t * 2.1))
	# толща светлеет к поверхности; небо (и его радиантная карта) обновляется только при заметной разнице
	if _water_sky != null and absf(-cam.position.y - _sky_depth) > 0.5:
		_sky_depth = -cam.position.y
		_water_sky.set_shader_parameter("depth", _sky_depth)
	if Game.main != null:
		Game.main.interference = _hurt * 0.25
		Game.main.desat = 0.3 + _hurt * 0.3


# ======================================================================= НЕБО

func _sky() -> void:
	var e := _env_base(Color(0.6, 0.7, 0.85))
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://src/shaders/end_sky_day.gdshader")
	sm.set_shader_parameter("cloud_tex", Mats.tex("fx_cloudmap"))
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 1.0
	e.ambient_light_energy = 0.32
	# воздушная перспектива: даль голубеет и тонет в дымке
	e.fog_enabled = true
	e.fog_light_color = Color(0.55, 0.65, 0.8)
	e.fog_density = 0.00016
	e.fog_aerial_perspective = 0.6
	e.fog_sky_affect = 0.0
	e.tonemap_exposure = 1.0
	e.glow_intensity = 0.3
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.85, 2.4, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 1100.0
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	sun.shadow_blur = 1.2
	add_child(sun)
	_forest_terrain()
	_forest_trees()
	_sky_wisps(sun.transform.basis.z)
	_make_cam(Vector3(0, 470, 0))
	cam.far = 16000.0


## Высота земли под лесом: пологие холмы, вдали горы, котловина озера. В точке падения — 0
func _forest_h_raw(x: float, z: float) -> float:
	var r := sqrt(x * x + z * z)
	var h := _hn.get_noise_2d(x, z) * 42.0 + _hd.get_noise_2d(x, z) * 8.0
	var m := 1.0 - absf(_hm.get_noise_2d(x, z))
	h += m * m * 620.0 * smoothstep(1800.0, 7500.0, r)
	# котловина озера: дно ровное ниже уровня воды, берега плавные
	var ld := _lake_d(x, z)
	h = lerpf(h, minf(h, _lake_y - 4.0), smoothstep(1.25, 0.92, ld))
	return h


## Форма озера (та же формула в end_forest_ground.gdshader): < 1 — вода
func _lake_d(x: float, z: float) -> float:
	var d := Vector2(x - LAKE.x, (z - LAKE.y) * 1.6).length() / 520.0
	return d + 0.16 * sin(x * 0.0113 + 1.3) * sin(z * 0.0127 + 0.4) + 0.07 * sin(x * 0.031 + 2.0) * sin(z * 0.027 + 0.9)


func _forest_h(x: float, z: float) -> float:
	return _forest_h_raw(x, z) - _h0


## Земля до горизонта: полярная сетка (у центра густо, к краю реже), полог леса — в шейдере; озеро в котловине
func _forest_terrain() -> void:
	_hn = FastNoiseLite.new()
	_hn.seed = 1996
	_hn.frequency = 1.0 / 900.0
	_hn.fractal_octaves = 4
	_hd = FastNoiseLite.new()
	_hd.seed = 1997
	_hd.frequency = 1.0 / 170.0
	_hd.fractal_octaves = 3
	_hm = FastNoiseLite.new()
	_hm.seed = 1998
	_hm.frequency = 1.0 / 3400.0
	_hm.fractal_octaves = 5
	_h0 = 0.0
	_lake_y = 1e9
	_lake_y = _forest_h_raw(LAKE.x, LAKE.y) - 6.0
	_h0 = _forest_h_raw(0.0, 0.0)
	var rings := 150
	var segs := 256
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.resize((rings + 1) * segs)
	norms.resize((rings + 1) * segs)
	for i in rings + 1:
		var r := 10.0 * (exp(i * 0.05) - 1.0)
		var e := maxf(1.5, r * 0.02)
		for j in segs:
			var a := TAU * j / segs
			var x := cos(a) * r
			var z := sin(a) * r
			var h := _forest_h(x, z)
			var hx := _forest_h(x + e, z) - h
			var hz := _forest_h(x, z + e) - h
			verts[i * segs + j] = Vector3(x, h, z)
			norms[i * segs + j] = Vector3(-hx / e, 1.0, -hz / e).normalized()
	for i in rings:
		for j in segs:
			var a0 := i * segs + j
			var b0 := i * segs + (j + 1) % segs
			var c0 := (i + 1) * segs + j
			var d0 := (i + 1) * segs + (j + 1) % segs
			idx.append_array(PackedInt32Array([a0, c0, b0, b0, c0, d0]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var gm := ShaderMaterial.new()
	gm.shader = load("res://src/shaders/end_forest_ground.gdshader")
	gm.set_shader_parameter("canopy", Mats.tex("fx_canopy"))
	gm.set_shader_parameter("noise_tex", Mats.tex("noise"))
	gm.set_shader_parameter("trees_r", TREES_R)
	gm.set_shader_parameter("lake_y", _lake_y - _h0)
	gm.set_shader_parameter("lake_c", LAKE)
	var g := MeshInstance3D.new()
	g.mesh = mesh
	g.material_override = gm
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(g)


## Кроны вокруг места падения: деревья кучками (лиственные и ельники), поляны и прогалины, по краю зоны лес
## редеет. Сетка 7 м сильно сбита (без рядов), часть мест пропущена. Лиственные — три разные кроны (форма, число
## «клубов»), у всех — стволы под кроной (видны вблизи). Чанки 60 м: каждый — свои MultiMesh (отсекаются по
## видимости), вблизи — подробная крона и стволы, дальше — простая крона.
func _forest_trees() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/shaders/end_crown.gdshader")
	mat.set_shader_parameter("leaf_tex", Mats.tex("leaves"))
	mat.set_shader_parameter("noise_tex", Mats.tex("noise"))
	# 0..2 — лиственные (вблизи), 3 — ель (вблизи); дальние: лиственная и ель попроще
	var near_m := [_crown_mesh(false, 1, 5, 1), _crown_mesh(false, 1, 4, 2), _crown_mesh(false, 1, 7, 3), _crown_mesh(true, 2, 1)]
	# дальние лиственные — тоже из нескольких клубов (одиночный шар сверху читался «помпоном»)
	var far_m := [_crown_mesh(false, 1, 3, 4), _crown_mesh(true, 1, 1)]
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.55
	trunk_mesh.bottom_radius = 1.0
	trunk_mesh.height = 1.0
	trunk_mesh.radial_segments = 6
	trunk_mesh.rings = 1
	trunk_mesh.cap_top = false
	trunk_mesh.cap_bottom = false
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.2, 0.17, 0.14)
	bark.albedo_texture = Mats.tex("noise")
	bark.uv1_scale = Vector3(1.0, 4.0, 1.0)
	bark.roughness = 1.0
	var clump := FastNoiseLite.new()
	clump.seed = 77
	clump.frequency = 1.0 / 140.0
	var gaps := FastNoiseLite.new()
	gaps.seed = 78
	gaps.frequency = 1.0 / 90.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 1996
	var chunks := {}
	var sp := 7.0
	var n := int(TREES_R / sp)
	for gx in range(-n, n + 1):
		for gz in range(-n, n + 1):
			var p := Vector2(gx + rng.randf_range(-0.5, 0.5), gz + rng.randf_range(-0.5, 0.5)) * sp + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
			if gx == 0 and gz == 0:
				p = Vector2(0.4, 0.3)
			var r := p.length()
			if r > TREES_R or rng.randf() > smoothstep(TREES_R, TREES_R - 80.0, r):
				continue
			# прогалины: крупные поляны по шуму и одиночные просветы
			var gn := gaps.get_noise_2d(p.x, p.y)
			if (gn > 0.26 or rng.randf() < 0.12 + smoothstep(0.05, 0.26, gn) * 0.5) and r > 8.0:
				continue
			var cl := clump.get_noise_2d(p.x, p.y)
			var con := cl < -0.18 or rng.randf() < 0.07
			var hg := _forest_h(p.x, p.y)
			var b := Basis(Vector3.UP, rng.randf() * TAU)
			var pos: Vector3
			var tint: Color
			var kind := 3
			var tr: Transform3D
			if con:
				var cr := rng.randf_range(2.3, 3.8)
				var half := rng.randf_range(6.5, 11.0)
				b = b.scaled(Vector3(cr, half, cr))
				pos = Vector3(p.x, hg + 3.0 + half, p.y)
				tint = Color(0.035, 0.06, 0.035).lerp(Color(0.06, 0.085, 0.045), rng.randf())
				tr = Transform3D(Basis().scaled(Vector3(0.28, 3.0 + half * 0.6, 0.28)), Vector3(p.x, hg + (3.0 + half * 0.6) * 0.5, p.y))
			else:
				kind = rng.randi_range(0, 2)
				var cr2 := rng.randf_range(2.4, 4.6) + pow(rng.randf(), 3.0) * 3.2
				var trunk := rng.randf_range(7.5, 14.0)
				var sy := cr2 * rng.randf_range(0.65, 0.95)
				# кроны чуть шире шага посадки — смыкаются в полог, без «горошин» на траве
				b = b.scaled(Vector3(cr2 * rng.randf_range(0.85, 1.15) * 1.18, sy, cr2 * rng.randf_range(0.85, 1.15) * 1.18))
				pos = Vector3(p.x, hg + trunk + sy * 0.4, p.y)
				var warm := clampf(cl * 1.5 + 0.5, 0.0, 1.0)
				tint = Color(0.05, 0.085, 0.03).lerp(Color(0.12, 0.15, 0.05), warm * 0.6 + rng.randf() * 0.4)
				var th := trunk + sy * 0.2
				var trr := 0.18 + cr2 * 0.035
				tr = Transform3D(Basis().scaled(Vector3(trr, th, trr)), Vector3(p.x, hg + th * 0.5 - 0.3, p.y))
			var key := Vector2i(floori(p.x / 60.0), floori(p.y / 60.0))
			if not chunks.has(key):
				chunks[key] = [[], [], [], [], []]
			(chunks[key][kind] as Array).append([Transform3D(b, pos), tint])
			(chunks[key][4] as Array).append([tr, Color(1, 1, 1)])
	for key: Vector2i in chunks.keys():
		var c := Vector3(key.x * 60.0 + 30.0, 0.0, key.y * 60.0 + 30.0)
		c.y = _forest_h(c.x, c.z)
		var lists: Array = chunks[key]
		# вблизи: каждая крона своим мешем; вдали: все лиственные — один простой меш
		for kind_i in 4:
			_mm_chunk(c, lists[kind_i], near_m[kind_i], mat, 0.0, 170.0)
		_mm_chunk(c, (lists[0] as Array) + (lists[1] as Array) + (lists[2] as Array), far_m[0], mat, 170.0, 0.0)
		_mm_chunk(c, lists[3], far_m[1], mat, 170.0, 0.0)
		_mm_chunk(c, lists[4], trunk_mesh, bark, 0.0, 120.0)


## MultiMesh экземпляров list ([Transform3D, цвет]) чанка с центром c; видимость от near до far (0 — без границы)
func _mm_chunk(c: Vector3, list: Array, mesh: Mesh, mat: Material, near: float, far: float) -> void:
	if list.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = list.size()
	for i in list.size():
		var it: Array = list[i]
		var tr: Transform3D = it[0]
		tr.origin -= c
		mm.set_instance_transform(i, tr)
		mm.set_instance_custom_data(i, it[1])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.position = c
	if near > 0.0:
		mmi.visibility_range_begin = near
		mmi.visibility_range_begin_margin = 10.0
	if far > 0.0:
		mmi.visibility_range_end = far
		mmi.visibility_range_end_margin = 10.0
	add_child(mmi)


## Крона: лиственная — несколько комковатых «клубов» (неровный силуэт, плоский низ), ель — ярусный конус.
## Цвет вершины (r) — затенение: низ и впадины темнее. lobes — сколько клубов (1 — дальняя упрощённая)
func _crown_mesh(conifer: bool, sub: int, lobes: int, seed := 0) -> ArrayMesh:
	var g := (1.0 + sqrt(5.0)) * 0.5
	var vs: Array[Vector3] = [Vector3(-1, g, 0), Vector3(1, g, 0), Vector3(-1, -g, 0), Vector3(1, -g, 0),
		Vector3(0, -1, g), Vector3(0, 1, g), Vector3(0, -1, -g), Vector3(0, 1, -g),
		Vector3(g, 0, -1), Vector3(g, 0, 1), Vector3(-g, 0, -1), Vector3(-g, 0, 1)]
	for i in vs.size():
		vs[i] = vs[i].normalized()
	var fs: Array[Vector3i] = [Vector3i(0, 11, 5), Vector3i(0, 5, 1), Vector3i(0, 1, 7), Vector3i(0, 7, 10),
		Vector3i(0, 10, 11), Vector3i(1, 5, 9), Vector3i(5, 11, 4), Vector3i(11, 10, 2), Vector3i(10, 7, 6),
		Vector3i(7, 1, 8), Vector3i(3, 9, 4), Vector3i(3, 4, 2), Vector3i(3, 2, 6), Vector3i(3, 6, 8),
		Vector3i(3, 8, 9), Vector3i(4, 9, 5), Vector3i(2, 4, 11), Vector3i(6, 2, 10), Vector3i(8, 6, 7),
		Vector3i(9, 8, 1)]
	for s in sub:
		var mid := {}
		var nf: Array[Vector3i] = []
		for f in fs:
			var ab := _ico_mid(vs, mid, f.x, f.y)
			var bc := _ico_mid(vs, mid, f.y, f.z)
			var ca := _ico_mid(vs, mid, f.z, f.x)
			nf.append(Vector3i(f.x, ab, ca))
			nf.append(Vector3i(f.y, bc, ab))
			nf.append(Vector3i(f.z, ca, bc))
			nf.append(Vector3i(ab, bc, ca))
		fs = nf
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# клубы: центр и радиус (у ели — один конус)
	var lc: Array[Vector3] = [Vector3.ZERO]
	var lr: Array[float] = [0.78]
	if not conifer and lobes > 1:
		lr[0] = 0.62
		var rr := RandomNumberGenerator.new()
		rr.seed = 4242 + lobes + seed * 977
		var lean := Vector3(rr.randf_range(-0.12, 0.12), 0.0, rr.randf_range(-0.12, 0.12))
		for k in lobes - 1:
			var a := TAU * (k + rr.randf_range(-0.3, 0.3)) / float(lobes - 1)
			var d := rr.randf_range(0.3, 0.55)
			lc.append(Vector3(cos(a) * d, rr.randf_range(-0.12, 0.38), sin(a) * d) + lean)
			lr.append(rr.randf_range(0.32, 0.58))
	var base := 0
	for li in lc.size():
		for v in vs:
			var p := v
			var ao := 1.0
			if conifer:
				# профиль ели: широкий низ (короткое «донышко»), к макушке — острый конус, ярусы веток
				var tt := (v.y + 1.0) * 0.5
				var dir := Vector2(v.x, v.z)
				dir = dir.normalized() if dir.length() > 0.001 else Vector2.ZERO
				var tier := 0.5 + 0.5 * sin(tt * 26.0 + atan2(v.z, v.x) * 2.0)
				var rad := pow(1.0 - tt, 0.85) * smoothstep(0.0, 0.14, tt) * (0.84 + 0.16 * tier)
				p = Vector3(dir.x * rad, v.y, dir.y * rad)
				ao = clampf(0.25 + 0.6 * tt + 0.3 * tier, 0.2, 1.0)
			else:
				var w := v + lc[li] * 3.0
				var lump := 0.5 * sin(w.x * 4.1 + 1.7) * sin(w.y * 3.7 + 0.4) * sin(w.z * 4.5 + 2.9) 					+ 0.3 * sin(w.x * 9.3 + 0.2) * sin(w.y * 8.1 + 1.1) * sin(w.z * 10.7 + 0.5)
				p = v * lr[li] * (1.0 + 0.22 * lump) + lc[li]
				if p.y < -0.3:
					p.y = -0.3 + (p.y + 0.3) * 0.35
				ao = clampf(0.3 + 0.6 * smoothstep(-0.5, 0.8, p.y) + 0.3 * lump + 0.15 * v.y, 0.15, 1.0)
			st.set_color(Color(ao, ao, ao))
			st.add_vertex(p)
		for f in fs:
			st.add_index(base + f.x)
			st.add_index(base + f.z)
			st.add_index(base + f.y)
		base += vs.size()
	st.generate_normals()
	return st.commit()


func _ico_mid(vs: Array[Vector3], cache: Dictionary, a: int, b: int) -> int:
	var key := Vector2i(mini(a, b), maxi(a, b))
	if cache.has(key):
		return cache[key]
	vs.append(((vs[a] + vs[b]) * 0.5).normalized())
	cache[key] = vs.size() - 1
	return vs.size() - 1


## Клочья облаков на высоте падения: мимо них летишь — видно скорость и глубину. Каждый клок — несколько
## объёмных эллипсоидов (шейдер end_cloud: толща по лучу, края рвёт 3D-шум), а не спрайты лицом к камере
func _sky_wisps(sun_dir: Vector3) -> void:
	var m := ShaderMaterial.new()
	m.shader = load("res://src/shaders/end_cloud.gdshader")
	m.set_shader_parameter("sun_dir", sun_dir)
	# меш чуть больше единичной сферы шейдера: грани многогранника не срезают края облака прямыми линиями
	var sm := SphereMesh.new()
	sm.radius = 1.03
	sm.height = 2.06
	sm.radial_segments = 24
	sm.rings = 12
	var rng := RandomNumberGenerator.new()
	rng.seed = 23091996
	for w in 11:
		var a := rng.randf() * TAU
		var d := rng.randf_range(18.0, 320.0) if w > 1 else rng.randf_range(8.0, 30.0)
		var c := Vector3(cos(a) * d, rng.randf_range(300.0, 520.0), sin(a) * d)
		for k in rng.randi_range(6, 11):
			var q := MeshInstance3D.new()
			var s := rng.randf_range(24.0, 70.0)
			var flat := rng.randf_range(0.5, 0.8)
			rng.randi()          # (был выбор кадра атласа; оставлен, чтобы клочья стояли на прежних местах)
			q.mesh = sm
			q.material_override = m
			q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			q.position = c + Vector3(rng.randf_range(-35, 35), rng.randf_range(-7, 7), rng.randf_range(-35, 35))
			# плоские снизу, вытянутые по ветру «лепёшки» разной толщины
			q.rotation.y = s * 1.7 + k
			q.scale = Vector3(s * 0.55, s * flat * 0.3, s * 0.42)
			q.set_instance_shader_parameter("seed", float(w * 13 + k) * 7.31)
			add_child(q)


func _sky_tick(dt: float) -> void:
	_vel.y = maxf(_vel.y - 9.8 * dt, -52.0)
	cam.position += _vel * dt
	# кувыркает, но смотреть можно: внизу всё ближе лес
	var tumble := Vector3(sin(t * 1.3) * 0.3, t * 0.55, sin(t * 2.1) * 0.45)
	cam.rotation = Vector3(clampf(_pitch - 0.4, -1.5, 0.6) + tumble.x, _yaw + tumble.y, tumble.z)
	var alt := cam.position.y
	_hurt = maxf(_hurt, clampf((240.0 - alt) / 300.0, 0.0, 0.75))
	if Game.main != null:
		Game.main.osd.shown = true
		Game.main.interference = clampf((120.0 - alt) / 120.0, 0.0, 0.5)
	if alt < 11.0:
		cam.position.y = 11.0
		_vel = Vector3.ZERO
		Snd.play("branches", 4.0)
		Snd.play("body_fall", 4.0)
		_death("sky")


# ======================================================================= ШОССЕ

func _highway() -> void:
	var e := _env_base(Color(0.01, 0.012, 0.025))
	# ночное небо: звёзды, Млечный Путь, зарево далёкого городка впереди
	var sky := Sky.new()
	var skm := ShaderMaterial.new()
	skm.shader = load("res://src/shaders/end_night_sky.gdshader")
	skm.set_shader_parameter("noise_tex", Mats.tex("noise"))
	sky.sky_material = skm
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# рассеянный свет ночи — нейтральный и слабый: асфальт тёмно-серый, а не того же синего, что небо
	e.ambient_light_color = Color(0.045, 0.047, 0.055)
	e.ambient_light_energy = 1.0
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.fog_enabled = true
	e.fog_light_color = Color(0.012, 0.014, 0.024)
	e.fog_density = 0.0035
	e.fog_sky_affect = 0.0
	# пыль в воздухе: фары грузовика рисуют лучи
	e.volumetric_fog_enabled = true
	e.volumetric_fog_density = 0.016
	e.volumetric_fog_albedo = Color(0.8, 0.78, 0.74)
	e.volumetric_fog_length = 110.0
	e.volumetric_fog_detail_spread = 1.6
	e.volumetric_fog_ambient_inject = 0.0
	e.volumetric_fog_sky_affect = 0.0
	e.glow_intensity = 0.8
	e.glow_hdr_threshold = 0.8
	e.glow_bloom = 0.02
	# луна за спиной: слабо освещает знак, асфальт и кусты
	var moon := DirectionalLight3D.new()
	moon.rotation = Vector3(-0.55, 0.45, 0)
	moon.light_color = Color(0.72, 0.76, 0.86)
	moon.light_energy = 0.32
	moon.light_volumetric_fog_energy = 0.0
	add_child(moon)
	# дорога, обочины и пустыня — одна поверхность
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12000, 12000)
	g.mesh = pm
	var rm := ShaderMaterial.new()
	rm.shader = load("res://src/shaders/end_road.gdshader")
	rm.set_shader_parameter("asphalt_tex", Mats.tex("asphalt"))
	rm.set_shader_parameter("desert_tex", Mats.tex("fx_desert"))
	rm.set_shader_parameter("noise_tex", Mats.tex("noise"))
	g.material_override = rm
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(g)
	_desert_brush()
	_mountains(7000.0, 15000.0, 0.0045, 1990, 900.0)
	_mountains(18000.0, 26000.0, 0.011, 1991, 1500.0)
	_road_sign()
	player = Player.new()
	add_child(player)
	player.cam.far = 30000.0
	player.global_position = Vector3(2.0, 0.3, 0)
	player.set_look(0.0, 0.0)
	player.surface_fn = func(p: Vector3) -> String: return "path" if absf(p.x) < 4.0 else "grass"
	# после выпадения ноги не слушаются: герой лежит на асфальте и только может смотреть
	player.frozen = true
	player.cine = true
	player.head.position = Vector3(0, 0.25, 0)
	player.cam.rotation = Vector3(0.05, 0.0, 0.5)
	var gb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1200, 1, 1200)
	cs.shape = bs
	cs.position.y = -0.5
	gb.add_child(cs)
	add_child(gb)
	Snd.loop("wind", "wind_open", 0.45, 1.0)
	Snd.loop("crickets", "crickets", 0.3, 2.0)
	_truck()


## Полынь вдоль дороги: низкие серые кусты, ловят свет фар и отбрасывают длинные тени
func _desert_brush() -> void:
	var mesh := _crown_mesh(false, 1, 3)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.3, 0.32, 0.26)
	mat.albedo_texture = Mats.tex("leaves")
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(2.0, 2.0, 2.0)
	mat.roughness = 1.0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var rng := RandomNumberGenerator.new()
	rng.seed = 5050
	var list: Array[Transform3D] = []
	while list.size() < 1400:
		var x := rng.randf_range(5.6, 160.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		var z := rng.randf_range(-420.0, 60.0)
		if absf(x) < 9.0 and rng.randf() < 0.6:
			continue
		var w := rng.randf_range(0.35, 0.8)
		var bas := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(w, w * rng.randf_range(0.6, 0.9), w))
		list.append(Transform3D(bas, Vector3(x, w * 0.25, z)))
	mm.instance_count = list.size()
	for i in list.size():
		mm.set_instance_transform(i, list[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)


## Кольцо гор-силуэтов: хребты по бокам долины ближе и выше, по оси дороги — дальше и ниже
func _mountains(r0: float, r1: float, shade: float, sd: int, hmax: float) -> void:
	var fn := FastNoiseLite.new()
	fn.seed = sd
	fn.frequency = 2.2
	fn.fractal_octaves = 5
	var segs := 720
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in segs + 1:
		var a := TAU * j / segs
		var side := absf(cos(a))
		var r := lerpf(r1, r0, side)
		var u := float(j) / segs
		var ridge := 1.0 - absf(fn.get_noise_2d(cos(a) * 3.0, sin(a) * 3.0))
		var h := (0.25 + 0.75 * ridge * ridge) * hmax * lerpf(0.45, 1.0, side) + fn.get_noise_1d(u * 40.0) * hmax * 0.08
		verts.append(Vector3(cos(a) * r, -60.0, sin(a) * r))
		verts.append(Vector3(cos(a) * r, h, sin(a) * r))
	for j in segs:
		var k := j * 2
		idx.append_array(PackedInt32Array([k, k + 1, k + 2, k + 2, k + 1, k + 3]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(shade, shade * 1.05, shade * 1.4)
	mat.disable_fog = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Зелёный указатель: световозвращающая плёнка, белая кайма и надпись (освещаются как сам щит), два столба
func _road_sign() -> void:
	var sign := Node3D.new()
	add_child(sign)
	sign.position = Vector3(5.5, 0, -18)
	sign.rotation.y = -0.12
	var post := StandardMaterial3D.new()
	post.albedo_color = Color(0.45, 0.46, 0.45)
	post.metallic = 0.6
	post.roughness = 0.5
	for px in [-0.55, 0.55]:
		_box(sign, Vector3(0.08, 2.75, 0.05), Vector3(px, 1.37, -0.06), post, false)
	var back := StandardMaterial3D.new()
	back.albedo_color = Color(0.36, 0.37, 0.37)
	back.metallic = 0.5
	back.roughness = 0.6
	_box(sign, Vector3(1.66, 0.96, 0.03), Vector3(0, 2.3, -0.03), back, false)
	var face := StandardMaterial3D.new()
	face.albedo_color = Color(0.03, 0.27, 0.12)
	face.roughness = 0.45
	face.metallic_specular = 0.7
	_box(sign, Vector3(1.6, 0.9, 0.012), Vector3(0, 2.3, -0.008), face, false)
	var rim := StandardMaterial3D.new()
	rim.albedo_color = Color(0.85, 0.86, 0.82)
	rim.roughness = 0.45
	for r in [[Vector3(1.48, 0.025, 0.004), Vector3(0, 2.71, 0.0)], [Vector3(1.48, 0.025, 0.004), Vector3(0, 1.89, 0.0)],
			[Vector3(0.025, 0.84, 0.004), Vector3(-0.74, 2.3, 0.0)], [Vector3(0.025, 0.84, 0.004), Vector3(0.74, 2.3, 0.0)]]:
		_box(sign, r[0], r[1], rim, false)
	var lb := Props.label("US 50\nELY  64", Props.font_sign(), 0.0058, Color(0.9, 0.9, 0.86))
	lb.shaded = true
	lb.position = Vector3(0, 2.3, 0.006)
	lb.visibility_range_end = 0.0
	sign.add_child(lb)


## Седельный тягач с фургоном: капот, кабина, габаритные огни по крыше и борту, фары с бликом в объективе
func _truck() -> void:
	var truck := Node3D.new()
	truck.name = "Truck"
	add_child(truck)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.16, 0.035, 0.03)
	paint.metallic = 0.3
	paint.roughness = 0.35
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.04, 0.04, 0.045)
	dark.roughness = 0.8
	var box_m := StandardMaterial3D.new()
	box_m.albedo_color = Color(0.34, 0.34, 0.33)
	box_m.metallic = 0.5
	box_m.roughness = 0.45
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.7, 0.7, 0.72)
	chrome.metallic = 0.9
	chrome.roughness = 0.2
	_box(truck, Vector3(2.2, 1.25, 2.0), Vector3(0, 1.45, -9.6), paint, false)          # капот
	_box(truck, Vector3(1.3, 1.0, 0.06), Vector3(0, 1.35, -10.62), chrome, false)       # решётка
	_box(truck, Vector3(2.5, 0.25, 0.3), Vector3(0, 0.7, -10.6), chrome, false)         # бампер
	_box(truck, Vector3(2.5, 2.7, 2.4), Vector3(0, 2.25, -7.5), paint, false)           # кабина
	_box(truck, Vector3(2.3, 0.75, 0.05), Vector3(0, 3.0, -8.72), dark, false)          # стекло
	_box(truck, Vector3(2.6, 3.0, 14.4), Vector3(0, 2.75, 0.9), box_m, false)           # фургон
	_box(truck, Vector3(2.4, 0.5, 18.0), Vector3(0, 0.95, -1.0), dark, false)           # рама
	for wz in [-9.3, -5.8, -4.6, 5.0, 6.3]:
		for wx in [-1.08, 1.08]:
			var wh := MeshInstance3D.new()
			var cy := CylinderMesh.new()
			cy.top_radius = 0.52
			cy.bottom_radius = 0.52
			cy.height = 0.32
			wh.mesh = cy
			wh.material_override = dark
			wh.rotation.z = PI * 0.5
			wh.position = Vector3(wx, 0.52, wz)
			truck.add_child(wh)
	# габаритные огни: янтарные по козырьку кабины и вдоль фургона
	var amber := StandardMaterial3D.new()
	amber.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	amber.albedo_color = Color(1.0, 0.55, 0.12)
	for k in 5:
		_box(truck, Vector3(0.1, 0.07, 0.06), Vector3(-0.5 + k * 0.25, 3.63, -8.7), amber, false)
	for sz in [-6.0, -1.5, 3.0, 7.8]:
		for sx in [-1.31, 1.31]:
			_box(truck, Vector3(0.03, 0.08, 0.12), Vector3(sx, 1.4, sz), amber, false)
	# фары: свет с тенями, светящиеся стёкла; в объективе — ореол постоянного экранного размера
	# и вертикальный «смаз» ПЗС-матрицы (так бытовые камеры 90-х рисуют яркие огни ночью)
	var glare := StandardMaterial3D.new()
	glare.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glare.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glare.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glare.albedo_texture = _glare_tex()
	glare.albedo_color = Color(1.0, 0.92, 0.8, 0.9)
	glare.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glare.fixed_size = true
	glare.no_depth_test = true
	glare.disable_fog = true
	glare.render_priority = 2
	var smear := glare.duplicate() as StandardMaterial3D
	smear.albedo_color = Color(1.0, 0.95, 0.85, 0.0)
	_smear_mat = smear
	for sx in [-0.9, 0.9]:
		var hl := SpotLight3D.new()
		hl.position = Vector3(sx, 1.15, -10.85)
		# дальний свет: яркое пятно на асфальте перед машиной, лучи в пыли (сила — на 100 м, а не на 10)
		hl.light_energy = 36.0
		hl.spot_range = 160.0
		hl.spot_angle = 20.0
		hl.spot_attenuation = 0.6
		hl.light_color = Color(1.0, 0.93, 0.78)
		hl.shadow_enabled = true
		hl.light_volumetric_fog_energy = 0.08
		hl.rotation.x = -0.035
		truck.add_child(hl)
		var lamp := MeshInstance3D.new()
		var ls := BoxMesh.new()
		ls.size = Vector3(0.42, 0.24, 0.06)
		lamp.mesh = ls
		var lm := StandardMaterial3D.new()
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.albedo_color = Color(1.0, 0.97, 0.9)
		lamp.material_override = lm
		lamp.position = Vector3(sx, 1.15, -10.66)
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		truck.add_child(lamp)
		# ореол фары — небольшой: издали две фары — две точки, а не одна круглая «луна»
		for gs in [0.014, 0.04]:
			var gq := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(gs, gs)
			gq.mesh = qm
			gq.material_override = glare
			gq.position = Vector3(sx, 1.15, -10.75)
			gq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			gq.add_to_group("glare")
			truck.add_child(gq)
		var sq := MeshInstance3D.new()
		var sqm := QuadMesh.new()
		sqm.size = Vector2(0.006, 1.2)
		sq.mesh = sqm
		sq.material_override = smear
		sq.position = Vector3(sx, 1.15, -10.75)
		sq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sq.add_to_group("glare")
		truck.add_child(sq)
	truck.position = Vector3(2.0, 0, -300)
	truck.rotation.y = PI


func _highway_tick(dt: float) -> void:
	var truck := get_node("Truck") as Node3D
	# камера: голова поворачивается за мышью, но встать нельзя
	if player != null:
		player.cam.rotation = Vector3(clampf(_pitch, -0.6, 0.6) + 0.05, _yaw, 0.5 + sin(t * 0.7) * 0.05)
		if t > 3.0 and t < 9.0:
			player.head.position.y = lerpf(player.head.position.y, 0.75, dt * 0.4)
	if t > 7.0:
		var sp := 30.0
		truck.position.z += sp * dt
		truck.position.x = move_toward(truck.position.x, player.global_position.x, dt * 0.6)
		if truck.position.z > -160.0 and not truck.has_meta("honk"):
			truck.set_meta("honk", true)
			Snd.play_at("horn", truck.position, self, 6.0, 1.0, 400.0, 30.0)
			Snd.play_at("truck_pass", truck.position, self, 4.0, 1.0, 300.0, 20.0)
		if truck.position.z > -45.0 and not truck.has_meta("brake"):
			truck.set_meta("brake", true)
			Snd.play_at("brakes", truck.position, self, 4.0, 1.0, 300.0, 25.0)
		if Game.main != null:
			Game.main.gain = clampf(1.0 + (truck.position.z + 120.0) / 40.0, 1.0, 3.5)
		# ореол фар в объективе растёт по мере приближения
		var gk := clampf(90.0 / maxf(player.global_position.z - truck.position.z - 10.0, 1.0), 0.6, 4.0)
		for gn in get_tree().get_nodes_in_group("glare"):
			(gn as Node3D).scale = Vector3(gk, 1.0, 1.0) if (gn as MeshInstance3D).material_override == _smear_mat else Vector3.ONE * gk
		if _smear_mat != null:
			_smear_mat.albedo_color.a = clampf((gk - 0.5) * 0.06, 0.0, 0.2)
		_hurt = maxf(_hurt, clampf((truck.position.z + 90.0) / 120.0, 0.0, 0.55))
		if truck.position.z > player.global_position.z - 10.0:
			# удар: запись обрывается
			Snd.play("death_hit", 4.0)
			Snd.play("impact_far", 6.0)
			if Game.main != null:
				Game.main.interference = 1.0
			truck.position.z = player.global_position.z - 10.0
			_death("highway")


# ======================================================================= СТЕНА

## Узкая щель между стенами жилого дома: за гипсокартоном живут люди, выхода нет
func _wall() -> void:
	_env_base(Color(0, 0, 0))
	env.ambient_light_color = Color(0.012, 0.011, 0.01)
	env.glow_intensity = 0.5
	var w := 0.62                 # просвет между стойками
	var L := 3.2
	var h := 2.6
	var sd := 0.089               # глубина стойки 2×4
	var dw := w * 0.5 + sd        # плоскость изнанки гипсокартона
	# коллизии — прежние: пол, потолок, грани стоек по бокам, торцы
	for c in [[Vector3(w, 0.1, L), Vector3(0, -0.05, 0)], [Vector3(w, 0.1, L), Vector3(0, h + 0.05, 0)],
			[Vector3(0.05, h, L), Vector3(-w * 0.5 - 0.025, h * 0.5, 0)], [Vector3(0.05, h, L), Vector3(w * 0.5 + 0.025, h * 0.5, 0)],
			[Vector3(w, h, 0.1), Vector3(0, h * 0.5, -L * 0.5 - 0.05)], [Vector3(w, h, 0.1), Vector3(0, h * 0.5, L * 0.5 + 0.05)]]:
		Props.collider(self, c[0], c[1])
	var wood := StandardMaterial3D.new()
	wood.albedo_texture = Mats.tex("wood")
	wood.albedo_color = Color(1.0, 0.92, 0.78)
	wood.uv1_triplanar = true
	wood.uv1_scale = Vector3(2.6, 0.9, 2.6)
	wood.roughness = 0.9
	var ply := StandardMaterial3D.new()
	ply.albedo_texture = Mats.tex("fx_plywood")
	ply.uv1_triplanar = true
	ply.uv1_scale = Vector3(0.8, 0.8, 0.8)
	ply.roughness = 0.95
	# изнанка гипсокартона: штамп читается изнутри полости на обеих стенах
	var board_l := StandardMaterial3D.new()
	board_l.albedo_texture = Mats.tex("fx_drywall")
	board_l.uv1_triplanar = true
	board_l.uv1_scale = Vector3(0.82, 0.82, -0.82)
	board_l.uv1_offset = Vector3(0.0, 0.12, 0.31)
	board_l.roughness = 0.95
	var board_r := board_l.duplicate() as StandardMaterial3D
	board_r.uv1_scale = Vector3(0.82, 0.82, 0.82)
	board_r.uv1_offset = Vector3(0.0, 0.4, 0.57)
	var ins := StandardMaterial3D.new()
	ins.albedo_texture = Mats.tex("fx_insul")
	ins.uv1_triplanar = true
	ins.uv1_scale = Vector3(2.2, 1.4, 2.2)
	ins.roughness = 1.0
	# пол (черновая фанера), верх — фанера перекрытия с балками
	_box(self, Vector3(dw * 2.0 + 0.05, 0.03, L + 0.2), Vector3(0, -0.015, 0), ply, false)
	_box(self, Vector3(dw * 2.0 + 0.05, 0.03, L + 0.2), Vector3(0, h + 0.2, 0), ply, false)
	for jz in [-1.2, 0.0, 1.2]:
		_box(self, Vector3(dw * 2.0 + 0.05, 0.19, 0.045), Vector3(0, h + 0.09, jz), wood, false)
	# стены: изнанка гипсокартона, нижние и верхние обвязки, стойки через 40,6 см, распорки
	for side in [-1.0, 1.0]:
		_box(self, Vector3(0.012, h + 0.2, L + 0.2), Vector3(side * (dw + 0.006), h * 0.5 + 0.1, 0), board_l if side > 0.0 else board_r, false)
		_box(self, Vector3(sd, 0.038, L + 0.2), Vector3(side * (w * 0.5 + sd * 0.5), 0.019, 0), wood, false)
		_box(self, Vector3(sd, 0.076, L + 0.2), Vector3(side * (w * 0.5 + sd * 0.5), h - 0.038, 0), wood, false)
		var z := -L * 0.5 + 0.1
		var k := 0
		while z < L * 0.5:
			_box(self, Vector3(sd, h - 0.114, 0.038), Vector3(side * (w * 0.5 + sd * 0.5), (h - 0.114) * 0.5 + 0.038, z), wood, false)
			if k % 2 == (0 if side > 0.0 else 1) and z + 0.406 < L * 0.5:
				_box(self, Vector3(sd, 0.038, 0.368), Vector3(side * (w * 0.5 + sd * 0.5), 1.22 + k * 0.03, z + 0.203), wood, false)
			z += 0.406
			k += 1
	# стекловата: в пролётах левой стены (часть сползла), в торцах — пачки до потолка
	for b in [[-1.30, 0.0, 1.2], [-0.49, 0.25, 0.9], [0.32, 0.0, 1.22], [1.13, 0.55, 0.7]]:
		var bh: float = b[2]
		_box(self, Vector3(sd * 0.9, bh, 0.36), Vector3(w * 0.5 + sd * 0.5 + 0.004, b[1] + bh * 0.5 + 0.04, b[0] + 0.2), ins, false)
	for ez in [-1.0, 1.0]:
		_box(self, Vector3(dw * 2.0, h, 0.14), Vector3(0, h * 0.5, ez * (L * 0.5 + 0.07)), ins, false)
		_box(self, Vector3(dw * 2.0, 0.09, 0.038), Vector3(0, 1.3, ez * (L * 0.5 - 0.02)), wood, false)
	# кабель в оплётке: от розетки по пролётам сквозь стойки
	var cable := StandardMaterial3D.new()
	cable.albedo_color = Color(0.78, 0.72, 0.5)
	cable.roughness = 0.6
	_box(self, Vector3(0.012, 0.014, L), Vector3(w * 0.5 + 0.06, 0.52, 0.0), cable, false)
	_box(self, Vector3(0.012, 0.15, 0.014), Vector3(w * 0.5 + 0.06, 0.45, 0.6), cable, false)
	# розетка соседей: синяя пластиковая коробка, свет сочится по щелям вокруг неё
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color(0.08, 0.2, 0.55)
	blue.roughness = 0.4
	_box(self, Vector3(0.075, 0.1, 0.055), Vector3(dw - 0.04, 0.35, 0.6), blue, false)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.75, 0.45)
	_slit_mat = glow
	for g in [[Vector3(0.004, 0.006, 0.066), Vector3(dw - 0.001, 0.403, 0.6)], [Vector3(0.004, 0.006, 0.066), Vector3(dw - 0.001, 0.297, 0.6)],
			[Vector3(0.004, 0.11, 0.004), Vector3(dw - 0.001, 0.35, 0.565)]]:
		_box(self, g[0], g[1], glow, false)
	# щель под гипсокартоном у пола: в соседской комнате горит свет
	for gz in [0.2, 0.61, 1.02]:
		_box(self, Vector3(0.004, 0.006, 0.36), Vector3(dw - 0.001, 0.045, gz + 0.2), glow, false)
	var lt := OmniLight3D.new()
	lt.name = "Slit"
	lt.position = Vector3(w * 0.5 + 0.02, 0.35, 0.6)
	lt.light_color = Color(1.0, 0.75, 0.45)
	lt.light_energy = 0.6
	lt.omni_range = 2.8
	lt.omni_attenuation = 1.4
	lt.shadow_enabled = true
	lt.shadow_bias = 0.03
	add_child(lt)
	var low := OmniLight3D.new()
	low.position = Vector3(w * 0.5 - 0.05, 0.06, 0.95)
	low.light_color = Color(1.0, 0.72, 0.42)
	low.light_energy = 0.12
	low.omni_range = 1.1
	add_child(low)
	# за другой стеной — комната с телевизором: голубое мерцание из щели у пола
	var tvm := StandardMaterial3D.new()
	tvm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tvm.albedo_color = Color(0.6, 0.7, 1.0)
	_tv_mat = tvm
	for gz in [-0.6, -0.19]:
		_box(self, Vector3(0.004, 0.005, 0.36), Vector3(-dw + 0.001, 0.045, gz), tvm, false)
	var tvl := OmniLight3D.new()
	tvl.name = "Tv"
	tvl.position = Vector3(-w * 0.5 + 0.02, 0.05, -0.35)
	tvl.light_color = Color(0.6, 0.72, 1.0)
	tvl.light_energy = 0.3
	tvl.omni_range = 2.4
	tvl.omni_attenuation = 1.2
	add_child(tvl)
	# пыль в полосе света
	var dust := _particles(70, 8.0, Vector3(0.25, 0.3, 0.4), Color(1.0, 0.85, 0.6, 0.35), 0.006, Vector3(0, 0.01, 0))
	dust.position = Vector3(0.05, 0.5, 0.6)
	add_child(dust)
	# надпись прежнего узника: карандаш и кровь по изнанке листа, счёт дней
	var lb := Props.label("ПОМОГИТЕ   HELP", Props.font_hand(), 0.0013, Color(0.3, 0.07, 0.05))
	lb.shaded = true
	lb.position = Vector3(-dw + 0.004, 1.42, 0.62)
	lb.rotation = Vector3(0, PI * 0.5, 0.06)
	lb.visibility_range_end = 0.0
	add_child(lb)
	var lt2 := Props.label("||||  ||||  ||||  |||", Props.font_hand(), 0.0012, Color(0.16, 0.15, 0.14))
	lt2.shaded = true
	lt2.position = Vector3(-dw + 0.004, 1.12, 0.66)
	lt2.rotation = Vector3(0, PI * 0.5, -0.03)
	lt2.visibility_range_end = 0.0
	add_child(lt2)
	player = Player.new()
	add_child(player)
	player.global_position = Vector3(0, 0.05, -0.8)
	player.set_look(PI, -0.1)
	player.surface_fn = func(_p: Vector3) -> String: return "wood"
	player.shake = 1.0
	Snd.loop("neighbors", "upstairs_tv", 0.75, 2.0)
	Snd.play("thud_land", -2.0)
	_hurt_rate = 0.016


func _wall_tick(_dt: float) -> void:
	if Input.is_action_just_pressed("use"):
		Snd.play("knock", 0.0)
		Snd.loop_vol("neighbors", 0.15, 0.3)
		get_tree().create_timer(4.0).timeout.connect(func() -> void:
			if not _done:
				Snd.loop_vol("neighbors", 0.75, 2.0))
	if randf() < _dt * 0.08:
		Snd.play("footsteps_above", -12.0, randf_range(0.9, 1.1), "Amb")
	var lt := get_node_or_null("Slit") as OmniLight3D
	if t > 38.0 and Game.main != null:
		Game.main.osd.battery = 0.08
		Game.main.osd.message = Loc.t("osd.battery")
	if t > 50.0:
		_slit_base = maxf(0.0, _slit_base - _dt * 0.3)
	# у одних соседей лампа (чуть дрожит напряжение), у других — телевизор: голубые вспышки смены кадров
	var lamp := 0.96 + 0.04 * sin(t * 13.0) * sin(t * 5.3)
	if lt != null:
		lt.light_energy = _slit_base * lamp
	if _slit_mat != null:
		var k := clampf(_slit_base / 0.6, 0.0, 1.0) * lamp
		_slit_mat.albedo_color = Color(1.0 * k, 0.75 * k, 0.45 * k)
	var cut := floorf(t * 0.7) + floorf(t * 1.9)
	var tv := 0.55 + 0.3 * sin(cut * 12.9898) + 0.12 * sin(t * 9.0 + cut)
	var tvl := get_node_or_null("Tv") as OmniLight3D
	if tvl != null:
		tvl.light_energy = 0.32 * tv
	if _tv_mat != null:
		_tv_mat.albedo_color = Color(0.6, 0.7, 1.0) * clampf(tv, 0.1, 1.0)


# ======================================================================= КОСМОС

## Открытый космос на орбите: тишина, звёзды, Земля во весь низ кадра. Пока смотришь на неё — краснеет быстрее
func _space() -> void:
	var e := _env_base(Color(0, 0, 0))
	var sky := Sky.new()
	_space_sky = ShaderMaterial.new()
	_space_sky.shader = load("res://src/shaders/end_space_sky.gdshader")
	sky.sky_material = _space_sky
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.02, 0.025, 0.035)
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.glow_intensity = 0.7
	e.glow_hdr_threshold = 1.0
	# солнце с запада-юго-запада, ~25° над местным горизонтом: на востоке у края виден терминатор
	var l := Vector3(-0.852, 0.423, 0.308).normalized()
	var sun := DirectionalLight3D.new()
	sun.look_at_from_position(Vector3.ZERO, -l, Vector3.UP)
	sun.light_energy = 2.2
	sun.light_color = Color(1.0, 0.97, 0.92)
	add_child(sun)
	# Земля: под камерой — Средиземное море у Сицилии (36° с. ш., 15,5° в. д.), север — вперёд (-Z)
	var lat0 := deg_to_rad(36.0)
	var lon0 := deg_to_rad(15.5)
	var up_o := Vector3(cos(lat0) * sin(lon0), sin(lat0), cos(lat0) * cos(lon0))
	var north_o := Vector3(-sin(lat0) * sin(lon0), cos(lat0), -sin(lat0) * cos(lon0))
	var east_o := north_o.cross(up_o)
	var em := ShaderMaterial.new()
	em.shader = load("res://src/shaders/end_earth.gdshader")
	em.set_shader_parameter("earth_tex", Mats.tex("fx_earth"))
	em.set_shader_parameter("cloud_tex", Mats.tex("fx_earth_clouds"))
	em.set_shader_parameter("noise_tex", Mats.tex("noise"))
	em.set_shader_parameter("center", EARTH_C)
	em.set_shader_parameter("radius", EARTH_R)
	em.set_shader_parameter("sun", l)
	_earth_mat = em
	_earth = _globe(EARTH_R + 12.0, em)
	_earth.basis = Basis(east_o, up_o, -north_o).transposed()
	# кромка атмосферы над лимбом
	var am := ShaderMaterial.new()
	am.shader = load("res://src/shaders/end_atmo.gdshader")
	am.set_shader_parameter("center", EARTH_C)
	am.set_shader_parameter("radius", EARTH_R)
	am.set_shader_parameter("sun", l)
	_globe(EARTH_R + 95.0, am)
	_make_cam(Vector3.ZERO)
	cam.far = 20000.0
	_pitch = -0.32
	_yaw = 0.4
	_hurt_rate = 0.022
	Snd.stop_all(0.0)
	Snd.loop("heart", "heartbeat", 0.0, 0.3)
	Snd.loop("space", "space_tone", 0.8, 1.5)
	Snd.muffle(0.55, true)
	if Game.main != null:
		Game.main.gain = 1.2


func _globe(r: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 256
	sm.rings = 128
	mi.mesh = sm
	mi.material_override = mat
	mi.position = EARTH_C
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _space_tick(dt: float) -> void:
	cam.rotation = Vector3(_pitch, _yaw + t * 0.012, sin(t * 0.2) * 0.1 + t * 0.008)
	var fwd := -cam.global_transform.basis.z
	var to_e := (EARTH_C - cam.global_position).normalized()
	var look := clampf((fwd.dot(to_e) - 0.25) / 0.45, 0.0, 1.0)
	_hurt_rate = 0.02 + look * 0.07
	# орбита: Земля медленно проворачивается под камерой, облака дрейфуют чуть быстрее
	if _earth != null:
		_earth.rotate_object_local(Vector3.UP, dt * 0.002)
	if _earth_mat != null:
		_earth_mat.set_shader_parameter("cloud_shift", t * 0.00004)
	# автоэкспозиция: пока в кадре яркая Земля, звёзд не видно
	if _space_sky != null:
		var g := 1.0 - 0.85 * clampf((fwd.dot(to_e) + 0.15) / 0.45, 0.0, 1.0)
		if absf(g - _star_gain) > 0.05:
			_star_gain = g
			_space_sky.set_shader_parameter("star_gain", g)
	if Game.main != null:
		Game.main.desat = look * 0.25
	if randf() < dt * 0.25:
		Snd.play("breath_heavy", -12.0, randf_range(0.9, 1.0))


# ======================================================================= ASYNC

func _async() -> void:
	_env_base(Color(0, 0, 0))
	env.ambient_light_color = Color(0.25, 0.26, 0.27)
	var wall := StandardMaterial3D.new()
	wall.albedo_color = Color(0.72, 0.73, 0.72)
	wall.albedo_texture = Mats.tex("concrete")
	wall.uv1_triplanar = true
	wall.uv1_scale = Vector3(0.5, 0.5, 0.5)
	var floor_m := StandardMaterial3D.new()
	floor_m.albedo_texture = Mats.tex("concrete_floor")
	floor_m.uv1_triplanar = true
	floor_m.uv1_scale = Vector3(0.4, 0.4, 0.4)
	var hz := StandardMaterial3D.new()
	hz.albedo_texture = Mats.tex("hazard")
	hz.uv1_scale = Vector3(4, 1, 1)
	# шлюзовой коридор
	var L := 14.0
	_box(self, Vector3(3.2, 0.2, L), Vector3(0, -0.1, -L * 0.5), floor_m, true)
	_box(self, Vector3(3.2, 0.2, L), Vector3(0, 2.9, -L * 0.5), wall, true)
	_box(self, Vector3(0.2, 3.0, L), Vector3(-1.6, 1.4, -L * 0.5), wall, true)
	_box(self, Vector3(0.2, 3.0, L), Vector3(1.6, 1.4, -L * 0.5), wall, true)
	_box(self, Vector3(3.2, 3.0, 0.3), Vector3(0, 1.4, -L), Mats_std(Color(0.5, 0.52, 0.5)), true)
	_box(self, Vector3(3.0, 0.01, 1.0), Vector3(0, 0.01, -L + 1.2), hz, false)
	# позади — свечение Порога
	var glow := StandardMaterial3D.new()
	glow.emission_enabled = true
	glow.emission = Color(0.6, 1.0, 0.75)
	glow.emission_energy_multiplier = 4.0
	glow.albedo_color = Color(0.6, 1.0, 0.75)
	_box(self, Vector3(3.0, 2.8, 0.05), Vector3(0, 1.4, 0.3), glow, false)
	# потолочные светильники: холодные лампы дневного света за матовым рассеивателем
	var tube := StandardMaterial3D.new()
	tube.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tube.albedo_color = Color(1.0, 1.0, 1.0)
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.55, 0.56, 0.55)
	frame.metallic = 0.4
	frame.roughness = 0.5
	for k in 4:
		var lt := OmniLight3D.new()
		lt.position = Vector3(0, 2.6, -2.0 - k * 3.2)
		lt.omni_range = 6.0
		lt.light_energy = 1.2
		lt.light_color = Color(0.95, 0.97, 1.0)
		lt.light_volumetric_fog_energy = 0.6
		add_child(lt)
		_box(self, Vector3(0.34, 0.05, 1.36), Vector3(0, 2.775, -2.0 - k * 3.2), frame, false)
		_box(self, Vector3(0.26, 0.012, 1.26), Vector3(0, 2.745, -2.0 - k * 3.2), tube, false)
	# решётки вентиляции, откуда пойдёт газ
	for vz in [-3.6, -8.8]:
		_vent(self, Vector3(0.9, 2.79, vz), 0.5)
	# надпись трафаретом на торцевой стене (3 м): крупно «ASYNC», ниже мельче — целиком в ширину стены
	var lb := Props.label("ASYNC", Props.font_sign(), 0.0095, Color(0.78, 0.11, 0.07))
	lb.position = Vector3(0, 2.38, -L + 0.17)
	lb.visibility_range_end = 0.0
	add_child(lb)
	var lb2 := Props.label("DECONTAMINATION  B-2", Props.font_sign(), 0.0036, Color(0.78, 0.11, 0.07))
	lb2.position = Vector3(0, 1.96, -L + 0.17)
	lb2.visibility_range_end = 0.0
	add_child(lb2)
	player = Player.new()
	add_child(player)
	player.global_position = Vector3(0, 0.05, -0.6)
	player.set_look(0.0, 0.0)
	player.surface_fn = func(_p: Vector3) -> String: return "concrete"
	Snd.loop("hum", "hum_fluor", 0.4, 1.0)
	Snd.play("threshold_pass", 0.0)
	_phase = 0
	# отладка: --async_at=iso (сразу изолятор) | gas (изолятор без допроса — сразу газ)
	match Cfg.arg("async_at", ""):
		"iso":
			_interrogation()
		"gas":
			_interrogation()
			_lines_left.clear()
			t = 12.5


func _async_tick(dt: float) -> void:
	match _phase:
		0:
			if t > 3.0 or (player != null and player.global_position.z < -4.0):
				_phase = 1
				t = 0.0
				Snd.play("gas_hiss", 2.0)
				Snd.play("alarm_short", -6.0)
				_gas()
		1:
			if Game.main != null:
				Game.main.desat = clampf(t / 6.0, 0.0, 0.8)
				Game.main.interference = clampf(t / 8.0, 0.0, 0.4)
			Snd.muffle(clampf(t / 7.0, 0.0, 0.8))
			if player != null:
				player.speed_mul = clampf(1.0 - t / 5.0, 0.15, 1.0)
			if t > 5.5:
				_phase = 2
				t = 0.0
				player.frozen = true
				player.cine = true
				Snd.play("body_fall", 0.0)
				var tw := create_tween().set_parallel(true)
				tw.tween_property(player.head, "position", Vector3(0.2, 0.18, 0), 0.6)
				tw.tween_property(player.cam, "rotation", Vector3(0.1, 0.3, 1.4), 0.6)
				_hazmat()
		2:
			if t > 6.5:
				_phase = 3
				t = 0.0
				Game.main.fade_to(Color(0, 0, 0, 1), 1.5)
		3:
			if t > 2.5:
				_phase = 4
				t = 0.0
				_interrogation()
		5:
			_cctv_control(dt)
			if _lines_left.is_empty() and t > 12.0:
				_phase = 6
				t = 0.0
				Snd.play("door_lock", 2.0)
				if Game.main != null:
					Game.main.burst(0.4)
		6:
			_cctv_control(dt)
			# в изолятор пускают газ: человек на камере шатается и падает
			if t > 2.5 and not _gas_on:
				_gas_on = true
				_gas_iso()
			if t > 6.5 and _subject != null and not _subject.has_meta("fell"):
				_subject.set_meta("fell", true)
				_subject.pose("slump")
				var tw := create_tween().set_parallel(true)
				tw.tween_property(_subject, "rotation:x", -1.45, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				tw.tween_property(_subject, "position:y", 0.12, 0.7)
				Snd.play("body_fall", 0.0)
			if t > 10.0:
				_phase = 7
				t = 0.0
				_gas_pov()
		7:
			# лёжа на полу, сквозь газ — лампа и решётка вентиляции; кадр краснеет
			cam.rotation = Vector3(1.35 + sin(t * 0.7) * 0.05, 0.2 + sin(t * 0.4) * 0.05, 0.4)


func _gas() -> void:
	# объёмный газ опускается от потолка; из решёток бьют мягкие клубы
	var gm := _gas_volume(Vector3(3.2, 3.0, 14.0), Vector3(0, 1.4, -7.0), 2.8,
		Vector4(0.9, 2.8, -3.6, 1.2), Vector4(0.9, 2.8, -8.8, 1.2))
	var tw0 := create_tween()
	tw0.tween_property(gm, "shader_parameter/fill", 1.0, 5.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for vz in [-3.6, -8.8]:
		add_child(_gas_puffs(Vector3(0.9, 2.72, vz), 70, 4.5, AABB(Vector3(-1.5, 0.0, -14.0), Vector3(3.0, 2.8, 14.0))))
	env.fog_enabled = true
	env.fog_light_color = Color(0.8, 0.82, 0.8)
	var tw := create_tween()
	tw.tween_property(env, "fog_density", 0.045, 6.0)


## Газ: объёмный туман в FogVolume (шейдер end_gas) — освещается лампами, гуще у решёток
func _gas_volume(size: Vector3, center: Vector3, ceiling: float, va: Vector4, vb: Vector4) -> ShaderMaterial:
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0
	env.volumetric_fog_albedo = Color(0.92, 0.92, 0.92)
	env.volumetric_fog_length = 22.0
	env.volumetric_fog_detail_spread = 1.4
	env.volumetric_fog_ambient_inject = 0.6
	env.volumetric_fog_sky_affect = 0.0
	var fv := FogVolume.new()
	fv.size = size
	fv.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	fv.position = center
	var m := ShaderMaterial.new()
	m.shader = load("res://src/shaders/end_gas.gdshader")
	m.set_shader_parameter("ceiling", ceiling)
	m.set_shader_parameter("vent_a", va)
	m.set_shader_parameter("vent_b", vb)
	m.set_shader_parameter("fill", 0.0)
	m.set_shader_parameter("density", 0.75)
	fv.material = m
	add_child(fv)
	return m


## Клубы газа из решётки: мягкие серые спрайты (tex/fx_smoke), случайный поворот и кадр, растут и тают;
## у стен, пола и потолка комнаты room не режутся (шейдер end_gas_puff), у самого объектива — растворяются
func _gas_puffs(pos: Vector3, amount: int, life: float, room: AABB) -> GPUParticles3D:
	var gp := GPUParticles3D.new()
	gp.amount = amount
	gp.lifetime = life
	gp.position = pos
	gp.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.22, 0.02, 0.22)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 38.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.3
	pm.gravity = Vector3(0, -0.12, 0)
	pm.damping_min = 0.35
	pm.damping_max = 0.7
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -14.0
	pm.angular_velocity_max = 14.0
	pm.anim_offset_min = 0.0
	pm.anim_offset_max = 1.0
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.25))
	sc.add_point(Vector2(0.5, 0.85))
	sc.add_point(Vector2(1.0, 1.4))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.15, 0.6, 1.0])
	gr.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.62), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0.0)])
	var grt := GradientTexture1D.new()
	grt.gradient = gr
	pm.color_ramp = grt
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.8
	pm.turbulence_noise_scale = 2.5
	pm.turbulence_influence_min = 0.03
	pm.turbulence_influence_max = 0.08
	gp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.3, 1.3)
	var qm := ShaderMaterial.new()
	qm.shader = load("res://src/shaders/end_gas_puff.gdshader")
	qm.set_shader_parameter("smoke_tex", Mats.tex("fx_smoke"))
	qm.set_shader_parameter("room_min", room.position)
	qm.set_shader_parameter("room_max", room.end)
	q.material = qm
	gp.draw_pass_1 = q
	gp.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 6, 8))
	return gp


## Решётка вентиляции в потолке: рамка, тёмный короб за ней, наклонные ламели
func _vent(parent: Node3D, pos: Vector3, size: float) -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.62, 0.63, 0.62)
	metal.metallic = 0.5
	metal.roughness = 0.45
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.03, 0.03, 0.03)
	_box(parent, Vector3(size, 0.01, size), pos + Vector3(0, 0.012, 0), dark, false)
	for k in 4:
		var e := [Vector3(size, 0.02, 0.03), Vector3(size, 0.02, 0.03), Vector3(0.03, 0.02, size), Vector3(0.03, 0.02, size)][k] as Vector3
		var o := [Vector3(0, 0, -size * 0.5), Vector3(0, 0, size * 0.5), Vector3(-size * 0.5, 0, 0), Vector3(size * 0.5, 0, 0)][k] as Vector3
		_box(parent, e, pos + o, metal, false)
	var n := int(size / 0.06)
	for i in n:
		var sl := _box(parent, Vector3(size - 0.04, 0.004, 0.035), pos + Vector3(0, -0.005, -size * 0.5 + 0.04 + i * 0.06), metal, false)
		sl.rotation.x = 0.6


func _hazmat() -> void:
	for k in 2:
		var h := Human.make("explorer", 300 + k, false)
		add_child(h)
		h.position = Vector3(-0.6 + k * 1.2, 0, -12.0)
		h.rotation.y = 0.0
		h.pose_name = "walk"
		h.anim_speed = 0.8
		var fl := SpotLight3D.new()
		fl.light_energy = 3.0
		fl.spot_range = 14.0
		fl.spot_angle = 18.0
		fl.position = Vector3(0, 1.4, 0.3)
		fl.rotation = Vector3(-0.25, PI, 0)
		# луч в газе — мягкая полоса, а не сплошное белое «яйцо» во весь кадр (камера считает почти белое
		# лампой и раздувает его): светит сам фонарь — маленькое яркое стекло
		fl.light_volumetric_fog_energy = 0.55
		fl.light_color = Color(1.0, 0.95, 0.85)
		h.add_child(fl)
		var lens := MeshInstance3D.new()
		var lq := SphereMesh.new()
		lq.radius = 0.045
		lq.height = 0.03
		lq.radial_segments = 12
		lq.rings = 4
		lens.mesh = lq
		var lm := StandardMaterial3D.new()
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.albedo_color = Color(1.0, 0.97, 0.9)
		lens.material_override = lm
		lens.position = Vector3(0, 1.4, 0.32)
		lens.rotation.x = PI * 0.5
		lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		h.add_child(lens)
		var tw := create_tween()
		tw.tween_property(h, "position:z", -2.2 - k * 0.4, 5.0)
		tw.tween_callback(func() -> void: h.pose("stand"))
	Snd.play("muffled_voices", -4.0)
	Snd.play("hazmat_steps", -6.0)


## Изолятор B. Вид с камеры наблюдения под потолком (ч/б). Герой — фигура внизу, им можно ходить.
func _interrogation() -> void:
	for ch in get_children():
		ch.queue_free()
	player = null
	Snd.stop_all(0.2)
	Snd.muffle(0.0)
	_env_base(Color(0, 0, 0))
	env.ambient_light_color = Color(0.35, 0.36, 0.36)
	var wall := StandardMaterial3D.new()
	wall.albedo_color = Color(0.78, 0.8, 0.78)
	wall.albedo_texture = Mats.tex("tile")
	wall.uv1_triplanar = true
	wall.uv1_scale = Vector3(0.6, 0.6, 0.6)
	var fl := StandardMaterial3D.new()
	fl.albedo_texture = Mats.tex("concrete_floor")
	fl.uv1_triplanar = true
	fl.uv1_scale = Vector3(0.5, 0.5, 0.5)
	var w := 3.6
	var d := 4.2
	var h := 2.6
	_box(self, Vector3(w, 0.2, d), Vector3(0, -0.1, 0), fl, true)
	_box(self, Vector3(w, 0.2, d), Vector3(0, h + 0.1, 0), wall, true)
	_box(self, Vector3(0.2, h, d), Vector3(-w * 0.5 - 0.1, h * 0.5, 0), wall, true)
	_box(self, Vector3(0.2, h, d), Vector3(w * 0.5 + 0.1, h * 0.5, 0), wall, true)
	_box(self, Vector3(w, h, 0.2), Vector3(0, h * 0.5, -d * 0.5 - 0.1), wall, true)
	_box(self, Vector3(w, h, 0.2), Vector3(0, h * 0.5, d * 0.5 + 0.1), wall, true)
	# дверь
	var door_m := StandardMaterial3D.new()
	door_m.albedo_color = Color(0.45, 0.47, 0.48)
	door_m.metallic = 0.5
	_box(self, Vector3(1.0, 2.1, 0.06), Vector3(1.0, 1.05, d * 0.5 - 0.02), door_m, false)
	var door_body := Props.interactable(self, Vector3(1.0, 2.1, 0.3), Vector3(1.0, 1.05, d * 0.5 - 0.15), "ui.use", func() -> void:
		Snd.play("door_rattle", 0.0))
	door_body.collision_layer = 3
	# стол, стулья, динамик, тёмное стекло
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.6, 0.6, 0.58)
	if Props.model(self, "metal_office_desk", Vector3(0, 0, -0.75), PI, Vector3(0.6, 1.0, 0.8)) == null:
		_box(self, Vector3(1.2, 0.05, 0.8), Vector3(0, 0.75, -0.6), tm, true)
	Props.model(self, "metal_stool_01", Vector3(0.0, 0, -1.6), 0.0, 1.0)
	# одностороннее зеркало: тёмное полупрозрачное серебрение — отражает комнату, а не чёрная дыра в кадре
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.36, 0.37, 0.39)
	glass.metallic = 1.0
	glass.roughness = 0.07
	glass.roughness_texture = Mats.tex("noise")
	glass.uv1_scale = Vector3(0.4, 0.4, 0.4)
	_box(self, Vector3(2.2, 1.0, 0.03), Vector3(-0.2, 1.5, -d * 0.5 + 0.01), glass, false)
	var frame_m := StandardMaterial3D.new()
	frame_m.albedo_color = Color(0.55, 0.56, 0.57)
	frame_m.metallic = 0.7
	frame_m.roughness = 0.35
	for k in 4:
		var fs := [Vector3(2.3, 0.05, 0.05), Vector3(2.3, 0.05, 0.05), Vector3(0.05, 1.1, 0.05), Vector3(0.05, 1.1, 0.05)][k] as Vector3
		var fo := [Vector3(0, 0.525, 0), Vector3(0, -0.525, 0), Vector3(-1.125, 0, 0), Vector3(1.125, 0, 0)][k] as Vector3
		_box(self, fs, Vector3(-0.2, 1.5, -d * 0.5 + 0.02) + fo, frame_m, false)
	# отражения в экранном пространстве: в стекле видны пол, стол и человек
	env.ssr_enabled = true
	env.ssr_max_steps = 96
	env.ssr_fade_in = 0.05
	env.ssr_fade_out = 1.5
	env.ssr_depth_tolerance = 0.3
	var spk := StandardMaterial3D.new()
	spk.albedo_color = Color(0.2, 0.2, 0.2)
	_box(self, Vector3(0.3, 0.3, 0.06), Vector3(-1.4, 2.2, -d * 0.5 + 0.03), spk, false)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, h - 0.2, 0)
	lamp.omni_range = 7.0
	lamp.light_energy = 1.3
	lamp.shadow_enabled = true
	lamp.light_volumetric_fog_energy = 1.5
	add_child(lamp)
	# светильник в решётчатом колпаке и решётка вентиляции (с пола их видно сквозь газ)
	var fix := StandardMaterial3D.new()
	fix.albedo_color = Color(0.5, 0.51, 0.5)
	fix.metallic = 0.5
	fix.roughness = 0.5
	_box(self, Vector3(0.28, 0.06, 0.28), Vector3(0, h - 0.03, 0), fix, false)
	var bulb := MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 0.09
	bs.height = 0.16
	bulb.mesh = bs
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(1.0, 0.97, 0.9)
	bulb.material_override = bm
	bulb.position = Vector3(0, h - 0.15, 0)
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bulb)
	for k in 4:
		var bar := _box(self, Vector3(0.012, 0.16, 0.012), Vector3(cos(k * PI * 0.5) * 0.11, h - 0.14, sin(k * PI * 0.5) * 0.11), fix, false)
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box(self, Vector3(0.24, 0.012, 0.24), Vector3(0, h - 0.225, 0), fix, false).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vent(self, Vector3(1.0, h - 0.006, -1.2), 0.45)
	# герой
	_subject = Human.make("player", 77, false)
	add_child(_subject)
	_subject.position = Vector3(0, 0, 0.2)
	_subject.rotation.y = PI
	_subject.pose("slump")
	_subject.position.y = -0.0
	if Props.model(self, "metal_stool_01", Vector3(0, 0, 0.25), 0.0, Vector3(1.2, 0.52, 1.2), false) == null:
		var stool := StandardMaterial3D.new()
		stool.albedo_color = Color(0.3, 0.3, 0.3)
		_box(self, Vector3(0.45, 0.45, 0.45), Vector3(0, 0.22, 0.25), stool, false)
	var cb := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cs.shape = cap
	cs.position.y = 0.9
	cb.add_child(cs)
	cb.name = "SubjectBody"
	add_child(cb)
	cb.position = _subject.position
	# камера наблюдения в углу
	_make_cam(Vector3(w * 0.5 - 0.25, h - 0.15, d * 0.5 - 0.25))
	cam.look_at(Vector3(-0.2, 0.6, -0.4))
	cam.fov = 78.0
	_free_look = false
	_cctv = true
	if Game.main != null:
		Game.main.bw = 1.0
		Game.main.desat = 0.0
		Game.main.interference = 0.05
		Game.main.osd.cam_label = Loc.t("osd.cam_iso")
		Game.main.osd.date_reset = false
		Game.main.osd.date_key = "osd.date_async"
		Game.main.osd.clock = 3.0 * 3600.0 + 12.0 * 60.0
		Game.main.fade_to(Color(0, 0, 0, 0), 2.0)
	Snd.loop("iso_hum", "hum_fluor", 0.35, 2.0)
	_phase = 5
	t = 0.0
	_lines_left = ["int.i01", "int.i02", "int.i03", "int.i04", "int.i05", "int.i06", "int.i07", "int.i08", "int.i09"]
	_speak_next.call_deferred()


func _speak_next() -> void:
	await get_tree().create_timer(3.0).timeout
	while not _lines_left.is_empty() and is_inside_tree():
		var key: String = _lines_left[0]
		Game.say(key, Loc.t("ui.who_speaker"))
		var path := Loc.voice_path(key)
		var wait := 3.5 + Loc.t(key).length() * 0.055
		if ResourceLoader.exists(path):
			var p := AudioStreamPlayer.new()
			p.stream = load(path)
			p.bus = "Voice"
			p.volume_db = -2.0
			add_child(p)
			p.play()
			wait = maxf((p.stream as AudioStream).get_length() + 1.6, 2.5)
		await get_tree().create_timer(wait).timeout
		if key == "int.i03" or key == "int.i07":
			await get_tree().create_timer(2.5).timeout
		_lines_left.pop_front()
		if key == "int.i01" and _subject != null:
			_subject.pose("sit")


func _cctv_control(dt: float) -> void:
	if _subject == null:
		return
	var body := get_node_or_null("SubjectBody") as CharacterBody3D
	if body == null:
		return
	var inp := Input.get_vector("move_l", "move_r", "move_f", "move_b")
	if inp.length() > 0.1 and t > 6.0:
		# движение относительно камеры
		var f := -cam.global_transform.basis.z
		f.y = 0
		f = f.normalized()
		var r := f.cross(Vector3.UP)
		var dir := (r * inp.x - f * inp.y).normalized()
		body.velocity = dir * 1.1
		body.move_and_slide()
		_subject.position = body.position
		_subject.rotation.y = lerp_angle(_subject.rotation.y, atan2(dir.x, dir.z), dt * 6.0)
		if _subject.pose_name != "walk":
			_subject.pose_name = "walk"
			_subject.anim_speed = 0.6
	elif _subject.pose_name == "walk":
		_subject.pose("stand")
	if Input.is_action_just_pressed("use"):
		var door := Vector3(1.0, 0, 2.1)
		if _subject.position.distance_to(door) < 1.3:
			Snd.play("door_rattle", 0.0)


## Газ из вентиляции изолятора (видно с камеры наблюдения)
func _gas_iso() -> void:
	Snd.play("gas_hiss", 2.0)
	Snd.play("alarm_short", -8.0)
	var gm := _gas_volume(Vector3(3.6, 2.6, 4.2), Vector3(0, 1.3, 0), 2.6, Vector4(1.0, 2.6, -1.2, 1.0), Vector4(1.0, 2.6, -1.2, 0.6))
	var tw0 := create_tween()
	tw0.tween_property(gm, "shader_parameter/fill", 1.0, 8.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	add_child(_gas_puffs(Vector3(1.0, 2.53, -1.2), 80, 5.0, AABB(Vector3(-1.8, 0.0, -2.1), Vector3(3.6, 2.6, 4.2))))
	env.fog_enabled = true
	env.fog_light_color = Color(0.85, 0.87, 0.85)
	env.fog_density = 0.0
	var tw := create_tween()
	tw.tween_property(env, "fog_density", 0.05, 9.0)
	if Game.main != null:
		var tw2 := create_tween()
		tw2.tween_method(func(v: float) -> void: Game.main.interference = v, 0.05, 0.3, 7.0)


## От первого лица: герой на полу изолятора, вверху газ и лампа; снова цветная запись камеры
func _gas_pov() -> void:
	if _subject != null:
		_subject.visible = false
	_subject = null
	_cctv = false
	_make_cam(Vector3(0.1, 0.22, 0.6))
	cam.fov = Cfg.fov
	if Game.main != null:
		Game.main.bw = 0.0
		Game.main.desat = 0.45
		Game.main.osd.cam_label = ""
		Game.main.burst(0.6)
	Snd.muffle(0.7, true)
	Snd.play("gasp", -6.0)
	_hurt = 0.35
	_hurt_rate = 0.085


func Mats_std(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, solid: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	if solid:
		var b := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		b.add_child(cs)
		b.position = pos
		parent.add_child(b)
	return mi


# ------------------------------------------------------------ кадр

func _process(dt: float) -> void:
	t += dt
	if _done:
		return
	_apply_look(dt)
	match kind:
		"ocean": _ocean_tick(dt)
		"sky": _sky_tick(dt)
		"highway": _highway_tick(dt)
		"wall": _wall_tick(dt)
		"space": _space_tick(dt)
		"async": _async_tick(dt)
	_hurt_tick(dt)
