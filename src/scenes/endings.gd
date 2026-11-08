extends Node3D
## Концовки. Случайные выходы через нулевую зону: океан, небо, подвал, шоссе, парк спустя годы.
## Выход Async: газ, люди в костюмах, изолятор под камерой наблюдения, допрос через динамик, навсегда.

const Props := preload("res://src/world/props.gd")
const ParkS := preload("res://src/scenes/park.gd")
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
var _hatch_tries := 0
var _hatch_busy := false
var _given_up := -1.0


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
	match kind:
		"ocean": _ocean()
		"sky": _sky()
		"basement": _basement()
		"highway": _highway()
		"wall": _wall()
		"async": _async()
		_: _ocean()


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


## Конец записи: «стоп», синий экран, карточка концовки
func finish(card := "") -> void:
	if _done:
		return
	_done = true
	Snd.play("tape_stop", -2.0)
	if Game.main != null:
		var tw := create_tween()
		tw.tween_method(func(v: float) -> void: Game.main.stopfx = v, 0.0, 1.0, 0.7)
		await tw.finished
	await get_tree().create_timer(0.8).timeout
	Snd.stop_all(0.3)
	Snd.muffle(0.0)
	if Game.main != null:
		Game.main.stopfx = 0.0
		Game.main.bw = 0.0
		Game.main.desat = 0.0
		Game.main.osd.shown = false
		Game.main.osd.message = ""
		Game.main.osd.cam_label = ""
		Game.main.set_fade(Color(0, 0, 0, 1))
	Game.show_card(card if card != "" else kind)


# ======================================================================= ОКЕАН

func _ocean() -> void:
	var e := _env_base(Color(0.5, 0.56, 0.6))
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.22, 0.25, 0.29)
	sm.sky_horizon_color = Color(0.45, 0.48, 0.5)
	sm.ground_horizon_color = Color(0.3, 0.36, 0.38)
	sm.ground_bottom_color = Color(0.08, 0.12, 0.14)
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.fog_enabled = true
	e.fog_light_color = Color(0.38, 0.41, 0.43)
	e.fog_density = 0.0035
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.35, 0.8, 0)
	sun.light_energy = 0.5
	add_child(sun)
	var water := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 600)
	pm.subdivide_width = 160
	pm.subdivide_depth = 160
	water.mesh = pm
	var wm := ShaderMaterial.new()
	wm.shader = WATER
	wm.set_shader_parameter("noise_tex", Mats.tex("water_n"))
	water.material_override = wm
	add_child(water)
	# снизу — тёмная толща
	var under := MeshInstance3D.new()
	var um := PlaneMesh.new()
	um.size = Vector2(600, 600)
	under.mesh = um
	under.position.y = -60.0
	var umat := StandardMaterial3D.new()
	umat.albedo_color = Color(0.0, 0.03, 0.04)
	umat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	under.material_override = umat
	add_child(under)
	_make_cam(Vector3(0, 6.0, 0))
	_vel = Vector3(0, -1.0, 0)
	_phase = 0
	Snd.loop("sea", "sea_waves", 0.9, 0.3)
	Snd.loop("wind", "wind_open", 0.5, 0.3)


func _ocean_tick(dt: float) -> void:
	var wave := _wave_h(cam.position)
	match _phase:
		0:
			_vel.y -= 9.8 * dt
			cam.position += _vel * dt
			cam.rotation = Vector3(-0.5 - t * 0.3, 0.3, 0.2 * sin(t * 3.0))
			if cam.position.y < wave:
				_phase = 1
				Snd.play("splash", 2.0)
				if Game.main != null:
					Game.main.burst(1.0)
				_vel = Vector3(0, -3.0, 0)
		1:
			# под водой, всплываем
			_vel.y = move_toward(_vel.y, 1.2, dt * 2.0)
			cam.position += _vel * dt
			_free_look = true
			cam.rotation = Vector3(_pitch, _yaw, 0)
			if cam.position.y > wave + 0.1 and t > 4.0:
				_phase = 2
				Snd.play("gasp", -2.0)
		2:
			cam.position.y = lerpf(cam.position.y, wave + 0.25 + sin(t * 1.3) * 0.15, dt * 3.0)
			cam.rotation = Vector3(_pitch + sin(t * 0.9) * 0.08, _yaw, sin(t * 0.7) * 0.12)
			if randf() < dt * 0.25:
				Snd.play("splash_small", -8.0)
			if t > 34.0:
				_phase = 3
				Game.main.osd.battery = 0.1
		3:
			cam.position.y -= dt * 0.8
			cam.rotation = Vector3(_pitch + 0.2, _yaw, sin(t) * 0.2)
			if t > 42.0:
				finish()
	var underwater := cam.position.y < _wave_h(cam.position) - 0.05
	Snd.muffle(0.85 if underwater else 0.0, true)
	env.fog_density = 0.25 if underwater else 0.0035
	env.fog_light_color = Color(0.05, 0.16, 0.17) if underwater else Color(0.38, 0.41, 0.43)
	if Game.main != null:
		Game.main.desat = 0.3 if underwater else 0.0


