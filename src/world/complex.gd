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
var hurt := 0.0                 # ранение 0..1; 1 — смерть
var _hurt_cd := 0.0             # пауза перед тем, как раны «отпускают»
var _no_fall_t := 0.0           # падение в яму на нижний слой и приземление из парка не ранят
var power := 1.0                # питание ламп (g_power): просадки и редкие отключения
var _power_t := 0.0             # до следующего события с питанием
var _power_ev := ""             # "", "dip", "out", "back"
var _power_left := 0.0
var _power_age := 0.0
var _space_t := 0.0             # пересчёт «размера пространства» для эха
var _room := 0.5
var _wet := 0.15
var _room_target := 0.5
var _wet_target := 0.15
var _amb_t := 30.0              # до следующего далёкого звука


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
		_flick_state.append({"t": randf_range(1.0, 10.0), "burst": 0.0, "off": 0.0, "sw": 0.0, "on": true})


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
		player.landed.connect(_on_landed)
		_no_fall_t = 4.0
	_sync_load(_focus_pos())


func _focus_pos() -> Vector3:
	if demo:
		return demo_cam.global_position
	return player.view_pos()


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
		var bas: Basis = bb[2] if bb.size() > 2 else Basis()
		PhysicsServer3D.body_add_shape(body, sh, Transform3D(bas, bb[0]))
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

## Высота потолка над полом в точке (м)
func ceil_at(p: Vector3) -> float:
	var L := layer()
	var c := cell_of(p)
	var h := L.height_m(c.x, c.y)
	if h <= 0.01:
		return 2.7
	return h - L.fh[LD.idx(c.x, c.y)] * 0.1


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
	if L.water[i] > 0:
		return "wet"
	match L.zone[i]:
		LD.Z_STORE, LD.Z_CLASS: return "tile"
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
	if not demo:
		_hurt_tick(dt)
		_update_power(dt)
		_update_space(dt)
		_ambient_tick(dt)
	elif demo_cam != null:
		# меню: камера медленно осматривается, чуть «дышит»
		demo_cam.rotation.y += sin(t * 0.07) * dt * 0.05
		demo_cam.rotation.x = sin(t * 0.13) * 0.035 - 0.02
		demo_cam.rotation.z = sin(t * 0.09) * 0.012
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
	b *= maxf(power, 0.03)
	var target_gain := clampf(0.45 / maxf(b, 0.12), 1.0, 2.3)
	gain = lerpf(gain, target_gain, dt * 0.8)
	var lit := clampf(b, 0.0, 1.2)
	var fogc := Color(0.16, 0.145, 0.085).lerp(Color(0.012, 0.011, 0.01), clampf(1.0 - lit, 0.0, 1.0))
	RenderingServer.global_shader_parameter_set("g_fog", Vector4(fogc.r, fogc.g, fogc.b, lerpf(0.045, 0.03, clampf(lit, 0.0, 1.0))))
	RenderingServer.global_shader_parameter_set("g_ambient", 0.012 + (1.0 - power) * 0.01)
	interference = maxf(clampf((8.0 - near_null) / 8.0, 0.0, 1.0) * 0.8, 0.0)
	if Game.main != null and not ended:
		Game.main.gain = gain
		Game.main.interference = maxf(interference, _ent_interference(fp))
	# гул ламп: громче там, где светло
	if not demo:
		Snd.loop("hum", "hum_fluor", clampf(0.25 + b * 0.6, 0.15, 0.85) * power * power, 0.25)
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


## Характер группы мигающих ламп: 0 — редкие запинки, 1 — умирающая трубка (гаснет надолго), 2 — гудит и дрожит
const FLICK_KIND := [0, 1, 2, 0, 1, 2, 1]


