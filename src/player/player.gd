class_name Player
extends CharacterBody3D
## Герой с видеокамерой в руках. Камера — это «объектив»: покачивание, запаздывание, тряска при беге.

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
	cam.far = 140.0
	cam.fov = Cfg.fov
	head.add_child(cam)
	cam.current = true


func set_look(y: float, p: float) -> void:
	yaw = y
	pitch = p
	rotation.y = yaw
	head.rotation.x = pitch


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse += (e as InputEventMouseMotion).relative


func _physics_process(dt: float) -> void:
	var inp := Vector2.ZERO
	if not frozen:
		inp = Input.get_vector("move_l", "move_r", "move_f", "move_b")
		if bot:
			inp = bot_input
	# взгляд
	if not frozen and not look_locked:
		var s := 0.0022 * Cfg.sens
		yaw -= _mouse.x * s
		pitch -= _mouse.y * s * (-1.0 if Cfg.invert_y else 1.0)
		pitch = clampf(pitch, deg_to_rad(-84.0), deg_to_rad(84.0))
	_mouse = Vector2.ZERO
	rotation.y = yaw
	head.rotation.x = pitch

	var want_crouch := not frozen and Input.is_action_pressed("crouch")
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
	if running:
		spd = RUN
		stamina -= dt / 7.5
		if stamina <= 0.0:
			stamina = 0.0
			exhausted = true
	else:
		stamina = minf(1.0, stamina + dt / (9.0 if inp.length() > 0.1 else 6.0))
	if crouching:
		spd = CROUCH
	spd *= speed_mul
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
	Snd.play("step_" + surf, vol, randf_range(0.92, 1.08), "Sfx")
	if noise_fn.is_valid():
		noise_fn.call(global_position, radius)


func _camera_motion(dt: float, hv: float) -> void:
	if cine:
		return
	bob_t += dt * (hv * 2.1 + 0.001)
	sway_t += dt
	var bob_amt := 0.0
	if Cfg.head_bob:
		bob_amt = clampf(hv / RUN, 0.0, 1.0)
	var by := sin(bob_t * 2.0) * 0.035 * bob_amt + sin(bob_t * 2.0) * 0.03 * (1.0 if running else 0.0)
	var bx := sin(bob_t) * 0.025 * bob_amt
	# «живые руки»: медленное дрожание камеры
	var hx := (sin(sway_t * 0.9) * 0.6 + sin(sway_t * 2.3) * 0.25) * 0.004
	var hy := (sin(sway_t * 0.7 + 1.3) * 0.6 + sin(sway_t * 1.9) * 0.3) * 0.004
	shake = move_toward(shake, 0.0, dt * 1.5)
	var sh := shake * shake
	head.position = Vector3(bx, eye + by, 0)
	cam.rotation = Vector3(hy + randf_range(-1, 1) * sh * 0.05 + by * 0.25,
		hx + randf_range(-1, 1) * sh * 0.05,
		sin(bob_t) * 0.012 * bob_amt + hx * 0.8 + (randf_range(-1, 1) * sh * 0.08))
	cam.fov = lerpf(cam.fov, Cfg.fov + (3.0 if running else 0.0), dt * 3.0)


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
	if frozen:
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