func _wave_h(p: Vector3) -> float:
	var tt := t
	return sin(p.x * 0.08 + tt * 0.9) * 0.6 + sin(p.z * 0.11 + tt * 1.3) * 0.45 + sin((p.x + p.z) * 0.21 + tt * 1.9) * 0.2


# ======================================================================= НЕБО

func _sky() -> void:
	var e := _env_base(Color(0.6, 0.7, 0.85))
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.25, 0.42, 0.75)
	sm.sky_horizon_color = Color(0.75, 0.8, 0.85)
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.fog_enabled = true
	e.fog_light_color = Color(0.72, 0.78, 0.86)
	e.fog_density = 0.0009
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0)
	add_child(sun)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4000, 4000)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = Mats.tex("suburb")
	gm.uv1_scale = Vector3(6, 6, 1)
	gm.roughness = 1.0
	g.material_override = gm
	add_child(g)
	# облака-клочья
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.95, 0.96, 1.0, 0.22)
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.albedo_texture = Mats.tex("noise")
	var rng := RandomNumberGenerator.new()
	rng.seed = 23091996
	for k in 14:
		var c := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		c.mesh = s
		c.material_override = cm
		c.scale = Vector3(rng.randf_range(40, 110), rng.randf_range(6, 14), rng.randf_range(40, 110))
		c.position = Vector3(rng.randf_range(-500, 500), rng.randf_range(250, 900), rng.randf_range(-500, 500))
		add_child(c)
	_make_cam(Vector3(0, 1300, 0))
	_vel = Vector3(0, -8.0, 0)
	Snd.loop("wind", "wind_fall", 1.0, 0.2)


func _sky_tick(dt: float) -> void:
	_vel.y = maxf(_vel.y - 9.8 * dt, -55.0)
	cam.position += _vel * dt
	cam.rotation = Vector3(-1.35 + sin(t * 1.7) * 0.35, t * 0.9, sin(t * 2.3) * 0.5)
	if Game.main != null:
		Game.main.osd.shown = true
	if cam.position.y < 140.0:
		if Game.main != null:
			Game.main.interference = 1.0
		Snd.play("impact_far", 0.0)
		cam.position.y = 140.0
		_vel = Vector3.ZERO
		finish()


# ======================================================================= ПОДВАЛ