func _update_flicker(dt: float) -> void:
	for g in 7:
		var s: Dictionary = _flick_state[g]
		var kind: int = FLICK_KIND[g]
		s.t = float(s.t) - dt
		if float(s.burst) > 0.0:
			# заикание: включается-выключается через случайные доли секунды
			s.burst = float(s.burst) - dt
			s.sw = float(s.sw) - dt
			if float(s.sw) <= 0.0:
				s.sw = randf_range(0.03, 0.11) if kind != 1 else randf_range(0.04, 0.26)
				s.on = not bool(s.on) if randf() < 0.8 else bool(s.on)
				flick[g] = randf_range(0.75, 1.0) if bool(s.on) else randf_range(0.0, 0.07)
			if float(s.burst) <= 0.0:
				if kind == 1 and randf() < 0.5:
					s.off = randf_range(1.5, 9.0)
					flick[g] = 0.0
				else:
					flick[g] = 1.0
					s.on = true
		elif float(s.off) > 0.0:
			s.off = float(s.off) - dt
			if float(s.off) <= 0.0:
				# стартер пытается зажечь трубку
				s.burst = randf_range(0.4, 1.4)
				_flick_sound(g, true)
		elif float(s.t) <= 0.0:
			match kind:
				0:
					s.burst = randf_range(0.08, 0.45)
					s.t = randf_range(7.0, 26.0)
				1:
					s.burst = randf_range(0.4, 2.2)
					s.t = randf_range(2.5, 9.0)
				_:
					s.burst = randf_range(0.05, 0.2)
					s.t = randf_range(3.0, 11.0)
			_flick_sound(g, false)
		elif kind == 2:
			flick[g] = 0.8 + 0.1 * sin(t * 13.0 + g) + randf_range(-0.07, 0.07)
		else:
			flick[g] = 1.0
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
	# вход срабатывает в физическом колбэке — сцену меняем после него
	Game.ending.call_deferred("async")


func enter_null(_id: String) -> void:
	if ended:
		return
	ended = true
	Game.ending.call_deferred("null")


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
		var st_n := 0
		for e in entities:
			if e.get("hunting") != null and bool(e.get("active")):
				st_n += 1
		print("BOT t=%.0f fps=%d layer=%d cell=%s chunks=%d pending=%d lf=%s d=%.1f null=%.1f gain=%.2f st=%d/%d" % [Game.run_time, Engine.get_frames_per_second(),
			cur, str(cell_of(player.global_position)), chunks.size(), pending.size(), lf_state, lf_d, near_null, gain, st_n, entities.size()])


func _physics_process(_dt: float) -> void:
	if player == null or ended:
		return
	if Cfg.has_arg("auto"):
		_bot(_dt)
	# провал в яму верхнего слоя
	if cur == 0 and layers.size() > 1 and player.global_position.y < layer().floor_y - 2.2 \
			and layer().flo[LD.idx(cell_of(player.global_position).x, cell_of(player.global_position).y)] == LD.F_PIT:
		var p := player.global_position
		Game.main.burst(1.0)
		Game.say("sub.pitfall")
		_no_fall_t = 8.0
		change_layer(1, p)
		Game.main.set_fade(Color(0, 0, 0, 0.7))
		Game.main.fade_to(Color(0, 0, 0, 0), 1.5)
		await get_tree().create_timer(2.5).timeout
		Game.say("sub.lower")
	# упал куда-то за пределы (страховка)
	if player.global_position.y < layer().floor_y - 40.0:
		var c := cell_of(player.global_position)
		player.global_position = Vector3((c.x + 0.5) * LD.C, layer().floor_y + 1.0, (c.y + 0.5) * LD.C)
		player.velocity = Vector3.ZERO


## Отладка: --tour=<папка> — обойти все «странные комнаты» и снять каждую
func _tour(dir: String) -> void:
	await get_tree().create_timer(1.0).timeout
	var L := layer()
	var keys := []
	for k in L.places.keys():
		if String(k).begins_with(Cfg.arg("tour_prefix", "room_")) and not String(k).ends_with("_c"):
			keys.append(k)
	keys.sort()
	if Cfg.has_arg("only"):
		var only := Cfg.arg("only").split(",")
		keys = keys.filter(func(k: Variant) -> bool:
			for o in only:
				if String(k).contains(o):
					return true
			return false)
	player.bot = false
	for k in keys:
		var p: Vector3 = L.places[k]
		p = wrap_near(p, player.global_position)
		var ctr := p
		if L.places.has(String(k) + "_c"):
			ctr = wrap_near(L.places[String(k) + "_c"], p)
		var hor := Vector3(ctr.x - p.x, 0, ctr.z - p.z)
		var structure := hor.length() > 2.0
		for view in 2:
			if player.freecam != null:
				player.toggle_freecam()
			if String(k).begins_with("find_"):
				# находка: свободной камерой сверху-сбоку, с двух сторон
				player.global_position = p + Vector3(0, 0.1, 0)
				player.velocity = Vector3.ZERO
				player.toggle_freecam()
				var off2 := Vector3(1.7, 1.6, 1.7) if view == 0 else Vector3(-1.7, 1.6, -1.7)
				player.freecam.global_position = p + off2
				player.freecam.look_at(p + Vector3(0, 0.4, 0))
				player.freecam.yaw = player.freecam.rotation.y
				player.freecam.pitch = player.freecam.rotation.x
			elif structure:
				# конструкция: от входа лицом к центру; второй кадр — свободной камерой сверху
				var dirv := hor.normalized()
				player.global_position = p + Vector3(0, 0.1, 0) - dirv * 0.6
				player.velocity = Vector3.ZERO
				player.set_look(atan2(-dirv.x, -dirv.z), -0.12)
				if view == 1:
					player.toggle_freecam()
					player.freecam.global_position = p - dirv * 1.5 + Vector3(0, 4.5, 0)
					player.freecam.look_at(ctr + Vector3(0, -0.5, 0))
					player.freecam.yaw = player.freecam.rotation.y
					player.freecam.pitch = player.freecam.rotation.x
			else:
				var off := Vector3(0, 0.1, 3.0) if view == 0 else Vector3(0, 0.1, -3.0)
				player.global_position = p + off
				player.velocity = Vector3.ZERO
				player.set_look(0.0 if view == 0 else PI, -0.08)
			_sync_load(player.global_position, 1)
			gain = 1.0
			for f in 30:
				await get_tree().process_frame
			await get_tree().create_timer(2.0).timeout
			await RenderingServer.frame_post_draw
			Game.main.screenshot(dir + "/" + String(k) + "_" + str(view) + ".png")
		print("TOUR ", k)
	get_tree().quit()


# ------------------------------------------------------------ ранения

## Приземление: высота падения по скорости (v² = 2gh). До 2,3 м — ничего, дальше кадр краснеет, с ~7 м — смерть
func _on_landed(speed: float) -> void:
	if _no_fall_t > 0.0 or ended:
		return
	var h := speed * speed / (2.0 * Player.GRAV)
	if h < 2.3:
		return
	var dmg := (h - 2.3) / 4.8
	Snd.play("body_fall", -2.0 + minf(dmg * 6.0, 6.0), randf_range(0.9, 1.05))
	if dmg < 1.0:
		Snd.play("grunt", -6.0, randf_range(0.9, 1.05))
	hurt_add(dmg)


## Получить урон: кадр вспыхивает красным, раны отпускают медленно; набралось 1 — смерть
func hurt_add(v: float) -> void:
	hurt += v
	_hurt_cd = 7.0
	Game.main.hurt_flash = clampf(0.5 + v, 0.0, 1.0)
	Game.main.burst(clampf(v, 0.2, 1.0))
	if player != null:
		player.shake = maxf(player.shake, clampf(0.5 + v, 0.0, 1.0))
	if hurt >= 1.0:
		if Cfg.has_arg("god"):
			hurt = 0.92
		else:
			hurt = 1.0
			Game.main.hurt = 1.0
			Game.die()


func _hurt_tick(dt: float) -> void:
	_no_fall_t = maxf(0.0, _no_fall_t - dt)
	if hurt > 0.0:
		_hurt_cd -= dt
		if _hurt_cd <= 0.0:
			hurt = maxf(0.0, hurt - dt * 0.018)
	if Game.main != null and not ended:
		Game.main.hurt = move_toward(Game.main.hurt, hurt, dt * 1.5)


# ------------------------------------------------------------ лампы: звук мигания и питание

## Щелчок/жужжание ближайшей мигающей лампы этой группы (если она рядом с героем)
func _flick_sound(g: int, start: bool) -> void:
	if demo or player == null:
		return
	var L := layer()
	var pc := cell_of(player.global_position)
	var best := Vector2i(999999, 0)
	var bd := 99
	for dz in range(-4, 5):
		for dx in range(-4, 5):
			var x := pc.x + dx
			var z := pc.y + dz
			if L.light[LD.idx(x, z)] != LD.L_FLICK or posmod(x * 7 + z * 13, 7) != g:
				continue
			var d := absi(dx) + absi(dz)
			if d < bd:
				bd = d
				best = Vector2i(x, z)
	if best.x == 999999:
		return
	var c := LD.cell_center(best.x, best.y)
	var p := Vector3(c.x, L.floor_y + L.height_m(best.x, best.y) - 0.1, c.y)
	Snd.play_at("lamp_start" if start else "lamp_buzz", p, self, -8.0, randf_range(0.9, 1.1), 16.0, 2.0)


