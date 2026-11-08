class_name Complex
extends Node3D
## Сцена Комплекса: подгрузка чанков вокруг игрока, два слоя, глобальные параметры шейдеров, звук гудения,
## «экспозиция» камеры, монстры и выходы.

const LD := preload("res://src/world/layer_data.gd")
const CB := preload("res://src/world/chunk_builder.gd")
const Props := preload("res://src/world/props.gd")

const LOAD_R := 2
const UNLOAD_R := 3

var layers: Array = []          # LayerData
var cur := 0                    # текущий слой
var player: Player
var demo := false               # фон меню: камера без игрока
var demo_cam: Camera3D
var chunks := {}                # Vector3i(cx, cz, layer) -> {node, body, shapes, cell_light, flick}
var pending := {}               # Vector3i -> task id
var results := {}               # Vector3i -> Dictionary (готово, ждёт создания узлов)
var _mutex := Mutex.new()
var env: WorldEnvironment
var t := 0.0
var flick := [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
var _flick_state := []
var gain := 1.0
var interference := 0.0
var dim := Vector4(0, -1000, 0, 0)
var null_pts: Array = []        # [Vector3, layer]
var entities: Array = []
var listeners: Array = []       # объекты с методом hear(pos, radius)
var near_null := 99.0
var cam_light := Vector4(0, -1000, 0, 0)
var ended := false
var spawn_hook: Callable


func _ready() -> void:
	env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0, 0, 0)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.0
	e.tonemap_white = 3.0
	e.glow_enabled = true
	e.glow_intensity = 0.55
	e.glow_strength = 1.0
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 1.05
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.set_glow_level(0, 0.0)
	e.set_glow_level(1, 1.0)
	e.set_glow_level(2, 0.6)
	e.set_glow_level(3, 0.4)
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.12
	e.adjustment_contrast = 1.04
	env.environment = e
	add_child(env)
	for i in 8:
		_flick_state.append({"t": randf_range(1.0, 10.0), "burst": 0.0, "off": 0.0})


func setup(layer_list: Array, start_layer: int, start_pos: Vector3, start_yaw: float, is_demo := false) -> void:
	layers = layer_list
	cur = start_layer
	demo = is_demo
	for i in layers.size():
		var L: LayerData = layers[i]
		for k in L.places.keys():
			if String(k).begins_with("null_"):
				var p: Vector3 = L.places[k]
				null_pts.append([p, i])
	if demo:
		demo_cam = Camera3D.new()
		demo_cam.fov = 62.0
		demo_cam.far = 120.0
		add_child(demo_cam)
		demo_cam.position = start_pos + Vector3(0, 1.6, 0)
		demo_cam.rotation.y = start_yaw
		demo_cam.current = true
	else:
		player = Player.new()
		add_child(player)
		player.global_position = start_pos
		player.set_look(start_yaw, 0.0)
		player.surface_fn = surface_at
		player.noise_fn = make_noise
	_sync_load(_focus_pos())


func _focus_pos() -> Vector3:
	if demo:
		return demo_cam.global_position
	return player.global_position


func layer() -> LayerData:
	return layers[cur]


# ------------------------------------------------------------ чанки

func _chunk_of(p: Vector3) -> Vector2i:
	var s := LD.C * LD.CHUNK
	return Vector2i(int(floor(p.x / s)), int(floor(p.z / s)))


func _sync_load(p: Vector3, r := LOAD_R) -> void:
	# первая загрузка — сразу (за кадром идёт затемнение)
	var c := _chunk_of(p)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var key := Vector3i(c.x + dx, c.y + dz, cur)
			if chunks.has(key):
				continue
			var res := CB.build(layers[cur], key.x, key.y)
			_make_chunk(key, res)