func _basement() -> void:
	_env_base(Color(0, 0, 0))
	env.ambient_light_color = Color(0.05, 0.045, 0.04)
	var conc := StandardMaterial3D.new()
	conc.albedo_texture = Mats.tex("concrete_dirty")
	conc.uv1_scale = Vector3(2, 2, 1)
	conc.uv1_triplanar = true
	conc.roughness = 1.0
	var room := Node3D.new()
	add_child(room)
	var w := 4.0
	var d := 5.0
	var h := 2.35
	_box(room, Vector3(w + 0.4, 0.2, d + 0.4), Vector3(0, -0.1, 0), conc, true)
	_box(room, Vector3(w + 0.4, 0.2, d + 0.4), Vector3(0, h + 0.1, 0), conc, true)
	_box(room, Vector3(0.2, h, d), Vector3(-w * 0.5 - 0.1, h * 0.5, 0), conc, true)
	_box(room, Vector3(0.2, h, d), Vector3(w * 0.5 + 0.1, h * 0.5, 0), conc, true)
	_box(room, Vector3(w, h, 0.2), Vector3(0, h * 0.5, -d * 0.5 - 0.1), conc, true)
	_box(room, Vector3(w, h, 0.2), Vector3(0, h * 0.5, d * 0.5 + 0.1), conc, true)
	# заложенный кирпичом проём
	var brick := StandardMaterial3D.new()
	brick.albedo_color = Color(0.45, 0.28, 0.22)
	brick.albedo_texture = Mats.tex("tile")
	brick.uv1_scale = Vector3(3, 2, 1)
	_box(room, Vector3(1.0, 2.0, 0.05), Vector3(1.0, 1.0, -d * 0.5 + 0.02), brick, false)
	# лестница к люку в потолке
	var wood := StandardMaterial3D.new()
	wood.albedo_texture = Mats.tex("wood")
	for k in 9:
		_box(room, Vector3(0.9, 0.06, 0.28), Vector3(-1.4, 0.25 + k * 0.24, 1.6 - k * 0.24), wood, false)
	_box(room, Vector3(0.05, 0.1, 2.9), Vector3(-1.87, 1.25, 0.65), wood, false).rotation.x = deg_to_rad(45.0)
	var ramp := StaticBody3D.new()
	var rcs := CollisionShape3D.new()
	var rsh := BoxShape3D.new()
	rsh.size = Vector3(0.9, 0.1, 3.2)
	rcs.shape = rsh
	ramp.add_child(rcs)
	ramp.position = Vector3(-1.4, 1.12, 0.62)
	ramp.rotation.x = deg_to_rad(45.0)
	room.add_child(ramp)
	# люк: тяжёлые доски, петли, кольцо-ручка
	var hatch := Node3D.new()
	hatch.name = "Hatch"
	room.add_child(hatch)
	hatch.position = Vector3(-1.4, h - 0.04, -0.55)
	var hw := StandardMaterial3D.new()
	hw.albedo_texture = Mats.tex("wood")
	hw.albedo_color = Color(0.7, 0.6, 0.5)
	for k in 4:
		_box(hatch, Vector3(0.21, 0.05, 0.9), Vector3(-0.32 + k * 0.215, 0, 0), hw, false)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.15, 0.14, 0.13)
	iron.metallic = 0.6
	_box(hatch, Vector3(0.9, 0.03, 0.08), Vector3(0, -0.03, 0.3), iron, false)
	_box(hatch, Vector3(0.9, 0.03, 0.08), Vector3(0, -0.03, -0.3), iron, false)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.04
	tm.outer_radius = 0.06
	ring.mesh = tm
	ring.material_override = iron
	ring.position = Vector3(0, -0.07, 0)
	ring.rotation.x = PI * 0.5
	hatch.add_child(ring)
	Props.interactable(hatch, Vector3(1.0, 0.4, 1.0), Vector3(0, -0.15, 0), "ui.hatch", _try_hatch)
	# полки, коробки, ящики, шина
	var rr := RandomNumberGenerator.new()
	rr.seed = 51
	if Props.model(room, "steel_frame_shelves_01", Vector3(1.6, 0, 1.0), -PI * 0.5, 0.1) != null:
		for k in 3:
			Props.model(room, "cardboard_box_01", Vector3(1.6, 0.05 + k * 0.52, 0.8 + k * 0.2), rr.randf_range(-0.4, 0.4), 0.8, false)
	else:
		for k in 3:
			_box(room, Vector3(0.4, 0.04, 1.6), Vector3(1.75, 0.5 + k * 0.5, 1.2), wood, false)
	Props.model(room, "plastic_crate_01", Vector3(-1.5, 0, -1.8), 0.4)
	Props.model(room, "plastic_crate_01", Vector3(-1.45, 0.27, -1.75), 0.9, 1.0, false)
	Props.model(room, "cardboard_box_01", Vector3(0.9, 0, -2.0), 0.2)
	Props.model(room, "old_tyre", Vector3(-1.75, 0.3, 0.4), PI * 0.5, 1.0, false)
	# зарубки на стене
	var lb := Props.label("||||  ||||  ||||  ||||  |||", Props.font_hand(), 0.004, Color(0.1, 0.09, 0.08))
	lb.position = Vector3(-w * 0.5 + 0.005, 1.3, -0.6)
	lb.rotation.y = PI * 0.5
	lb.visibility_range_end = 0.0
	room.add_child(lb)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.2, h - 0.35, 0.3)
	lamp.light_color = Color(1.0, 0.82, 0.55)
	lamp.light_energy = 1.4
	lamp.omni_range = 6.0
	lamp.shadow_enabled = true
	lamp.name = "Bulb"
	add_child(lamp)
	var bulb := MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 0.05
	bs.height = 0.1
	bulb.mesh = bs
	var bm := StandardMaterial3D.new()
	bm.emission_enabled = true
	bm.emission = Color(1.0, 0.85, 0.6)
	bm.emission_energy_multiplier = 6.0
	bulb.material_override = bm
	bulb.position = lamp.position
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bulb.name = "BulbMesh"
	add_child(bulb)
	var cord := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.006
	cm.bottom_radius = 0.006
	cm.height = 0.3
	cord.mesh = cm
	cord.position = lamp.position + Vector3(0, 0.2, 0)
	cord.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cord)
	lamp.position.y -= 0.12
	player = Player.new()
	add_child(player)
	player.global_position = Vector3(0, 0.05, -0.5)
	player.set_look(PI, 0.0)
	player.surface_fn = func(_p: Vector3) -> String: return "concrete"
	Snd.loop("upstairs", "upstairs_tv", 0.55, 2.0)
	Snd.play("thud_land", -2.0)
	player.shake = 1.0


