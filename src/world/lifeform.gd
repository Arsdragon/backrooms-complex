extends Node3D
## Сущность (Lifeform): высокая, тёмная, из мокрых «лоз», длинные руки, сгорбленная.
## Бродит в темноте, зовёт человеческим голосом, слышит шаги. Рядом с ней лампы гаснут.
## Увидела — бежит, крича. Догнала — красный экран.

const LD := preload("res://src/world/layer_data.gd")

enum S { DORMANT, ROAM, LURE, INVESTIGATE, CHASE, SEARCH, LEAVE }

var cx: Node = null
var state := S.DORMANT
var j := {}
var mat: ShaderMaterial
var eyes: Array = []
var path: Array = []
var path_i := 0
var target := Vector3.ZERO
var last_seen := Vector3.ZERO
var speed := 0.0
var cur_speed := 0.0
var state_t := 0.0
var spawn_cd := 150.0          # первая встреча — не сразу
var repath_t := 0.0
var see_t := 0.0               # сколько видит героя подряд (реакция)
var lost_t := 0.0
var chase_t := 0.0
var scream_cd := 0.0
var sound_cd := 0.0
var step_t := 0.0
var phase := 0.0
var dimv := 0.0
var interf := 0.0
var _twitch := Vector3.ZERO
var _twitch_t := 0.0
var kills := true


func setup(complex: Node) -> void:
	cx = complex
	_build()
	visible = false
	if Cfg.has_arg("lf_now"):
		spawn_cd = 1.0


# ------------------------------------------------------------ тело

