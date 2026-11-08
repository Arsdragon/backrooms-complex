extends RefCounted
## Предметы мира по описаниям декора из WorldGen. Всё собирается из примитивов.

const DECAL := preload("res://src/shaders/decal.gdshader")
const LD := preload("res://src/world/layer_data.gd")

static var _decals := {}
static var park_mode := false   # парк/концовки: модели с обычными PBR-материалами
static var _font_hand: Font = null
static var _font_sign: Font = null


static func font_hand() -> Font:
	if _font_hand == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Segoe Print", "Ink Free", "Comic Sans MS", "sans-serif"])
		f.font_weight = 700
		_font_hand = f
	return _font_hand


static func font_sign() -> Font:
	if _font_sign == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Bahnschrift", "Arial Narrow", "Arial", "sans-serif"])
		f.font_weight = 700
		_font_sign = f
	return _font_sign


# ------------------------------------------------------------ материалы

static func m_wood() -> Material: return Mats.col(Color(0.58, 0.42, 0.28), "wood", 1.0)
static func m_iron() -> Material: return Mats.col(Color(0.13, 0.14, 0.13), "metal", 0.5)
static func m_green() -> Material: return Mats.col(Color(0.14, 0.27, 0.17), "metal", 0.4)
static func m_conc() -> Material: return Mats.col(Color(0.78, 0.76, 0.7), "concrete", 1.0)
static func m_plastic(c := Color(0.86, 0.85, 0.8)) -> Material: return Mats.col(c, "metal", 0.15)
static func m_metal() -> Material: return Mats.col(Color(0.58, 0.59, 0.58), "metal", 0.6)
static func m_black() -> Material: return Mats.col(Color(0.045, 0.045, 0.045), "metal", 0.3)
static func m_cloth(c: Color) -> Material: return Mats.col(c, "fabric", 0.7)
static func m_wall() -> Material: return Mats.prop("wall_w", {"tex": "wall_yellow", "world_uv": 1.0, "world_scale": Vector2(0.8, 0.8), "tex_mix": 1.0})
static func m_carpet() -> Material: return Mats.prop("carpet_w", {"tex": "carpet", "world_uv": 1.0, "world_scale": Vector2(1.5, 1.5), "tex_mix": 1.0})
static func m_bark() -> Material: return Mats.col(Color(1, 1, 1), "bark", 1.0, {"uv_scale": Vector2(2.0, 3.0)})
static func m_leaves() -> Material: return Mats.prop("leaves_cut", {"tex": "leaves", "tex_mix": 1.0, "alpha_cut": 0.3, "uv_scale": Vector2(2, 2)})
static func m_emit(c: Color, power := 2.0) -> Material:
	return Mats.col(c, "metal", 0.0, {"emit": power, "emit_color": Vector3(c.r, c.g, c.b)})


static func decal_mat(key: String, params: Dictionary) -> ShaderMaterial:
	if _decals.has(key):
		return _decals[key]
	var m := ShaderMaterial.new()
	m.shader = DECAL
	m.set_shader_parameter("noise_tex", Mats.tex("noise"))
	m.set_shader_parameter("tex", Mats.tex(String(params.get("tex", "mold"))))
	for k in params.keys():
		if k != "tex":
			m.set_shader_parameter(k, params[k])
	_decals[key] = m
	return m


# ------------------------------------------------------------ примитивы

static func box(p: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi)
	return mi


static func cyl(p: Node3D, rt: float, rb: float, h: float, pos: Vector3, mat: Material, rot := Vector3.ZERO, seg := 12) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi)
	return mi


static func sph(p: Node3D, r: float, pos: Vector3, mat: Material, sc := Vector3.ONE, seg := 12) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = maxi(4, seg / 2)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.scale = sc
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi)
	return mi


## Палка между двумя точками
static func rod(p: Node3D, a: Vector3, b: Vector3, r: float, mat: Material, seg := 6) -> MeshInstance3D:
	var d := b - a
	var mi := cyl(p, r, r, d.length(), (a + b) * 0.5, mat, Vector3.ZERO, seg)
	var up := d.normalized()
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(up).normalized()
	var z := x.cross(up).normalized()
	mi.basis = Basis(x, up, z)
	return mi


static func quad(p: Node3D, size: Vector2, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi)
	return mi


## Готовая модель (Poly Haven). sc — масштаб (число или Vector3). Возвращает null, если модели нет.
static func model(p: Node3D, id: String, pos := Vector3.ZERO, rot := 0.0, sc: Variant = 1.0, collide := true) -> Node3D:
	var m := Models.make(id, not park_mode)
	if m == null:
		return null
	var s3: Vector3 = sc if typeof(sc) == TYPE_VECTOR3 else Vector3.ONE * float(sc)
	p.add_child(m)
	m.position = pos
	m.rotation.y = rot
	m.scale = s3
	if collide:
		var bb := Models.aabb(id)
		var c := (bb.position + bb.size * 0.5) * s3
		collider(p, bb.size * s3, pos + Basis(Vector3.UP, rot) * c, 1, Vector3(0, rot, 0))
	return m


static func collider(p: Node3D, size: Vector3, pos: Vector3, layer := 1, rot := Vector3.ZERO) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = layer
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	b.position = pos
	b.rotation = rot
	p.add_child(b)
	return b


static func interactable(p: Node3D, size: Vector3, pos: Vector3, hint: String, cb: Callable) -> StaticBody3D:
	var b := collider(p, size, pos, 2)
	b.set_meta("interact", cb)
	b.set_meta("hint", hint)
	return b


static func trigger(p: Node3D, size: Vector3, pos: Vector3, cb: Callable) -> Area3D:
	var a := Area3D.new()
	a.collision_layer = 0
	a.collision_mask = 1
	a.monitoring = true
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	a.add_child(cs)
	a.position = pos
	p.add_child(a)
	a.body_entered.connect(func(body: Node3D) -> void:
		if body is Player:
			cb.call())
	return a


static func set_light(n: Node, c: Color) -> void:
	if n is GeometryInstance3D and not (n is Label3D):
		(n as GeometryInstance3D).set_instance_shader_parameter("light_level", Vector4(c.r * 2.0, c.g * 2.0, c.b * 2.0, c.a))
	elif n is Label3D:
		var lb := n as Label3D
		var lum := clampf((c.r + c.g + c.b * 0.5) * 2.0 + 0.04, 0.03, 1.2)
		var base: Color = lb.get_meta("ink", lb.modulate)
		lb.modulate = Color(base.r * lum, base.g * lum, base.b * lum, base.a)
	for ch in n.get_children():
		set_light(ch, c)


## Все материалы предмета → обои/ковёр («Комплекс перепутал материал»)
static func swap_mats(n: Node, m: Material) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_override = m
	for ch in n.get_children():
		swap_mats(ch, m)


# ------------------------------------------------------------ точка входа

static func spawn_all(cx: Node3D, parent: Node3D, decos: Array, layer: int) -> void:
	for d in decos:
		var dd: Dictionary = d
		var n := spawn(cx, dd, layer)
		if n == null:
			continue
		parent.add_child(n)
		n.position = dd.p
		if not n.has_meta("keep_rot"):
			n.rotation.y = float(dd.get("r", 0.0))
		if n.has_meta("tilt"):
			n.rotation.x = float(n.get_meta("tilt"))
		var lc: Color = dd.get("light", Color(0.4, 0, 0, 0))
		set_light(n, lc)
		if n.has_method("on_spawned"):
			n.on_spawned(cx)


static func spawn(cx: Node3D, d: Dictionary, layer: int) -> Node3D:
	var k := String(d.get("k", ""))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(d.get("seed", hash(d.p)))
	match k:
		"obj": return obj(String(d.get("what", "chair")), String(d.get("wrong", "none")), rng, d)
		"copy": return copy_person(cx, d, rng, layer)
		"copy_self": return copy_self(cx, d)
		"graf": return graffiti(d)
		"tag": return cable_tag(d)
		"sign": return sign_board(d)
		"note": return note(cx, d)
		"stain": return stain(d, rng)
		"mold": return mold_patch(d, rng)
		"papers": return papers(rng)
		"grass": return grass_patch(d, rng)
		"async": return async_item(cx, String(d.get("what", "case")), d, rng)
		"threshold": return threshold(cx)
		"null": return null_zone(cx, d)
		"nest": return nest(rng)
		"house": return house_item(String(d.get("what", "sofa")), rng)
		"sound": return sound_emitter(d)
		"voice_wall": return voice_wall(cx)
		"red_city": return red_city(d, rng)
	return null


# ------------------------------------------------------------ парк и мебель

