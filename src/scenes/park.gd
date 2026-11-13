extends Node3D
## Парк в Сан-Хосе, 14 июля 1990, около 16:12. Солнце, люди, мороженое.
## Через минуту-полторы что-то идёт не так: стихают птицы и ветер, проступает гул ламп — и земля исчезает.
## Земля, трава и дорожки — park_ground.gd, деревья — park_trees.gd, дальние планы — park_far.gd.

const Props := preload("res://src/world/props.gd")
const Ground := preload("res://src/scenes/park_ground.gd")
const Trees := preload("res://src/scenes/park_trees.gd")
const Far := preload("res://src/scenes/park_far.gd")
const SKY_SHADER := preload("res://src/shaders/park_sky.gdshader")
const WATER_SHADER := preload("res://src/shaders/park_water.gdshader")

const PLAZA_R := 9.0
const PLAYGROUND := Vector3(-24, 0, -6)
const BLANKET := Vector3(20, 0, -10)

var player: Player
var t := 0.0
var fall_at := 85.0
var wrong := 0.0
var falling := false
var path_pts: PackedVector3Array
var people: Array = []          # [Human, kind, data]
var spot := Vector3(-16, 0, 30) # место, где «тонко»
var ground: Ground
var trees: Trees
var _std_cache := {}
var _env: Environment
var _sun: DirectionalLight3D
var _birds_cd := 1.0
var _ctrl: Array = []
var _tree_pos: Array = []       # [Vector2, радиус] — занятые деревьями места
var _wind_mats: Array = []
var _wind := 1.0
var _sat := 1.0
var _ground_mi: MeshInstance3D
var _pit: Node3D = null
var _hole := Vector4.ZERO       # провал: x, z, радиус, фаза формы (как uniform park_hole)

const HOLE_R := 1.3


func _ready() -> void:
	Props.park_mode = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 140790
	if Cfg.has_arg("fall_at"):
		fall_at = float(Cfg.arg("fall_at"))
	if Cfg.has_arg("vhs"):
		Cfg.vhs = float(Cfg.arg("vhs"))
	var t0 := Time.get_ticks_msec()
	_environment()
	ground = Ground.new()
	_path()
	_playground_ground()
	_prof("paths", t0)
	ground.build_height()
	_prof("height", t0)
	trees = Trees.new()
	_prof("tree meshes", t0)
	_trees(rng)
	_prof("trees", t0)
	_furniture(rng)
	_plaza_props(rng)
	_borders()
	_desire_paths()
	ground.finish_mask()
	_prof("furniture+mask", t0)
	_ground_mi = ground.build(self)
	ground.build_grass(self)
	_prof("ground mesh+grass", t0)
	_wind_mats = ground.wind_mats + trees.wind_mats
	_people(rng)
	_skyline(rng)
	player = Player.new()
	add_child(player)
	player.cam.far = 700.0
	player.global_position = path_pts[0] + Vector3(0, 0.1, 0)
	var dir := path_pts[3] - path_pts[0]
	player.set_look(atan2(-dir.x, -dir.z), -0.05)
	if Cfg.has_arg("pos"):
		var pp := Cfg.arg("pos").split(",")
		var pv := Vector3(float(pp[0]), float(pp[1]), float(pp[2]))
		pv.y = maxf(pv.y, ground.height(pv.x, pv.z) + 0.1)
		player.global_position = pv
		player.set_look(float(Cfg.arg("yaw", "0")), float(Cfg.arg("pitch", "0")))
	player.surface_fn = func(p: Vector3) -> String:
		return "path" if _near_path(p) < 1.4 else "grass"
	if Cfg.has_arg("near"):
		Game._near_test(float(Cfg.arg("near")), self)
	if Cfg.testing():
		print("PARK built in ", Time.get_ticks_msec() - t0, " ms")
	Snd.set_reverb(0.2, 0.05)
	Snd.loop("park_amb", "park_ambience", 0.85, 2.0)
	Snd.loop("park_wind", "wind_trees", 0.5, 2.0)
	_subs_intro()


func _prof(what: String, t0: int) -> void:
	if Cfg.has_arg("gen_prof"):
		print("PARK ", what, ": ", Time.get_ticks_msec() - t0, " ms")


func _exit_tree() -> void:
	# общие настройки теней — как в проекте (их меняли под солнце парка)
	RenderingServer.directional_shadow_atlas_set_size(int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size", 2048)),
		bool(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/16_bits", true)))
	RenderingServer.directional_soft_shadow_filter_set_quality(int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 1)) as RenderingServer.ShadowQuality)


func _subs_intro() -> void:
	await get_tree().create_timer(2.5).timeout
	Game.say("sub.park1")
	await get_tree().create_timer(4.0).timeout
	Game.say("sub.park2")


# ------------------------------------------------------------ окружение

func _environment() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = SKY_SHADER
	sm.set_shader_parameter("clouds", Mats.tex("park_clouds"))
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.72
	e.ambient_light_sky_contribution = 0.75
	e.ambient_light_color = Color(0.8, 0.76, 0.66)
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# бытовая камера: чуть пересвечено, светлое уходит в белое
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.18
	e.tonemap_white = 5.0
	e.ssao_enabled = true
	e.ssao_radius = 1.4
	e.ssao_intensity = 1.8
	e.ssao_power = 1.6
	e.ssao_detail = 0.6
	e.ssao_horizon = 0.08
	e.ssao_light_affect = 0.1
	e.glow_enabled = true
	e.glow_intensity = 0.55
	e.glow_strength = 1.0
	e.glow_bloom = 0.06
	e.glow_hdr_threshold = 0.95
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# жаркая дымка: тёплый туман, вдали цвет берётся из неба
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	e.fog_light_color = Color(0.84, 0.81, 0.73)
	e.fog_light_energy = 1.0
	e.fog_sun_scatter = 0.18
	e.fog_density = 0.0016
	e.fog_aerial_perspective = 0.6
	e.fog_sky_affect = 0.0
	e.adjustment_enabled = true
	e.adjustment_brightness = 1.0
	e.adjustment_contrast = 1.1
	e.adjustment_saturation = _sat
	e.adjustment_color_correction = _grade()
	we.environment = e
	# автоэкспозиция камеры: небо в кадре — земля темнеет, тень — светлеет
	var ca := CameraAttributesPractical.new()
	ca.auto_exposure_enabled = true
	ca.auto_exposure_speed = 0.7
	ca.auto_exposure_scale = 0.42
	ca.auto_exposure_min_sensitivity = 60.0
	ca.auto_exposure_max_sensitivity = 200.0
	we.camera_attributes = ca
	_env = e
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation = Vector3(deg_to_rad(-34.0), deg_to_rad(-128.0), 0)
	_sun.light_color = Color(1.0, 0.92, 0.78)
	_sun.light_energy = 1.55
	_sun.light_angular_distance = 0.53
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.directional_shadow_max_distance = 110.0
	_sun.directional_shadow_split_1 = 0.06
	_sun.directional_shadow_split_2 = 0.16
	_sun.directional_shadow_split_3 = 0.4
	_sun.directional_shadow_blend_splits = true
	_sun.directional_shadow_fade_start = 0.85
	_sun.shadow_blur = 1.0
	_sun.shadow_normal_bias = 1.2
	add_child(_sun)
	RenderingServer.directional_shadow_atlas_set_size(4096, true)
	# полутень солнца (PCSS) без TAA: при малом числе выборок поворот ядра по пикселям виден точечным
	# «растром» в тенях — берём больше выборок, края тени гладкие, как размытые объективом
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)


