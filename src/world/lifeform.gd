extends Node3D
## Сущность (Lifeform): высокая, тёмная, из мокрых «лоз», длинные руки, сгорбленная.
## Бродит в темноте, зовёт человеческим голосом, слышит шаги. Рядом с ней лампы гаснут.
## Увидела — бежит, крича. Догнала — красный экран.

const LD := preload("res://src/world/layer_data.gd")
const P := preload("res://src/world/props.gd")

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
	if Game.survival():
		spawn_cd = 95.0
	if Cfg.has_arg("lf_now"):
		spawn_cd = 1.0


# ------------------------------------------------------------ тело

static func strands(length: float, radius: float, count: int, twist: float, taper := 0.55) -> ArrayMesh:
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var uvs := PackedVector2Array()
	var rings := maxi(4, int(length / 0.07))
	# 7 граней: при попиксельном свете пятигранник читался «карандашом»; кольцо на 1 вершину длиннее —
	# у шва своя вершина с u = 1, текстура не сжимается в одну грань
	var sides := 7
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
			for k in sides + 1:
				var b := k * TAU / sides
				var dir := Vector3(cos(b), 0, sin(b))
				ring.append([c + dir * r, dir, Vector2(float(s) / count + float(k) / sides * 0.3, t * length)])
			pts.append(ring)
		for i in rings:
			for k in sides:
				var k2 := k + 1
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


## Кость-конечность вниз по −y от сустава: тонкая, с утолщением у суставов (мыщелки), чуть кривая —
## гладкая труба (без граней и щелей), волокнистая кожа даёт карта нормалей
func _limb(parent: Node3D, length: float, radius: float, _count := 0, twist := 0.0, up := false) -> MeshInstance3D:
	var pts := PackedVector3Array()
	var rr := PackedFloat32Array()
	var segs := maxi(8, int(length / 0.06))
	var ph := twist * 7.0 + length * 3.0
	for i in segs + 1:
		var t := float(i) / segs
		# профиль: сустав — узел, середина — тоньше, к концу сужается
		var knob := exp(-pow(t / 0.12, 2.0)) * 0.55 + exp(-pow((1.0 - t) / 0.1, 2.0)) * 0.35
		var r := radius * (0.62 - 0.18 * t + knob) * (1.0 + 0.06 * sin(t * 17.0 + ph))
		pts.append(Vector3(sin(t * 4.0 + ph) * radius * 0.25, -length * t, cos(t * 3.0 + ph) * radius * 0.2))
		rr.append(r)
	# закруглённые концы
	var p2 := PackedVector3Array([pts[0] + Vector3(0, rr[0] * 0.8, 0)])
	var r2 := PackedFloat32Array([0.0])
	p2.append_array(pts)
	r2.append_array(rr)
	p2.append(pts[pts.size() - 1] - Vector3(0, rr[rr.size() - 1] * 0.8, 0))
	r2.append(0.0)
	var mi := MeshInstance3D.new()
	mi.mesh = P.loft(p2, r2, r2, 12)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if up:
		mi.rotation.x = PI
	parent.add_child(mi)
	return mi