func _stream(p: Vector3) -> void:
	var c := _chunk_of(p)
	# заявки на постройку: сначала ближние
	var want := []
	for dz in range(-LOAD_R, LOAD_R + 1):
		for dx in range(-LOAD_R, LOAD_R + 1):
			want.append(Vector3i(c.x + dx, c.y + dz, cur))
	want.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return absi(a.x - c.x) + absi(a.y - c.y) < absi(b.x - c.x) + absi(b.y - c.y))
	var started := 0
	for k in want:
		var key: Vector3i = k
		if chunks.has(key) or pending.has(key):
			continue
		if pending.size() >= 3 or started >= 2:
			break
		var L: LayerData = layers[key.z]
		var tid := WorkerThreadPool.add_task(_build_task.bind(key, L))
		pending[key] = tid
		started += 1
	# готовые — создаём узлы (по одному за кадр, чтобы не дёргалось)
	var done := []
	for key in pending.keys():
		if WorkerThreadPool.is_task_completed(pending[key]):
			WorkerThreadPool.wait_for_task_completion(pending[key])
			done.append(key)
	for key in done:
		pending.erase(key)
	var made := 0
	_mutex.lock()
	var ready_keys := results.keys()
	_mutex.unlock()
	for k in ready_keys:
		if made >= 1:
			break
		var key: Vector3i = k
		_mutex.lock()
		var res: Dictionary = results[key]
		results.erase(key)
		_mutex.unlock()
		if key.z != cur or chunks.has(key):
			continue
		_make_chunk(key, res)
		made += 1
	# выгрузка дальних
	for k in chunks.keys():
		var key: Vector3i = k
		if key.z != cur or absi(key.x - c.x) > UNLOAD_R or absi(key.y - c.y) > UNLOAD_R:
			_free_chunk(key)


func _build_task(key: Vector3i, L: LayerData) -> void:
	var res := CB.build(L, key.x, key.y)
	_mutex.lock()
	results[key] = res
	_mutex.unlock()


func _make_chunk(key: Vector3i, res: Dictionary) -> void:
	var n := Node3D.new()
	n.name = "ch_%d_%d_%d" % [key.x, key.y, key.z]
	add_child(n)
	var mesh := ArrayMesh.new()
	var surf: Dictionary = res.surf
	for mid in surf.keys():
		var s: Dictionary = surf[mid]
		if (s.v as PackedVector3Array).is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = s.v
		arr[Mesh.ARRAY_NORMAL] = s.n
		arr[Mesh.ARRAY_TEX_UV] = s.uv
		arr[Mesh.ARRAY_COLOR] = s.c
		arr[Mesh.ARRAY_TEX_UV2] = s.uv2
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, Mats.arch(int(mid)))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(body, get_world_3d().space)
	PhysicsServer3D.body_set_collision_layer(body, 1)
	PhysicsServer3D.body_set_collision_mask(body, 0)
	var shapes := []
	for b in res.boxes:
		var bb: Array = b
		var sh := PhysicsServer3D.box_shape_create()
		PhysicsServer3D.shape_set_data(sh, bb[1])
		PhysicsServer3D.body_add_shape(body, sh, Transform3D(Basis(), bb[0]))
		shapes.append(sh)
	chunks[key] = {"node": n, "body": body, "shapes": shapes, "cell_light": res.cell_light}
	Props.spawn_all(self, n, res.deco, key.z)


func _free_chunk(key: Vector3i) -> void:
	var ch: Dictionary = chunks[key]
	(ch.node as Node).queue_free()
	PhysicsServer3D.free_rid(ch.body)
	for s in ch.shapes:
		PhysicsServer3D.free_rid(s)
	chunks.erase(key)


func _exit_tree() -> void:
	for key in pending.keys():
		WorkerThreadPool.wait_for_task_completion(pending[key])
	pending.clear()
	for key in chunks.keys():
		var ch: Dictionary = chunks[key]
		PhysicsServer3D.free_rid(ch.body)
		for s in ch.shapes:
			PhysicsServer3D.free_rid(s)
	chunks.clear()