## Цветокоррекция бытовой камеры: приподнятые тени, тёплые света (синий в светах приглушён)
func _grade() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 0.5, 0.82, 1.0])
	g.colors = PackedColorArray([Color(0.035, 0.04, 0.035), Color(0.16, 0.165, 0.145), Color(0.53, 0.52, 0.475), Color(0.86, 0.845, 0.79), Color(1.0, 0.985, 0.93)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	gt.width = 256
	return gt


# ------------------------------------------------------------ дорожки и земля

func _path() -> void:
	# петля дорожки вокруг площади с фонтаном
	_ctrl = [Vector3(0, 0, 44), Vector3(22, 0, 34), Vector3(34, 0, 10), Vector3(30, 0, -18), Vector3(12, 0, -34),
		Vector3(-14, 0, -32), Vector3(-32, 0, -14), Vector3(-34, 0, 12), Vector3(-22, 0, 32)]
	path_pts = PackedVector3Array()
	var n := _ctrl.size()
	for i in n:
		var p0: Vector3 = _ctrl[(i - 1 + n) % n]
		var p1: Vector3 = _ctrl[i]
		var p2: Vector3 = _ctrl[(i + 1) % n]
		var p3: Vector3 = _ctrl[(i + 2) % n]
		for k in 12:
			var tt := k / 12.0
			path_pts.append(_catmull(p0, p1, p2, p3, tt))
	var loop := PackedVector2Array()
	for p in path_pts:
		loop.append(Vector2(p.x, p.z))
	ground.paint_road(loop, 1.4, true)
	# площадь у фонтана и дорожки-спицы от петли к ней
	ground.paint_plaza(Vector2.ZERO, PLAZA_R)
	for k in 3:
		var a2: Vector3 = _ctrl[k * 3]
		var d2 := Vector2(-a2.x, -a2.z).normalized()
		ground.paint_road(PackedVector2Array([Vector2(a2.x, a2.z), d2 * -(PLAZA_R - 1.0)]), 1.2, false)


## Детская площадка в песке, ровные места под пледом и тележкой
func _playground_ground() -> void:
	ground.paint_sand(Vector2(PLAYGROUND.x, PLAYGROUND.z), Vector2(6.2, 4.4), 0.12, 1.6)
	ground.flat_spots.append([Vector2(PLAYGROUND.x, PLAYGROUND.z), 8.0])
	ground.flat_spots.append([Vector2(BLANKET.x, BLANKET.z), 3.5])
	ground.flat_spots.append([Vector2(8.0, 7.0), 3.0])


## Тропинки «напрямик», вытоптанные через газон
func _desire_paths() -> void:
	var lines := [[Vector2(-31.5, 2.0), Vector2(-27.5, -2.5)], [Vector2(13.0, 39.0), Vector2(7.5, 27.0), Vector2(5.0, 12.0)]]
	for ln in lines:
		var pts: Array = ln
		for s in pts.size() - 1:
			var a: Vector2 = pts[s]
			var b: Vector2 = pts[s + 1]
			var steps := int(a.distance_to(b) / 0.5)
			for i in steps + 1:
				var p := a.lerp(b, float(i) / steps)
				p += Vector2(sin(p.y * 0.4) * 0.25, cos(p.x * 0.35) * 0.25)
				ground.paint_bare(p, 0.75, 0.62)


func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


func _near_path(p: Vector3) -> float:
	var best := 1e9
	for i in range(0, path_pts.size(), 2):
		best = minf(best, Vector2(p.x - path_pts[i].x, p.z - path_pts[i].z).length())
	if Vector2(p.x, p.z).length() < PLAZA_R:
		best = 0.0
	return best


# ------------------------------------------------------------ деревья

func _free_spot(p: Vector2, gap: float) -> bool:
	for e in _tree_pos:
		var q: Vector2 = e[0]
		var r: float = e[1]
		if p.distance_to(q) < gap + r:
			return false
	return true


func _plant(kind: String, p: Vector2, sc: float, rng: RandomNumberGenerator, collide := true) -> MeshInstance3D:
	var y := ground.height(p.x, p.y) - 0.05
	var hue := rng.randf_range(-0.6, 0.6)
	var mi := trees.spawn(self, kind, Vector3(p.x, y, p.y), rng.randf() * TAU, sc, hue, collide)
	var cr: float = mi.get_meta("crown")
	_tree_pos.append([p, 2.0 if kind == "palm" else cr * 0.45])
	# земля под деревом: под дубом и эвкалиптом почти голая, под пальмой — пятачок у ствола
	match kind:
		"palm": ground.paint_bare(p, 1.3 * sc, 0.85)
		"oak": ground.paint_bare(p, cr * 0.75, 0.82)
		"euc": ground.paint_bare(p, cr * 0.7, 0.75)
		_: ground.paint_bare(p, cr * 0.55, 0.6)
	return mi


func _trees(rng: RandomNumberGenerator) -> void:
	var m := path_pts.size()
	# «тонкое место» — старый дуб, у которого гудит
	_plant("oak", Vector2(spot.x + 2.5, spot.z + 1.5), 1.25, rng)
	# аллея вашингтоний с внешней стороны дорожки от входа
	for k in 6:
		var i := 5 + k * 6
		var a := path_pts[i % m]
		var b := path_pts[(i + 1) % m]
		var side := (b - a).cross(Vector3.UP).normalized()
		var p := a - side * 4.2
		_plant("palm", Vector2(p.x, p.z), rng.randf_range(0.9, 1.15), rng)
	# эвкалиптовая роща в северо-западном углу и пара у восточного края
	for c in [[Vector2(-42, -40), 6], [Vector2(43, -38), 2]]:
		var ctr: Vector2 = c[0]
		var placed := 0
		var guard := 0
		while placed < int(c[1]) and guard < 200:
			guard += 1
			var p := ctr + Vector2(rng.randf_range(-9, 9), rng.randf_range(-9, 9))
			if not ground.clear_at(p, 4.0) or not _free_spot(p, 3.0) or absf(p.x) > 53.0 or absf(p.y) > 53.0:
				continue
			_plant("euc", p, rng.randf_range(0.85, 1.1), rng)
			placed += 1
	# дубы на открытых лужайках и платаны/ясени по всему парку
	var want := {"oak": 7, "broad": 26}
	for kind in ["oak", "broad"]:
		var placed := 0
		var guard := 0
		while placed < int(want[kind]) and guard < 900:
			guard += 1
			var p := Vector2(rng.randf_range(-53, 53), rng.randf_range(-53, 53))
			if p.length() < PLAZA_R + 5.0 or not ground.clear_at(p, 3.8):
				continue
			if p.distance_to(Vector2(BLANKET.x, BLANKET.z)) < 7.0 or p.distance_to(Vector2(PLAYGROUND.x, PLAYGROUND.z)) < 9.0:
				continue
			if p.distance_to(Vector2(spot.x, spot.z)) < 5.0 or p.distance_to(Vector2(path_pts[0].x, path_pts[0].z)) < 7.0:
				continue
			if not _free_spot(p, 3.5 if kind == "broad" else 5.0):
				continue
			_plant(kind, p, rng.randf_range(0.85, 1.2) if kind == "broad" else rng.randf_range(0.9, 1.15), rng)
			placed += 1
	# живые изгороди олеандра по валу у края парка
	for side_i in 4:
		for g in 3:
			var u0 := rng.randf_range(-44.0, 44.0)
			var n := rng.randi_range(3, 7)
			var e := rng.randf_range(54.5, 56.5)
			for k in n:
				var u := u0 + k * rng.randf_range(1.5, 2.1)
				var p := [Vector2(u, -e), Vector2(e, u), Vector2(-u, e), Vector2(-e, -u)][side_i] as Vector2
				if not ground.clear_at(p, 2.0) or not _free_spot(p, 0.6):
					continue
				trees.spawn(self, "shrub", Vector3(p.x, ground.height(p.x, p.y) - 0.1, p.y), rng.randf() * TAU, rng.randf_range(0.85, 1.15), rng.randf_range(-0.5, 0.5), true)
				ground.paint_bare(p, 1.4, 0.7)
	# край парка за невидимой оградой: полоса деревьев на валу, за улицей — деревья у домов (недоступны)
	for row in 2:
		var s := rng.randf() * 6.0
		var side_len := 136.0 if row == 0 else 170.0
		while s < 4.0 * side_len:
			var side_i := int(s / side_len)
			var u := fmod(s, side_len) - side_len * 0.5
			var off := rng.randf_range(59.5, 64.5) if row == 0 else rng.randf_range(82.5, 86.0)
			var p := [Vector2(u, -off), Vector2(off, u), Vector2(-u, off), Vector2(-off, -u)][side_i] as Vector2
			var r := rng.randf()
			var kind := "broad" if r < 0.5 else ("euc" if r < 0.7 else ("oak" if r < 0.85 else "palm"))
			if row == 1:
				kind = "broad" if r < 0.6 else ("palm" if r < 0.85 else "euc")
			var mi := trees.spawn(self, kind, Vector3(p.x, ground.height(p.x, p.y) - 0.05, p.y), rng.randf() * TAU, rng.randf_range(0.95, 1.3) if row == 0 else rng.randf_range(0.8, 1.1), rng.randf_range(-0.6, 0.6), false)
			if row == 1:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			s += rng.randf_range(6.0, 10.0) if row == 0 else rng.randf_range(11.0, 22.0)
	_street_cars(rng)


## Машины у бордюра на улице за парком
func _street_cars(rng: RandomNumberGenerator) -> void:
	var cols := [Color(0.55, 0.12, 0.1), Color(0.75, 0.73, 0.68), Color(0.2, 0.24, 0.32), Color(0.52, 0.46, 0.34), Color(0.16, 0.16, 0.17), Color(0.36, 0.42, 0.36)]
	for k in 11:
		var side_i := rng.randi_range(0, 3)
		var u := rng.randf_range(-60.0, 60.0)
		var off := 69.6 if rng.randf() < 0.6 else 78.15
		var p := [Vector2(u, -off), Vector2(off, u), Vector2(-u, off), Vector2(-off, -u)][side_i] as Vector2
		var car := Node3D.new()
		add_child(car)
		Props._car(car)
		car.position = Vector3(p.x, 0.0, p.y)
		car.rotation.y = (0.0 if side_i % 2 == 1 else PI * 0.5) + (PI if rng.randf() < 0.5 else 0.0)
		_to_std(car)
		var paint := StandardMaterial3D.new()
		paint.albedo_color = cols[rng.randi_range(0, cols.size() - 1)]
		paint.roughness = 0.35
		paint.metallic = 0.25
		for ch in car.get_children():
			var mi := ch as MeshInstance3D
			if mi == null:
				continue
			var sm := mi.material_override as StandardMaterial3D
			if sm != null and sm.emission_enabled:
				# днём фары не горят
				var off_m := StandardMaterial3D.new()
				off_m.albedo_color = sm.emission * 0.6
				off_m.roughness = 0.3
				mi.material_override = off_m
			elif sm != null and sm.albedo_color.g > 0.4 and sm.albedo_color.r < 0.5:
				mi.material_override = paint


# ------------------------------------------------------------ вещи

func _on_ground(n: Node3D, p: Vector3) -> void:
	n.position = ground.at(p)


func _furniture(rng: RandomNumberGenerator) -> void:
	var m := path_pts.size()
	# скамейки и фонари вдоль дорожки
	for k in 10:
		var i := (k * m / 10 + 3) % m
		var a := path_pts[i]
		var b := path_pts[(i + 1) % m]
		var side := (b - a).cross(Vector3.UP).normalized()
		var out := 1.0 if k % 2 == 0 else -1.0
		var bench := Node3D.new()
		add_child(bench)
		Props._bench(bench)
		_on_ground(bench, a + side * 2.2 * out)
		bench.rotation.y = atan2(-side.x * out, -side.z * out)
		_to_std(bench)
		# вытоптано перед скамейкой
		var bp := a + side * 2.2 * out - side * 0.75 * out
		var along := (b - a).normalized()
		ground.paint_bare(Vector2(bp.x, bp.z), 0.9, 0.85, Vector2(along.x, along.z), 1.6)
		var lamp := Node3D.new()
		add_child(lamp)
		Props._lamp(lamp)
		_on_ground(lamp, path_pts[(i + m / 20) % m] - side * 2.0 * out)
		_to_std(lamp)
		_lamp_off(lamp)
		if k % 3 == 0:
			var bin := Node3D.new()
			add_child(bin)
			Props._bin(bin)
			var bpos := a + side * 2.2 * out + (b - a).normalized() * 1.6
			_on_ground(bin, bpos)
			_to_std(bin)
			ground.paint_bare(Vector2(bpos.x, bpos.z), 0.8, 0.7)
	# фонтан в центре (с настоящей водой)
	var f := Node3D.new()
	add_child(f)
	Props._fountain(f)
	_to_std(f)
	var wm := ShaderMaterial.new()
	wm.shader = WATER_SHADER
	wm.set_shader_parameter("noise_tex", Mats.tex("park_noise"))
	# чаша — тот же светлый бетон, что и площадь (мировые UV, чтобы швы текстуры не плыли по примитивам)
	var cm := StandardMaterial3D.new()
	cm.albedo_texture = Mats.tex("park_concrete")
	cm.albedo_color = Color(0.92, 0.9, 0.86)
	cm.uv1_triplanar = true
	cm.uv1_world_triplanar = true
	cm.uv1_scale = Vector3(0.45, 0.45, 0.45)
	cm.roughness = 0.85
	for ch in f.get_children():
		if ch.has_meta("water"):
			(ch as MeshInstance3D).material_override = wm
			(ch as MeshInstance3D).position.y -= 0.04
		elif ch is MeshInstance3D:
			(ch as MeshInstance3D).material_override = cm
	var wl := Props.SoundEmitter.new()
	wl.snd = "water_loop"
	wl.every = 0.0
	wl.vol = -8.0
	wl.max_dist = 30.0
	wl.position = Vector3(0, 1.0, 0)
	add_child(wl)
	# детская площадка
	var pg := Node3D.new()
	add_child(pg)
	pg.position = PLAYGROUND
	var sl := Node3D.new()
	pg.add_child(sl)
	Props._slide(sl)
	sl.position = Vector3(-2, 0, 0)
	var sw := Node3D.new()
	pg.add_child(sw)
	Props._swing(sw, false)
	sw.position = Vector3(3, 0, 1)
	_to_std(pg)
	# под качелями и у конца горки песок выбит ногами
	for sx in [-0.55, 0.55]:
		ground.paint_bare(Vector2(PLAYGROUND.x + 3 + sx, PLAYGROUND.z + 1), 0.9, 0.5, Vector2(0, 1), 1.8)
	# тележка с мороженым
	var cart := Node3D.new()
	add_child(cart)
	Props._cart(cart)
	_on_ground(cart, Vector3(7.5, 0, 6.5))
	cart.rotation.y = -0.7
	_to_std(cart)
	var jingle := Props.SoundEmitter.new()
	jingle.snd = "jingle"
	jingle.every = 0.0
	jingle.vol = -9.0
	jingle.max_dist = 40.0
	jingle.position = Vector3(0, 1.2, 0)
	cart.add_child(jingle)
	# плед для пары
	var bl := Node3D.new()
	add_child(bl)
	Props._blanket(bl)
	_on_ground(bl, BLANKET)
	bl.rotation.y = 0.4
	_to_std(bl)
	# под пледом травинок нет (прямоугольник по его размеру 2×2 м и повороту); вокруг трава примята.
	# Если плед станет другим (Props._blanket), поменять полуразмеры здесь
	ground.cut_grass(Vector2(BLANKET.x, BLANKET.z), Vector2(1.03, 1.03), bl.rotation.y)
	ground.paint_bare(Vector2(BLANKET.x, BLANKET.z), 1.2, 0.45)
	# табличка у входа
	var sg := Node3D.new()
	add_child(sg)
	Props._sign_park(sg)
	var s0 := path_pts[2]
	var sdir := (path_pts[3] - path_pts[1]).normalized()
	var sside := sdir.cross(Vector3.UP).normalized()
	_on_ground(sg, s0 + sside * 2.4)
	var to_start := path_pts[0] - sg.position
	sg.rotation.y = atan2(to_start.x, to_start.z)
	_to_std(sg)


## Площадь у фонтана: скамейки по кругу лицом к фонтану, бетонные вазоны с кустами, урны, пара фонарей.
## Входы дорожек-спиц свободны
func _plaza_props(rng: RandomNumberGenerator) -> void:
	var spokes: Array = []
	for k in 3:
		var a2: Vector3 = _ctrl[k * 3]
		spokes.append(atan2(a2.z, a2.x))
	var free := func(ang: float, gap: float) -> bool:
		for sa in spokes:
			if absf(angle_difference(ang, float(sa))) < gap:
				return false
		return true
	var cm := StandardMaterial3D.new()
	cm.albedo_texture = Mats.tex("park_concrete")
	cm.albedo_color = Color(0.8, 0.78, 0.74)
	cm.uv1_triplanar = true
	cm.uv1_world_triplanar = true
	cm.uv1_scale = Vector3(0.6, 0.6, 0.6)
	cm.roughness = 0.9
	var soil := StandardMaterial3D.new()
	soil.albedo_texture = Mats.tex("park_dirt")
	soil.albedo_color = Color(0.55, 0.5, 0.45)
	soil.roughness = 1.0
	var a0 := rng.randf() * TAU
	var placed := 0
	for i in 12:
		var ang := a0 + i * TAU / 12.0
		if not free.call(ang, 0.3):
			continue
		var dir := Vector3(cos(ang), 0, sin(ang))
		if placed % 2 == 0:
			# скамейка у края площади, лицом к фонтану
			var bench := Node3D.new()
			add_child(bench)
			Props._bench(bench)
			_on_ground(bench, dir * (PLAZA_R - 1.3))
			bench.rotation.y = atan2(-dir.x, -dir.z)
			_to_std(bench)
			if placed % 4 == 0:
				var bin := Node3D.new()
				add_child(bin)
				Props._bin(bin)
				_on_ground(bin, dir.rotated(Vector3.UP, 0.17) * (PLAZA_R - 1.1))
				_to_std(bin)
		else:
			# бетонный вазон с кустом олеандра
			var pc := dir * (PLAZA_R - 2.6)
			var pl := Node3D.new()
			add_child(pl)
			_on_ground(pl, pc)
			pl.rotation.y = ang
			var box := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(1.5, 0.48, 1.5)
			box.mesh = bm
			box.material_override = cm
			box.position.y = 0.24
			pl.add_child(box)
			var top := MeshInstance3D.new()
			var tm := BoxMesh.new()
			tm.size = Vector3(1.3, 0.02, 1.3)
			top.mesh = tm
			top.material_override = soil
			top.position.y = 0.475
			pl.add_child(top)
			var body := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var sh := BoxShape3D.new()
			sh.size = Vector3(1.5, 0.9, 1.5)
			cs.shape = sh
			cs.position.y = 0.45
			body.add_child(cs)
			pl.add_child(body)
			trees.spawn(self, "shrub", pl.position + Vector3(0, 0.42, 0), rng.randf() * TAU, rng.randf_range(0.4, 0.5), rng.randf_range(-0.4, 0.3), false)
		placed += 1
	# два фонаря у входов на площадь
	for k in 2:
		var sa2: float = spokes[k]
		var ld := Vector3(cos(sa2 + 0.38), 0, sin(sa2 + 0.38))
		var lamp := Node3D.new()
		add_child(lamp)
		Props._lamp(lamp)
		_on_ground(lamp, ld * (PLAZA_R - 0.5))
		_to_std(lamp)
		_lamp_off(lamp)


## Бордюр площади (низкая бетонная полоса, у входов дорожек разрывы) и деревянный брус вокруг песочницы:
## край покрытия — настоящая кромка, а не нарисованная по маске граница
func _borders() -> void:
	var cm := StandardMaterial3D.new()
	cm.albedo_texture = Mats.tex("park_concrete")
	cm.albedo_color = Color(0.86, 0.84, 0.8)
	cm.uv1_triplanar = true
	cm.uv1_world_triplanar = true
	cm.uv1_scale = Vector3(0.7, 0.7, 0.7)
	cm.roughness = 0.9
	var ring := PackedVector2Array()
	for i in 160:
		var a := float(i) / 160.0 * TAU
		ring.append(Vector2(cos(a), sin(a)) * (PLAZA_R - 0.15))
	_border(ring, 0.3, 0.045, cm, func(p: Vector2) -> bool: return ground.sample(Ground.ASPH, p) < 0.45)
	# брус песочницы: по краю песка (paint_sand: полуразмеры 6.2×4.4, скругление 1.6, поворот 0.12), снаружи
	var wm := StandardMaterial3D.new()
	wm.albedo_texture = Mats.tex("wood")
	# выветренный брус: серо-бурый (рыжую текстуру доски гасим холодным множителем)
	wm.albedo_color = Color(0.78, 0.92, 1.22)
	wm.uv1_triplanar = true
	wm.uv1_world_triplanar = true
	wm.uv1_scale = Vector3(0.9, 0.9, 0.9)
	wm.roughness = 0.95
	var half := Vector2(6.2, 4.4) + Vector2(0.1, 0.1)
	var rr := 1.6 + 0.1
	var box := PackedVector2Array()
	var cs := cos(0.12)
	var sn := sin(0.12)
	for k in 4:
		var cx := (half.x - rr) * (1.0 if k == 0 or k == 3 else -1.0)
		var cz := (half.y - rr) * (1.0 if k < 2 else -1.0)
		for j in 7:
			var a := (k + j / 6.0) * PI * 0.5
			var l := Vector2(cx + cos(a) * rr, cz + sin(a) * rr)
			box.append(Vector2(PLAYGROUND.x + l.x * cs - l.y * sn, PLAYGROUND.z + l.x * sn + l.y * cs))
	# где песочница заходит на дорожку, бруса нет (асфальт рисуется поверх песка)
	_border(box, 0.2, 0.13, wm, func(p: Vector2) -> bool: return ground.sample(Ground.ASPH, p) < 0.3)


## Бортик вдоль замкнутой линии pts (мир x, z, против часовой при взгляде сверху на x→z): сечение w×h над землёй
## (и на 6 см в землю), длинные отрезки дробятся по 0,8 м (верх идёт по рельефу); где skip(середина) — разрыв с торцами
func _border(src: PackedVector2Array, w: float, h: float, mat: Material, skip: Callable) -> void:
	var pts := PackedVector2Array()
	for i in src.size():
		var a := src[i]
		var b := src[(i + 1) % src.size()]
		var k := maxi(1, ceili(a.distance_to(b) / 0.8))
		for j in k:
			pts.append(a.lerp(b, float(j) / k))
	var n := pts.size()
	var outw: Array[Vector2] = []
	var on: Array[bool] = []
	for i in n:
		var t := (pts[(i + 1) % n] - pts[(i - 1 + n) % n]).normalized()
		outw.append(Vector2(t.y, -t.x))
		on.append(not bool(skip.call((pts[i] + pts[(i + 1) % n]) * 0.5)))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quad := func(q: Array, nrm: Vector3) -> void:
		for e in [0, 1, 2, 0, 2, 3]:
			st.set_normal(nrm)
			st.add_vertex(q[e])
	var prof := func(i: int) -> Array:
		var p := pts[i]
		var o := outw[i] * w * 0.5
		var hi := ground.height(p.x - o.x, p.y - o.y)
		var ho := ground.height(p.x + o.x, p.y + o.y)
		var top := maxf(hi, ho) + h
		return [Vector3(p.x - o.x, hi - 0.06, p.y - o.y), Vector3(p.x - o.x, top, p.y - o.y),
			Vector3(p.x + o.x, top, p.y + o.y), Vector3(p.x + o.x, ho - 0.06, p.y + o.y)]
	for i in n:
		if not on[i]:
			continue
		var j := (i + 1) % n
		var a: Array = prof.call(i)
		var b: Array = prof.call(j)
		var o3 := Vector3(outw[i].x, 0.0, outw[i].y)
		quad.call([a[1], a[2], b[2], b[1]], Vector3.UP)
		quad.call([a[2], a[3], b[3], b[2]], o3)
		quad.call([a[0], a[1], b[1], b[0]], -o3)
		var tg := Vector3(pts[j].x - pts[i].x, 0.0, pts[j].y - pts[i].y).normalized()
		if not on[(i - 1 + n) % n]:
			quad.call([a[0], a[1], a[2], a[3]], -tg)
		if not on[j]:
			quad.call([b[0], b[1], b[2], b[3]], tg)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	if mat is BaseMaterial3D:
		(mat as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)


## Днём фонари не горят: светящийся плафон → матовое стекло
func _lamp_off(n: Node) -> void:
	for ch in n.get_children():
		var mi := ch as MeshInstance3D
		if mi == null:
			continue
		var sm := mi.material_override as StandardMaterial3D
		if sm != null and sm.emission_enabled:
			var g := StandardMaterial3D.new()
			g.albedo_color = Color(0.82, 0.8, 0.72)
			g.roughness = 0.25
			g.rim_enabled = false
			mi.material_override = g


func _people(rng: RandomNumberGenerator) -> void:
	var m := path_pts.size()
	var jog := Human.make("jogger", 11, false)
	add_child(jog)
	jog.pose_name = "run"
	people.append([jog, "loop", {"i": float(m / 3), "speed": 3.2}])
	var mom := Human.make("mother", 12, false)
	add_child(mom)
	var st := Node3D.new()
	Props._stroller(st)
	_to_std(st)
	mom.add_child(st)
	st.position = Vector3(0, 0, 0.75)
	st.rotation.y = PI
	mom.pose_name = "walk"
	mom.anim_speed = 0.7
	people.append([mom, "loop", {"i": float(m * 2 / 3), "speed": -0.95, "push": true}])
	var kid := Human.make("kid", 13, false)
	add_child(kid)
	kid.position = ground.at(Vector3(-20, 0, -3))
	kid.rotation.y = 2.6
	# шарик на нитке: узел шарика — конец нитки (в кулаке), сам шарик над ним; держится «вверх» в мире
	var bal := Node3D.new()
	Props._balloon(bal)
	_to_std(bal)
	kid.hold(bal, "r", Vector3(0, -0.07, 0.02))
	kid.pose("hold_up")
	people.append([kid, "idle", {"balloon": bal}])
	var old := Human.make("oldman", 14, false)
	add_child(old)
	var b0 := path_pts[(3 + m * 4 / 10) % m]
	var b1 := path_pts[(4 + m * 4 / 10) % m]
	var side := (b1 - b0).cross(Vector3.UP).normalized()
	old.position = ground.at(b0 + side * 2.2)
	old.rotation.y = atan2(-side.x, -side.z)
	old.pose("read")
	_newspaper.call_deferred(old)
	people.append([old, "idle", {}])
	var couple_a := Human.make("couple", 15, false)
	add_child(couple_a)
	couple_a.position = ground.at(Vector3(19.5, 0, -10.2))
	couple_a.rotation.y = 0.9
	couple_a.pose("sit_ground")
	var couple_b := Human.make("civ_b", 16, false)
	add_child(couple_b)
	couple_b.position = ground.at(Vector3(20.5, 0, -9.6))
	couple_b.rotation.y = -2.1
	couple_b.pose("sit_ground")
	people.append([couple_a, "idle", {}])
	people.append([couple_b, "idle", {}])
	var suit := Human.make("suit", 17, false)
	add_child(suit)
	suit.pose_name = "walk"
	var bc := MeshInstance3D.new()
	var bcm := BoxMesh.new()
	bcm.size = Vector3(0.42, 0.3, 0.09)
	bc.mesh = bcm
	var bcmat := StandardMaterial3D.new()
	bcmat.albedo_color = Color(0.25, 0.14, 0.07)
	bc.material_override = bcmat
	suit.hand("r").add_child(bc)
	bc.position = Vector3(0, -0.2, 0)
	people.append([suit, "cross", {"a": Vector3(-50, 0, 20), "b": Vector3(50, 0, -25), "t": 0.3, "speed": 1.35}])
	var vendor := Human.make("vendor", 18, false)
	add_child(vendor)
	vendor.position = ground.at(Vector3(8.6, 0, 7.4))
	vendor.rotation.y = 2.4
	vendor.pose("stand")
	people.append([vendor, "idle", {}])
	var teen := Human.make("teen", 19, false)
	add_child(teen)
	var t0 := path_pts[(3 + m * 7 / 10) % m]
	var t1 := path_pts[(4 + m * 7 / 10) % m]
	var side2 := (t1 - t0).cross(Vector3.UP).normalized()
	teen.position = ground.at(t0 - side2 * 2.2)
	teen.rotation.y = atan2(side2.x, side2.z)
	teen.pose("sit")
	people.append([teen, "idle", {}])


## Газета старика: развёрнутый лист с изгибом по сгибу, держится обеими руками перед лицом. Ставится, когда
## поза уже применена к скелету (руки на месте): ширина — по расстоянию между кистями, края — в кулаках
func _newspaper(old: Human) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(old):
		return
	var hl := old.to_local(old.hand("l").global_position)
	var hr := old.to_local(old.hand("r").global_position)
	var w := clampf(hl.distance_to(hr) + 0.1, 0.44, 0.6)
	var h := w * 0.72
	var paper := MeshInstance3D.new()
	paper.mesh = _sheet_mesh(w, h)
	var pm := StandardMaterial3D.new()
	pm.albedo_texture = Mats.tex("park_newspaper")
	pm.roughness = 0.9
	pm.backlight_enabled = true
	pm.backlight = Color(0.25, 0.24, 0.22)
	paper.material_override = pm
	paper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	old.add_child(paper)
	# лицевая (внутренняя) сторона смотрит на старика (+z — вперёд у человека), верх чуть от него
	var mid := (hl + hr) * 0.5
	paper.position = Vector3(mid.x, mid.y + h * 0.18, mid.z + 0.03)
	paper.rotation = Vector3(-0.22, PI, 0.0)


## Лист газеты w×h: две половины под углом (сгиб посередине), углы чуть провисают. Внутренняя сторона (+z) —
## нижняя половина текстуры, внешняя (−z) — верхняя, отражённая, чтобы снаружи первая полоса была справа
func _sheet_mesh(w: float, h: float) -> ArrayMesh:
	var nx := 12
	var ny := 5
	var mesh := ArrayMesh.new()
	for side in 2:
		var v := PackedVector3Array()
		var n := PackedVector3Array()
		var uv := PackedVector2Array()
		var idx := PackedInt32Array()
		var sg := 1.0 if side == 0 else -1.0
		for j in ny + 1:
			for i in nx + 1:
				var u := float(i) / nx
				var vv := float(j) / ny
				var x := (u - 0.5) * w
				var ax := absf(x) / (w * 0.5)
				var z := absf(x) * 0.32 - ax * ax * (1.0 - vv) * 0.025
				var y := (0.5 - vv) * h - ax * ax * 0.02
				v.append(Vector3(x, y, z - sg * 0.0015))
				n.append(Vector3(-signf(x) * 0.31 * sg, 0.0, sg).normalized())
				if side == 0:
					uv.append(Vector2(u, lerpf(792.0, 1536.0, vv) / 1536.0))
				else:
					uv.append(Vector2(1.0 - u, lerpf(0.0, 744.0, vv) / 1536.0))
		for j in ny:
			for i in nx:
				var a := j * (nx + 1) + i
				if side == 0:
					idx.append_array([a, a + 1, a + nx + 1, a + 1, a + nx + 2, a + nx + 1])
				else:
					idx.append_array([a, a + nx + 1, a + 1, a + 1, a + nx + 1, a + nx + 2])
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


func _skyline(rng: RandomNumberGenerator) -> void:
	Far.build(self, rng)


## Материалы предметов (шейдер Комплекса) → обычные освещаемые
func _to_std(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var sm := mi.material_override as ShaderMaterial
		if sm != null:
			if not _std_cache.has(sm):
				var m := StandardMaterial3D.new()
				var c: Variant = sm.get_shader_parameter("color")
				var col := Color(1, 1, 1)
				if c is Vector3:
					col = Color((c as Vector3).x, (c as Vector3).y, (c as Vector3).z)
				elif c is Color:
					col = c
				m.albedo_color = col
				var tm: Variant = sm.get_shader_parameter("tex_mix")
				var tx: Variant = sm.get_shader_parameter("tex")
				# слабая примесь текстуры (эмаль, пластик: «metal» ~0,35) в шейдере Комплекса — лишь оттенок; как альбедо
				# она превращает белую эмаль в крапчатый «камень», поэтому берём только явные текстуры (дерево, ткань)
				if tm != null and float(tm) > 0.5 and tx is Texture2D:
					m.albedo_texture = tx
				var ac: Variant = sm.get_shader_parameter("alpha_cut")
				if tx is Texture2D and tx == Mats.tex("leaves"):
					# крона сплошная, без дыр: светлые пятна текстуры — светлая листва, тёмные — тень
					m.albedo_color = Color(0.52, 0.68, 0.34)
					ac = null
				if ac != null and float(ac) > 0.0:
					m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					m.alpha_scissor_threshold = float(ac)
					m.cull_mode = BaseMaterial3D.CULL_DISABLED
				var em: Variant = sm.get_shader_parameter("emit")
				if em != null and float(em) > 0.0:
					m.emission_enabled = true
					var ec: Variant = sm.get_shader_parameter("emit_color")
					m.emission = Color((ec as Vector3).x, (ec as Vector3).y, (ec as Vector3).z) if ec is Vector3 else col
					m.emission_energy_multiplier = float(em) * 0.5
				m.roughness = 0.85
				var uvs: Variant = sm.get_shader_parameter("uv_scale")
				if uvs is Vector2:
					m.uv1_scale = Vector3((uvs as Vector2).x, (uvs as Vector2).y, 1)
				_std_cache[sm] = m
			mi.material_override = _std_cache[sm]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for ch in n.get_children():
		_to_std(ch)


# ------------------------------------------------------------ кадр

func _process(dt: float) -> void:
	t += dt
	var m := path_pts.size()
	for e in people:
		var h: Human = e[0]
		var kind: String = e[1]
		var d: Dictionary = e[2]
		if kind == "loop":
			var sp: float = d.speed
			var i0 := int(d.i)
			var a := path_pts[i0 % m]
			var b := path_pts[(i0 + 1) % m]
			var side := (b - a).cross(Vector3.UP).normalized()
			var fwd := (b - a).normalized() * signf(sp)
			var p := a.lerp(b, float(d.i) - i0)
			var av := _avoid(d, p, fwd, side, 0.55 if sp > 0 else -0.55, absf(sp) * 0.62 * a.distance_to(b), dt)
			d.i = fposmod(float(d.i) + sp * dt * 0.62 * (1.0 - wrong * 0.85) * av.y, float(m))
			i0 = int(d.i)
			a = path_pts[i0 % m]
			b = path_pts[(i0 + 1) % m]
			p = a.lerp(b, float(d.i) - i0)
			side = (b - a).cross(Vector3.UP).normalized()
			h.position = p + side * av.x
			var dir := (b - a).normalized() * signf(sp) * av.y + side * float(d.get("off_v", 0.0)) * 0.6
			if dir.length() > 0.05:
				h.rotation.y = lerp_angle(h.rotation.y, atan2(dir.x, dir.z), clampf(dt * 6.0, 0.0, 1.0))
			h.anim_speed = (1.0 if sp > 0 else 0.7) * (1.0 - wrong * 0.9) * maxf(av.y, 0.15)
		elif d.has("balloon"):
			# шарик тянет нитку вверх и чуть по ветру, покачивается
			var bn: Node3D = d.balloon
			var sw := Vector2(0.1 + sin(t * 0.83) * 0.07, sin(t * 0.61 + 1.3) * 0.08) * _wind
			bn.global_basis = Basis(Vector3.RIGHT, sw.y) * Basis(Vector3.BACK, -sw.x) * Basis(Vector3.UP, sin(t * 0.4) * 0.5)
		elif kind == "cross":
			var pa: Vector3 = d.a
			var pb: Vector3 = d.b
			var fwd2 := (pb - pa).normalized()
			var side2 := fwd2.cross(Vector3.UP).normalized()
			var av2 := _avoid(d, pa.lerp(pb, float(d.t)), fwd2, side2, 0.0, float(d.speed), dt)
			d.t = fposmod(float(d.t) + dt * float(d.speed) / 110.0 * (1.0 - wrong * 0.9) * av2.y, 1.0)
			h.position = ground.at(pa.lerp(pb, float(d.t)) + side2 * av2.x)
			var dir2 := fwd2 * av2.y + side2 * float(d.get("off_v", 0.0)) * 0.6
			if dir2.length() > 0.05:
				h.rotation.y = lerp_angle(h.rotation.y, atan2(dir2.x, dir2.z), clampf(dt * 6.0, 0.0, 1.0))
			h.anim_speed = (1.0 - wrong * 0.9) * maxf(av2.y, 0.15)
	# «что-то не так»: после минуты стихают птицы и ветер, проступает гул ламп
	var near_spot := player.global_position.distance_to(spot) if player != null else 99.0
	var ramp_start := fall_at - 25.0
	wrong = clampf((t - ramp_start) / 25.0, 0.0, 1.0)
	wrong = maxf(wrong, clampf(1.0 - (near_spot - 2.0) / 14.0, 0.0, 1.0) * 0.9)
	Snd.loop_vol("park_amb", 0.85 * (1.0 - wrong * 0.85), 0.5)
	Snd.loop("park_hum", "hum_fluor", wrong * 0.55, 0.5)
	if not falling:
		Snd.loop_vol("park_wind", 0.5 * (1.0 - wrong * 0.6), 2.0)
	_birds_cd -= dt
	if _birds_cd <= 0.0 and wrong < 0.5:
		_birds_cd = randf_range(1.5, 5.0)
		Snd.play("bird", randf_range(-22.0, -12.0), randf_range(0.9, 1.15), "Amb")
	if Game.main != null and not falling:
		Game.main.interference = wrong * 0.25
		if randf() < wrong * dt * 0.8:
			Game.main.burst(0.3 + wrong * 0.5)
	if _env != null:
		_env.adjustment_saturation = _sat - wrong * 0.35
	# ветер стихает вместе со звуком: листья и трава замирают
	var w := 1.0 - wrong * 0.85
	if absf(w - _wind) > 0.002:
		_wind = w
		for wm in _wind_mats:
			(wm as ShaderMaterial).set_shader_parameter("wind", _wind)
	if not falling and Game.gen_ready() and (t >= fall_at or (near_spot < 1.6 and t > 8.0)):
		_fall()


## Обход героя: человек не проходит сквозь камеру — заранее отходит в сторону, вплотную — останавливается и ждёт.
## p — точка на его «рельсе», fwd — куда идёт, side — поперёк, base_off — обычное смещение от рельса, speed — м/с.
## Возвращает (смещение поперёк, доля скорости 0..1); состояние — в d (off, off_v, go)
func _avoid(d: Dictionary, p: Vector3, fwd: Vector3, side: Vector3, base_off: float, speed: float, dt: float) -> Vector2:
	var off: float = d.get("off", base_off)
	var go: float = d.get("go", 1.0)
	var want := base_off
	var want_go := 1.0
	if player != null and not falling:
		var rel := player.global_position - p
		rel.y = 0.0
		var ahead := rel.dot(fwd)
		var lat := rel.dot(side)
		var reach := 0.85 if bool(d.get("push", false)) else 0.0    # коляска впереди
		var look := speed * 2.4 + 2.5 + reach
		if ahead > -0.7 and ahead < look and absf(lat - base_off) < 1.7:
			var l1 := lat - 1.5
			var l2 := lat + 1.5
			want = clampf(l1 if absf(l1) < absf(l2) else l2, -2.8, 2.8)
		# обойти не успел — остановиться
		if ahead > -0.3 and ahead < 1.5 + reach and absf(lat - off) < 0.95:
			want_go = 0.0
	var ov: float = d.get("off_v", 0.0)
	ov = move_toward(ov, clampf((want - off) * 2.5, -1.4, 1.4), dt * 4.0)
	off += ov * dt
	go = move_toward(go, want_go, dt * (3.5 if want_go < go else 1.2))
	d.off = off
	d.off_v = ov
	d.go = go
	return Vector2(off, go)


func _fall() -> void:
	falling = true
	Game.say("sub.fall")
	Snd.play("glitch", -2.0)
	if Game.main != null:
		Game.main.burst(1.0)
	await get_tree().create_timer(0.25).timeout
	# земля под ногами расходится: провал с рваной кромкой, под ним — тёмный колодец
	var c := player.global_position
	_open_hole(Vector3(c.x, ground.height(c.x, c.z), c.z))
	await get_tree().create_timer(0.35).timeout
	# героя затягивает вниз; сам он уже ничего не решает
	player.collision_mask = 0
	player.frozen = true
	player.velocity = Vector3(0, -2.0, 0)
	Snd.loop_vol("park_amb", 0.0, 0.2)
	Snd.loop_vol("park_wind", 0.0, 0.2)
	Snd.stop_loop("park_hum", 0.3)
	Snd.play("fall_whoosh", 0.0)
	# объектив проходит кромку: срыв записи
	await get_tree().create_timer(0.3).timeout
	if Game.main != null:
		Game.main.burst(0.9)
	await get_tree().create_timer(0.6).timeout
	Game.main.set_fade(Color(0, 0, 0, 1))
	Snd.stop_loop("park_amb", 0.1)
	Snd.stop_loop("park_wind", 0.1)
	Snd.set_reverb(0.55, 0.18)
	await get_tree().create_timer(0.6).timeout
	Game.fall_from_park()


## Радиус провала по направлению a (как park_hole_r в park_ground.gdshaderinc)
static func hole_r(a: float, r: float, w: float) -> float:
	return r * (1.0 + 0.13 * sin(3.0 * a + w) + 0.07 * sin(7.0 * a + w * 2.3) + 0.04 * sin(13.0 * a + w * 0.7))


## Провал в точке c: дыра в земле и траве (шейдеры), под ней колодец из сырой земли, уходящий в черноту.
## Радиус растёт от нуля — кромка «расползается» из-под ног
func _open_hole(c: Vector3) -> void:
	var w := randf() * TAU
	_hole = Vector4(c.x, c.z, 0.0, w)
	_pit = _pit_mesh(c, 0.01, w)
	add_child(_pit)
	Snd.play("branches", -10.0, 0.6)
	var tw := create_tween()
	tw.tween_method(_set_hole_r, 0.0, HOLE_R, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _set_hole_r(r: float) -> void:
	_hole.z = r
	var mats: Array = ground.wind_mats.duplicate()
	if _ground_mi != null:
		mats.append(_ground_mi.material_override)
	for m in mats:
		(m as ShaderMaterial).set_shader_parameter("park_hole", _hole)
	if _pit != null:
		# меш пересобирается под текущий радиус: верх стенок всё время точно по рельефу (масштаб его бы перекосил)
		_pit.mesh = _pit_arrays(_pit.position, maxf(r, 0.01), _hole.w)


## Колодец под провалом: MeshInstance3D в точке c с мешем стенок для радиуса r
func _pit_mesh(c: Vector3, r: float, w: float) -> MeshInstance3D:
	# солнце внутрь колодца не попадает (земля теней не отбрасывает) — свет запечён в цвет вершин
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = Mats.tex("park_dirt")
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.position = c
	mi.mesh = _pit_arrays(c, r, w)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4.0
	return mi


## Стенки колодца: кольца по форме кромки, верх — по рельефу; к глубине стенки темнеют до черноты, дно закрыто.
## Над стенками — «юбка» под дёрном: от кромки наружу на 0,35 м чуть ниже земли. Земля у провала — тонкая
## плоскость, отрезанная по кривой park_hole_r; где хорда меша или верх стенки не совпадают с кривой, в щели
## видна тёмная юбка, а не небо под землёй (раньше по всей кромке шла белая нитка)
func _pit_arrays(c: Vector3, r: float, w: float) -> ArrayMesh:
	var seg := 96
	# отрицательные «глубины» — юбка: [вынос наружу, м; опускание под землю, м]
	var lip := [[0.35, 0.05], [0.12, 0.03]]
	var depths := [0.0, 0.06, 0.18, 0.4, 0.8, 1.4, 2.3, 3.6, 5.5, 8.0, 11.0]
	var rings := lip.size() + depths.size()
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	for k in rings:
		var out := 0.0
		var dep := 0.0
		var below := 0.025
		if k < lip.size():
			out = float(lip[k][0]) * minf(r / HOLE_R, 1.0)
			below = float(lip[k][1])
		else:
			dep = float(depths[k - lip.size()])
		var last := k == rings - 1
		var shrink := 1.0 - 0.06 * smoothstep(0.1, 3.0, dep) - (0.97 if last else 0.0)
		# дёрн и сырая земля у кромки в тени, ниже — чернота (юбка — как верх стенки)
		var lum := 0.22 * exp(-dep * 2.6) + 0.015 * exp(-dep * 0.6)
		for s in seg + 1:
			var a := float(s) / seg * TAU
			var dir := Vector3(cos(a), 0.0, sin(a))
			# стенки только сужаются книзу: нависаний (и изнанки стенок) сверху не видно
			var rr := hole_r(a, r, w) * shrink + out
			var o := dir * rr
			var top := ground.height(c.x + o.x, c.z + o.z) - c.y - below
			v.append(Vector3(o.x, top - dep, o.z))
			n.append(Vector3.UP if k < lip.size() else -dir)
			uv.append(Vector2(a * HOLE_R / 1.1, (dep + below - out) / 1.1))
			col.append(Color(lum, lum * 0.93, lum * 0.85))
	var row := seg + 1
	for k in rings - 1:
		for s in seg:
			var a0 := k * row + s
			idx.append_array([a0, a0 + 1, a0 + row, a0 + 1, a0 + row + 1, a0 + row])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh
