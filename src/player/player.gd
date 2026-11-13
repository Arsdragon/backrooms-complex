class_name Player
extends CharacterBody3D
## Герой с видеокамерой в руках. Камера — это «объектив»: покачивание, запаздывание, тряска при беге.
## «Камера в руках»: лёгкое пружинное отставание за мышью (большая часть поворота — сразу, остаток догоняет
## с маленьким перелётом), медленный дрейф рук, толчки от шагов, крен при повороте, изредка «дыхание»
## автофокуса (main.defocus + чуть меняется угол зрения).

signal landed(speed: float)

const WALK := 2.3
const RUN := 4.9
const CROUCH := 1.15
const EYE := 1.62
const EYE_CROUCH := 1.0
const GRAV := 14.0

var head: Node3D
var cam: Camera3D
var col: CollisionShape3D
var cap: CapsuleShape3D

var frozen := false            # кат-сцены: ввод отключён
var cine := false              # камерой управляет сцена (не трогать голову/камеру)
var look_locked := false
var yaw := 0.0
var pitch := 0.0
var crouching := false
var running := false
var stamina := 1.0
var exhausted := false
var still_time := 0.0          # сколько секунд стоит неподвижно (Сущность хуже находит)
var step_dist := 0.0
var bob_t := 0.0
var sway_t := 0.0
var shake := 0.0
var fall_speed := 0.0
var air_time := 0.0
var eye := EYE
var surface_fn: Callable       # (pos) -> String: carpet/concrete/tile/wood/grass/wet
var noise_fn: Callable         # (pos, radius) — шум для монстров
var breath := 0.0
var _breath_cd := 0.0
var _land_lock := 0.0
var _mouse := Vector2.ZERO
var interact_hint := ""
var _cur_interact: Node = null
var speed_mul := 1.0
var bot := false               # автотест: ввод задаёт бот
var bot_input := Vector2.ZERO
var bot_run := false
var freecam: FreeCam = null    # свободная камера (G в «Приключении» и полигоне)
var _mantle_t := 0.0           # подтягивание на уступ (идёт, пока > 0)
var _mantle_len := 0.0
var _mantle_from := Vector3.ZERO
var _mantle_to := Vector3.ZERO
var _push_t := 0.0             # сколько упирается вперёд в стену
## Дальняя плоскость камеры, м (сцены могут менять: player.far = 300.0)
var far := 140.0:
	set(v):
		far = v
		if cam != null:
			cam.far = v
# камера в руках
var _aim_prev := Vector2.ZERO  # прошлый (pitch, yaw) — сколько повернули за шаг физики
var _d_aim := Vector2.ZERO
var _lag := Vector2.ZERO       # отставание камеры от взгляда (pitch, yaw), рад
var _lag_v := Vector2.ZERO
var _roll := 0.0               # крен на повороте
var _kick := Vector3.ZERO      # толчки шагов (pitch, yaw, roll), пружина
var _kick_v := Vector3.ZERO
var _step_side := 1.0
var _hand := FastNoiseLite.new()
var _hand_t := 0.0
var _fov_base := 68.0
var _focus_t := 0.0            # до следующего самопроизвольного «поиска» фокуса
var _focus_k := -1.0           # фаза поиска 0..1 (−1 — не ищет)
var _focus_amp := 0.0
var _focus_d := 3.0            # расстояние, на которое наведён фокус
var _focus_check := 0.0
var shadow_body: Node3D = null  # тень оператора на солнце (парк): тело, которое видно только тенью


func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.3
	cap = CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.75
	col = CollisionShape3D.new()
	col.shape = cap
	col.position.y = 0.875
	add_child(col)
	head = Node3D.new()
	head.position.y = EYE
	add_child(head)
	cam = Camera3D.new()
	cam.near = 0.05
	cam.far = far
	cam.fov = Cfg.fov
	head.add_child(cam)
	cam.current = true
	_fov_base = Cfg.fov
	_hand.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hand.seed = randi()
	_hand.frequency = 1.0
	_hand.fractal_octaves = 2
	_focus_t = randf_range(14.0, 30.0)
	# в парке солнце: у человека с камерой в руках есть тень (в Комплексе теней нет — свет без карт теней)
	if Game.state == "park":
		set_shadow_body(true)


## Тень оператора: ноги, туловище, голова и руки, поднятые к камере у лица. Меши только отбрасывают тень —
## в кадре их нет (камера внутри «головы»), но на солнечной траве под ногами видна тень человека с камерой.
func set_shadow_body(on: bool) -> void:
	if not on:
		if shadow_body != null:
			shadow_body.queue_free()
			shadow_body = null
		return
	if shadow_body != null:
		return
	shadow_body = Node3D.new()
	shadow_body.name = "ShadowBody"
	add_child(shadow_body)
	# ноги (чуть врозь), туловище, плечи
	_limb(Vector3(-0.1, 0.06, 0.02), Vector3(-0.11, 0.86, 0.0), 0.075)
	_limb(Vector3(0.1, 0.06, -0.02), Vector3(0.11, 0.86, 0.0), 0.075)
	_limb(Vector3(0.0, 0.92, 0.02), Vector3(0.0, 1.38, 0.03), 0.17, Vector3(1.2, 1.0, 0.7))
	_limb(Vector3(-0.19, 1.4, 0.03), Vector3(0.19, 1.4, 0.03), 0.07)
	# шея и голова (камера героя — у глаз, перед лицом)
	_limb(Vector3(0.0, 1.42, 0.04), Vector3(0.0, 1.52, 0.05), 0.055)
	var h := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.105
	hs.height = 0.24
	h.mesh = hs
	h.position = Vector3(0.0, 1.62, 0.06)
	_shadow_only(h)
	# руки: плечо → локоть (вниз и вперёд) → кисти у камеры
	for sx: float in [-1.0, 1.0]:
		var sh := Vector3(0.21 * sx, 1.39, 0.03)
		var el := Vector3(0.24 * sx, 1.2, -0.14)
		var hd := Vector3(0.08 * sx, 1.5, -0.2)
		_limb(sh, el, 0.05)
		_limb(el, hd, 0.045)
	# видеокамера в руках
	var cm := MeshInstance3D.new()
	var bx := BoxMesh.new()
	bx.size = Vector3(0.11, 0.13, 0.26)
	cm.mesh = bx
	cm.position = Vector3(0.03, 1.58, -0.17)
	_shadow_only(cm)


## Отрезок тела капсулой от a до b (радиус r, sc — сплющить поперёк: x/z)
func _limb(a: Vector3, b: Vector3, r: float, sc := Vector3.ONE) -> void:
	var m := MeshInstance3D.new()
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = a.distance_to(b) + r * 2.0
	c.radial_segments = 10
	c.rings = 3
	m.mesh = c
	var y := (b - a).normalized()
	var x := Vector3.FORWARD.cross(y)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	m.transform = Transform3D(Basis(x * sc.x, y * sc.y, z * sc.z), (a + b) * 0.5)
	_shadow_only(m)


func _shadow_only(m: MeshInstance3D) -> void:
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	m.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	shadow_body.add_child(m)


func set_look(y: float, p: float) -> void:
	yaw = y
	pitch = p
	rotation.y = yaw
	head.rotation.x = pitch
	# телепорт взгляда — не «дёргать» пружину камеры
	_aim_prev = Vector2(pitch, yaw)
	_lag = Vector2.ZERO
	_lag_v = Vector2.ZERO


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and freecam == null:
		_mouse += (e as InputEventMouseMotion).relative
	if e.is_action_pressed("freecam") and Game.freecam_ok() and (freecam != null or not frozen):
		toggle_freecam()
		get_viewport().set_input_as_handled()


func toggle_freecam() -> void:
	if freecam != null:
		freecam.queue_free()
		freecam = null
		cam.current = true
		Snd.play("ui_move", -10.0)
		return
	freecam = FreeCam.new()
	get_parent().add_child(freecam)
	freecam.copy_from(cam.global_transform)
	freecam.current = true
	Snd.play("ui_click", -10.0)


## Откуда сейчас смотрит камера (для подгрузки мира)
func view_pos() -> Vector3:
	if freecam != null and is_instance_valid(freecam):
		return freecam.global_position
	return global_position