func change_layer(new_layer: int, keep_pos: Vector3) -> void:
	for k in chunks.keys():
		_free_chunk(k)
	for key in pending.keys():
		WorkerThreadPool.wait_for_task_completion(pending[key])
	pending.clear()
	_mutex.lock()
	results.clear()
	_mutex.unlock()
	cur = new_layer
	_sync_load(keep_pos, 1)
	for e in entities:
		if is_instance_valid(e) and e.has_method("on_layer_changed"):
			e.on_layer_changed(cur)


# ------------------------------------------------------------ запросы к миру

## Свет в точке: Color(ровный, мигающий, красный, группа) — для предметов и монстров
func light_at(p: Vector3) -> Color:
	var cs := LD.C
	var fx := p.x / cs - 0.5
	var fz := p.z / cs - 0.5
	var x0 := int(floor(fx))
	var z0 := int(floor(fz))
	var tx := fx - x0
	var tz := fz - z0
	var acc := Vector4.ZERO
	var grp := 0.0
	var wsum := 0.0
	for k in 4:
		var x := x0 + (k & 1)
		var z := z0 + (k >> 1)
		var w := (tx if (k & 1) else 1.0 - tx) * (tz if (k >> 1) else 1.0 - tz)
		var v := _cell_light(x, z)
		if v.w < 0.0:
			continue
		acc += Vector4(v.x, v.y, v.z, 0) * w
		wsum += w
		if v.w > 0.0:
			grp = v.w
	if wsum <= 0.0:
		return Color(0, 0, 0, 0)
	acc /= wsum
	return Color(acc.x, acc.y, acc.z, grp)


func _cell_light(x: int, z: int) -> Vector4:
	var cx := int(floor(float(x) / LD.CHUNK))
	var cz := int(floor(float(z) / LD.CHUNK))
	var ch: Dictionary = chunks.get(Vector3i(cx, cz, cur), {})
	if ch.is_empty():
		return Vector4(0, 0, 0, -1)
	var cl: PackedFloat32Array = ch.cell_light
	var i := ((z - cz * LD.CHUNK) * LD.CHUNK + (x - cx * LD.CHUNK)) * 4
	return Vector4(cl[i], cl[i + 1], cl[i + 2], cl[i + 3])


## Видимая яркость с учётом мигания
func brightness_at(p: Vector3) -> float:
	var c := light_at(p)
	var g := int(c.a * 8.0 + 0.5)
	return c.r + c.g * float(flick[clampi(g, 0, 7)]) + c.b * 0.6


func surface_at(p: Vector3) -> String:
	var L := layer()
	var x := int(floor(p.x / LD.C))
	var z := int(floor(p.z / LD.C))
	var i := LD.idx(x, z)
	match L.zone[i]:
		LD.Z_CONCRETE, LD.Z_CELLAR: return "concrete"
		LD.Z_TILE: return "tile"
		LD.Z_HOUSE: return "wood"
		LD.Z_DARK: return "wet" if (x * 31 + z * 17) % 5 < 2 else "carpet"
	return "carpet"


func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / LD.C)), int(floor(p.z / LD.C)))


## Есть ли прямая видимость между точками по сетке (стены блокируют, проёмы — нет)
func line_clear(a: Vector3, b: Vector3) -> bool:
	var L := layer()
	var ca := cell_of(a)
	var cb := cell_of(b)
	var x := ca.x
	var z := ca.y
	var dx := b.x - a.x
	var dz := b.z - a.z
	var stepx := 1 if dx > 0 else -1
	var stepz := 1 if dz > 0 else -1
	var tdx := absf(LD.C / dx) if absf(dx) > 0.0001 else 1e9
	var tdz := absf(LD.C / dz) if absf(dz) > 0.0001 else 1e9
	var nx := ((x + (1 if stepx > 0 else 0)) * LD.C - a.x) / dx if absf(dx) > 0.0001 else 1e9
	var nz := ((z + (1 if stepz > 0 else 0)) * LD.C - a.z) / dz if absf(dz) > 0.0001 else 1e9
	var guard := 0
	while (x != cb.x or z != cb.y) and guard < 64:
		guard += 1
		if nx < nz:
			var d := 0 if stepx > 0 else 2
			var ev := L.edge(x, z, d)
			if ev == LD.E_WALL:
				return false
			if ev == LD.E_DOOR:
				# узкий проём: виден только если луч проходит близко к центру ребра
				var tz2 := a.z + dz * nx
				var mid := (z + 0.5) * LD.C
				if absf(tz2 - mid) > 0.55:
					return false
			x += stepx
			nx += tdx
		else:
			var d2 := 1 if stepz > 0 else 3
			var ev2 := L.edge(x, z, d2)
			if ev2 == LD.E_WALL:
				return false
			if ev2 == LD.E_DOOR:
				var tx2 := a.x + dx * nz
				var mid2 := (x + 0.5) * LD.C
				if absf(tx2 - mid2) > 0.55:
					return false
			z += stepz
			nz += tdz
	return true