## Попытка открыть люк: упирается, толкает, бьёт — заколочен снаружи
func _try_hatch() -> void:
	if _hatch_busy or _given_up >= 0.0 or player == null:
		return
	_hatch_busy = true
	_hatch_tries += 1
	player.frozen = true
	var n := _hatch_tries
	var pushes := 2 + mini(n, 3)
	for i in pushes:
		Snd.play("hatch_strain", randf_range(-3.0, 1.0), randf_range(0.9, 1.1))
		if i % 2 == 0:
			Snd.play("grunt", -4.0, randf_range(0.92, 1.08))
		player.shake = 0.6 + n * 0.1
		if Game.main != null:
			Game.main.burst(0.25)
		await get_tree().create_timer(0.55).timeout
	if n >= 3:
		for i in 4:
			Snd.play("knock", 2.0, randf_range(0.85, 1.0))
			player.shake = 0.5
			await get_tree().create_timer(0.4).timeout
	Game.say("sub.hatch%d" % mini(n, 5))
	Snd.loop_vol("upstairs", 0.55, 0.5)
	player.frozen = false
	_hatch_busy = false
	if n >= 5:
		# сдался: садится под люком
		_given_up = t
		player.frozen = true
		player.cine = true
		var tw := create_tween().set_parallel(true)
		tw.tween_property(player.head, "position", Vector3(0, 0.75, 0), 2.5).set_trans(Tween.TRANS_SINE)
		tw.tween_property(player.cam, "rotation", Vector3(-0.35, 0.0, 0.08), 2.5)
		await get_tree().create_timer(4.0).timeout
		Game.say("sub.hatch6")


func _basement_tick(_dt: float) -> void:
	if Cfg.has_arg("auto_hatch") and not _hatch_busy and _given_up < 0.0 and t > 3.0 + _hatch_tries * 5.0:
		player.global_position = Vector3(-1.4, 1.35, 0.1)
		player.set_look(PI, 1.2)
		_try_hatch()
	var lamp := get_node_or_null("Bulb") as OmniLight3D
	if lamp != null and _given_up < 0.0:
		var fl := 1.4
		if t > 40.0 and randf() < 0.05:
			fl = randf_range(0.3, 1.0)
		lamp.light_energy = fl
	if randf() < _dt * 0.12:
		Snd.play("footsteps_above", -10.0, randf_range(0.9, 1.1), "Amb")
	# если герой так и не полез к люку — батарея всё равно садится
	if _given_up < 0.0 and t > 150.0:
		_given_up = t
	if _given_up >= 0.0:
		var gt := t - _given_up
		if Game.main != null:
			Game.main.osd.battery = 0.08
			Game.main.osd.message = Loc.t("osd.battery")
		if gt > 4.0 and gt < 12.0 and lamp != null:
			lamp.light_energy = 1.4 if randf() > 0.25 else randf_range(0.0, 0.6)
		if gt > 12.0 and lamp != null:
			lamp.visible = false
			(get_node("BulbMesh") as Node3D).visible = false
		if gt > 16.0:
			finish()