func _physics_process(dt: float) -> void:
	var inp := Vector2.ZERO
	var fc := freecam != null
	if not frozen and not fc:
		inp = Input.get_vector("move_l", "move_r", "move_f", "move_b")
		if bot:
			inp = bot_input
	# взгляд
	if not frozen and not look_locked and not fc:
		var s := 0.0022 * Cfg.sens
		yaw -= _mouse.x * s
		pitch -= _mouse.y * s * (-1.0 if Cfg.invert_y else 1.0)
		pitch = clampf(pitch, deg_to_rad(-84.0), deg_to_rad(84.0))
	_mouse = Vector2.ZERO
	rotation.y = yaw
	head.rotation.x = pitch
	_d_aim = Vector2(pitch, yaw) - _aim_prev
	_aim_prev = Vector2(pitch, yaw)

	# подтягивание на уступ: короткая анимация вместо обычного движения
	if _mantle_t > 0.0:
		_mantle_t -= dt
		var k := clampf(1.0 - _mantle_t / _mantle_len, 0.0, 1.0)
		var up := smoothstep(0.0, 0.6, k)
		var fw := smoothstep(0.45, 1.0, k)
		global_position = Vector3(lerpf(_mantle_from.x, _mantle_to.x, fw), lerpf(_mantle_from.y, _mantle_to.y + 0.05, up), lerpf(_mantle_from.z, _mantle_to.z, fw))
		velocity = Vector3.ZERO
		fall_speed = 0.0
		air_time = 0.0
		eye = move_toward(eye, EYE - 0.35 * sin(k * PI), dt * 4.0)
		_camera_motion(dt, 0.0)
		return
	var want_crouch := not frozen and ((Input.is_action_pressed("crouch") and not fc) or Cfg.has_arg("crouch") or (fc and crouching))
	if crouching and not want_crouch:
		# встать можно, только если над головой есть место
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.3, 0), global_position + Vector3(0, 1.85, 0), 1)
		q.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			want_crouch = true
	crouching = want_crouch
	var want_run := not frozen and (Input.is_action_pressed("run") or (bot and bot_run)) and inp.y < -0.1 and not crouching
	if exhausted and stamina > 0.35:
		exhausted = false
	running = want_run and not exhausted and is_on_floor()
	var spd := WALK
	# выносливость есть только в «Выживании» (и в полигоне по флажку)
	var stam_on := Game.stamina_on()
	if running:
		spd = RUN
		if stam_on:
			stamina -= dt / 7.5
			if stamina <= 0.0:
				stamina = 0.0
				exhausted = true
	else:
		stamina = minf(1.0, stamina + dt / (9.0 if inp.length() > 0.1 else 6.0))
	if not stam_on:
		stamina = 1.0
		exhausted = false
	if crouching:
		spd = CROUCH
	spd *= speed_mul * Game.speed_mode()
	if _land_lock > 0.0:
		_land_lock -= dt
		spd *= 0.35

	var dir := (transform.basis * Vector3(inp.x, 0, inp.y))
	dir.y = 0
	if dir.length() > 1.0:
		dir = dir.normalized()
	var target := dir * spd
	var acc := 9.0 if is_on_floor() else 1.5
	velocity.x = move_toward(velocity.x, target.x, acc * dt * maxf(spd, 2.0))
	velocity.z = move_toward(velocity.z, target.z, acc * dt * maxf(spd, 2.0))
	if not is_on_floor():
		velocity.y -= GRAV * dt
		air_time += dt
		fall_speed = maxf(fall_speed, -velocity.y)
	var was_air := not is_on_floor()
	move_and_slide()
	# упёрся в уступ по грудь — подтянуться
	if is_on_floor() and is_on_wall() and inp.y < -0.5 and not frozen and freecam == null:
		_push_t += dt
		if _push_t > 0.22:
			_push_t = 0.0
			_try_mantle()
	else:
		_push_t = 0.0
	if is_on_floor():
		if was_air and air_time > 0.25:
			landed.emit(fall_speed)
			if fall_speed > 6.0:
				shake = 1.0
				_land_lock = 0.8
				if noise_fn.is_valid():
					noise_fn.call(global_position, 18.0)
		air_time = 0.0
		fall_speed = 0.0

	# высота глаз (присед)
	var target_eye := EYE_CROUCH if crouching else EYE
	eye = move_toward(eye, target_eye, dt * 3.0)
	cap.height = 1.75 if not crouching else 1.2
	col.position.y = cap.height * 0.5
	if shadow_body != null:
		shadow_body.scale = Vector3(1.0, eye / EYE, 1.0)

	# неподвижность
	var hv := Vector2(velocity.x, velocity.z).length()
	if hv < 0.15 and is_on_floor():
		still_time += dt
	else:
		still_time = 0.0

	# шаги и шум
	if is_on_floor() and hv > 0.4:
		step_dist += hv * dt
		var stride := 0.75 if not running else 1.05
		if crouching:
			stride = 0.6
		if step_dist >= stride:
			step_dist = 0.0
			_footstep()
	_camera_motion(dt, hv)
	_breathing(dt)
	_interact_scan()