## Шум (шаги, падение) — слышат монстры
func make_noise(p: Vector3, radius: float) -> void:
	for l in listeners:
		if is_instance_valid(l):
			l.hear(p, radius)


# ------------------------------------------------------------ кадр

func _process(dt: float) -> void:
	t += dt
	var fp := _focus_pos()
	_stream(fp)
	_update_flicker(dt)
	RenderingServer.global_shader_parameter_set("g_time", t)
	RenderingServer.global_shader_parameter_set("g_flick_a", Vector4(flick[0], flick[1], flick[2], flick[3]))
	RenderingServer.global_shader_parameter_set("g_flick_b", Vector4(flick[4], flick[5], flick[6], flick[7]))
	RenderingServer.global_shader_parameter_set("g_dim", dim)
	RenderingServer.global_shader_parameter_set("g_cam_light", cam_light)
	# ближайшая нулевая зона
	near_null = 99.0
	var np := Vector3(0, -1000, 0)
	for e in null_pts:
		if int(e[1]) != cur:
			continue
		var p: Vector3 = _wrap_near(e[0], fp)
		var d := p.distance_to(fp)
		if d < near_null:
			near_null = d
			np = p
	var nstr := clampf(1.0 - near_null / 22.0, 0.0, 1.0)
	RenderingServer.global_shader_parameter_set("g_null", Vector4(np.x, np.y + 1.2, np.z, nstr * (0.75 + 0.25 * flick[7])))
	# туман и «экспозиция»: яркость вокруг
	var b := 0.0
	var fwd := Vector3.FORWARD
	if player != null:
		fwd = -player.cam.global_transform.basis.z
	elif demo_cam != null:
		fwd = -demo_cam.global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	for k in 4:
		b += brightness_at(fp + fwd * (k * 2.5) + Vector3(0, 1, 0)) * (0.4 if k == 0 else 0.2)
	var target_gain := clampf(0.45 / maxf(b, 0.12), 1.0, 2.3)
	gain = lerpf(gain, target_gain, dt * 0.8)
	var lit := clampf(b, 0.0, 1.2)
	var fogc := Color(0.16, 0.145, 0.085).lerp(Color(0.012, 0.011, 0.01), clampf(1.0 - lit, 0.0, 1.0))
	RenderingServer.global_shader_parameter_set("g_fog", Vector4(fogc.r, fogc.g, fogc.b, lerpf(0.045, 0.03, clampf(lit, 0.0, 1.0))))
	RenderingServer.global_shader_parameter_set("g_ambient", 0.012)
	interference = maxf(clampf((8.0 - near_null) / 8.0, 0.0, 1.0) * 0.8, 0.0)
	if Game.main != null and not ended:
		Game.main.gain = gain
		Game.main.interference = maxf(interference, _ent_interference(fp))
	# гул ламп: громче там, где светло
	if not demo:
		Snd.loop("hum", "hum_fluor", clampf(0.25 + b * 0.6, 0.15, 0.85), 0.8)
		Snd.loop("room", "room_tone", 0.7, 1.0)
		Snd.loop("null", "null_hum", clampf(1.0 - near_null / 16.0, 0.0, 1.0) * 0.9, 0.4, "Amb")