static func obj(what: String, wrong: String, rng: RandomNumberGenerator, d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var inner := Node3D.new()
	n.add_child(inner)
	match what:
		"bench": _bench(inner)
		"lamp": _lamp(inner)
		"bin": _bin(inner)
		"tree": _tree(inner, rng)
		"fountain": _fountain(inner)
		"slide": _slide(inner)
		"swing": _swing(inner, wrong == "ceiling")
		"cart": _cart(inner)
		"car":
			if model(inner, "covered_car") == null:
				_car(inner)
		"stroller": _stroller(inner)
		"balloon": _balloon(inner)
		"blanket": _blanket(inner)
		"phone": _phone(inner)
		"chair": _chair(inner)
		"desk": _desk(inner)
		"cabinet": _cabinet(inner)
		"cooler": _cooler(inner)
		"ochair": _ochair(inner)
		"boxes": _boxes(inner, rng)
		"tv": _tv(inner)
		"shelf": _shelf(inner, rng)
		"sign_park": _sign_park(inner)
		"hill_chair": _hill_chair(inner)
		"debris": _debris(inner, rng)
		"wetsign": model(inner, "WetFloorSign_01", Vector3.ZERO, 0.0, 1.15, false)
		"wheelchair": model(inner, "wheelchair_01")
		"hydrant": model(inner, "fire_hydrant")
		"trashbag": model(inner, "trashbag", Vector3.ZERO, 0.0, 1.0, false)
		"tyre": model(inner, "old_tyre", Vector3(0, 0.3, 0), 0.0, 1.0, false)
		"utilitybox": model(inner, "utility_box_01")
		"crate": model(inner, "plastic_crate_01", Vector3.ZERO, 0.0, 1.0, false)
		"covered_car": model(inner, "covered_car")
		_: _chair(inner)
	match wrong:
		"stretch":
			var ax := rng.randi_range(0, 2)
			inner.scale = [Vector3(rng.randf_range(2.2, 3.5), 1, 1), Vector3(1, rng.randf_range(1.8, 2.6), 1), Vector3(1, 1, rng.randf_range(2.5, 4.0))][ax]
		"ceiling":
			if what != "swing" and what != "balloon":
				inner.rotation.x = PI
				inner.position.y = 2.7 + (0.15 if what == "lamp" else 0.0)
				if what == "lamp":
					inner.position.y = 4.2
		"stack":
			for k2 in 2:
				var dup := inner.duplicate()
				n.add_child(dup)
				dup.position = Vector3(rng.randf_range(-0.15, 0.15), 0.55 * (k2 + 1), rng.randf_range(-0.15, 0.15))
				dup.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))
		"sink":
			inner.position.y -= rng.randf_range(0.3, 0.6)
			inner.rotation = Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
		"wallpaper":
			swap_mats(inner, m_wall())
		"row":
			for k3 in 3:
				var dup2 := inner.duplicate()
				n.add_child(dup2)
				dup2.position = Vector3(0, 0, -(k3 + 1) * 0.35)
		"tilt":
			inner.rotation = Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(0.4, 0.9) * (1 if rng.randf() < 0.5 else -1))
		"wall":
			pass
	if what == "tree" and wrong == "wallpaper":
		pass
	return n


static func _bench(p: Node3D) -> void:
	if model(p, "modular_street_seating", Vector3.ZERO, 0.0, Vector3(0.45, 1.0, 1.0)) != null:
		return
	var w := m_wood()
	var ir := m_iron()
	for k in 3:
		box(p, Vector3(1.8, 0.035, 0.1), Vector3(0, 0.45, -0.12 + k * 0.12), w)
	for k in 2:
		box(p, Vector3(1.8, 0.1, 0.035), Vector3(0, 0.62 + k * 0.14, -0.22), w, Vector3(-0.15, 0, 0))
	for s in [-0.75, 0.75]:
		box(p, Vector3(0.05, 0.45, 0.06), Vector3(s, 0.22, 0.12), ir)
		box(p, Vector3(0.05, 0.85, 0.06), Vector3(s, 0.42, -0.2), ir, Vector3(-0.15, 0, 0))
		box(p, Vector3(0.05, 0.05, 0.45), Vector3(s, 0.43, -0.02), ir)
	collider(p, Vector3(1.8, 0.5, 0.5), Vector3(0, 0.25, 0))


static func _lamp(p: Node3D) -> void:
	var g := m_green()
	cyl(p, 0.06, 0.09, 3.3, Vector3(0, 1.65, 0), g)
	cyl(p, 0.13, 0.13, 0.12, Vector3(0, 0.06, 0), g)
	box(p, Vector3(0.26, 0.04, 0.26), Vector3(0, 3.32, 0), g)
	box(p, Vector3(0.2, 0.32, 0.2), Vector3(0, 3.5, 0), m_emit(Color(1.0, 0.85, 0.55), 1.6))
	cyl(p, 0.02, 0.17, 0.14, Vector3(0, 3.72, 0), g, Vector3.ZERO, 4)
	collider(p, Vector3(0.2, 3.3, 0.2), Vector3(0, 1.65, 0))


static func _bin(p: Node3D) -> void:
	if model(p, "metal_trash_can", Vector3.ZERO, 0.0, 1.0) != null:
		return
	var g := m_green()
	cyl(p, 0.27, 0.24, 0.85, Vector3(0, 0.43, 0), g, Vector3.ZERO, 14)
	cyl(p, 0.28, 0.28, 0.04, Vector3(0, 0.86, 0), m_iron(), Vector3.ZERO, 14)
	box(p, Vector3(0.3, 0.12, 0.2), Vector3(0, 0.86, 0), Mats.col(Color(0.8, 0.8, 0.75), "paper", 0.8), Vector3(0.3, 0.4, 0.1))
	collider(p, Vector3(0.5, 0.85, 0.5), Vector3(0, 0.42, 0))


static func _tree(p: Node3D, rng: RandomNumberGenerator) -> void:
	var b := m_bark()
	var lean := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
	cyl(p, 0.24, 0.34, 3.2, Vector3(lean.x * 0.5, 1.6, lean.z * 0.5), b, Vector3(lean.z * 0.15, 0, -lean.x * 0.15), 10)
	cyl(p, 0.36, 0.52, 0.3, Vector3(0, 0.15, 0), b, Vector3.ZERO, 10)
	var top := Vector3(lean.x, 3.1, lean.z)
	for k in 5:
		var a2 := k * TAU / 5 + rng.randf_range(-0.4, 0.4)
		var s0 := Vector3(lean.x * 0.7, 2.3 + k * 0.15, lean.z * 0.7)
		var e := Vector3(cos(a2) * rng.randf_range(1.0, 1.7), rng.randf_range(3.6, 4.4), sin(a2) * rng.randf_range(1.0, 1.7))
		rod(p, s0, e, 0.09 - k * 0.008, b)
	rod(p, top, Vector3(lean.x, 4.6, lean.z), 0.12, b)
	var lv := m_leaves()
	for k in 13:
		var a3 := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 2.1
		var y := 4.3 + rng.randf_range(-0.7, 0.9) - r * 0.25
		sph(p, rng.randf_range(0.95, 1.45), Vector3(cos(a3) * r + lean.x, y, sin(a3) * r + lean.z), lv, Vector3(1.0, 0.78, 1.0), 10)
	collider(p, Vector3(0.6, 3.0, 0.6), Vector3(0, 1.5, 0))


static func _fountain(p: Node3D) -> void:
	var c := m_conc()
	for k in 16:
		var a := k * TAU / 16
		box(p, Vector3(0.62, 0.5, 0.22), Vector3(cos(a) * 1.65, 0.25, sin(a) * 1.65), c, Vector3(0, -a + PI * 0.5, 0))
	cyl(p, 1.6, 1.6, 0.36, Vector3(0, 0.18, 0), m_carpet(), Vector3.ZERO, 20).set_meta("water", true)
	cyl(p, 0.18, 0.25, 1.0, Vector3(0, 0.6, 0), c)
	cyl(p, 0.6, 0.25, 0.18, Vector3(0, 1.15, 0), c, Vector3.ZERO, 16)
	cyl(p, 0.55, 0.55, 0.05, Vector3(0, 1.23, 0), m_carpet(), Vector3.ZERO, 16).set_meta("water", true)
	collider(p, Vector3(3.6, 0.5, 3.6), Vector3(0, 0.25, 0))


static func _slide(p: Node3D) -> void:
	var red := Mats.col(Color(0.75, 0.15, 0.12), "metal", 0.2)
	var mt := m_metal()
	for s in [-0.3, 0.3]:
		box(p, Vector3(0.05, 2.0, 0.05), Vector3(s, 1.0, -1.0), mt)
	for k in 6:
		box(p, Vector3(0.6, 0.04, 0.05), Vector3(0, 0.3 + k * 0.3, -1.0), mt)
	box(p, Vector3(0.7, 0.06, 2.8), Vector3(0, 1.0, 0.25), red, Vector3(-0.62, 0, 0))
	box(p, Vector3(0.05, 0.25, 2.8), Vector3(-0.35, 1.1, 0.25), red, Vector3(-0.62, 0, 0))
	box(p, Vector3(0.05, 0.25, 2.8), Vector3(0.35, 1.1, 0.25), red, Vector3(-0.62, 0, 0))
	collider(p, Vector3(0.8, 1.6, 2.4), Vector3(0, 0.8, 0.2))


static func _swing(p: Node3D, ceiling: bool) -> void:
	var mt := m_metal()
	var top := 2.69 if ceiling else 2.2
	if not ceiling:
		for s in [-1.2, 1.2]:
			rod(p, Vector3(s, 0, -0.7), Vector3(s, top, 0), 0.04, mt)
			rod(p, Vector3(s, 0, 0.7), Vector3(s, top, 0), 0.04, mt)
		rod(p, Vector3(-1.25, top, 0), Vector3(1.25, top, 0), 0.05, mt)
	for s2 in [-0.55, 0.55]:
		var seat_y := 0.5 if not ceiling else 1.2
		for e in [-0.2, 0.2]:
			rod(p, Vector3(s2 + e, top, 0), Vector3(s2 + e, seat_y, 0), 0.008, mt, 4)
		box(p, Vector3(0.45, 0.04, 0.18), Vector3(s2, seat_y, 0), Mats.col(Color(0.12, 0.12, 0.12), "metal", 0.2))


