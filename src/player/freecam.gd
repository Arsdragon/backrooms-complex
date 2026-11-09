class_name FreeCam
extends Camera3D
## Свободная камера: летает сквозь стены. WASD — двигаться, Пробел / Ctrl — вверх / вниз, Shift — быстрее.
## Герой (если есть) стоит на месте; по G камера возвращается к нему.

const SPEED := 4.5

var yaw := 0.0
var pitch := 0.0
var _mouse := Vector2.ZERO


func _ready() -> void:
	near = 0.05
	far = 160.0
	fov = Cfg.fov


## Встать туда же, куда смотрит другая камера
func copy_from(t: Transform3D) -> void:
	global_position = t.origin
	var fwd := -t.basis.z
	yaw = atan2(-fwd.x, -fwd.z)
	pitch = asin(clampf(fwd.y, -1.0, 1.0))
	rotation = Vector3(pitch, yaw, 0.0)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse += (e as InputEventMouseMotion).relative


func _process(dt: float) -> void:
	var s := 0.0022 * Cfg.sens
	yaw -= _mouse.x * s
	pitch -= _mouse.y * s * (-1.0 if Cfg.invert_y else 1.0)
	pitch = clampf(pitch, deg_to_rad(-89.0), deg_to_rad(89.0))
	_mouse = Vector2.ZERO
	rotation = Vector3(pitch, yaw, 0.0)
	var inp := Input.get_vector("move_l", "move_r", "move_f", "move_b")
	var up := (1.0 if Input.is_action_pressed("fly_up") else 0.0) - (1.0 if Input.is_action_pressed("crouch") else 0.0)
	var v := global_transform.basis * Vector3(inp.x, 0.0, inp.y) + Vector3.UP * up
	if v.length() > 1.0:
		v = v.normalized()
	var sp := SPEED * (3.0 if Input.is_action_pressed("run") else 1.0)
	global_position += v * sp * dt
	fov = lerpf(fov, Cfg.fov, dt * 3.0)