func _ent_interference(_p: Vector3) -> float:
	var m := 0.0
	for e in entities:
		if is_instance_valid(e) and e.has_method("interference"):
			m = maxf(m, float(e.interference()))
	return m


## Ближайшая к опорной точке копия точки на торе
func _wrap_near(p: Vector3, ref: Vector3) -> Vector3:
	var span := LD.N * LD.C
	var q := p
	q.x += round((ref.x - q.x) / span) * span
	q.z += round((ref.z - q.z) / span) * span
	return q


func wrap_near(p: Vector3, ref: Vector3) -> Vector3:
	return _wrap_near(p, ref)


func _update_flicker(dt: float) -> void:
	for g in 7:
		var s: Dictionary = _flick_state[g]
		s.t = float(s.t) - dt
		if float(s.burst) > 0.0:
			s.burst = float(s.burst) - dt
			var on := randf() < 0.55
			flick[g] = (1.0 if on else 0.05) if randf() < 0.6 else float(flick[g])
			if float(s.burst) <= 0.0:
				flick[g] = 1.0 if randf() < 0.85 else 0.0
				if flick[g] == 0.0:
					s.off = randf_range(0.5, 4.0)
		elif float(s.off) > 0.0:
			s.off = float(s.off) - dt
			if float(s.off) <= 0.0:
				flick[g] = 1.0
				s.burst = randf_range(0.1, 0.5)
		elif float(s.t) <= 0.0:
			s.burst = randf_range(0.2, 1.6)
			s.t = randf_range(2.0, 12.0)
	# зелёный свет нулевой зоны — неровная пульсация
	flick[7] = 0.55 + 0.35 * sin(t * 3.1) * sin(t * 7.7 + 1.0) + (0.3 if randf() < 0.04 else 0.0)


# ------------------------------------------------------------ события

## Герой только что провалился из парка: падение, камера лежит на ковре, потом её поднимают
func landing_intro() -> void:
	player.frozen = true
	player.cine = true
	player.head.position = Vector3(0, 1.62, 0)
	Game.main.set_fade(Color(0, 0, 0, 1))
	Game.main.burst(1.0)
	await get_tree().create_timer(0.15).timeout
	Game.main.fade_to(Color(0, 0, 0, 0.0), 0.25)
	# короткое падение с высоты — камера кувыркается
	var tw := create_tween()
	tw.tween_property(player.cam, "rotation", Vector3(-0.9, 0.4, 1.4), 0.55)
	await get_tree().create_timer(0.5).timeout
	Snd.play("body_fall", 0.0)
	Snd.play("camera_drop", -2.0)
	Game.main.burst(1.0)
	player.shake = 1.0
	# камера лежит на боку у самого пола
	player.head.position = Vector3(0.35, 0.12, 0.2)
	player.cam.rotation = Vector3(0.22, 0.6, 1.45)
	Game.main.set_fade(Color(0, 0, 0, 0.55))
	Game.main.fade_to(Color(0, 0, 0, 0.0), 2.5)
	await get_tree().create_timer(3.2).timeout
	Snd.play("cloth", -8.0)
	Game.say("sub.wake")
	var tw2 := create_tween().set_parallel(true)
	tw2.tween_property(player.head, "position", Vector3(0, player.EYE, 0), 1.6).set_trans(Tween.TRANS_SINE)
	tw2.tween_property(player.cam, "rotation", Vector3.ZERO, 1.4).set_trans(Tween.TRANS_SINE)
	await tw2.finished
	player.cine = false
	player.frozen = false
	await get_tree().create_timer(2.5).timeout
	Game.say("sub.wake2")