static func _cart(p: Node3D) -> void:
	var wht := m_plastic(Color(0.92, 0.9, 0.86))
	var stripe := Mats.col(Color(0.3, 0.55, 0.8), "metal", 0.1)
	box(p, Vector3(1.5, 0.8, 0.75), Vector3(0, 0.75, 0), wht)
	box(p, Vector3(1.52, 0.12, 0.77), Vector3(0, 0.95, 0), stripe)
	box(p, Vector3(1.55, 0.05, 0.8), Vector3(0, 1.17, 0), Mats.col(Color(0.6, 0.6, 0.6), "metal", 0.6))
	for s in [-0.55, 0.55]:
		cyl(p, 0.2, 0.2, 0.06, Vector3(s, 0.2, 0.4), m_black(), Vector3(PI * 0.5, 0, 0), 14)
	rod(p, Vector3(0.6, 1.15, 0), Vector3(0.6, 3.0, 0), 0.025, m_metal())
	var umb := Mats.col(Color(0.85, 0.3, 0.3), "fabric", 0.4)
	cyl(p, 0.02, 1.1, 0.45, Vector3(0.6, 2.85, 0), umb, Vector3.ZERO, 8)
	collider(p, Vector3(1.5, 1.2, 0.8), Vector3(0, 0.6, 0))


static func _car(p: Node3D) -> void:
	var paint := Mats.col(Color(0.45, 0.5, 0.42), "metal", 0.35)
	var dark := m_black()
	box(p, Vector3(1.75, 0.62, 4.6), Vector3(0, 0.55, 0), paint)
	box(p, Vector3(1.55, 0.5, 2.3), Vector3(0, 1.1, -0.2), paint)
	box(p, Vector3(1.5, 0.42, 2.25), Vector3(0, 1.12, -0.2), Mats.col(Color(0.05, 0.06, 0.07), "metal", 0.1))
	for sx in [-0.78, 0.78]:
		for sz in [-1.45, 1.4]:
			cyl(p, 0.32, 0.32, 0.22, Vector3(sx, 0.32, sz), dark, Vector3(0, 0, PI * 0.5), 14)
	for sx2 in [-0.6, 0.6]:
		box(p, Vector3(0.3, 0.14, 0.04), Vector3(sx2, 0.66, 2.31), m_emit(Color(1.0, 0.95, 0.75), 1.2))
		box(p, Vector3(0.3, 0.12, 0.04), Vector3(sx2, 0.66, -2.31), m_emit(Color(0.8, 0.1, 0.08), 0.6))
	box(p, Vector3(1.8, 0.16, 0.1), Vector3(0, 0.36, 2.33), Mats.col(Color(0.6, 0.6, 0.6), "metal", 0.6))
	collider(p, Vector3(1.8, 1.4, 4.6), Vector3(0, 0.7, 0))


static func _stroller(p: Node3D) -> void:
	var fr := m_metal()
	var cl := m_cloth(Color(0.25, 0.3, 0.55))
	sph(p, 0.35, Vector3(0, 0.75, 0), cl, Vector3(0.9, 0.6, 1.3))
	for sx in [-0.25, 0.25]:
		for sz in [-0.3, 0.3]:
			cyl(p, 0.1, 0.1, 0.04, Vector3(sx, 0.1, sz), m_black(), Vector3(0, 0, PI * 0.5), 10)
			rod(p, Vector3(sx, 0.1, sz), Vector3(sx * 0.8, 0.6, sz * 0.5), 0.015, fr, 4)
	rod(p, Vector3(-0.22, 0.65, -0.35), Vector3(-0.22, 1.05, -0.65), 0.015, fr, 4)
	rod(p, Vector3(0.22, 0.65, -0.35), Vector3(0.22, 1.05, -0.65), 0.015, fr, 4)
	rod(p, Vector3(-0.25, 1.05, -0.65), Vector3(0.25, 1.05, -0.65), 0.02, fr, 4)


static func _balloon(p: Node3D) -> void:
	sph(p, 0.17, Vector3(0, -0.2, 0), Mats.col(Color(0.85, 0.08, 0.08), "metal", 0.05, {"wet": 0.6}), Vector3(1, 1.15, 1))
	rod(p, Vector3(0, -0.4, 0), Vector3(0.05, -1.4, 0.02), 0.003, m_plastic(), 3)


static func _blanket(p: Node3D) -> void:
	for i in 4:
		for k in 4:
			var c := Color(0.75, 0.12, 0.1) if (i + k) % 2 == 0 else Color(0.92, 0.9, 0.85)
			box(p, Vector3(0.5, 0.012, 0.5), Vector3(-0.75 + i * 0.5, 0.006, -0.75 + k * 0.5), m_cloth(c))
	cyl(p, 0.18, 0.15, 0.25, Vector3(0.5, 0.13, 0.4), Mats.col(Color(0.6, 0.45, 0.25), "wood", 0.8), Vector3.ZERO, 10)


static func _phone(p: Node3D) -> void:
	box(p, Vector3(0.22, 0.08, 0.2), Vector3(0, 0.04, 0), m_plastic(Color(0.85, 0.8, 0.7)))
	box(p, Vector3(0.24, 0.05, 0.06), Vector3(0, 0.1, 0), m_plastic(Color(0.85, 0.8, 0.7)))


static func _chair(p: Node3D) -> void:
	if model(p, "plastic_monobloc_chair_01", Vector3.ZERO, 0.0, 1.0, false) != null:
		return
	var pl := m_plastic(Color(0.86, 0.85, 0.8))
	box(p, Vector3(0.45, 0.04, 0.42), Vector3(0, 0.45, 0), pl)
	box(p, Vector3(0.45, 0.4, 0.04), Vector3(0, 0.67, -0.2), pl, Vector3(-0.12, 0, 0))
	for sx in [-0.2, 0.2]:
		for sz in [-0.18, 0.18]:
			box(p, Vector3(0.03, 0.45, 0.03), Vector3(sx, 0.22, sz), pl)


static func _desk(p: Node3D) -> void:
	if model(p, "metal_office_desk", Vector3.ZERO, 0.0, Vector3(0.75, 1.0, 0.8)) != null:
		return
	var w := Mats.col(Color(0.62, 0.55, 0.45), "wood", 0.6)
	box(p, Vector3(1.4, 0.04, 0.7), Vector3(0, 0.74, 0), w)
	box(p, Vector3(0.04, 0.72, 0.68), Vector3(-0.68, 0.36, 0), w)
	box(p, Vector3(0.45, 0.72, 0.68), Vector3(0.47, 0.36, 0), w)
	box(p, Vector3(1.3, 0.4, 0.02), Vector3(0, 0.5, -0.33), w)
	collider(p, Vector3(1.4, 0.76, 0.7), Vector3(0, 0.38, 0))


static func _cabinet(p: Node3D) -> void:
	var g := Mats.col(Color(0.52, 0.53, 0.5), "metal", 0.5)
	box(p, Vector3(0.48, 1.32, 0.62), Vector3(0, 0.66, 0), g)
	for k in 4:
		box(p, Vector3(0.42, 0.02, 0.01), Vector3(0, 0.3 + k * 0.32, 0.315), m_black())
		box(p, Vector3(0.12, 0.03, 0.03), Vector3(0, 0.42 + k * 0.32, 0.32), m_metal())
	collider(p, Vector3(0.48, 1.32, 0.62), Vector3(0, 0.66, 0))


static func _cooler(p: Node3D) -> void:
	box(p, Vector3(0.32, 1.0, 0.32), Vector3(0, 0.5, 0), m_plastic(Color(0.85, 0.84, 0.8)))
	cyl(p, 0.15, 0.15, 0.45, Vector3(0, 1.22, 0), Mats.col(Color(0.5, 0.7, 0.85), "metal", 0.1, {"wet": 0.5}), Vector3.ZERO, 12)


static func _ochair(p: Node3D) -> void:
	if model(p, "SchoolChair_01", Vector3.ZERO, 0.0, 1.0, false) != null:
		return
	var c := m_cloth(Color(0.2, 0.22, 0.28))
	box(p, Vector3(0.5, 0.08, 0.48), Vector3(0, 0.48, 0), c)
	box(p, Vector3(0.46, 0.55, 0.07), Vector3(0, 0.82, -0.22), c)
	cyl(p, 0.03, 0.03, 0.4, Vector3(0, 0.25, 0), m_black())


static func _boxes(p: Node3D, rng: RandomNumberGenerator) -> void:
	if Models.has("cardboard_box_01"):
		var n := rng.randi_range(2, 4)
		for k in n:
			var sc := rng.randf_range(0.8, 1.25)
			var y := 0.0 if k < 2 else 0.34 * sc
			model(p, "cardboard_box_01", Vector3(rng.randf_range(-0.35, 0.35), y, rng.randf_range(-0.35, 0.35)), rng.randf_range(-0.5, 0.5), sc, k < 2)
		return
	var cb := Mats.col(Color(0.62, 0.48, 0.3), "paper", 0.6)
	for k in rng.randi_range(2, 5):
		var s := Vector3(rng.randf_range(0.35, 0.6), rng.randf_range(0.25, 0.45), rng.randf_range(0.35, 0.55))
		box(p, s, Vector3(rng.randf_range(-0.3, 0.3), s.y * 0.5 + (0.4 if k > 2 else 0.0), rng.randf_range(-0.3, 0.3)), cb, Vector3(0, rng.randf_range(-0.4, 0.4), 0))