## Есть ли впереди уступ высотой 0,45–1,6 м с местом для героя сверху
func _try_mantle() -> void:
	var fwd := -transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var space := get_world_3d().direct_space_state
	var top := global_position + Vector3(0, 1.8, 0) + fwd * 0.62
	var q := PhysicsRayQueryParameters3D.create(top, top - Vector3(0, 1.45, 0), 1)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var hp: Vector3 = hit.position
	var hn: Vector3 = hit.normal
	var hy := hp.y - global_position.y
	if hy < 0.45 or hy > 1.62 or hn.y < 0.8:
		return
	# уступ не узкий (не перила): пол есть и чуть дальше
	var q2 := PhysicsRayQueryParameters3D.create(top + fwd * 0.3, top + fwd * 0.3 - Vector3(0, 1.45, 0), 1)
	q2.exclude = [get_rid()]
	var hit2 := space.intersect_ray(q2)
	if hit2.is_empty() or absf((hit2.position as Vector3).y - hp.y) > 0.15:
		return
	# над краем и над головой свободно
	for probe in [global_position + Vector3(0, 0.3, 0), hp + fwd * 0.15 + Vector3(0, 0.05, 0)]:
		var pv: Vector3 = probe
		var qu := PhysicsRayQueryParameters3D.create(pv, pv + Vector3(0, hy + 1.75 if pv.y < hp.y else 1.75, 0), 1)
		qu.exclude = [get_rid()]
		if not space.intersect_ray(qu).is_empty():
			return
	_mantle_from = global_position
	_mantle_to = hp + fwd * 0.2
	_mantle_len = 0.5 + hy * 0.35
	_mantle_t = _mantle_len
	Snd.play("cloth", -8.0, randf_range(0.9, 1.1))
	if hy > 1.0:
		Snd.play("grunt", -12.0, randf_range(0.95, 1.1))


func _footstep() -> void:
	var surf := "carpet"
	if surface_fn.is_valid():
		surf = String(surface_fn.call(global_position))
	var vol := -9.0
	var radius := 9.0
	if running:
		vol = -3.0
		radius = 22.0
	elif crouching:
		vol = -19.0
		radius = 2.5
	Snd.play("step_" + surf, vol, randf_range(0.92, 1.08), "World")
	if noise_fn.is_valid():
		noise_fn.call(global_position, radius)
	# толчок камеры от шага: чуть вниз и вбок, попеременно (только с включённым покачиванием)
	if Cfg.head_bob:
		var s := 1.0 if running else (0.4 if crouching else 0.65)
		_step_side = -_step_side
		_kick_v += Vector3(-0.07 * s, 0.025 * s * _step_side, 0.045 * s * _step_side)


func _camera_motion(dt: float, hv: float) -> void:
	if cine:
		return
	bob_t += dt * (hv * 2.1 + 0.001)
	sway_t += dt
	var bob_amt := 0.0
	if Cfg.head_bob:
		bob_amt = clampf(hv / RUN, 0.0, 1.0)
	var by := sin(bob_t * 2.0) * 0.035 * bob_amt + sin(bob_t * 2.0) * 0.03 * (1.0 if running and Cfg.head_bob else 0.0)
	var bx := sin(bob_t) * 0.025 * bob_amt
	# 1) отставание за мышью: камера «весит» — догоняет взгляд пружиной с лёгким перелётом.
	#    Видна только часть отставания (45%): поворот ощущается сразу, без «ваты».
	var da := _d_aim.clamp(Vector2(-0.25, -0.25), Vector2(0.25, 0.25))
	_d_aim = Vector2.ZERO
	_lag -= da
	_lag = _lag.limit_length(0.06)
	var w := 24.0
	_lag_v += (-w * w * _lag - 2.0 * 0.62 * w * _lag_v) * dt
	_lag += _lag_v * dt
	var lag := _lag * 0.45
	# 2) крен при повороте: рука с камерой чуть заваливается в сторону поворота
	var yaw_rate := da.y / maxf(dt, 0.001)
	_roll = lerpf(_roll, clampf(yaw_rate * 0.0045, -0.03, 0.03), minf(1.0, dt * 6.0))
	# 3) «живые руки»: медленный дрейф и мелкий тремор; на ходу и на бегу — сильнее
	_hand_t += dt
	var amp := 1.0 + clampf(hv / RUN, 0.0, 1.0) * 0.9 + (0.7 if running else 0.0)
	if crouching:
		amp *= 0.8
	var hx := (_hand.get_noise_2d(_hand_t * 0.22, 0.0) * 0.0055 + _hand.get_noise_2d(_hand_t * 1.3, 40.0) * 0.0009) * amp
	var hy := (_hand.get_noise_2d(_hand_t * 0.19, 100.0) * 0.0065 + _hand.get_noise_2d(_hand_t * 1.1, 140.0) * 0.0009) * amp
	var hr := _hand.get_noise_2d(_hand_t * 0.15, 200.0) * 0.006 * amp
	# 4) толчки шагов — затухающая пружина
	_kick_v += (-190.0 * _kick - 2.0 * 0.55 * 13.8 * _kick_v) * dt
	_kick += _kick_v * dt
	# 5) автофокус: изредка «ищет» (и когда резко сменилось расстояние до того, на что смотрим)
	var breath_fov := _autofocus(dt)
	shake = move_toward(shake, 0.0, dt * 1.5)
	var sh := shake * shake
	head.position = Vector3(bx, eye + by, 0)
	cam.rotation = Vector3(hx + lag.x + _kick.x + randf_range(-1, 1) * sh * 0.05 + by * 0.25,
		hy + lag.y + _kick.y + randf_range(-1, 1) * sh * 0.05,
		sin(bob_t) * 0.012 * bob_amt + hr + _roll + _kick.z + (randf_range(-1, 1) * sh * 0.08))
	_fov_base = lerpf(_fov_base, Cfg.fov + (3.0 if running else 0.0), dt * 3.0)
	cam.fov = _fov_base + breath_fov