func climb_ladder(to: String) -> void:
	if player.frozen:
		return
	player.frozen = true
	Game.say("sub.climb")
	Snd.play("ladder", -2.0)
	var tw: Tween = Game.main.fade_to(Color(0, 0, 0, 1), 1.0)
	await tw.finished
	var L0: LayerData = layers[0]
	var key := "winch_cell_" + to.substr(to.length() - 1)
	var c: Vector2i = L0.places.get(key, Vector2i(0, 0))
	var target := Vector3((c.x + 0.5) * LD.C, L0.floor_y + 0.05, (c.y + 0.5) * LD.C)
	target = wrap_near(target, player.global_position)
	change_layer(0, target)
	player.global_position = target
	player.velocity = Vector3.ZERO
	await get_tree().create_timer(0.8).timeout
	Game.main.fade_to(Color(0, 0, 0, 0), 1.0)
	player.frozen = false


func enter_threshold() -> void:
	if ended:
		return
	ended = true
	Game.ending("async")


func enter_null(_id: String) -> void:
	if ended:
		return
	ended = true
	Game.ending("null")


var _bot_path: Array = []
var _bot_i := 0
var _bot_log := 0.0
var _bot_stuck := 0.0
var _bot_last := Vector3.ZERO


## Автотест: бот бродит по Комплексу и пишет в лог состояние мира
func _bot(dt: float) -> void:
	player.bot = true
	var L := layer()
	if _bot_i >= _bot_path.size():
		var me := cell_of(player.global_position)
		var goal := me + Vector2i(randi_range(-25, 25), randi_range(-25, 25))
		_bot_path = Pathfind.find(L, me, goal, 3000)
		_bot_i = 1
	if _bot_i < _bot_path.size():
		var c: Vector2i = _bot_path[_bot_i]
		var wp := Vector3((c.x + 0.5) * LD.C, L.floor_y, (c.y + 0.5) * LD.C)
		var to := wp - player.global_position
		to.y = 0
		if to.length() < 0.6:
			_bot_i += 1
		else:
			var yaw := atan2(-to.x, -to.z)
			player.yaw = lerp_angle(player.yaw, yaw, clampf(dt * 6.0, 0.0, 1.0))
			player.bot_input = Vector2(0, -1)
			player.bot_run = Cfg.has_arg("botrun")
	_bot_stuck += dt
	if _bot_stuck > 4.0:
		if player.global_position.distance_to(_bot_last) < 0.5:
			_bot_path.clear()
		_bot_last = player.global_position
		_bot_stuck = 0.0
	_bot_log += dt
	if _bot_log > 5.0:
		_bot_log = 0.0
		var lf_state := "-"
		var lf_d := -1.0
		for e in entities:
			if e.has_method("interference") and e.get("state") != null:
				lf_state = str(e.get("state"))
				lf_d = (e as Node3D).global_position.distance_to(player.global_position)
		print("BOT t=%.0f fps=%d layer=%d cell=%s chunks=%d pending=%d lf=%s d=%.1f null=%.1f gain=%.2f" % [Game.run_time, Engine.get_frames_per_second(),
			cur, str(cell_of(player.global_position)), chunks.size(), pending.size(), lf_state, lf_d, near_null, gain])


func _physics_process(_dt: float) -> void:
	if player == null or ended:
		return
	if Cfg.has_arg("auto"):
		_bot(_dt)
	# провал в яму верхнего слоя
	if cur == 0 and layers.size() > 1 and player.global_position.y < layer().floor_y - 2.2:
		var p := player.global_position
		Game.main.burst(1.0)
		Game.say("sub.pitfall")
		change_layer(1, p)
		Game.main.set_fade(Color(0, 0, 0, 0.7))
		Game.main.fade_to(Color(0, 0, 0, 0), 1.5)
		await get_tree().create_timer(2.5).timeout
		Game.say("sub.lower")
	# упал куда-то за пределы (страховка)
	if player.global_position.y < layer().floor_y - 30.0:
		var c := cell_of(player.global_position)
		player.global_position = Vector3((c.x + 0.5) * LD.C, layer().floor_y + 1.0, (c.y + 0.5) * LD.C)
		player.velocity = Vector3.ZERO