static func _tv(p: Node3D) -> void:
	box(p, Vector3(0.7, 0.5, 0.5), Vector3(0, 0.25, 0), Mats.col(Color(0.35, 0.25, 0.18), "wood", 0.7))
	if model(p, "television_02", Vector3(0, 0.5, 0), 0.0, 1.35, false) != null:
		box(p, Vector3(0.4, 0.3, 0.01), Vector3(0, 0.79, 0.245), Mats.col(Color(0.5, 0.55, 0.55), "noise", 1.0, {"emit": 0.5, "emit_color": Vector3(0.6, 0.65, 0.7)}))
		return
	box(p, Vector3(0.6, 0.5, 0.6), Vector3(0, 0.75, 0), Mats.col(Color(0.2, 0.19, 0.18), "metal", 0.3))
	box(p, Vector3(0.48, 0.38, 0.02), Vector3(0, 0.77, 0.3), Mats.col(Color(0.5, 0.55, 0.55), "noise", 1.0, {"emit": 0.5, "emit_color": Vector3(0.6, 0.65, 0.7)}))


static func _shelf(p: Node3D, rng: RandomNumberGenerator) -> void:
	if model(p, "steel_frame_shelves_01", Vector3.ZERO, 0.0, 0.1) != null:
		for k in 3:
			if rng.randf() < 0.6 and Models.has("cardboard_box_01"):
				model(p, "cardboard_box_01", Vector3(rng.randf_range(-0.25, 0.25), 0.05 + k * 0.52, 0), rng.randf_range(-0.3, 0.3), 0.8, false)
		return
	var g := Mats.col(Color(0.5, 0.5, 0.48), "metal", 0.5)
	for sx in [-0.45, 0.45]:
		for sz in [-0.18, 0.18]:
			box(p, Vector3(0.03, 1.8, 0.03), Vector3(sx, 0.9, sz), g)
	for k in 4:
		box(p, Vector3(0.95, 0.025, 0.4), Vector3(0, 0.3 + k * 0.45, 0), g)


static func _sign_park(p: Node3D) -> void:
	box(p, Vector3(0.08, 1.4, 0.08), Vector3(0, 0.7, 0), Mats.col(Color(0.35, 0.25, 0.15), "wood", 0.8))
	box(p, Vector3(0.9, 0.55, 0.04), Vector3(0, 1.5, 0), Mats.col(Color(0.15, 0.32, 0.2), "wood", 0.4))
	var lb := label(Loc.t("sign.park"), font_sign(), 0.0045, Color(0.9, 0.88, 0.8))
	lb.position = Vector3(0, 1.5, 0.025)
	p.add_child(lb)


static func _hill_chair(p: Node3D) -> void:
	sph(p, 1.0, Vector3(0, -0.35, 0), m_carpet(), Vector3(1.9, 1.0, 1.6), 16)
	var ch := Node3D.new()
	p.add_child(ch)
	ch.position = Vector3(0.1, 0.62, 0)
	ch.rotation = Vector3(0.1, 0.5, -0.08)
	_chair(ch)
	collider(p, Vector3(2.8, 0.6, 2.4), Vector3(0, 0.3, 0))


static func _debris(p: Node3D, rng: RandomNumberGenerator) -> void:
	for k in rng.randi_range(3, 6):
		box(p, Vector3(rng.randf_range(0.3, 0.6), 0.015, rng.randf_range(0.3, 0.6)),
			Vector3(rng.randf_range(-0.9, 0.9), 0.01 + k * 0.004, rng.randf_range(-0.9, 0.9)),
			Mats.col(Color(0.82, 0.8, 0.74), "noise", 0.3) if k % 2 == 0 else m_carpet(), Vector3(rng.randf_range(-0.1, 0.1), rng.randf() * TAU, 0))
	box(p, Vector3(0.6, 0.08, 1.2), Vector3(0.4, 0.05, -0.3), Mats.col(Color(0.7, 0.7, 0.68), "metal", 0.3), Vector3(0.15, 0.4, 0.05))


# ------------------------------------------------------------ люди-копии

static func copy_person(cx: Node3D, d: Dictionary, rng: RandomNumberGenerator, layer: int) -> Node3D:
	var who := String(d.get("who", "civ_a"))
	var wrong := String(d.get("wrong", "none"))
	var holder := Node3D.new()
	var h := Human.make("civ_a" if who == "couple" else who, int(d.get("seed", 1)), true)
	holder.add_child(h)
	var ps := String(d.get("pose", "stand"))
	if who == "oldman":
		ps = "read"
	elif who == "couple":
		ps = "sit_ground"
	if ps == "run":
		h.pose("run", float(d.get("phase", 0.0)) * TAU)
		h.pose_name = "run_frozen"
	else:
		h.pose(ps)
	h.apply_wrong(wrong, rng)
	h.uncanny(rng)
	if bool(d.get("mold", false)):
		h.tune({"mold": 0.55})
	match who:
		"kid":
			if rng.randf() < 0.6:
				var bal := Node3D.new()
				_balloon(bal)
				bal.position = Vector3(0, 1.45, 0)
				h.hold(bal, "r", Vector3(0, 0.2, 0))
				h.pose("hold_up")
		"oldman":
			box(h.hand("l"), Vector3(0.45, 0.32, 0.01), Vector3(0.15, -0.12, 0.08), Mats.col(Color(0.82, 0.8, 0.74), "paper", 1.0, {"pale": 0.3}), Vector3(0, 0, 0.1))
		"suit":
			box(h.hand("r"), Vector3(0.42, 0.3, 0.09), Vector3(0, -0.2, 0), Mats.col(Color(0.2, 0.12, 0.06), "metal", 0.3, {"pale": 0.3}))
		"couple":
			var h2 := Human.make("civ_b", int(d.get("seed", 1)) + 7, true)
			h2.pose("sit_ground")
			holder.add_child(h2)
			if wrong == "fused":
				h2.position = Vector3(0.12, 0, 0.05)
				h2.rotation.y = PI * 0.85
				h2.scale = Vector3(1.0, 1.06, 1.0)
			else:
				h2.position = Vector3(0.6, 0, 0)
	if wrong == "melt_bench":
		var b := Node3D.new()
		_bench(b)
		swap_mats(b, Mats.col(Color(0.58, 0.42, 0.28), "wood", 1.0, {"pale": 0.25, "smear": 1.0}))
		holder.add_child(b)
		b.position = Vector3(0, -0.05, -0.05)
		h.position.z = 0.05
	if wrong == "stroller_fused":
		var s := Node3D.new()
		_stroller(s)
		holder.add_child(s)
		s.position = Vector3(0, 0, 0.45)
		s.rotation.y = PI
		h.pose("push")
		h.position.y -= 0.35
		h.position.z = -0.1
	if wrong == "seated_air":
		h.position.y += 0.0
	h.breathe = 1.0 if rng.randf() < 0.4 else 0.0
	h.react = bool(d.get("react", false))
	if h.react and cx.get("player") != null:
		h.look_target = cx.player
	# тихий звук рядом с некоторыми копиями
	if rng.randf() < 0.3:
		var se := SoundEmitter.new()
		se.snd = ["copy_whisper", "copy_breath", "copy_moan"][rng.randi_range(0, 2)]
		se.every = rng.randf_range(9.0, 20.0)
		se.vol = -14.0
		se.position = Vector3(0, 1.4, 0)
		holder.add_child(se)
	holder.set_meta("copy", true)
	return holder


static func copy_self(cx: Node3D, d: Dictionary) -> Node3D:
	var holder := Node3D.new()
	var b := Node3D.new()
	_bench(b)
	holder.add_child(b)
	var h := Human.make("player", 77, true)
	holder.add_child(h)
	h.pose("film")
	h.position = Vector3(0, -0.45, 0.02)
	(h.j["pelvis"] as Node3D).position.y = 0.95
	h.pose("sit")
	h._r("sh_l", -1.2, 0.4, -0.2)
	h._r("sh_r", -1.2, -0.4, 0.2)
	h._r("el_l", -1.1)
	h._r("el_r", -1.1)
	h.position = Vector3(0, 0.0, 0.05)
	# видеокамера в руках, горит REC
	var cam := Node3D.new()
	box(cam, Vector3(0.12, 0.13, 0.28), Vector3(0, 0, 0), Mats.col(Color(0.1, 0.1, 0.1), "metal", 0.3, {"pale": 0.2}))
	cyl(cam, 0.045, 0.045, 0.08, Vector3(0, 0.0, 0.17), m_black(), Vector3(PI * 0.5, 0, 0), 10)
	sph(cam, 0.012, Vector3(0.04, 0.05, 0.12), m_emit(Color(1.0, 0.05, 0.05), 3.0))
	h.hold(cam, "r", Vector3(-0.08, -0.12, 0.08))
	h.react = true
	h.look_target = cx.player if cx.get("player") != null else null
	var se := SoundEmitter.new()
	se.snd = "tape_whir"
	se.every = 0.0
	se.vol = -16.0
	se.position = Vector3(0, 1.0, 0)
	holder.add_child(se)
	var tr := ProxTrigger.new()
	tr.radius = 4.0
	tr.once = true
	tr.cb = func() -> void:
		if Game.main != null:
			Game.main.burst(0.8)
		Snd.play("sting_low", -6.0)
		Game.say("sub.self")
	holder.add_child(tr)
	return holder


# ------------------------------------------------------------ надписи, метки, таблички

static func label(text: String, font: Font, px: float, ink: Color, outline := 0) -> Label3D:
	var lb := Label3D.new()
	lb.text = text
	lb.font = font
	lb.font_size = 64
	lb.pixel_size = px
	lb.modulate = ink
	lb.set_meta("ink", ink)
	lb.outline_size = outline
	lb.double_sided = false
	lb.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	lb.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	lb.visibility_range_end = 30.0
	lb.autowrap_mode = TextServer.AUTOWRAP_OFF
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return lb