# ======================================================================= ШОССЕ

func _highway() -> void:
	var e := _env_base(Color(0.01, 0.012, 0.025))
	e.ambient_light_color = Color(0.06, 0.065, 0.09)
	e.fog_enabled = true
	e.fog_light_color = Color(0.02, 0.02, 0.035)
	e.fog_density = 0.006
	var moon := DirectionalLight3D.new()
	moon.rotation = Vector3(-0.7, 2.2, 0)
	moon.light_color = Color(0.55, 0.6, 0.85)
	moon.light_energy = 0.25
	add_child(moon)
	var ground := StandardMaterial3D.new()
	ground.albedo_color = Color(0.32, 0.27, 0.2)
	ground.albedo_texture = Mats.tex("concrete_floor")
	ground.uv1_scale = Vector3(300, 300, 1)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1200, 1200)
	g.mesh = pm
	g.material_override = ground
	add_child(g)
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_texture = Mats.tex("asphalt")
	asphalt.uv1_scale = Vector3(2, 300, 1)
	var road := MeshInstance3D.new()
	var rm := PlaneMesh.new()
	rm.size = Vector2(8, 1200)
	road.mesh = rm
	road.material_override = asphalt
	road.position.y = 0.01
	add_child(road)
	var line := StandardMaterial3D.new()
	line.albedo_color = Color(0.9, 0.8, 0.3)
	for k in 120:
		var dash := MeshInstance3D.new()
		var dm := PlaneMesh.new()
		dm.size = Vector2(0.15, 3.0)
		dash.mesh = dm
		dash.material_override = line
		dash.position = Vector3(0, 0.02, -600 + k * 10.0)
		add_child(dash)
	# звёзды
	var star := StandardMaterial3D.new()
	star.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star.albedo_color = Color(0.9, 0.9, 1.0)
	star.disable_fog = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 31190
	for k in 220:
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = rng.randf_range(0.6, 1.6)
		sm.height = sm.radius * 2.0
		sm.radial_segments = 4
		sm.rings = 2
		s.mesh = sm
		s.material_override = star
		var a := rng.randf() * TAU
		var el := rng.randf_range(0.08, 1.4)
		s.position = Vector3(cos(a) * cos(el), sin(el), sin(a) * cos(el)) * 900.0
		add_child(s)
	# горы-силуэты
	var mt := StandardMaterial3D.new()
	mt.albedo_color = Color(0.02, 0.02, 0.03)
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.disable_fog = true
	for k in 10:
		var m := MeshInstance3D.new()
		var sp := SphereMesh.new()
		m.mesh = sp
		m.material_override = mt
		var a2 := k * TAU / 10.0
		m.scale = Vector3(rng.randf_range(120, 220), rng.randf_range(30, 70), 80)
		m.position = Vector3(cos(a2) * 700, -10, sin(a2) * 700)
		m.rotation.y = -a2
		add_child(m)
	# знак
	var sign := Node3D.new()
	add_child(sign)
	sign.position = Vector3(5.5, 0, -18)
	var post := StandardMaterial3D.new()
	post.albedo_color = Color(0.5, 0.5, 0.5)
	_box(sign, Vector3(0.1, 2.2, 0.1), Vector3(0, 1.1, 0), post, false)
	var face := StandardMaterial3D.new()
	face.albedo_color = Color(0.05, 0.3, 0.12)
	_box(sign, Vector3(1.6, 0.9, 0.05), Vector3(0, 2.4, 0), face, false)
	var lb := Props.label("US 50\nELY  64", Props.font_sign(), 0.006, Color(0.95, 0.95, 0.9))
	lb.position = Vector3(0, 2.4, 0.03)
	lb.visibility_range_end = 0.0
	sign.add_child(lb)
	player = Player.new()
	add_child(player)
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
	# грузовик
	var truck := Node3D.new()
	truck.name = "Truck"
	add_child(truck)
	var tb := StandardMaterial3D.new()
	tb.albedo_color = Color(0.2, 0.2, 0.22)
	_box(truck, Vector3(2.5, 3.2, 14), Vector3(0, 2.0, 0), tb, false)
	_box(truck, Vector3(2.5, 2.6, 2.4), Vector3(0, 1.7, -8.0), tb, false)
	for sx in [-0.9, 0.9]:
		var hl := SpotLight3D.new()
		hl.position = Vector3(sx, 1.0, -9.3)
		hl.light_energy = 6.0
		hl.spot_range = 90.0
		hl.spot_angle = 22.0
		hl.light_color = Color(1.0, 0.95, 0.8)
		truck.add_child(hl)
		var lamp := MeshInstance3D.new()
		var ls := SphereMesh.new()
		ls.radius = 0.18
		ls.height = 0.36
		lamp.mesh = ls
		var lm := StandardMaterial3D.new()
		lm.emission_enabled = true
		lm.emission = Color(1.0, 0.95, 0.8)
		lm.emission_energy_multiplier = 12.0
		lamp.material_override = lm
		lamp.position = Vector3(sx, 1.0, -9.25)
		truck.add_child(lamp)
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
		if truck.position.z > player.global_position.z - 10.0:
			# удар: запись обрывается
			Snd.play("death_hit", 4.0)
			Snd.play("impact_far", 6.0)
			if Game.main != null:
				Game.main.interference = 1.0
			truck.position.z = player.global_position.z - 10.0
			finish()


