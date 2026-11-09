extends Node3D
## Подвижная копия нижнего слоя: человеческая фигура в чёрной плесени. Идёт, перекрещивая ноги,
## плачет почти по-человечески. Медленная, но не отстаёт. Коснулась — красный экран.

const LD := preload("res://src/world/layer_data.gd")

var cx: Node = null
var body: Human
var active := false
var hunting := false
var path: Array = []
var path_i := 0
var target := Vector3.ZERO
var repath := 0.0
var wail_cd := 4.0
var hunt_t := 0.0
var idle_t := 0.0
var phase := 0.0
var cur_speed := 0.0
var spawn_cd := 30.0
var interf := 0.0
var step_t := 0.0
var extra := false             # вторая копия («Выживание»): появляется позже и в другом месте


func setup(complex: Node) -> void:
	cx = complex
	body = Human.make("civ_c", 913, true)
	add_child(body)
	body.tune({"mold": 0.9, "pale": 0.7, "smear": 2.0, "wet": 0.6})
	body.pose("stand")
	body.scale = Vector3(1.0, 1.08, 1.0)
	visible = false
	if extra:
		spawn_cd = 90.0


func interference() -> float:
	return interf


func on_layer_changed(l: int) -> void:
	active = false
	visible = false
	spawn_cd = (70.0 if extra else (15.0 if Game.survival() else 25.0)) if l == 1 else 9999.0


func hear(p: Vector3, radius: float) -> void:
	if not active:
		return
	if global_position.distance_to(p) < radius * 1.3:
		target = p
		hunting = true
		hunt_t = 0.0


func _spawn() -> bool:
	var L: LayerData = cx.layer()
	var pl: Player = cx.player
	var best := Vector3.ZERO
	var bd := 1e9
	# другие плачущие копии — чтобы не появиться в том же месте
	var others := []
	for e in cx.entities:
		if e != self and is_instance_valid(e) and (e as Node).get_script() == get_script() and bool(e.active):
			others.append((e as Node3D).global_position)
	var near_other := func(p: Vector3) -> bool:
		for o in others:
			if (o as Vector3).distance_to(p) < 18.0:
				return true
		return false
	for k in 3:
		var key := "stalker_%d" % k
		if not L.places.has(key):
			continue
		var p: Vector3 = cx.wrap_near(L.places[key], pl.global_position)
		var d := p.distance_to(pl.global_position)
		if near_other.call(p):
			continue
		if d > 22.0 and d < bd and not cx.line_clear(p + Vector3(0, 1, 0), pl.global_position + Vector3(0, 1, 0)):
			bd = d
			best = p
	if bd > 120.0:
		var c := Pathfind.cell_at_path_distance(L, cx.cell_of(pl.global_position), 12, 20, true)
		if c.x == 999999:
			return false
		best = Vector3((c.x + 0.5) * LD.C, L.floor_y, (c.y + 0.5) * LD.C)
		if near_other.call(best):
			return false
	global_position = best
	active = true
	visible = true
	hunting = false
	return true


func _physics_process(dt: float) -> void:
	if cx == null or cx.ended:
		return
	var pl: Player = cx.player
	if pl == null:
		return
	if cx.cur != 1:
		visible = false
		active = false
		return
	if not active:
		spawn_cd -= dt
		if spawn_cd <= 0.0 and Game.run_time > 30.0:
			if not _spawn():
				spawn_cd = 10.0
		return
	var d := global_position.distance_to(pl.global_position)
	if d > 70.0:
		active = false
		visible = false
		spawn_cd = 20.0
		return
	# видит героя в пределах 12 м (если тот движется)
	if d < 12.0 and (pl.still_time < 1.0 or d < 3.0) and cx.line_clear(global_position + Vector3(0, 1.2, 0), pl.global_position + Vector3(0, 1.2, 0)):
		target = pl.global_position
		hunting = true
		hunt_t = 0.0
	var speed := 0.0
	if hunting:
		hunt_t += dt
		speed = 1.55
		if hunt_t > 40.0:
			hunting = false
	else:
		idle_t += dt
		speed = 0.0 if fmod(idle_t, 14.0) < 6.0 else 0.8
	repath -= dt
	var L: LayerData = cx.layer()
	if repath <= 0.0:
		repath = 0.8
		var goal: Vector2i = cx.cell_of(target if hunting else global_position + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8)))
		path = Pathfind.find(L, cx.cell_of(global_position), goal, 900)
		path_i = 1
	var want := Vector3.ZERO
	if hunting and d < 4.0 and cx.line_clear(global_position + Vector3(0, 1, 0), pl.global_position + Vector3(0, 1, 0)):
		want = pl.global_position - global_position
	elif path_i < path.size():
		var c: Vector2i = path[path_i]
		var wp := Vector3((c.x + 0.5) * LD.C, L.floor_y, (c.y + 0.5) * LD.C)
		want = wp - global_position
		if Vector2(want.x, want.z).length() < 0.4:
			path_i += 1
	want.y = 0
	cur_speed = move_toward(cur_speed, speed if want.length() > 0.05 else 0.0, dt * 2.0)
	if want.length() > 0.05:
		var dir := want.normalized()
		global_position += dir * cur_speed * dt
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), dt * 3.0)
	global_position.y = L.floor_y
	_walk(dt)
	if d < 1.0 and not Cfg.has_arg("god"):
		Game.die()
		set_physics_process(false)
		return
	wail_cd -= dt
	if wail_cd <= 0.0:
		wail_cd = randf_range(5.0, 10.0) if hunting else randf_range(10.0, 20.0)
		Snd.play_at("st_wail", global_position + Vector3(0, 1.6, 0), cx, -2.0, randf_range(0.9, 1.08), 45.0, 4.0)
	step_t -= dt * cur_speed
	if step_t <= 0.0 and cur_speed > 0.2:
		step_t = 0.7
		Snd.play_at("st_step", global_position, cx, -10.0, randf_range(0.9, 1.1), 20.0, 2.5)
	interf = clampf(1.0 - d / 9.0, 0.0, 1.0) * 0.35
	var lc: Color = cx.light_at(global_position + Vector3(0, 1.2, 0))
	_apply(self, Vector4(lc.r, lc.g, lc.b, lc.a))


## Походка «крест-накрест»: ноги перекрещиваются через середину, голова набок
func _walk(dt: float) -> void:
	phase += dt * (cur_speed * 3.4 + 0.4)
	var s := sin(phase)
	var c := cos(phase)
	var b := body
	b._r("hip_l", -s * 0.5, 0, 0.32 * maxf(0.0, s))
	b._r("hip_r", s * 0.5, 0, -0.32 * maxf(0.0, -s))
	b._r("kn_l", maxf(0.0, c) * 0.7)
	b._r("kn_r", maxf(0.0, -c) * 0.7)
	b._r("spine", 0.18 + sin(phase * 0.5) * 0.05, 0, sin(phase) * 0.08)
	b._r("neck", 0.35, 0, 0.55 + sin(phase * 0.3) * 0.1)
	b._r("sh_l", 0.1 + s * 0.15, 0, -0.05)
	b._r("sh_r", 0.1 - s * 0.15, 0, 0.05)
	b._r("el_l", -0.05)
	b._r("el_r", -0.05)


static func _apply(n: Node, c: Vector4) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).set_instance_shader_parameter("light_level", c)
	for ch in n.get_children():
		_apply(ch, c)