## Питание: редкие просадки (все лампы проседают и дрожат) и ещё более редкие отключения на несколько секунд
func _update_power(dt: float) -> void:
	if _power_t <= 0.0 and _power_ev == "":
		_power_t = randf_range(120.0, 300.0) if Game.run_time < 60.0 else randf_range(90.0, 260.0)
	if Cfg.has_arg("blackout") and Game.run_time > 3.0 and _power_ev == "" and not has_meta("bo_done"):
		set_meta("bo_done", true)
		_power_t = 0.01
	match _power_ev:
		"":
			power = move_toward(power, 1.0, dt * 2.0)
			_power_t -= dt
			if _power_t <= 0.0 and not ended:
				var out := randf() < (0.4 if Game.survival() else 0.3) or Cfg.has_arg("blackout")
				_power_ev = "out" if out else "dip"
				_power_age = 0.0
				_power_left = randf_range(6.0, 14.0) if out else randf_range(0.5, 1.6)
				Snd.play("power_down" if out else "power_dip", -4.0 if out else -8.0)
				if out:
					Game.main.burst(0.4)
		"dip":
			_power_left -= dt
			power = clampf(0.45 + 0.25 * sin(t * 31.0) + randf_range(-0.15, 0.15), 0.12, 0.9)
			if _power_left <= 0.0:
				_power_ev = ""
				_power_t = 0.0
		"out":
			_power_left -= dt
			_power_age += dt
			# сначала гаснет с запинкой, потом — полная темнота
			if _power_age < 0.7:
				power = randf_range(0.1, 0.8) if randf() < 0.25 else move_toward(power, 0.0, dt * 2.5)
			else:
				power = 0.0
			if _power_left <= 0.0:
				_power_ev = "back"
				_power_age = 0.0
				_power_left = randf_range(1.2, 2.4)
				Snd.play("power_up", -5.0)
		"back":
			_power_left -= dt
			_power_age += dt
			# лампы «схватываются» по очереди: редкие короткие вспышки, потом ровный свет
			if _power_left > 0.5:
				if _power_age > 0.08:
					_power_age = 0.0
					power = randf_range(0.5, 1.0) if randf() < 0.45 else randf_range(0.0, 0.15)
			else:
				power = move_toward(power, 1.0, dt * 3.0)
			if _power_left <= 0.0:
				_power_ev = ""
				_power_t = 0.0
	RenderingServer.global_shader_parameter_set("g_power", power)
	if Cfg.has_arg("blackout") and Engine.get_process_frames() % 30 == 0:
		print("POWER t=%.1f ev=%s p=%.2f left=%.1f" % [Game.run_time, _power_ev, power, _power_left])


# ------------------------------------------------------------ звук пространства

## Эхо по размеру места: сколько клеток вокруг доступно за несколько шагов и как высоко потолок
func _update_space(dt: float) -> void:
	_space_t -= dt
	if _space_t <= 0.0 and player != null:
		_space_t = 0.4
		var L := layer()
		var pc := cell_of(player.global_position)
		var seen := {pc: 0}
		var q := [pc]
		var head := 0
		var hsum := 0.0
		while head < q.size() and q.size() < 260:
			var c: Vector2i = q[head]
			head += 1
			hsum += L.height_m(c.x, c.y) - L.fh[LD.idx(c.x, c.y)] * 0.1
			var dd: int = seen[c]
			if dd >= 7:
				continue
			for d in 4:
				if not LD.edge_passable(L.edge(c.x, c.y, d)) and L.edge(c.x, c.y, d) != LD.E_WINDOW:
					continue
				var nb: Vector2i = c + LD.DIRS[d]
				if seen.has(nb) or L.flo[LD.idx(nb.x, nb.y)] == LD.F_SOLID:
					continue
				seen[nb] = dd + 1
				q.append(nb)
		var n := float(q.size())
		var hh := hsum / maxf(1.0, float(head))
		_room_target = clampf(0.12 + n / 150.0 + (hh - 3.0) * 0.07, 0.08, 0.97)
		_wet_target = clampf(0.05 + n / 520.0 + (hh - 3.0) * 0.045, 0.04, 0.45)
		if hh < 2.2:
			_room_target = 0.06
			_wet_target = 0.04
	_room = move_toward(_room, _room_target, dt * 0.6)
	_wet = move_toward(_wet, _wet_target, dt * 0.4)
	Snd.set_reverb(_room, _wet)


## Далёкие звуки Комплекса: где-то хлопнула дверь, стук, шаги, звонок, лифт — редко и тихо
const FAR_SOUNDS := ["door_open", "knock", "footsteps_above", "impact_far", "phone_ring", "elev_ding", "pipe_knock", "muffled_voices", "lamp_start"]


func _ambient_tick(dt: float) -> void:
	_amb_t -= dt
	if _amb_t > 0.0 or player == null or ended:
		return
	_amb_t = randf_range(28.0, 70.0)
	var a := randf() * TAU
	var p := player.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(16.0, 30.0) + Vector3(0, 1.4, 0)
	var nm: String = FAR_SOUNDS[randi() % FAR_SOUNDS.size()]
	if cur == 1 and randf() < 0.3:
		nm = "muffled_voices"
	Snd.play_at(nm, p, self, randf_range(-14.0, -8.0), randf_range(0.85, 1.0), 45.0, 6.0)