# ======================================================================= СТЕНА

## Узкая щель между стенами жилого дома: за гипсокартоном живут люди, выхода нет
func _wall() -> void:
	_env_base(Color(0, 0, 0))
	env.ambient_light_color = Color(0.02, 0.018, 0.015)
	var stud := StandardMaterial3D.new()
	stud.albedo_texture = Mats.tex("wood")
	stud.uv1_triplanar = true
	stud.uv1_scale = Vector3(1.5, 1.5, 1.5)
	var board := StandardMaterial3D.new()
	board.albedo_color = Color(0.62, 0.58, 0.5)
	board.albedo_texture = Mats.tex("plaster")
	board.uv1_triplanar = true
	var ins := StandardMaterial3D.new()
	ins.albedo_color = Color(0.75, 0.55, 0.35)
	ins.albedo_texture = Mats.tex("fiber")
	ins.uv1_triplanar = true
	ins.uv1_scale = Vector3(2, 2, 2)
	var w := 0.62
	var L := 3.2
	var h := 2.6
	_box(self, Vector3(w, 0.1, L), Vector3(0, -0.05, 0), stud, true)
	_box(self, Vector3(w, 0.1, L), Vector3(0, h + 0.05, 0), stud, true)
	_box(self, Vector3(0.05, h, L), Vector3(-w * 0.5 - 0.025, h * 0.5, 0), board, true)
	_box(self, Vector3(0.05, h, L), Vector3(w * 0.5 + 0.025, h * 0.5, 0), board, true)
	_box(self, Vector3(w, h, 0.1), Vector3(0, h * 0.5, -L * 0.5 - 0.05), ins, true)
	_box(self, Vector3(w, h, 0.1), Vector3(0, h * 0.5, L * 0.5 + 0.05), ins, true)
	for k in 3:
		_box(self, Vector3(w, 0.09, 0.04), Vector3(0, 0.5 + k * 0.8, -1.0 + k * 0.9), stud, false)
	# щель розетки: оттуда — тёплый свет соседской комнаты
	var glow := StandardMaterial3D.new()
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.75, 0.45)
	glow.emission_energy_multiplier = 3.0
	glow.albedo_color = Color(1.0, 0.8, 0.5)
	_box(self, Vector3(0.01, 0.08, 0.05), Vector3(w * 0.5 - 0.005, 0.35, 0.6), glow, false)
	var lt := OmniLight3D.new()
	lt.name = "Slit"
	lt.position = Vector3(w * 0.5 - 0.05, 0.35, 0.6)
	lt.light_color = Color(1.0, 0.75, 0.45)
	lt.light_energy = 0.6
	lt.omni_range = 2.5
	add_child(lt)
	var lb := Props.label("ПОМОГИТЕ  HELP  ||||  ||||  |||", Props.font_hand(), 0.003, Color(0.25, 0.08, 0.06))
	lb.position = Vector3(-w * 0.5 + 0.005, 1.4, -0.4)
	lb.rotation.y = PI * 0.5
	lb.visibility_range_end = 0.0
	add_child(lb)
	player = Player.new()
	add_child(player)
	player.global_position = Vector3(0, 0.05, -0.8)
	player.set_look(PI, -0.1)
	player.surface_fn = func(_p: Vector3) -> String: return "wood"
	player.shake = 1.0
	Snd.loop("neighbors", "upstairs_tv", 0.75, 2.0)
	Snd.play("thud_land", -2.0)


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
	if t > 50.0 and lt != null:
		lt.light_energy = maxf(0.0, lt.light_energy - _dt * 0.3)
	if t > 58.0:
		finish()


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
	for k in 4:
		var lt := OmniLight3D.new()
		lt.position = Vector3(0, 2.6, -2.0 - k * 3.2)
		lt.omni_range = 6.0
		lt.light_energy = 1.2
		lt.light_color = Color(0.95, 0.97, 1.0)
		add_child(lt)
		_box(self, Vector3(0.25, 0.06, 1.3), Vector3(0, 2.78, -2.0 - k * 3.2), glow, false)
	var lb := Props.label("ASYNC  —  DECONTAMINATION  B-2", Props.font_sign(), 0.005, Color(0.85, 0.12, 0.08))
	lb.position = Vector3(0, 2.3, -L + 0.17)
	lb.visibility_range_end = 0.0
	add_child(lb)
	player = Player.new()
	add_child(player)
	player.global_position = Vector3(0, 0.05, -0.6)
	player.set_look(0.0, 0.0)
	player.surface_fn = func(_p: Vector3) -> String: return "concrete"
	Snd.loop("hum", "hum_fluor", 0.4, 1.0)
	Snd.play("threshold_pass", 0.0)
	_phase = 0


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
			if t > 9.0:
				_phase = 7
				t = 0.0
				_copy_room()
		7:
			if t > 9.0:
				finish("async")