## Поиск автофокуса: картинка на долю секунды «плывёт» (main.defocus), угол зрения чуть дышит. Возвращает добавку к fov.
func _autofocus(dt: float) -> float:
	_focus_check -= dt
	_focus_t -= dt
	if _focus_check <= 0.0 and freecam == null:
		_focus_check = 0.35
		var d := _focus_probe()
		# фокус перескакивает, когда расстояние меняется в разы (стена вплотную ↔ даль коридора)
		if _focus_k < 0.0 and absf(log(d / _focus_d)) > 1.1 and _focus_t < 26.0:
			_start_focus(clampf(absf(log(d / _focus_d)) * 0.25, 0.25, 0.55))
		_focus_d = d
	if _focus_k < 0.0 and _focus_t <= 0.0:
		_start_focus(randf_range(0.2, 0.38))
	if _focus_k < 0.0:
		return 0.0
	_focus_k += dt / 0.75
	if _focus_k >= 1.0:
		_focus_k = -1.0
		return 0.0
	var k := _focus_k
	var blur := sin(k * PI) * (0.75 + 0.25 * sin(k * PI * 3.0)) * _focus_amp
	if Game.main != null:
		Game.main.defocus = maxf(float(Game.main.defocus), blur)
	return sin(k * PI * 2.0) * (1.0 - k) * 0.55 * _focus_amp


func _start_focus(amp: float) -> void:
	_focus_k = 0.0
	_focus_amp = amp
	_focus_t = randf_range(25.0, 55.0)


## Расстояние до того, что в центре кадра (для автофокуса)
func _focus_probe() -> float:
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * 30.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return 30.0
	return maxf(0.3, from.distance_to(hit.position))


func _breathing(dt: float) -> void:
	var target := 0.0
	if running:
		target = 0.7
	if exhausted:
		target = 1.0
	breath = move_toward(breath, maxf(target, 1.0 - stamina), dt * 0.3)
	_breath_cd -= dt
	if breath > 0.35 and _breath_cd <= 0.0:
		_breath_cd = lerpf(2.4, 1.0, breath)
		Snd.play("breath_heavy", lerpf(-20.0, -8.0, breath), randf_range(0.95, 1.05))


func _interact_scan() -> void:
	interact_hint = ""
	_cur_interact = null
	if frozen or freecam != null:
		return
	var space := get_world_3d().direct_space_state
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * 2.2
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2)
	q.collide_with_areas = true
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var n: Object = hit.collider
	var node := n as Node
	while node != null and not node.has_meta("interact"):
		node = node.get_parent()
	if node == null:
		return
	_cur_interact = node
	interact_hint = Loc.t(String(node.get_meta("hint", "ui.use")))


func try_interact() -> bool:
	if _cur_interact == null or not is_instance_valid(_cur_interact):
		return false
	var cb: Callable = _cur_interact.get_meta("interact")
	if cb.is_valid():
		cb.call()
		return true
	return false