static func graffiti(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var key := String(d.get("key", "graf.g05"))
	var txt := ""
	if key == "graf.arrow":
		txt = "<---" if bool(d.get("flip", false)) else "--->"
	else:
		txt = Loc.t(key)
	var inks := [Color(0.16, 0.1, 0.06), Color(0.08, 0.07, 0.07), Color(0.32, 0.06, 0.04), Color(0.1, 0.12, 0.2)]
	var ink: Color = inks[absi(hash(key)) % inks.size()]
	var lb := label(txt, font_hand(), 0.0042 if key != "graf.arrow" else 0.007, ink)
	lb.position = Vector3(float(d.get("along", 0.0)), 0, 0.012)
	lb.rotation.z = (float(absi(hash(d.p)) % 100) / 100.0 - 0.5) * 0.12
	lb.width = 400.0
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.add_child(lb)
	return n


static func cable_tag(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var dist := int(d.get("dist", 0))
	var txt := ""
	if bool(d.get("floor", false)):
		var t := Node3D.new()
		n.add_child(t)
		box(t, Vector3(0.12, 0.004, 0.5), Vector3(0, 0.003, 0), Mats.col(Color(0.9, 0.75, 0.15), "metal", 0.1))
		box(t, Vector3(0.28, 0.004, 0.12), Vector3(0, 0.003, -0.25), Mats.col(Color(0.9, 0.75, 0.15), "metal", 0.1), Vector3(0, PI * 0.25, 0))
		var lb0 := label("%d M" % dist, font_sign(), 0.003, Color(0.1, 0.1, 0.1))
		lb0.rotation = Vector3(-PI * 0.5, 0, 0)
		lb0.position = Vector3(0.18, 0.006, 0.1)
		n.add_child(lb0)
		return n
	# на стене: жёлтая лента со стрелкой к станции
	var side := int(d.get("side", 0))
	var to := int(d.get("dir", 0))
	box(n, Vector3(0.42, 0.11, 0.006), Vector3(0, 0, 0.004), Mats.col(Color(0.9, 0.75, 0.15), "metal", 0.1))
	# стрелка: направление к станции относительно стены
	var o_side: Vector2i = LD.DIRS[side]
	var o_to: Vector2i = LD.DIRS[to]
	var right := Vector2i(-o_side.y, o_side.x)
	var arrow := "<--"
	if o_to == -o_side:
		arrow = "v"
	elif o_to == o_side:
		arrow = "^"
	elif o_to == right:
		arrow = "-->"
	else:
		arrow = "<--"
	txt = "KV31 %s %dM" % [arrow, dist]
	var lb := label(txt, font_sign(), 0.0022, Color(0.08, 0.07, 0.06))
	lb.position = Vector3(0, 0, 0.009)
	n.add_child(lb)
	return n


static func sign_board(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var s := float(d.get("size", 1.0))
	box(n, Vector3(1.3 * s, 0.5 * s, 0.02), Vector3(0, 0, 0.012), Mats.col(Color(0.88, 0.88, 0.84), "metal", 0.2))
	var lb := label(Loc.t(String(d.get("key", "sign.station"))), font_sign(), 0.0034 * s, Color(0.07, 0.08, 0.1))
	lb.position = Vector3(0, 0, 0.026)
	lb.width = 340.0
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.add_child(lb)
	return n


static func note(cx: Node3D, d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var key := String(d.get("key", "note.n01"))
	if bool(d.get("clip", false)) or key.begins_with("note.a_") or key == "note.u01" or key == "note.u04":
		if model(n, "clipboard", Vector3.ZERO, 0.0, 1.0, false) != null:
			box(n, Vector3(0.2, 0.004, 0.27), Vector3(0, 0.03, 0.01), Mats.col(Color(0.95, 0.93, 0.86), "paper", 1.0))
			interactable(n, Vector3(0.5, 0.25, 0.5), Vector3(0, 0.1, 0), "ui.read", func() -> void:
				Game.show_note(key))
			return n
	box(n, Vector3(0.21, 0.004, 0.29), Vector3(0, 0.003, 0), Mats.col(Color(0.95, 0.93, 0.86), "paper", 1.0))
	box(n, Vector3(0.21, 0.004, 0.29), Vector3(0.03, 0.006, 0.02), Mats.col(Color(0.92, 0.9, 0.82), "paper", 1.0), Vector3(0, 0.2, 0))
	interactable(n, Vector3(0.5, 0.25, 0.5), Vector3(0, 0.1, 0), "ui.read", func() -> void:
		Game.show_note(key))
	return n


static func stain(d: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var s := float(d.get("s", 1.4))
	var mat: Material
	if bool(d.get("burn", false)):
		mat = decal_mat("burn", {"radial": 1.0, "tint": Color(0.02, 0.02, 0.015, 0.75)})
	elif bool(d.get("tire", false)):
		mat = decal_mat("tire", {"stripes": 1.0, "tint": Color(0.03, 0.03, 0.03, 0.65)})
		s = 2.5
	elif bool(d.get("wet", false)):
		mat = decal_mat("wet", {"radial": 1.0, "tint": Color(0.05, 0.045, 0.02, 0.5), "sheen": 1.0})
	else:
		mat = decal_mat("dirt", {"radial": 1.0, "tint": Color(0.18, 0.14, 0.06, 0.35)})
	var q := quad(n, Vector2(s, s * (2.4 if bool(d.get("tire", false)) else 1.0)), Vector3(0, 0.006, 0), mat, Vector3(-PI * 0.5, 0, 0))
	q.set_instance_shader_parameter("seed", rng.randf() * 10.0)
	return n


static func mold_patch(d: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var s := float(d.get("s", 1.0))
	var mat := decal_mat("mold", {"tex": "mold", "tint": Color(1, 1, 1, 0.92), "tex_color": 1.0})
	var q := quad(n, Vector2(s, s * rng.randf_range(0.7, 1.3)), Vector3(float(d.get("along", 0.0)), 0, 0.012), mat, Vector3(0, 0, rng.randf() * TAU))
	q.set_instance_shader_parameter("seed", rng.randf())
	return n


static func papers(rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	for k in rng.randi_range(1, 4):
		box(n, Vector3(0.21, 0.002, 0.29), Vector3(rng.randf_range(-0.4, 0.4), 0.002 + k * 0.001, rng.randf_range(-0.4, 0.4)),
			Mats.col(Color(0.9, 0.88, 0.8), "paper", 1.0), Vector3(0, rng.randf() * TAU, 0))
	return n


static func grass_patch(d: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var s := float(d.get("s", 3.0))
	var mat := decal_mat("grass", {"radial": 1.0, "tint": Color(0.3, 0.42, 0.16, 0.8)})
	var q := quad(n, Vector2(s, s), Vector3(0, 0.007, 0), mat, Vector3(-PI * 0.5, 0, 0))
	q.set_instance_shader_parameter("seed", rng.randf() * 5.0)
	var gm := Mats.col(Color(0.32, 0.45, 0.18), "leaves", 0.3)
	for k in 26:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * s * 0.38
		var hgt := rng.randf_range(0.06, 0.16)
		box(n, Vector3(0.012, hgt, 0.004), Vector3(cos(a) * r, hgt * 0.5, sin(a) * r), gm, Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, 0))
	return n


# ------------------------------------------------------------ Async

static func async_item(cx: Node3D, what: String, d: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var olive := Mats.col(Color(0.24, 0.27, 0.22), "metal", 0.4)
	var blk := m_black()
	match what:
		"lamp_stand", "lamp_stand_off":
			var on := what == "lamp_stand"
			for k in 3:
				var a := k * TAU / 3
				rod(n, Vector3(0, 1.1, 0), Vector3(cos(a) * 0.45, 0, sin(a) * 0.45), 0.015, blk, 4)
			rod(n, Vector3(0, 1.1, 0), Vector3(0, 1.85, 0), 0.02, blk, 6)
			var head := Node3D.new()
			n.add_child(head)
			head.position = Vector3(0, 1.95, 0)
			head.rotation.x = -0.5
			if model(head, "portable_searchlight", Vector3(0, -0.12, -0.15), PI, 2.0, false) == null:
				box(head, Vector3(0.36, 0.28, 0.14), Vector3.ZERO, blk)
			box(head, Vector3(0.3, 0.22, 0.01), Vector3(0, 0, 0.075), m_emit(Color(1.0, 0.97, 0.9), 3.5) if on else Mats.col(Color(0.5, 0.5, 0.48), "metal", 0.2))
			if bool(d.get("fallen", false)):
				n.rotation.z = 1.35
				n.position.y = 0.2
				n.set_meta("keep_rot", false)
			rod(n, Vector3(0, 0.02, 0), Vector3(0.9, 0.02, 0.6), 0.012, blk, 4)
		"case", "case_open":
			if model(n, "metal_toolbox" if what == "case" else "industrial_pastic_container", Vector3.ZERO, 0.0, 1.3) != null:
				return n
			box(n, Vector3(0.7, 0.32, 0.45), Vector3(0, 0.16, 0), olive)
			if what == "case_open":
				box(n, Vector3(0.7, 0.06, 0.45), Vector3(0, 0.45, -0.25), olive, Vector3(-1.2, 0, 0))
				box(n, Vector3(0.6, 0.04, 0.35), Vector3(0, 0.3, 0), Mats.col(Color(0.12, 0.12, 0.12), "fabric", 0.8))
			else:
				box(n, Vector3(0.2, 0.04, 0.05), Vector3(0, 0.34, 0), blk)
		"crate":
			if model(n, "wooden_military_crate" if rng.randf() < 0.6 else "old_military_crate") != null:
				return n
			box(n, Vector3(0.8, 0.6, 0.8), Vector3(0, 0.3, 0), Mats.col(Color(0.5, 0.42, 0.3), "wood", 0.8))
			var lb := label("ASYNC  KV31", font_sign(), 0.0025, Color(0.1, 0.1, 0.1))
			lb.position = Vector3(0, 0.35, 0.41)
			n.add_child(lb)
		"table":
			box(n, Vector3(1.8, 0.04, 0.75), Vector3(0, 0.76, 0), Mats.col(Color(0.75, 0.75, 0.72), "metal", 0.3))
			for sx in [-0.8, 0.8]:
				rod(n, Vector3(sx, 0, -0.3), Vector3(sx, 0.75, 0.3), 0.015, blk, 4)
				rod(n, Vector3(sx, 0, 0.3), Vector3(sx, 0.75, -0.3), 0.015, blk, 4)
			for k in 2:
				var mon := Node3D.new()
				n.add_child(mon)
				mon.position = Vector3(-0.45 + k * 0.8, 0.78, -0.1)
				mon.rotation.y = (k - 0.5) * 0.4
				box(mon, Vector3(0.42, 0.36, 0.4), Vector3(0, 0.2, 0), Mats.col(Color(0.75, 0.73, 0.66), "metal", 0.3))
				box(mon, Vector3(0.34, 0.26, 0.01), Vector3(0, 0.21, 0.2), Mats.col(Color(0.2, 0.6, 0.3), "noise", 1.0, {"emit": 0.7, "emit_color": Vector3(0.2, 0.9, 0.4)}))
			box(n, Vector3(0.45, 0.03, 0.15), Vector3(0.1, 0.79, 0.22), Mats.col(Color(0.75, 0.73, 0.66), "metal", 0.3))
			collider(n, Vector3(1.8, 0.8, 0.75), Vector3(0, 0.4, 0))
		"spool":
			cyl(n, 0.4, 0.4, 0.05, Vector3(0, 0.4, -0.2), Mats.col(Color(0.55, 0.42, 0.25), "wood", 0.8), Vector3(PI * 0.5, 0, 0), 14)
			cyl(n, 0.4, 0.4, 0.05, Vector3(0, 0.4, 0.2), Mats.col(Color(0.55, 0.42, 0.25), "wood", 0.8), Vector3(PI * 0.5, 0, 0), 14)
			cyl(n, 0.3, 0.3, 0.36, Vector3(0, 0.4, 0), Mats.col(Color(0.75, 0.32, 0.08), "metal", 0.3), Vector3(PI * 0.5, 0, 0), 14)
		"generator":
			if model(n, "portable_generator", Vector3.ZERO, 0.0, 1.1) == null:
				box(n, Vector3(0.9, 0.6, 0.6), Vector3(0, 0.35, 0), Mats.col(Color(0.7, 0.55, 0.12), "metal", 0.4))
			var se := SoundEmitter.new()
			se.snd = "generator"
			se.every = 0.0
			se.vol = -10.0
			se.position = Vector3(0, 0.5, 0)
			n.add_child(se)
		"board":
			box(n, Vector3(1.4, 0.95, 0.03), Vector3(0, 1.35, 0), Mats.col(Color(0.92, 0.92, 0.9), "metal", 0.1))
			for sx in [-0.65, 0.65]:
				rod(n, Vector3(sx, 0, 0), Vector3(sx, 1.8, 0), 0.02, blk, 4)
			var lb2 := label(Loc.t("sign.board"), font_hand(), 0.0011, Color(0.1, 0.12, 0.35))
			lb2.position = Vector3(0, 1.4, 0.02)
			lb2.width = 1150.0
			lb2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			n.add_child(lb2)
		"rover":
			box(n, Vector3(0.5, 0.22, 0.7), Vector3(0, 0.18, 0), Mats.col(Color(0.65, 0.62, 0.55), "metal", 0.4))
			for sx in [-0.3, 0.3]:
				box(n, Vector3(0.1, 0.18, 0.75), Vector3(sx, 0.1, 0), blk)
			rod(n, Vector3(0, 0.29, -0.15), Vector3(0, 0.6, -0.15), 0.02, blk, 4)
			box(n, Vector3(0.14, 0.1, 0.16), Vector3(0, 0.65, -0.15), blk)
			sph(n, 0.012, Vector3(0.05, 0.69, -0.07), m_emit(Color(1, 0.1, 0.05), 2.0))
		"barrier":
			model(n, "concrete_road_barrier")
		"gasmask":
			model(n, "old_gas_mask", Vector3(0, 0.08, 0), 0.0, 1.0, false)
			n.set_meta("tilt", 1.4)
		"cones":
			cyl(n, 0.02, 0.15, 0.5, Vector3(0, 0.25, 0), Mats.col(Color(0.95, 0.4, 0.08), "metal", 0.1), Vector3.ZERO, 10)
			box(n, Vector3(0.32, 0.03, 0.32), Vector3(0, 0.015, 0), Mats.col(Color(0.95, 0.4, 0.08), "metal", 0.1))
		"tripod":
			for k2 in 3:
				var a2 := k2 * TAU / 3
				rod(n, Vector3(0, 1.3, 0), Vector3(cos(a2) * 0.4, 0, sin(a2) * 0.4), 0.012, blk, 4)
			box(n, Vector3(0.14, 0.15, 0.32), Vector3(0, 1.4, 0), Mats.col(Color(0.15, 0.15, 0.15), "metal", 0.3))
			cyl(n, 0.05, 0.05, 0.1, Vector3(0, 1.41, 0.2), blk, Vector3(PI * 0.5, 0, 0), 10)
			sph(n, 0.012, Vector3(0.05, 1.49, 0.14), m_emit(Color(1, 0.05, 0.05), 3.0))
		"radio":
			if model(n, "vintage_radio_transceiver", Vector3.ZERO, 0.0, 0.8, false) == null:
				box(n, Vector3(0.32, 0.22, 0.16), Vector3(0, 0.11, 0), olive)
				rod(n, Vector3(0.12, 0.22, 0), Vector3(0.18, 0.75, -0.05), 0.006, blk, 4)
			box(n, Vector3(0.06, 0.03, 0.01), Vector3(-0.1, 0.25, 0.16), m_emit(Color(0.9, 0.6, 0.2), 1.2))
			var rad := RadioPlayer.new()
			rad.position = Vector3(0, 0.2, 0)
			n.add_child(rad)
			interactable(n, Vector3(0.6, 0.5, 0.6), Vector3(0, 0.2, 0), "ui.radio", rad.toggle)
		"motioncam":
			if model(n, "security_camera_01", Vector3(0, -0.1, 0.15), 0.0, 1.0, false) == null:
				box(n, Vector3(0.14, 0.12, 0.25), Vector3(0, 0, 0.18), Mats.col(Color(0.8, 0.8, 0.76), "metal", 0.3))
				rod(n, Vector3(0, 0, 0), Vector3(0, 0, 0.1), 0.015, blk, 4)
			var led := sph(n, 0.012, Vector3(0.04, 0.03, 0.31), m_emit(Color(1, 0.05, 0.05), 3.0))
			led.set_meta("blink", true)
		"winch":
			# стальная рама над ямой, барабан, трос вниз
			var steel := Mats.col(Color(0.4, 0.42, 0.42), "metal", 0.6)
			var hw := LD.C * 0.5 + 0.1
			for sx in [-hw, hw]:
				for sz in [-hw, hw]:
					box(n, Vector3(0.1, 2.4, 0.1), Vector3(sx, 1.2, sz), steel)
			box(n, Vector3(hw * 2 + 0.1, 0.12, 0.12), Vector3(0, 2.4, -hw), steel)
			box(n, Vector3(hw * 2 + 0.1, 0.12, 0.12), Vector3(0, 2.4, hw), steel)
			box(n, Vector3(0.12, 0.12, hw * 2 + 0.1), Vector3(0, 2.42, 0), steel)
			cyl(n, 0.16, 0.16, 0.5, Vector3(hw - 0.4, 2.25, 0), Mats.col(Color(0.7, 0.55, 0.12), "metal", 0.4), Vector3(0, 0, PI * 0.5), 12)
			rod(n, Vector3(0, 2.4, 0), Vector3(0, -6.5, 0), 0.012, blk, 4)
			for k3 in 4:
				box(n, Vector3(LD.C, 0.04, 0.4), Vector3(0, 0.02, -hw - 0.25 + (k3 % 2) * (hw * 2 + 0.5)), Mats.col(Color(0.45, 0.42, 0.35), "wood", 0.6))
			var lbw := label("WINCH 2 / 14D\nDO NOT DESCEND\nWITHOUT TETHER", font_sign(), 0.0022, Color(0.85, 0.1, 0.08))
			lbw.position = Vector3(0, 1.6, -hw - 0.06)
			n.add_child(lbw)
		"ladder":
			var rope := Mats.col(Color(0.55, 0.45, 0.3), "fabric", 0.6)
			for sx2 in [-0.22, 0.22]:
				rod(n, Vector3(sx2, 0.0, 0.0), Vector3(sx2, 9.5, 0.0), 0.015, rope, 4)
			for k4 in 28:
				box(n, Vector3(0.48, 0.03, 0.05), Vector3(0, 0.25 + k4 * 0.33, 0), Mats.col(Color(0.5, 0.38, 0.25), "wood", 0.7))
			var to := String(d.get("to", "winch_0"))
			interactable(n, Vector3(0.7, 2.0, 0.5), Vector3(0, 1.0, 0), "ui.climb", func() -> void:
				if cx.has_method("climb_ladder"):
					cx.climb_ladder(to))
	return n


static func threshold(cx: Node3D) -> Node3D:
	var n := Node3D.new()
	var steel := Mats.col(Color(0.42, 0.44, 0.45), "metal", 0.6)
	# рама из двух клеток шириной
	var w := 3.0
	box(n, Vector3(0.35, 2.7, 0.5), Vector3(-w * 0.5 - 0.17, 1.35, -0.1), steel)
	box(n, Vector3(0.35, 2.7, 0.5), Vector3(w * 0.5 + 0.17, 1.35, -0.1), steel)
	box(n, Vector3(w + 0.7, 0.35, 0.5), Vector3(0, 2.52, -0.1), steel)
	for k in 6:
		box(n, Vector3(0.1, 0.1, 0.55), Vector3(-w * 0.5 - 0.17, 0.3 + k * 0.4, -0.1), Mats.col(Color(0.7, 0.55, 0.12), "metal", 0.4))
	# светящийся проём
	var glow := Mats.prop("threshold_glow", {"tex": "noise", "tex_mix": 0.4, "color": Vector3(0.75, 1.0, 0.85), "emit": 3.0, "emit_color": Vector3(0.6, 1.0, 0.75), "smear": 2.0})
	box(n, Vector3(w, 2.35, 0.05), Vector3(0, 1.17, -0.25), glow)
	# полосы на полу
	box(n, Vector3(w + 1.0, 0.004, 1.4), Vector3(0, 0.004, 0.75), Mats.prop("hazard_floor", {"tex": "hazard", "tex_mix": 1.0, "uv_scale": Vector2(4, 1)}))
	var lb := label(Loc.t("sign.threshold"), font_sign(), 0.0042, Color(0.88, 0.1, 0.08))
	lb.position = Vector3(0, 2.95, 0.16)
	lb.width = 900.0
	n.add_child(lb)
	var se := SoundEmitter.new()
	se.snd = "threshold_hum"
	se.every = 0.0
	se.vol = -4.0
	se.max_dist = 35.0
	se.position = Vector3(0, 1.2, 0)
	n.add_child(se)
	trigger(n, Vector3(w - 0.4, 2.0, 0.6), Vector3(0, 1.0, 0.2), func() -> void:
		if cx.has_method("enter_threshold"):
			cx.enter_threshold())
	return n


static func null_zone(cx: Node3D, d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var dist := Mats.prop("null_shimmer", {"tex": "noise", "tex_mix": 1.0, "color": Vector3(0.6, 1.0, 0.75), "emit": 0.9, "emit_color": Vector3(0.4, 1.0, 0.6), "smear": 6.0, "uv_scale": Vector2(3, 3)})
	var core := sph(n, 0.35, Vector3(0, 0.9, 0), dist, Vector3(0.6, 2.2, 0.6), 10)
	core.set_meta("spin", true)
	var mote := Mats.col(Color(0.7, 1.0, 0.8), "metal", 0.0, {"emit": 2.0, "emit_color": Vector3(0.5, 1.0, 0.7)})
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(d.p)
	for k in 14:
		var m := sph(n, 0.012, Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0.1, 2.2), rng.randf_range(-0.6, 0.6)), mote, Vector3.ONE, 4)
		m.set_meta("float", rng.randf() * TAU)
	var anim := NullAnim.new()
	n.add_child(anim)
	var id := String(d.get("id", "null_0"))
	trigger(n, Vector3(0.9, 2.0, 0.9), Vector3(0, 1.0, 0), func() -> void:
		if cx.has_method("enter_null"):
			cx.enter_null(id))
	return n


static func nest(rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var black := Mats.col(Color(0.03, 0.03, 0.028), "fiber", 0.5, {"wet": 1.0, "smear": 1.5})
	for k in 9:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 1.3)
		sph(n, rng.randf_range(0.35, 0.8), Vector3(cos(a) * r, rng.randf_range(-0.1, 0.25), sin(a) * r), black,
			Vector3(rng.randf_range(1.0, 1.8), rng.randf_range(0.35, 0.7), rng.randf_range(1.0, 1.8)), 10)
	for k2 in 16:
		var a2 := rng.randf() * TAU
		var s := Vector3(cos(a2) * rng.randf_range(0.5, 1.4), 0.2, sin(a2) * rng.randf_range(0.5, 1.4))
		var e := s + Vector3(rng.randf_range(-1, 1), rng.randf_range(0.6, 2.6), rng.randf_range(-1, 1))
		rod(n, s, e, rng.randf_range(0.015, 0.04), black, 4)
	# остатки снаряжения
	box(n, Vector3(0.6, 0.3, 0.4), Vector3(1.4, 0.15, 0.6), Mats.col(Color(0.24, 0.27, 0.22), "metal", 0.4, {"mold": 0.7}), Vector3(0.2, 0.7, 0.1))
	var se := SoundEmitter.new()
	se.snd = "nest_creak"
	se.every = 14.0
	se.vol = -10.0
	se.position = Vector3(0, 0.5, 0)
	n.add_child(se)
	return n


static func house_item(what: String, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var fab := m_cloth(Color(0.45, 0.32, 0.3))
	var wd := Mats.col(Color(0.45, 0.3, 0.2), "wood", 0.8)
	match what:
		"sofa":
			if model(n, "Sofa_01", Vector3.ZERO, 0.0, 1.15) != null:
				return n
			box(n, Vector3(2.0, 0.42, 0.85), Vector3(0, 0.21, 0), fab)
			box(n, Vector3(2.0, 0.5, 0.2), Vector3(0, 0.62, -0.33), fab)
			box(n, Vector3(0.2, 0.3, 0.85), Vector3(-0.9, 0.55, 0), fab)
			box(n, Vector3(0.2, 0.3, 0.85), Vector3(0.9, 0.55, 0), fab)
			collider(n, Vector3(2.0, 0.8, 0.85), Vector3(0, 0.4, 0))
		"armchair":
			if model(n, "ArmChair_01") != null:
				return n
			box(n, Vector3(0.9, 0.42, 0.85), Vector3(0, 0.21, 0), fab)
			box(n, Vector3(0.9, 0.55, 0.2), Vector3(0, 0.64, -0.33), fab)
		"tv":
			_tv(n)
			var se := SoundEmitter.new()
			se.snd = "tv_static"
			se.every = 0.0
			se.vol = -14.0
			se.position = Vector3(0, 0.8, 0)
			n.add_child(se)
		"rug":
			box(n, Vector3(2.2, 0.01, 1.6), Vector3(0, 0.005, 0), m_cloth(Color(0.5, 0.2, 0.18)))
		"floorlamp":
			rod(n, Vector3(0, 0, 0), Vector3(0, 1.5, 0), 0.015, m_black(), 6)
			cyl(n, 0.12, 0.22, 0.28, Vector3(0, 1.55, 0), m_emit(Color(1.0, 0.85, 0.6), 1.2))
		"clock":
			model(n, "wall_clock", Vector3.ZERO, 0.0, 1.0, false)
		"stove":
			model(n, "electric_stove", Vector3.ZERO, 0.0, 1.05)
		"microwave":
			model(n, "vintage_microwave", Vector3.ZERO, 0.0, 0.55, false)
		"frame":
			box(n, Vector3(0.5, 0.4, 0.03), Vector3(0, 0, 0.015), wd)
			box(n, Vector3(0.42, 0.32, 0.01), Vector3(0, 0, 0.032), Mats.prop("photo_smear", {"tex": "face_smear", "tex_mix": 1.0, "color": Vector3(0.8, 0.75, 0.7)}))
		"counter":
			box(n, Vector3(2.2, 0.9, 0.6), Vector3(0, 0.45, 0), Mats.col(Color(0.82, 0.8, 0.72), "wood", 0.3))
			box(n, Vector3(2.25, 0.04, 0.64), Vector3(0, 0.92, 0), Mats.col(Color(0.5, 0.5, 0.48), "concrete", 0.5))
			collider(n, Vector3(2.2, 0.95, 0.6), Vector3(0, 0.47, 0))
		"fridge":
			box(n, Vector3(0.75, 1.75, 0.7), Vector3(0, 0.88, 0), m_plastic(Color(0.9, 0.88, 0.82)))
			box(n, Vector3(0.03, 0.4, 0.03), Vector3(-0.3, 1.2, 0.37), m_metal())
			collider(n, Vector3(0.75, 1.75, 0.7), Vector3(0, 0.88, 0))
			var se2 := SoundEmitter.new()
			se2.snd = "fridge_hum"
			se2.every = 0.0
			se2.vol = -16.0
			se2.position = Vector3(0, 1.0, 0)
			n.add_child(se2)
		"table":
			if model(n, "WoodenTable_01", Vector3.ZERO, 0.0, Vector3(0.75, 1.35, 1.1)) != null:
				for k in 3:
					model(n, "dining_chair_02", Vector3(-0.45 + k * 0.45, 0, 0.62 if k != 1 else -0.62), PI if k != 1 else 0.0, 1.0, false)
				return n
			box(n, Vector3(1.2, 0.04, 0.8), Vector3(0, 0.75, 0), wd)
			for sx in [-0.55, 0.55]:
				for sz in [-0.35, 0.35]:
					box(n, Vector3(0.05, 0.75, 0.05), Vector3(sx, 0.37, sz), wd)
			for k in 3:
				var ch := Node3D.new()
				n.add_child(ch)
				ch.position = Vector3(-0.5 + k * 0.5, 0, 0.65 if k != 1 else -0.65)
				ch.rotation.y = PI if k != 1 else 0.0
				_chair(ch)
				swap_mats(ch, wd)
			collider(n, Vector3(1.2, 0.8, 0.8), Vector3(0, 0.4, 0))
		"stairs":
			for k2 in 12:
				box(n, Vector3(1.0, 0.2, 0.3), Vector3(0, 0.1 + k2 * 0.2, -1.2 + k2 * 0.25), Mats.col(Color(0.5, 0.36, 0.24), "wood", 0.8))
			box(n, Vector3(0.05, 1.0, 3.2), Vector3(-0.5, 1.6, 0.2), wd, Vector3(-0.68, 0, 0))
			collider(n, Vector3(1.0, 1.2, 3.0), Vector3(0, 0.6, 0.2), 1, Vector3(-0.68, 0, 0))
		"phone":
			box(n, Vector3(0.18, 0.26, 0.08), Vector3(0, 0, 0.04), m_plastic(Color(0.85, 0.8, 0.7)))
			box(n, Vector3(0.05, 0.22, 0.06), Vector3(0.05, 0, 0.1), m_plastic(Color(0.85, 0.8, 0.7)))
	return n


static func sound_emitter(d: Dictionary) -> Node3D:
	var se := SoundEmitter.new()
	se.snd = String(d.get("snd", "copy_whisper"))
	se.every = float(d.get("every", 0.0))
	se.vol = -6.0
	return se


static func voice_wall(cx: Node3D) -> Node3D:
	var v := VoiceWall.new()
	return v


static func red_city(d: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var w := float(d.get("w", 60.0))
	var dep := float(d.get("d", 80.0))
	var win := Mats.prop("city_win", {"tex": "city_windows", "tex_mix": 0.0, "color": Vector3(0.02, 0.015, 0.015), "emit": 0.55, "emit_color": Vector3(1.0, 0.1, 0.05),
		"emit_mask": 1.0, "world_uv": 1.0, "world_scale": Vector2(24.0, 48.0), "fog_mul": 0.15})
	var dark := Mats.col(Color(0.02, 0.015, 0.015), "concrete", 0.5, {"fog_mul": 0.15})
	var road := Mats.col(Color(0.05, 0.04, 0.04), "asphalt", 1.0, {"emit": 0.06, "emit_color": Vector3(0.6, 0.05, 0.03), "fog_mul": 0.15})
	# город лежит ниже перехода: улица, дома с красными окнами, деревья, поворот
	var base_y := -14.0
	box(n, Vector3(w * 3.0, 0.2, dep * 2.5), Vector3(0, base_y, -dep * 0.4), dark)
	box(n, Vector3(6.0, 0.22, dep * 2.4), Vector3(rng.randf_range(-6, 6), base_y + 0.05, -dep * 0.4), road)
	for k in 46:
		var bx := rng.randf_range(-w * 1.3, w * 1.3)
		var bz := rng.randf_range(-dep * 1.4, dep * 0.1)
		if absf(bx) < 6.0:
			continue
		var bw := rng.randf_range(5.0, 12.0)
		var bh := rng.randf_range(6.0, 30.0)
		var bd := rng.randf_range(5.0, 12.0)
		var b := box(n, Vector3(bw, bh, bd), Vector3(bx, base_y + bh * 0.5, bz), win)
		b.material_override = win
	var tree := Mats.col(Color(0.01, 0.01, 0.01), "leaves", 0.0, {"fog_mul": 0.15})
	for k2 in 30:
		var tx := rng.randf_range(-9, 9)
		if absf(tx) < 3.5:
			continue
		var tz := rng.randf_range(-dep * 1.3, 0.0)
		cyl(n, 0.15, 0.2, 3.0, Vector3(tx, base_y + 1.5, tz), tree)
		sph(n, 1.6, Vector3(tx, base_y + 3.8, tz), tree, Vector3(1, 1.2, 1), 8)
	box(n, Vector3(0.1, 2.6, 0.1), Vector3(4.0, base_y + 1.3, -10.0), m_iron())
	box(n, Vector3(0.9, 0.9, 0.05), Vector3(4.0, base_y + 2.8, -10.0), Mats.col(Color(0.8, 0.65, 0.1), "metal", 0.2, {"emit": 0.15, "emit_color": Vector3(0.6, 0.1, 0.05)}), Vector3(0, 0, PI * 0.25))
	n.set_meta("no_fog", true)
	return n


# ------------------------------------------------------------ вспомогательные узлы

class SoundEmitter extends Node3D:
	var snd := "copy_whisper"
	var every := 0.0       # 0 — зациклено
	var vol := -8.0
	var max_dist := 22.0
	var _p: AudioStreamPlayer3D
	var _t := 0.0

	func _ready() -> void:
		_t = randf_range(1.0, maxf(every, 2.0))
		if every <= 0.0:
			var st := Snd.get_stream(snd)
			if st == null:
				return
			_p = AudioStreamPlayer3D.new()
			_p.stream = st
			_p.volume_db = vol
			_p.max_distance = max_dist
			_p.unit_size = 2.5
			_p.bus = "World"
			_p.attenuation_filter_cutoff_hz = 5000.0
			add_child(_p)
			_p.play(randf() * 2.0)
			_p.finished.connect(func() -> void: _p.play())

	func _process(dt: float) -> void:
		if every <= 0.0:
			return
		_t -= dt
		if _t <= 0.0:
			_t = every * randf_range(0.7, 1.4)
			var cam := get_viewport().get_camera_3d()
			if cam != null and cam.global_position.distance_to(global_position) < max_dist:
				Snd.play_at(snd, global_position, get_parent(), vol, randf_range(0.9, 1.1), max_dist)


class ProxTrigger extends Node3D:
	var radius := 3.0
	var once := true
	var cb: Callable
	var _done := false

	func _process(_dt: float) -> void:
		if _done:
			return
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var d := cam.global_position.distance_to(global_position + Vector3(0, 1.0, 0))
		if d < radius:
			_done = once
			if cb.is_valid():
				cb.call()


class NullAnim extends Node3D:
	var _t := 0.0

	func _process(dt: float) -> void:
		_t += dt
		for ch in get_parent().get_children():
			if ch.has_meta("spin"):
				(ch as Node3D).rotation.y = _t * 0.7
				(ch as Node3D).scale = Vector3(0.6 + sin(_t * 3.3) * 0.08, 2.2 + sin(_t * 1.7) * 0.2, 0.6 + cos(_t * 2.9) * 0.08)
			elif ch.has_meta("float"):
				var ph: float = ch.get_meta("float")
				var c := ch as Node3D
				c.position.y = fposmod(c.position.y + dt * (0.2 + 0.1 * sin(ph)), 2.3)
				c.position.x += sin(_t * 2.0 + ph) * dt * 0.1


class RadioPlayer extends Node3D:
	var on := false
	var _p: AudioStreamPlayer3D
	var _static: AudioStreamPlayer3D
	var _line := 0
	var _wait := 0.0
	const LINES := ["radio.r01", "radio.r02", "radio.r03", "radio.r04", "radio.r05"]

	func toggle() -> void:
		on = not on
		Snd.play_at("radio_click", global_position, self, -4.0)
		if on:
			_static = AudioStreamPlayer3D.new()
			_static.stream = Snd.get_stream("radio_static")
			_static.volume_db = -10.0
			_static.bus = "World"
			_static.max_distance = 20.0
			add_child(_static)
			_static.play()
			_static.finished.connect(func() -> void:
				if on and is_instance_valid(_static):
					_static.play())
			_line = 0
			_wait = 1.2
		else:
			if is_instance_valid(_static):
				_static.queue_free()
			if is_instance_valid(_p):
				_p.queue_free()
			Game.subs_clear()

	func _process(dt: float) -> void:
		if not on:
			return
		if is_instance_valid(_p) and _p.playing:
			return
		_wait -= dt
		if _wait > 0.0:
			return
		var key: String = LINES[_line % LINES.size()]
		_line += 1
		_wait = 2.5 if _line % LINES.size() != 0 else 12.0
		var path := Loc.voice_path(key)
		Game.say(key, Loc.t("ui.who_radio"))
		if ResourceLoader.exists(path):
			_p = AudioStreamPlayer3D.new()
			_p.stream = load(path)
			_p.volume_db = -2.0
			_p.bus = "Voice"
			_p.max_distance = 25.0
			add_child(_p)
			_p.play()


class VoiceWall extends Node3D:
	## Человек за стеной встроенного дома: зовёт, стучит; потом — шум и тишина
	var stage := 0
	var _t := 0.0
	var _cd := 0.0

	func _process(dt: float) -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var d := cam.global_position.distance_to(global_position)
		if stage >= 6:
			return
		_cd -= dt
		if d > 14.0:
			return
		_t += dt
		if _cd > 0.0:
			return
		match stage:
			0:
				Snd.play_at("knock", global_position, self, -2.0)
				_cd = 3.0
				stage = 1
			1:
				_voice("sub.wall1")
				_cd = 6.0
				stage = 2
			2:
				Snd.play_at("knock", global_position, self, 0.0)
				_cd = 4.0
				stage = 3 if d < 6.0 else 2
			3:
				_voice("sub.wall2")
				_cd = 7.0
				stage = 4
			4:
				_voice("sub.wall3")
				_cd = 6.0
				stage = 5
			5:
				Snd.play_at("noise_rush", global_position, self, 4.0)
				if Game.main != null:
					Game.main.burst(1.0)
				_cd = 99.0
				stage = 6

	func _voice(key: String) -> void:
		Game.say(key, Loc.t("ui.who_wall"))
		var path := Loc.voice_path(key)
		if ResourceLoader.exists(path):
			var p := AudioStreamPlayer3D.new()
			p.stream = load(path)
			p.volume_db = -6.0
			p.bus = "World"
			p.max_distance = 20.0
			p.attenuation_filter_cutoff_hz = 1200.0
			p.attenuation_filter_db = -30.0
			add_child(p)
			p.play()
			p.finished.connect(p.queue_free)