func _gas() -> void:
	var gp := GPUParticles3D.new()
	gp.amount = 160
	gp.lifetime = 4.0
	gp.position = Vector3(0, 2.7, -4.0)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 60.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, -0.2, 0)
	pm.scale_min = 1.5
	pm.scale_max = 3.0
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1.4, 0.1, 5.0)
	gp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var qm := StandardMaterial3D.new()
	qm.albedo_color = Color(0.9, 0.93, 0.9, 0.22)
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.albedo_texture = Mats.tex("noise")
	q.material = qm
	gp.draw_pass_1 = q
	add_child(gp)
	env.fog_enabled = true
	env.fog_light_color = Color(0.8, 0.82, 0.8)
	var tw := create_tween()
	tw.tween_property(env, "fog_density", 0.25, 5.0)


func _hazmat() -> void:
	for k in 2:
		var h := Human.make("explorer", 300 + k, false)
		add_child(h)
		h.position = Vector3(-0.6 + k * 1.2, 0, -12.0)
		h.rotation.y = 0.0
		h.pose_name = "walk"
		h.anim_speed = 0.8
		var fl := SpotLight3D.new()
		fl.light_energy = 4.0
		fl.spot_range = 14.0
		fl.spot_angle = 18.0
		fl.position = Vector3(0, 1.4, 0.3)
		fl.rotation.x = -0.25
		h.add_child(fl)
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
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.03, 0.035, 0.04)
	glass.metallic = 0.8
	glass.roughness = 0.1
	_box(self, Vector3(2.2, 1.0, 0.03), Vector3(-0.2, 1.5, -d * 0.5 + 0.01), glass, false)
	var spk := StandardMaterial3D.new()
	spk.albedo_color = Color(0.2, 0.2, 0.2)
	_box(self, Vector3(0.3, 0.3, 0.06), Vector3(-1.4, 2.2, -d * 0.5 + 0.03), spk, false)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, h - 0.2, 0)
	lamp.omni_range = 7.0
	lamp.light_energy = 1.3
	lamp.shadow_enabled = true
	add_child(lamp)
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