static func strands(length: float, radius: float, count: int, twist: float, taper := 0.55) -> ArrayMesh:
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var uvs := PackedVector2Array()
	var rings := maxi(4, int(length / 0.07))
	var sides := 5
	for s in count:
		var ph := s * TAU / count
		var pts := []
		for i in rings + 1:
			var t := float(i) / rings
			var a := ph + twist * TAU * t
			var orb := radius * 0.55 * (1.0 - 0.25 * t)
			var c := Vector3(cos(a) * orb, -length * t, sin(a) * orb)
			var r := radius * 0.5 * lerpf(1.0, taper, t) * (0.8 + 0.2 * sin(t * 19.0 + s * 2.1))
			var ring := []
			for k in sides:
				var b := k * TAU / sides
				var dir := Vector3(cos(b), 0, sin(b))
				ring.append([c + dir * r, dir, Vector2(float(s) / count + float(k) / sides * 0.3, t * length)])
			pts.append(ring)
		for i in rings:
			for k in sides:
				var k2 := (k + 1) % sides
				var q := [pts[i][k], pts[i][k2], pts[i + 1][k2], pts[i + 1][k]]
				var p0: Vector3 = q[0][0]
				var p1: Vector3 = q[1][0]
				var p3: Vector3 = q[3][0]
				var outv: Vector3 = q[0][1]
				var flip := (p1 - p0).cross(p3 - p0).dot(outv) * -1.0 < 0.0
				var order := [0, 1, 2, 0, 2, 3] if not flip else [0, 2, 1, 0, 3, 2]
				for o in order:
					vs.append(q[o][0])
					ns.append(q[o][1])
					uvs.append(q[o][2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	arr[Mesh.ARRAY_TEX_UV] = uvs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _joint(name: String, parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	j[name] = n
	return n


func _limb(parent: Node3D, length: float, radius: float, count: int, twist: float, up := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = strands(length, radius, count, twist)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if up:
		mi.rotation.x = PI
	parent.add_child(mi)
	return mi


func _build() -> void:
	mat = Mats.prop("lifeform", {"tex": "fiber", "tex_mix": 0.8, "color": Vector3(0.035, 0.034, 0.03), "wet": 0.55, "smear": 1.4, "uv_scale": Vector2(1.0, 2.5)})
	var root := _joint("root", self, Vector3.ZERO)
	var pelvis := _joint("pelvis", root, Vector3(0, 1.3, 0))
	var spine := _joint("spine", pelvis, Vector3(0, 0.0, 0))
	_limb(spine, 0.95, 0.34, 6, 0.3, true)
	_limb(spine, 0.7, 0.2, 3, -0.4, true)
	var chest := _joint("chest", spine, Vector3(0, 0.92, 0))
	var neck := _joint("neck", chest, Vector3(0, 0.02, 0.02))
	_limb(neck, 0.36, 0.1, 4, 0.4, true)
	var head := _joint("head", neck, Vector3(0, 0.32, 0))
	var hm := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.1
	sm.height = 0.2
	sm.radial_segments = 10
	sm.rings = 6
	hm.mesh = sm
	hm.material_override = mat
	hm.scale = Vector3(0.85, 1.9, 1.15)
	hm.position = Vector3(0, 0.1, 0.03)
	head.add_child(hm)
	var em := Mats.col(Color(0.9, 0.9, 0.82), "metal", 0.0, {"emit": 1.6, "emit_color": Vector3(0.85, 0.85, 0.75)})
	for s in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		var es := SphereMesh.new()
		es.radius = 0.012
		es.height = 0.024
		es.radial_segments = 6
		es.rings = 3
		e.mesh = es
		e.material_override = em
		e.position = Vector3(0.04 * s, 0.12, 0.13)
		head.add_child(e)
		eyes.append(e)
		e.visible = false
	for s in [-1.0, 1.0]:
		var nm := "l" if s < 0 else "r"
		var sh := _joint("sh_" + nm, chest, Vector3(0.24 * s, -0.04, 0))
		_limb(sh, 0.95, 0.11, 4, 0.35)
		var el := _joint("el_" + nm, sh, Vector3(0, -0.95, 0))
		_limb(el, 0.98, 0.085, 4, 0.45)
		var wr := _joint("wr_" + nm, el, Vector3(0, -0.98, 0))
		for f in 4:
			var fj := Node3D.new()
			wr.add_child(fj)
			fj.rotation = Vector3(randf_range(-0.3, 0.3), 0, (f - 1.5) * 0.18)
			_limb(fj, 0.38, 0.028, 2, 0.3)
	for s in [-1.0, 1.0]:
		var nm2 := "l" if s < 0 else "r"
		var hp := _joint("hip_" + nm2, pelvis, Vector3(0.13 * s, 0, 0))
		_limb(hp, 0.66, 0.15, 4, 0.3)
		var kn := _joint("kn_" + nm2, hp, Vector3(0, -0.66, 0))
		_limb(kn, 0.66, 0.11, 4, 0.4)
		var an := _joint("an_" + nm2, kn, Vector3(0, -0.66, 0))
		var toe := Node3D.new()
		an.add_child(toe)
		toe.rotation.x = -1.35
		_limb(toe, 0.28, 0.06, 3, 0.4)


func _r(n: String, x: float, y := 0.0, z := 0.0) -> void:
	(j[n] as Node3D).rotation = Vector3(x, y, z)


## Поза по состоянию: стоит сгорбившись / крадётся / бежит на четырёх / кричит
func _animate(dt: float) -> void:
	var v := cur_speed
	_twitch_t -= dt
	if _twitch_t <= 0.0:
		_twitch_t = randf_range(0.08, 0.7)
		_twitch = Vector3(randf_range(-0.25, 0.25), randf_range(-0.6, 0.6), randf_range(-0.3, 0.3))
	var running := v > 3.2
	phase += dt * (v * (1.6 if running else 2.4) + 0.2)
	var s := sin(phase)
	var c := cos(phase)
	var pel: Node3D = j["pelvis"]
	if running:
		# бег почти на четвереньках
		pel.position.y = 1.05 + absf(c) * 0.12
		_r("spine", 1.15 + s * 0.08, _twitch.y * 0.2, 0)
		_r("neck", -0.9 + _twitch.x * 0.5, _twitch.y, 0)
		_r("head", -0.3, 0, _twitch.z)
		_r("sh_l", -1.2 + s * 1.1, 0, -0.25)
		_r("sh_r", -1.2 - s * 1.1, 0, 0.25)
		_r("el_l", -0.3 - maxf(0.0, c) * 0.9)
		_r("el_r", -0.3 - maxf(0.0, -c) * 0.9)
		_r("hip_l", -s * 1.0 - 0.3)
		_r("hip_r", s * 1.0 - 0.3)
		_r("kn_l", 0.4 + maxf(0.0, c) * 1.4)
		_r("kn_r", 0.4 + maxf(0.0, -c) * 1.4)
	elif v > 0.2:
		# крадётся: длинные шаги, руки волочатся
		pel.position.y = 1.25 + absf(c) * 0.05
		_r("spine", 0.65 + s * 0.05, s * 0.1, 0)
		_r("neck", -0.35 + _twitch.x * 0.3, _twitch.y * 0.5, 0)
		_r("head", 0.1, 0, _twitch.z * 0.6)
		_r("sh_l", -0.25 + s * 0.35, 0, -0.12)
		_r("sh_r", -0.25 - s * 0.35, 0, 0.12)
		_r("el_l", -0.2)
		_r("el_r", -0.25)
		_r("hip_l", -s * 0.55)
		_r("hip_r", s * 0.55)
		_r("kn_l", maxf(0.0, c) * 0.9 + 0.1)
		_r("kn_r", maxf(0.0, -c) * 0.9 + 0.1)
	else:
		# стоит, покачиваясь, дёргает головой
		var b := sin(state_t * 1.3) * 0.04
		pel.position.y = 1.22 + b * 0.5
		_r("spine", 0.55 + b, 0, b)
		_r("neck", -0.25 + _twitch.x * 0.7, _twitch.y * 1.2, 0)
		_r("head", 0.15, 0, _twitch.z)
		_r("sh_l", -0.1 + b * 2.0, 0, -0.1)
		_r("sh_r", -0.05 - b * 2.0, 0, 0.1)
		_r("el_l", -0.15)
		_r("el_r", -0.1)
		_r("hip_l", 0.1)
		_r("hip_r", -0.1)
		_r("kn_l", 0.25)
		_r("kn_r", 0.2)


# ------------------------------------------------------------ восприятие

func _player() -> Player:
	if cx == null:
		return null
	return cx.get("player")


func hear(p: Vector3, radius: float) -> void:
	if state == S.DORMANT or state == S.LEAVE or state == S.CHASE:
		return
	if global_position.distance_to(p) < radius * 1.15:
		target = p
		if state != S.INVESTIGATE:
			_go(S.INVESTIGATE)
		repath_t = 0.0


func _can_see(pl: Player) -> bool:
	var eye := global_position + Vector3(0, 2.0, 0)
	var pp := pl.global_position + Vector3(0, 1.2, 0)
	var d := eye.distance_to(pp)
	var lit: float = cx.brightness_at(pl.global_position + Vector3(0, 1.0, 0))
	var rng := 9.0 + clampf(lit, 0.0, 1.2) * 14.0
	if state == S.CHASE:
		rng += 8.0
	if d > rng:
		return false
	# замер: если герой стоит неподвижно — замечает только вплотную или на ярком свету рядом
	if pl.still_time > 0.9 and state != S.CHASE and d > 2.4 and not (lit > 0.8 and d < 6.0):
		return false
	if pl.still_time > 1.5 and state == S.CHASE and d > 3.2 and not cx.line_clear(global_position, pl.global_position):
		return false
	# поле зрения
	var fwd := global_transform.basis.z
	var to := (pp - eye)
	to.y = 0
	if d > 3.5 and fwd.dot(to.normalized()) < -0.2:
		return false
	return cx.line_clear(global_position + Vector3(0, 1.0, 0), pl.global_position + Vector3(0, 1.0, 0))


# ------------------------------------------------------------ логика

func _go(s: int) -> void:
	state = s
	state_t = 0.0
	repath_t = 0.0
	path.clear()
	path_i = 0


func interference() -> float:
	return interf


func on_layer_changed(_l: int) -> void:
	_despawn(60.0)


func _despawn(cd: float) -> void:
	state = S.DORMANT
	visible = false
	spawn_cd = cd
	dimv = 0.0


func _spawn() -> bool:
	var pl := _player()
	if pl == null:
		return false
	var L: LayerData = cx.layer()
	var pc: Vector2i = cx.cell_of(pl.global_position)
	var avoid := func(c: Vector2i) -> bool:
		var p := Vector3((c.x + 0.5) * LD.C, L.floor_y, (c.y + 0.5) * LD.C)
		return cx.line_clear(p + Vector3(0, 1, 0), pl.global_position + Vector3(0, 1, 0)) and p.distance_to(pl.global_position) < 30.0
	var c2 := Pathfind.cell_at_path_distance(L, pc, 14, 22, true, avoid)
	if c2.x == 999999:
		return false
	global_position = Vector3((c2.x + 0.5) * LD.C, L.floor_y, (c2.y + 0.5) * LD.C)
	visible = true
	# что будет делать: заманивать из темноты или бродить
	var dark := L.light[LD.idx(c2.x, c2.y)] != LD.L_ON
	_go(S.LURE if (dark and randf() < 0.55) else S.ROAM)
	sound_cd = randf_range(2.0, 5.0)
	if Cfg.has_arg("lf_chase"):
		last_seen = pl.global_position
		_start_chase()
	return true


func _intensity() -> float:
	var t: float = Game.run_time
	var lay: int = cx.cur
	return clampf(0.4 + t / 900.0 + lay * 0.35, 0.4, 1.4)


func _physics_process(dt: float) -> void:
	if cx == null or not is_instance_valid(cx):
		return
	var pl := _player()
	if pl == null or not is_instance_valid(pl) or cx.ended:
		visible = false
		return
	state_t += dt
	if state == S.DORMANT:
		dimv = move_toward(dimv, 0.0, dt)
		cx.dim = Vector4(0, -1000, 0, 0)
		interf = 0.0
		spawn_cd -= dt
		# далёкие крики для атмосферы
		sound_cd -= dt
		if sound_cd <= 0.0 and Game.run_time > 45.0:
			sound_cd = randf_range(40.0, 90.0)
			Snd.play("lf_far", randf_range(-20.0, -12.0), randf_range(0.85, 1.05))
		if spawn_cd <= 0.0:
			if not _spawn():
				spawn_cd = 5.0
		return
	var d := global_position.distance_to(pl.global_position)
	var sees := _can_see(pl)
	if sees:
		see_t += dt
		last_seen = pl.global_position
	else:
		see_t = maxf(0.0, see_t - dt * 0.5)
	match state:
		S.ROAM:
			speed = 1.3
			if path_i >= path.size():
				_wander(pl)
			if see_t > 0.45 or d < 3.0:
				_start_chase()
			elif state_t > 70.0:
				_go(S.LEAVE)
		S.LURE:
			speed = 0.0
			sound_cd -= dt
			if sound_cd <= 0.0:
				sound_cd = randf_range(6.0, 11.0)
				Snd.play_at("lf_lure", global_position + Vector3(0, 1.6, 0), cx, -4.0, randf_range(0.92, 1.05), 45.0, 5.0)
			if see_t > 0.6 or d < 4.5:
				_start_chase()
			elif state_t > 45.0:
				_go(S.ROAM)
		S.INVESTIGATE:
			speed = 2.3
			if see_t > 0.35 or d < 2.5:
				_start_chase()
			elif path_i >= path.size() and state_t > 1.0:
				_go(S.SEARCH)
		S.CHASE:
			chase_t += dt
			speed = 6.1 if chase_t < 2.0 else 4.75 * _intensity() / 1.1
			speed = clampf(speed, 4.4, 6.1)
			target = last_seen
			if sees:
				lost_t = 0.0
			else:
				lost_t += dt
			scream_cd -= dt
			if scream_cd <= 0.0:
				scream_cd = randf_range(2.5, 5.0)
				Snd.play_at("lf_scream", global_position + Vector3(0, 2.0, 0), cx, 2.0, randf_range(0.9, 1.1), 60.0, 6.0)
			if d < 1.25 and kills and not Cfg.has_arg("god"):
				Game.die()
				set_physics_process(false)
				return
			if lost_t > 4.0 or chase_t > 26.0:
				_go(S.SEARCH)
		S.SEARCH:
			speed = 1.8
			if path_i >= path.size():
				_wander(pl, 4)
			if see_t > 0.5:
				_start_chase()
			elif state_t > 14.0:
				_go(S.LEAVE)
		S.LEAVE:
			speed = 2.0
			if path_i >= path.size() or state_t > 25.0 or d > 60.0:
				_despawn(randf_range(70.0, 130.0) / _intensity())
				return
			if see_t > 0.8 and d < 12.0:
				_start_chase()
	_move(dt, pl)
	_animate(dt)
	# свет рядом гаснет, камера шипит
	var target_dim := clampf(1.0 - (d - 4.0) / 16.0, 0.0, 1.0) * (1.0 if state == S.CHASE else 0.8)
	dimv = move_toward(dimv, target_dim, dt * 0.8)
	cx.dim = Vector4(global_position.x, global_position.y + 1.5, global_position.z, dimv)
	interf = clampf(1.0 - d / 12.0, 0.0, 1.0) * (0.55 if state == S.CHASE else 0.3)
	for e in eyes:
		(e as Node3D).visible = state == S.LURE or state == S.CHASE or (d < 8.0)
	var lc: Color = cx.light_at(global_position + Vector3(0, 1.5, 0))
	var lv := Vector4(lc.r, lc.g, lc.b, lc.a) * (1.0 - dimv * 0.7)
	lv.w = lc.a
	_apply_light(self, lv)
	# звуки шагов и дыхания
	step_t -= dt * cur_speed
	if step_t <= 0.0 and cur_speed > 0.3:
		step_t = 1.1 if cur_speed > 3.0 else 1.3
		Snd.play_at("lf_step", global_position, cx, -6.0 if cur_speed > 3.0 else -12.0, randf_range(0.85, 1.15), 35.0, 3.0)
	if state != S.LURE and state != S.CHASE:
		sound_cd -= dt
		if sound_cd <= 0.0:
			sound_cd = randf_range(5.0, 12.0)
			Snd.play_at("lf_breath", global_position + Vector3(0, 2.0, 0), cx, -10.0, randf_range(0.85, 1.1), 25.0, 3.0)


func _start_chase() -> void:
	if state == S.CHASE:
		return
	_go(S.CHASE)
	chase_t = 0.0
	lost_t = 0.0
	scream_cd = 0.0
	if Game.main != null:
		Game.main.burst(0.6)
	Snd.play("sting_chase", -4.0)


func _wander(pl: Player, rad := 10) -> void:
	var L: LayerData = cx.layer()
	var me: Vector2i = cx.cell_of(global_position)
	var pc: Vector2i = cx.cell_of(pl.global_position)
	# бродит, постепенно сближаясь с героем
	var goal := me
	if randf() < 0.6:
		goal = pc + Vector2i(randi_range(-rad, rad), randi_range(-rad, rad))
	else:
		goal = me + Vector2i(randi_range(-rad, rad), randi_range(-rad, rad))
	path = Pathfind.find(L, me, goal, 1500)
	path_i = 1


func _move(dt: float, pl: Player) -> void:
	var L: LayerData = cx.layer()
	repath_t -= dt
	if (state == S.CHASE or state == S.INVESTIGATE or state == S.LEAVE) and repath_t <= 0.0:
		repath_t = 0.45 if state == S.CHASE else 1.5
		var me: Vector2i = cx.cell_of(global_position)
		var goal: Vector2i = cx.cell_of(target)
		if state == S.LEAVE:
			var away := (global_position - pl.global_position)
			away.y = 0
			away = away.normalized() * 40.0
			goal = cx.cell_of(global_position + away)
		path = Pathfind.find(L, me, goal, 2000 if state == S.CHASE else 1200)
		path_i = 1
	var want := Vector3.ZERO
	if state == S.CHASE and cx.line_clear(global_position + Vector3(0, 1, 0), pl.global_position + Vector3(0, 1, 0)) and global_position.distance_to(pl.global_position) < 7.0:
		want = pl.global_position - global_position
	elif path_i < path.size():
		var c: Vector2i = path[path_i]
		var wp := Vector3((c.x + 0.5) * LD.C, L.floor_y, (c.y + 0.5) * LD.C)
		want = wp - global_position
		if Vector2(want.x, want.z).length() < 0.5:
			path_i += 1
	want.y = 0
	var dist := want.length()
	var tgt_speed := speed if dist > 0.05 else 0.0
	cur_speed = move_toward(cur_speed, tgt_speed, dt * 6.0)
	if dist > 0.05:
		var dir := want / dist
		global_position += dir * minf(cur_speed * dt, dist + 0.3)
		var yaw := atan2(dir.x, dir.z)
		rotation.y = lerp_angle(rotation.y, yaw, clampf(dt * 7.0, 0.0, 1.0))
	elif state == S.LURE or state == S.ROAM:
		# смотрит в сторону героя
		var to := pl.global_position - global_position
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), dt * 0.8)
	global_position.y = L.floor_y


static func _apply_light(n: Node, c: Vector4) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).set_instance_shader_parameter("light_level", c)
	for ch in n.get_children():
		_apply_light(ch, c)