func _part(parent: Node3D, m: Mesh, pos := Vector3.ZERO, rot := Vector3.ZERO, sc := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = sc
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Сущность: измождённый высокий силуэт — узкий таз, впалый живот, выпирающая грудная клетка с рёбрами
## и хребтом, длинная тонкая шея, вытянутый череп с провалами глазниц и отвисшей челюстью, очень длинные
## костлявые руки с длинными пальцами-когтями. Кожа — тёмная, матовая с влажным отливом, волокнистая
## (fiber + карта нормалей); с плеч и спины свисают мокрые волокна. Суставы — мыщелки, без щелей.
## Близко к камере тело растворяется точками (near_cut) — ближняя плоскость его не режет
func _build() -> void:
	# кожа: почти чёрная, сажево-матовая, волокнистая (мелкие частые волокна — сильная карта нормалей), лишь
	# лёгкий влажный отлив; вершины колышутся сильнее (контур «дрожит»), а не гладкий резиновый шланг
	mat = Mats.prop("lifeform_v3", {"tex": "fiber", "tex_mix": 0.85, "color": Vector3(0.03, 0.027, 0.024), "wet": 0.14, "smear": 1.05,
		"uv_scale": Vector2(2.5, 7.0), "nmap": Mats.tex("fiber_n"), "bump": 2.4, "gloss": 10.0, "spec": 0.025, "near_cut": 0.42})
	var root := _joint("root", self, Vector3.ZERO)
	var pelvis := _joint("pelvis", root, Vector3(0, 1.3, 0))
	var spine := _joint("spine", pelvis, Vector3(0, 0.0, 0))
	# торс вверх от таза: таз — талия-провал — грудная клетка — плечи — основание шеи
	var ys := [-0.1, -0.02, 0.08, 0.2, 0.32, 0.45, 0.58, 0.7, 0.8, 0.88, 0.94, 0.98]
	var rx := [0.07, 0.14, 0.13, 0.085, 0.082, 0.13, 0.16, 0.165, 0.15, 0.12, 0.06, 0.0]
	var rz := [0.06, 0.1, 0.085, 0.06, 0.07, 0.11, 0.125, 0.115, 0.09, 0.07, 0.05, 0.0]
	var cz := [0.0, -0.01, -0.005, -0.03, -0.02, 0.01, 0.025, 0.02, 0.0, -0.01, -0.01, -0.01]
	var tp := PackedVector3Array()
	var ta := PackedFloat32Array()
	var tb := PackedFloat32Array()
	for i in ys.size():
		tp.append(Vector3(0, ys[i], cz[i]))
		ta.append(rx[i])
		tb.append(rz[i])
	_part(spine, P.loft(tp, ta, tb, 18))
	# рёбра: тонкие дуги поверх грудной клетки, хребет — бугорки по спине
	for k in 6:
		var y := 0.46 + k * 0.065
		var rr: float = 0.15 - absf(k - 2.5) * 0.012
		for sd in [-1.0, 1.0]:
			var pts := PackedVector3Array()
			var rad := PackedFloat32Array()
			for i in 7:
				var a := lerpf(-1.35, 1.25, float(i) / 6.0)
				pts.append(Vector3(sd * sin(a + 1.4) * rr * 1.04, y - 0.04 * float(i) / 6.0, -cos(a + 1.4) * rr * 0.78 + 0.02))
				rad.append(0.011 * (1.0 - float(i) / 8.0))
			_part(spine, P.loft(pts, rad, rad, 6))
	for k2 in 10:
		var yk := 0.1 + k2 * 0.085
		_part(spine, P.blob_mesh(0.022, 0.2, k2, Vector3(1.2, 0.8, 1.0), 12), Vector3(0, yk, -0.075 - 0.02 * sin(yk * 3.0)))
	var chest := _joint("chest", spine, Vector3(0, 0.92, 0))
	var neck := _joint("neck", chest, Vector3(0, 0.02, 0.02))
	_limb(neck, 0.36, 0.07, 0, 0.4, true)
	var head := _joint("head", neck, Vector3(0, 0.32, 0))
	# череп: вытянутый, затылок назад; глазницы — тёмные провалы; челюсть отвисла
	_part(head, P.blob_mesh(0.1, 0.12, 31, Vector3(0.78, 1.55, 1.08), 20, 2.0), Vector3(0, 0.12, 0.0))
	var sock := Mats.prop("lifeform_sock", {"tex": "noise", "tex_mix": 0.0, "color": Vector3(0.0, 0.0, 0.0), "near_cut": 0.42})
	for s in [-1.0, 1.0]:
		var sk := _part(head, P.blob_mesh(0.022, 0.0, 3, Vector3(1.0, 1.3, 0.6), 10), Vector3(0.038 * s, 0.14, 0.095))
		sk.material_override = sock
	_part(head, P.horn(Vector3(0, 0.04, 0.04), Vector3(0, -0.07, 0.06), 0.04, Vector3(0, 0, 0.0), 10, 6))
	# глаза: не белые «точки мультика», а тусклый отблеск в глубине глазниц
	var em := Mats.col(Color(0.2, 0.19, 0.14), "metal", 0.0, {"emit": 0.45, "emit_color": Vector3(0.55, 0.5, 0.32), "wet": 1.0})
	for s in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		var es := SphereMesh.new()
		es.radius = 0.0045
		es.height = 0.009
		es.radial_segments = 6
		es.rings = 3
		e.mesh = es
		e.material_override = em
		e.position = Vector3(0.038 * s, 0.14, 0.098)
		head.add_child(e)
		eyes.append(e)
		e.visible = false
	var strand_m := Mats.prop("lifeform_strand", {"tex": "fiber", "tex_mix": 0.6, "color": Vector3(0.04, 0.036, 0.032), "wet": 0.3, "smear": 1.6,
		"uv_scale": Vector2(1.0, 4.0), "near_cut": 0.42})
	for s in [-1.0, 1.0]:
		var nm := "l" if s < 0 else "r"
		var sh := _joint("sh_" + nm, chest, Vector3(0.21 * s, -0.04, 0))
		_part(sh, P.blob_mesh(0.07, 0.15, 5, Vector3(1.0, 0.9, 1.0), 12), Vector3(0, 0.0, 0))
		_limb(sh, 0.95, 0.075, 0, 0.35)
		var el := _joint("el_" + nm, sh, Vector3(0, -0.95, 0))
		_limb(el, 0.98, 0.06, 0, 0.45)
		var wr := _joint("wr_" + nm, el, Vector3(0, -0.98, 0))
		_part(wr, P.blob_mesh(0.032, 0.2, 7, Vector3(1.3, 0.9, 0.8), 10))
		for f in 4:
			var fj := Node3D.new()
			wr.add_child(fj)
			fj.rotation = Vector3(randf_range(-0.3, 0.3), 0, (f - 1.5) * 0.18)
			_part(fj, P.horn(Vector3.ZERO, Vector3(0, -0.4, 0.04), 0.016, Vector3(0, 0, 0.05), 6, 8))
		# мокрые волокна свисают с плеча
		for k3 in 2:
			var pts2 := PackedVector3Array()
			var r2 := PackedFloat32Array()
			var ln := randf_range(0.5, 1.1)
			for i in 8:
				var t := float(i) / 7.0
				pts2.append(Vector3(s * 0.04 * k3 + sin(t * 5.0 + k3) * 0.03, -ln * t, -0.04 + cos(t * 4.0) * 0.03))
				r2.append(0.007 * (1.0 - t * 0.7))
			var sm := MeshInstance3D.new()
			sm.mesh = P.loft(pts2, r2, r2, 5)
			sm.material_override = strand_m
			sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			sh.add_child(sm)
	# волокна по всему телу: тонкие мокрые пряди отходят от спины, плеч и рук и висят — силуэт рваный
	var fib := Mats.prop("lifeform_fiber", {"tex": "fiber", "tex_mix": 0.6, "color": Vector3(0.025, 0.022, 0.02), "wet": 0.2, "smear": 0.5,
		"uv_scale": Vector2(1.0, 6.0), "near_cut": 0.42, "gloss": 8.0, "spec": 0.02})
	var frng := RandomNumberGenerator.new()
	frng.seed = 4217
	for nm3 in ["chest", "sh_l", "sh_r", "el_l", "el_r", "spine"]:
		var host: Node3D = j[nm3] if j.has(nm3) else spine
		var cnt := 7 if nm3 == "chest" or nm3 == "spine" else 5
		for k4 in cnt:
			var pts3 := PackedVector3Array()
			var r3 := PackedFloat32Array()
			var ln3 := frng.randf_range(0.18, 0.7)
			var o3 := Vector3(frng.randf_range(-0.12, 0.12), frng.randf_range(-0.6, 0.0) if nm3 != "spine" else frng.randf_range(0.2, 0.85),
				frng.randf_range(-0.09, 0.05))
			var bend := Vector3(frng.randf_range(-0.08, 0.08), 0.0, frng.randf_range(-0.08, 0.04))
			if nm3.begins_with("sh") or nm3.begins_with("el"):
				# с поверхности руки, кончик отходит наружу
				var aa := frng.randf() * TAU
				o3 = Vector3(cos(aa) * 0.05, -frng.randf_range(0.05, 0.85), sin(aa) * 0.05)
				bend = Vector3(cos(aa), 0.0, sin(aa)) * frng.randf_range(0.05, 0.14)
			for i in 7:
				var t := float(i) / 6.0
				pts3.append(o3 + Vector3(bend.x * t * t, -ln3 * t, bend.z * t * t + sin(t * 4.0 + k4) * 0.012))
				r3.append(lerpf(0.0045, 0.001, t))
			var fm := MeshInstance3D.new()
			fm.mesh = P.loft(pts3, r3, r3, 4)
			fm.material_override = fib
			fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			host.add_child(fm)
	for s in [-1.0, 1.0]:
		var nm2 := "l" if s < 0 else "r"
		var hp := _joint("hip_" + nm2, pelvis, Vector3(0.12 * s, 0, 0))
		_part(hp, P.blob_mesh(0.075, 0.12, 9, Vector3(1.0, 0.9, 1.0), 12))
		_limb(hp, 0.66, 0.085, 0, 0.3)
		var kn := _joint("kn_" + nm2, hp, Vector3(0, -0.66, 0))
		_limb(kn, 0.66, 0.065, 0, 0.4)
		var an := _joint("an_" + nm2, kn, Vector3(0, -0.66, 0))
		_part(an, P.blob_mesh(0.035, 0.15, 11, Vector3(1.0, 0.9, 1.2), 10))
		for t2 in 3:
			var toe := Node3D.new()
			an.add_child(toe)
			toe.rotation = Vector3(-1.35, (t2 - 1) * 0.3, 0)
			_part(toe, P.horn(Vector3.ZERO, Vector3(0, -0.24, -0.03), 0.02, Vector3(0, 0, -0.03), 6, 6))


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
	spawn_cd = cd * (0.7 if Game.survival() else 1.0)
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
	var extra := 0.15 if Game.survival() else 0.0
	return clampf(0.4 + extra + t / 900.0 + lay * 0.35, 0.4, 1.5)


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
	_keep_off_camera(pl)
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
	path = Pathfind.find(L, me, goal, 1500, true)
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
		path = Pathfind.find(L, me, goal, 2000 if state == S.CHASE else 1200, true)
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
	global_position.y = L.ground(global_position)


## Не входить в камеру: ближе 0,9 м по горизонтали — отодвинуть (догнала — смерть уже на 1,25 м;
## в режиме бога и в кадре смерти тело иначе разрезала бы ближняя плоскость)
func _keep_off_camera(pl: Player) -> void:
	var to := global_position - pl.global_position
	to.y = 0.0
	var d := to.length()
	if d < 0.9:
		var dir := to / d if d > 0.01 else -pl.global_basis.z
		var y := global_position.y
		global_position = pl.global_position + Vector3(dir.x, 0.0, dir.z) * 0.9
		global_position.y = y


static func _apply_light(n: Node, c: Vector4) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).set_instance_shader_parameter("light_level", c)
	for ch in n.get_children():
		_apply_light(ch, c)