## Последний кадр: камера в Комплексе, копия героя на стуле под мигающей лампой
func _copy_room() -> void:
	for ch in get_children():
		ch.queue_free()
	_subject = null
	Snd.stop_all(0.1)
	Snd.play("cam_switch", -4.0)
	_env_base(Color(0, 0, 0))
	env.ambient_light_color = Color(0.05, 0.05, 0.04)
	var wall := StandardMaterial3D.new()
	wall.albedo_texture = Mats.tex("wall_yellow_dirty")
	wall.uv1_triplanar = true
	wall.uv1_scale = Vector3(1.2, 1.2, 1.2)
	var carpet := StandardMaterial3D.new()
	carpet.albedo_texture = Mats.tex("carpet_wet")
	carpet.uv1_triplanar = true
	carpet.uv1_scale = Vector3(0.7, 0.7, 0.7)
	var ceil_m := StandardMaterial3D.new()
	ceil_m.albedo_texture = Mats.tex("ceiling_tile")
	ceil_m.uv1_triplanar = true
	ceil_m.uv1_scale = Vector3(0.8, 0.8, 0.8)
	_box(self, Vector3(6, 0.2, 6), Vector3(0, -0.1, 0), carpet, false)
	_box(self, Vector3(6, 0.2, 6), Vector3(0, 2.8, 0), ceil_m, false)
	_box(self, Vector3(0.2, 2.7, 6), Vector3(-3, 1.35, 0), wall, false)
	_box(self, Vector3(6, 2.7, 0.2), Vector3(0, 1.35, -3), wall, false)
	_box(self, Vector3(0.2, 2.7, 6), Vector3(3, 1.35, 0), wall, false)
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	lamp.position = Vector3(0, 2.55, -0.5)
	lamp.light_color = Color(1.0, 0.95, 0.75)
	lamp.omni_range = 6.0
	add_child(lamp)
	var ch := Node3D.new()
	add_child(ch)
	Props._chair(ch)
	ch.position = Vector3(0, 0, -0.8)
	for c in ch.get_children():
		if c is MeshInstance3D:
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.85, 0.84, 0.8)
			(c as MeshInstance3D).material_override = m
	var copy := Human.make("player", 77, false)
	add_child(copy)
	copy.position = Vector3(0, -0.02, -0.8)
	copy.pose("slump")
	copy.react = false
	_paleify(copy)
	_make_cam(Vector3(2.6, 2.6, 2.4))
	cam.look_at(Vector3(0, 0.9, -0.8))
	cam.fov = 70.0
	if Game.main != null:
		Game.main.osd.cam_label = Loc.t("osd.cam_complex")
		Game.main.bw = 0.85
	Snd.loop("hum", "hum_fluor", 0.6, 0.5)
	_subject = copy


func _paleify(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var src := mi.material_override as StandardMaterial3D
		var m := StandardMaterial3D.new()
		var c := src.albedo_color if src != null else Color(1, 1, 1)
		m.albedo_color = c.lerp(Color(0.88, 0.85, 0.78), 0.65)
		if src != null and src.albedo_texture != null and src.albedo_texture == Mats.tex("face"):
			m.albedo_texture = Mats.tex("face_smear")
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.roughness = 1.0
		mi.material_override = m
	for ch in n.get_children():
		_paleify(ch)


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
		"basement": _basement_tick(dt)
		"highway": _highway_tick(dt)
		"wall": _wall_tick(dt)
		"async": _async_tick(dt)
	if kind == "async" and _phase == 7 and _subject != null:
		var lamp := get_node_or_null("Lamp") as OmniLight3D
		if lamp != null:
			lamp.light_energy = 1.2 if randf() > 0.08 else randf_range(0.0, 0.5)
		if t > 4.0:
			var head: Node3D = _subject.j["head"]
			head.rotation.y = lerpf(head.rotation.y, 0.7, dt * 0.25)
