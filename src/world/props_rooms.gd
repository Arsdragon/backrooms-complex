extends RefCounted
## Начинка «странных комнат»: двери в стену, телевизоры, телефон, автоматы, жилой угол, класс, магазин, трубы…

const P := preload("res://src/world/props.gd")
const TV_SHADER := preload("res://src/shaders/tv_screen.gdshader")
const BEAM_SHADER := preload("res://src/shaders/fx_beam.gdshader")
const SPOT_SHADER := preload("res://src/shaders/fx_spot.gdshader")
const RAIN_SHADER := preload("res://src/shaders/fx_rain.gdshader")

static var _tv_mats := {}


static func spawn(cx: Node3D, d: Dictionary, rng: RandomNumberGenerator, layer: int) -> Node3D:
	match String(d.get("k", "")):
		"model": return model(d, rng)
		"door": return door(d)
		"exit_sign": return exit_sign()
		"tv_on": return tv_on(cx, d)
		"phone_ring": return phone_ring(d)
		"vending": return vending(rng)
		"speaker": return speaker(rng)
		"speaker_hub": return speaker_hub(rng)
		"residence": return residence(cx, d, rng, layer)
		"body": return body(cx, d, rng)
		"chalkboard": return chalkboard(d)
		"store_sign": return store_sign(d)
		"price": return price(d)
		"pipes": return pipes(d, rng)
		"cubicle": return cubicle(cx, d, rng)
		"stairs": return stairs(d)
		"panel": return panel(d)
		"giant": return giant(d)
		"outlet": return outlet()
		"vent": return vent(d)
		"peel": return peel(rng)
		"tile_fallen": return tile_fallen(rng)
		"survey": return survey(cx, rng)
		"rat": return rat()
		"drips": return drips(rng)
		"chairs": return chairs(d, rng)
		"tv_stack": return tv_stack(cx, rng)
		"railing": return railing(d, rng)
		"hazmat": return hazmat(cx, d, rng)
		"clothes": return clothes(rng)
		"tripod_cam": return tripod_cam(rng)
		"drag": return drag(rng)
		"lone_door": return lone_door(rng)
		"lost_camp": return lost_camp(cx, rng)
		"text": return text(d)
		"spin": return spin(d)
		"cake": return cake(rng)
		"projector": return projector(d)
		"elevator": return elevator(d)
		"mannequin": return mannequin(d, rng)
		"fridge": return fridge()
		"fan_big": return fan_big()
		"washer": return washer(d)
		"pedestal": return pedestal(d)
		"ropes": return ropes(d)
		"rain": return rain(d)
		"ceil_stain": return ceil_stain(d, rng)
		"streak": return streak(d, rng)
		"bulb":
			var nb := Node3D.new()
			hang_bulb(nb, Vector3(0, float(d.get("ceil", 2.7)), 0), bool(d.get("rose", false)), bool(d.get("shade", false)))
			return nb
		"red_lamp": return red_lamp(d)
		"dome": return dome_lamp(d)
	return null


static var _rose_mesh: ArrayMesh = null


## Голая лампочка на шнуре: патрон с цепочкой, колба светится (от сети). top — точка на потолке (локально).
## Центр колбы — на 0,35 м ниже потолка, там же источник света сетки (L_BULB в chunk_builder/light_grid).
## rose — потолочная розетка (дом): лепной диск 38 см закрывает плоское пятно светильника на потолке;
## shade — абажур-конус из ткани над колбой, просвечивает
static func hang_bulb(n: Node3D, top: Vector3, rose := false, shade := false) -> void:
	var cord := 0.24
	P.rod(n, top, top - Vector3(0, cord, 0), 0.004, P.m_black(), 4)
	P.cyl(n, 0.035, 0.035, 0.012, top - Vector3(0, 0.006, 0), P.m_plastic(Color(0.85, 0.83, 0.78)), Vector3.ZERO, 10)
	if rose:
		if _rose_mesh == null:
			_rose_mesh = P.lathe(PackedVector2Array([Vector2(0.0, -0.045), Vector2(0.05, -0.045), Vector2(0.07, -0.04), Vector2(0.09, -0.036),
				Vector2(0.12, -0.034), Vector2(0.14, -0.028), Vector2(0.165, -0.022), Vector2(0.18, -0.012), Vector2(0.19, -0.003), Vector2(0.192, 0.0)]), 40, 40.0)
		P.mesh_node(n, _rose_mesh, P.mc(Color(0.82, 0.8, 0.74), "plaster", 0.6, {"albedo_cap": 0.6}), top)
	if shade:
		var sh := CylinderMesh.new()
		sh.top_radius = 0.06
		sh.bottom_radius = 0.17
		sh.height = 0.18
		sh.radial_segments = 24
		sh.rings = 2
		sh.cap_top = false
		sh.cap_bottom = false
		var fab := P.mc(Color(0.62, 0.52, 0.38), "fabric", 0.8, {"emit": 0.9, "emit_color": Vector3(1.0, 0.68, 0.36), "emit_mask": 1.0,
			"powered": 1.0, "ds": true, "albedo_cap": 0.5})
		P.mesh_node(n, sh, fab, top - Vector3(0, cord + 0.1, 0))
		var wire := TorusMesh.new()
		wire.inner_radius = 0.166
		wire.outer_radius = 0.172
		wire.rings = 24
		wire.ring_segments = 4
		P.mesh_node(n, wire, P.mc(Color(0.4, 0.32, 0.2), "metal", 0.3), top - Vector3(0, cord + 0.19, 0))
	var sock := Node3D.new()
	n.add_child(sock)
	sock.position = top - Vector3(0, cord, 0)
	P.model(sock, "pull_chain_light_socket", Vector3.ZERO, 0.0, 1.0, false)
	var bulb := P.model(sock, "lightbulb_01", Vector3(0, -0.067, 0), 0.0, 1.0, false)
	if bulb != null:
		bulb.rotation.x = PI
		var glow := P.m_emit(Color(1.0, 0.86, 0.62), 3.2, true)
		for mi in Models._meshes(bulb):
			var m := mi as MeshInstance3D
			for i in m.mesh.get_surface_count():
				var src := m.mesh.surface_get_material(i)
				if src != null and src.resource_name.to_lower().contains("glass"):
					m.set_surface_override_material(i, glow)


static var _dome_mesh: ArrayMesh = null


## Потолочный плафон-«таблетка» из молочного стекла (коридор отеля, L_BULB): латунный ободок у потолка
## закрывает плоское пятно светильника, купол светится ровно, к краю чуть темнее; по центру — винт-шишечка
static func dome_lamp(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var top := float(d.get("ceil", 2.7))
	if _dome_mesh == null:
		_dome_mesh = P.lathe(PackedVector2Array([Vector2(0.0, -0.1), Vector2(0.05, -0.098), Vector2(0.1, -0.09), Vector2(0.135, -0.075),
			Vector2(0.158, -0.055), Vector2(0.17, -0.035), Vector2(0.174, -0.02)]), 32, 40.0)
	P.cyl(n, 0.19, 0.19, 0.022, Vector3(0, top - 0.011, 0), P.mc(Color(0.55, 0.43, 0.22), "metal", 0.4, {"gloss": 80.0, "spec": 0.35}), Vector3.ZERO, 32)
	P.mesh_node(n, _dome_mesh, P.mc(Color(0.85, 0.82, 0.74), "noise", 0.15, {"emit": 1.8, "emit_color": Vector3(1.0, 0.88, 0.66), "powered": 1.0,
		"albedo_cap": 0.6}), Vector3(0, top, 0))
	P.cyl(n, 0.012, 0.008, 0.02, Vector3(0, top - 0.105, 0), P.mc(Color(0.55, 0.43, 0.22), "metal", 0.4, {"gloss": 80.0, "spec": 0.35}), Vector3.ZERO, 10)
	return n


## Красная лампа комнаты колонок (L_RED): круглое основание на потолке закрывает плоское пятно светильника,
## под ним — патрон и красная стеклянная колба в проволочной клетке (как у фотолабораторных/аварийных ламп).
## Колба — на 0,15 м ниже потолка, там же источник света сетки
static func red_lamp(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var top := float(d.get("ceil", 2.7))
	var steel := P.mc(Color(0.18, 0.18, 0.17), "metal", 0.4, {"gloss": 50.0, "spec": 0.15})
	P.cyl(n, 0.17, 0.175, 0.03, Vector3(0, top - 0.015, 0), steel, Vector3.ZERO, 24)
	P.cyl(n, 0.035, 0.04, 0.05, Vector3(0, top - 0.055, 0), steel, Vector3.ZERO, 12)
	# колба светится по всей поверхности, к краю темнее (стекло толще) — не точка, а шар 13 см
	P.sph(n, 0.065, Vector3(0, top - 0.15, 0), P.m_emit(Color(1.0, 0.12, 0.06), 2.6, true), Vector3(1, 1.15, 1), 16)
	# клетка: обручи и прутья
	for yy in [top - 0.09, top - 0.15, top - 0.21]:
		var ring := TorusMesh.new()
		var rr := 0.085 if absf(yy - (top - 0.15)) < 0.01 else 0.07
		ring.inner_radius = rr - 0.003
		ring.outer_radius = rr + 0.003
		ring.rings = 20
		ring.ring_segments = 4
		P.mesh_node(n, ring, steel, Vector3(0, yy, 0))
	for k in 6:
		var a := TAU * k / 6.0
		var pts := PackedVector3Array()
		var rr2 := PackedFloat32Array()
		for i in 7:
			var t := float(i) / 6.0
			var r := 0.04 + 0.05 * sin(t * PI)
			pts.append(Vector3(cos(a) * r, top - 0.07 - t * 0.16, sin(a) * r))
			rr2.append(0.003)
		P.mesh_node(n, P.loft(pts, rr2, rr2, 4), steel)
	return n


# ------------------------------------------------------------ общее

## Модели, которые висят на стене/потолке или лежат на других вещах: тени-«контакта» на полу под ними нет
const NO_BLOB := ["wall_clock", "hanging_picture_frame_01", "pull_chain_light_socket", "ceiling_fan", "lightbulb_01", "industrial_wall_lamp",
	"hanging_industrial_lamp", "mounted_fluorescent_lights", "fire_alarm", "security_camera_01", "security_camera_02", "dartboard",
	"street_lamp_02", "postcard_set_01", "office_notepads", "clipboard", "mousetrap", "street_rat", "water_manhole_cover"]


## Модель из описания: id, s — масштаб, y — подъём; "on" — [id опоры, масштаб опоры по y]: поставить на её верх
## (высота берётся из габаритов опоры, а не на глаз); "ground" — поднять модель с низом ниже нуля на пол
static func model(d: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var sc: Variant = d.get("s", 1.0)
	var id := String(d.get("id", "cardboard_box_01"))
	var s3: Vector3 = sc if typeof(sc) == TYPE_VECTOR3 else Vector3.ONE * float(sc)
	var y := float(d.get("y", 0.0))
	var on: Array = d.get("on", [])
	if not on.is_empty():
		y = P.top_of(String(on[0]), float(on[1]) if on.size() > 1 else 1.0)
	if bool(d.get("ground", false)) and Models.has(id):
		y -= Models.aabb(id).position.y * s3.y
	elif on.is_empty() and y == 0.0 and id not in NO_BLOB and Models.has(id):
		# мебель на полу: модель, у которой низ чуть выше нуля (качалка — 10 см), — опустить на пол
		var lo := Models.aabb(id).position.y * s3.y
		if lo > 0.02 and lo < 0.3:
			y = -lo
	var m := P.model(n, id, Vector3(0, y, 0), 0.0, sc, bool(d.get("collide", true)))
	if m == null:
		return null
	if d.has("tilt"):
		m.rotation += d.tilt
	# тень-«контакт»: под мебелью на полу — по габаритам; под вещью на столе — маленькая на столешнице
	if id not in NO_BLOB and not d.has("tilt"):
		var bb := Models.aabb(id)
		if bb.size.y * s3.y > 0.05:
			# пятно — на полу (или на опоре); у моделей с трубками/ножками ниже нуля — на уровне узла
			var c := (bb.position + bb.size * 0.5) * s3
			var big := bb.size.y * s3.y > 0.5
			P.blob(n, Vector2(bb.size.x * s3.x * 1.12 + (0.14 if big else 0.04), bb.size.z * s3.z * 1.12 + (0.14 if big else 0.04)),
				Vector3(c.x, maxf(y + bb.position.y * s3.y, 0.0 if y <= 0.0 else y), c.z), 0.55 if big else 0.4)
	# ценник на стойке — у правого переднего угла вещи, лицом туда же, куда вещь
	if d.has("price"):
		var bb2 := Models.aabb(id)
		var pr := price({"text": String(d.price)})
		n.add_child(pr)
		pr.position = Vector3(bb2.end.x * s3.x + 0.16, 0.95, bb2.end.z * s3.z * 0.5)
		pr.rotation.y = -0.35
	return n


static func _wall_mat(id: String) -> Material:
	return P.m_wall()


# ------------------------------------------------------------ двери, которые открываются в стену

static func door(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var kind := String(d.get("kind", "wall"))
	var s := 1.0
	match kind:
		"tiny": s = 0.32
		"giant": s = 2.6
		"small": s = 0.6
	var root := Node3D.new()
	n.add_child(root)
	root.scale = Vector3.ONE * s
	if kind == "ceiling":
		# дверь лежит на потолке по центру узла (полотно 2,18 м — в пределах клетки 2,4 м)
		root.rotation.x = -PI * 0.5
		root.position = Vector3(0, float(d.get("ceil", 2.7)) - 0.02, 1.09)
	var frame := P.m_plastic(Color(0.86, 0.84, 0.78))
	var leafc := Color(0.55, 0.42, 0.3) if rng_pick(d) < 0.5 else Color(0.72, 0.7, 0.64)
	var leafm := P.mc(leafc, "wood", 0.7)
	P.box(root, Vector3(0.08, 2.18, 0.08), Vector3(-0.5, 1.09, 0.03), frame)
	P.box(root, Vector3(0.08, 2.18, 0.08), Vector3(0.5, 1.09, 0.03), frame)
	P.box(root, Vector3(1.08, 0.08, 0.08), Vector3(0, 2.14, 0.03), frame)
	# за дверью — та же стена, только темнее (проёма нет)
	P.box(root, Vector3(0.92, 2.1, 0.01), Vector3(0, 1.05, 0.005), P.mc(Color(0.35, 0.32, 0.2), "wall_yellow", 0.8))
	var hinge := Node3D.new()
	hinge.position = Vector3(-0.46, 0, 0.04)
	root.add_child(hinge)
	P.box(hinge, Vector3(0.92, 2.08, 0.045), Vector3(0.46, 1.04, 0.0), leafm)
	P.sph(hinge, 0.03, Vector3(0.84, 1.0, 0.04), P.m_metal())
	hinge.set_meta("door", true)
	var opened := [false]
	P.interactable(root, Vector3(1.0, 2.1, 0.3), Vector3(0, 1.05, 0.15), "ui.door", func() -> void:
		if opened[0]:
			return
		opened[0] = true
		Snd.play_at("door_open", n.global_position + Vector3(0, 1, 0), n, -2.0, randf_range(0.9, 1.05))
		var tw := n.create_tween()
		tw.tween_property(hinge, "rotation:y", -1.75, 1.4).set_trans(Tween.TRANS_SINE))
	return n


static func rng_pick(d: Dictionary) -> float:
	return float(absi(hash(d.get("p", Vector3.ZERO))) % 1000) / 1000.0


static func exit_sign() -> Node3D:
	var n := Node3D.new()
	# корпус табло, зелёный рассеиватель, белые буквы светятся (у EXIT свой аккумулятор — при отключении горит)
	P.box(n, Vector3(0.42, 0.18, 0.08), Vector3(0, 0, 0.04), P.m_plastic(Color(0.9, 0.9, 0.86)))
	P.box(n, Vector3(0.38, 0.14, 0.01), Vector3(0, 0, 0.085), P.m_emit(Color(0.2, 0.9, 0.35), 1.6))
	var lb := P.label(Loc.t("sign.exit"), P.font_sign(), 0.0016, Color(0.95, 1.0, 0.95), 0, 0.0, 2.6, false)
	lb.position = Vector3(0, 0, 0.0905)
	n.add_child(lb)
	return n


# ------------------------------------------------------------ телевизоры

static func tv_mat(cx: Node3D, ch: String) -> Material:
	if _tv_mats.has(ch) and is_instance_valid(_tv_mats[ch]):
		var cached: ShaderMaterial = _tv_mats[ch]
		return cached
	var m := ShaderMaterial.new()
	m.shader = TV_SHADER
	m.set_shader_parameter("noise_tex", Mats.tex("noise"))
	if ch == "static":
		m.set_shader_parameter("channel_static", 1.0)
		m.set_shader_parameter("screen", Mats.tex("noise"))
	else:
		m.set_shader_parameter("screen", TVHub.hub(cx).texture(ch))
	_tv_mats[ch] = m
	return m


static func _crt(parent: Node3D, cx: Node3D, ch: String, pos: Vector3, rot := 0.0, sc := 1.0) -> Node3D:
	var t := Node3D.new()
	parent.add_child(t)
	t.position = pos
	t.rotation.y = rot
	t.scale = Vector3.ONE * sc
	if P.model(t, "television_02", Vector3.ZERO, 0.0, 1.35, false) == null:
		P.box(t, Vector3(0.6, 0.5, 0.55), Vector3(0, 0.25, 0), P.mc(Color(0.2, 0.19, 0.18), "metal", 0.3))
	var q := P.quad(t, Vector2(0.4, 0.3), Vector3(0, 0.29, 0.166), tv_mat(cx, ch))
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return t


static func tv_on(cx: Node3D, d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var ch := String(d.get("ch", "static"))
	P.box(n, Vector3(0.7, 0.5, 0.5), Vector3(0, 0.25, 0), P.mc(Color(0.35, 0.25, 0.18), "wood", 0.7))
	_crt(n, cx, ch, Vector3(0, 0.5, 0))
	var se := P.SoundEmitter.new()
	se.snd = {"news": "tv_news", "async_ad": "tv_jingle", "home": "tv_home", "explorers": "tv_static"}.get(ch, "tv_static")
	se.every = 0.0
	se.vol = -15.0
	se.max_dist = 16.0
	se.position = Vector3(0, 0.8, 0)
	n.add_child(se)
	P.collider(n, Vector3(0.7, 0.95, 0.55), Vector3(0, 0.47, 0))
	P.blob(n, Vector2(0.95, 0.75), Vector3.ZERO, 0.55)
	return n


static func tv_stack(cx: Node3D, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var chs := ["static", "static", "bars", "news", "explorers", "static", "home", "static", "weather"]
	var k := 0
	for row in 3:
		for col in 3:
			var ch: String = chs[(k + rng.randi_range(0, 8)) % chs.size()]
			_crt(n, cx, ch, Vector3(-0.6 + col * 0.6 + rng.randf_range(-0.04, 0.04), row * 0.5, rng.randf_range(-0.05, 0.05)), rng.randf_range(-0.1, 0.1))
			k += 1
	var se := P.SoundEmitter.new()
	se.snd = "tv_static"
	se.every = 0.0
	se.vol = -10.0
	se.position = Vector3(0, 0.8, 0)
	n.add_child(se)
	P.collider(n, Vector3(1.8, 1.5, 0.6), Vector3(0, 0.75, 0))
	P.blob(n, Vector2(2.1, 0.85), Vector3.ZERO, 0.55)
	return n


# ------------------------------------------------------------ звонящий телефон

static func phone_ring(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	P._desk(n)
	var ph := Node3D.new()
	n.add_child(ph)
	ph.position = Vector3(0.1, P.desk_top(), 0.05)
	P._phone(ph)
	var ring := AudioStreamPlayer3D.new()
	ring.stream = Snd.get_stream("phone_ring")
	ring.bus = "World"
	ring.max_distance = 40.0
	ring.unit_size = 4.0
	ring.volume_db = -2.0
	ring.position = Vector3(0, 0.9, 0)
	n.add_child(ring)
	ring.finished.connect(func() -> void:
		if ring.has_meta("on"):
			ring.play())
	ring.set_meta("on", true)
	ring.autoplay = true
	var done := [false]
	P.blob_under(n, 0.5)
	P.interactable(n, Vector3(0.6, 0.5, 0.6), Vector3(0.1, 0.85, 0.05), "ui.phone", func() -> void:
		if done[0]:
			return
		done[0] = true
		ring.remove_meta("on")
		ring.stop()
		Snd.play("phone_pickup", -4.0)
		var key := "sub.phone"
		Game.say(key, Loc.t("ui.who_phone"))
		var path := Loc.voice_path(key)
		if ResourceLoader.exists(path):
			var p := AudioStreamPlayer.new()
			p.stream = load(path)
			p.bus = "Voice"
			p.volume_db = -3.0
			n.add_child(p)
			p.play()
			p.finished.connect(func() -> void:
				Snd.play("phone_busy", -8.0))
		else:
			Snd.play("phone_busy", -8.0))
	return n


# ------------------------------------------------------------ автоматы, колонки

## Торговый автомат: крашеный корпус, за пыльным стеклом — подсвеченные полки с пачками и банками,
## справа — панель с кнопками и монетоприёмником, внизу — лоток выдачи. Подсветка от сети: гаснет при отключении
static func vending(rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var bodyc: Color = [Color(0.5, 0.09, 0.07), Color(0.12, 0.2, 0.42), Color(0.4, 0.38, 0.33)][rng.randi_range(0, 2)]
	var body := P.mc(bodyc, "metal", 0.45, {"gloss": 50.0, "spec": 0.14})
	var blk := P.m_black()
	# корпус: задняя часть, боковины, верх и низ рамой вокруг ниши витрины
	P.box(n, Vector3(0.95, 1.85, 0.62), Vector3(0, 0.925, -0.09), body)
	P.box(n, Vector3(0.08, 1.85, 0.18), Vector3(-0.435, 0.925, 0.31), body)
	P.box(n, Vector3(0.27, 1.85, 0.18), Vector3(0.34, 0.925, 0.31), body)
	P.box(n, Vector3(0.62, 0.36, 0.18), Vector3(-0.085, 1.67, 0.31), body)
	P.box(n, Vector3(0.62, 0.36, 0.18), Vector3(-0.085, 0.18, 0.31), body)
	# ниша витрины: тёмная задняя стенка, подсвеченная сверху лампой; полки и товар
	var inner := P.mc(Color(0.07, 0.07, 0.075), "metal", 0.3, {"emit": 0.22, "emit_color": Vector3(0.75, 0.82, 0.9), "powered": 1.0})
	P.box(n, Vector3(0.62, 1.13, 0.02), Vector3(-0.085, 0.925, 0.23), inner)
	P.box(n, Vector3(0.6, 0.02, 0.04), Vector3(-0.085, 1.475, 0.37), P.m_emit(Color(0.85, 0.92, 1.0), 2.4, true))
	var shelf := P.mc(Color(0.45, 0.46, 0.46), "metal", 0.6, {"gloss": 50.0, "spec": 0.2, "emit": 0.08, "emit_color": Vector3(0.8, 0.85, 0.9), "powered": 1.0})
	for r in 5:
		var sy := 0.42 + r * 0.21
		P.box(n, Vector3(0.6, 0.012, 0.15), Vector3(-0.085, sy, 0.31), shelf)
		var c0 := Color.from_hsv(rng.randf(), rng.randf_range(0.55, 0.85), rng.randf_range(0.3, 0.5))
		for c in 6:
			# ряд одинаковых пачек; товар подсвечен изнутри автомата
			var pc := c0 if rng.randf() < 0.7 else Color.from_hsv(rng.randf(), 0.7, 0.4)
			var pm := P.mc(pc, "paper", 0.3, {"emit": 0.05, "emit_color": Vector3(pc.r, pc.g, pc.b), "powered": 1.0, "gloss": 40.0, "spec": 0.12})
			var hgt := rng.randf_range(0.11, 0.15)
			if rng.randf() < 0.08:
				continue
			if r >= 3:
				P.cyl(n, 0.032, 0.032, 0.12, Vector3(-0.33 + c * 0.098, sy + 0.066, 0.33), pm, Vector3.ZERO, 10)
			else:
				P.box(n, Vector3(0.075, hgt, 0.03), Vector3(-0.33 + c * 0.098, sy + 0.006 + hgt * 0.5, 0.33), pm, Vector3(rng.randf_range(-0.12, 0.05), 0, 0))
	# пыльное стекло витрины (отражает лампы коридора)
	var gl := ShaderMaterial.new()
	gl.shader = Models.GLASS
	gl.set_shader_parameter("noise_tex", Mats.tex("noise"))
	gl.set_shader_parameter("dirt", 0.55)
	P.quad(n, Vector2(0.62, 1.14), Vector3(-0.085, 0.925, 0.395), gl)
	# панель выбора: табло, кнопки, монетоприёмник; лоток выдачи
	P.box(n, Vector3(0.2, 0.6, 0.01), Vector3(0.335, 1.15, 0.405), blk)
	P.box(n, Vector3(0.12, 0.04, 0.005), Vector3(0.335, 1.38, 0.411), P.m_emit(Color(0.9, 0.25, 0.08), 1.6, true))
	for k in 8:
		P.box(n, Vector3(0.035, 0.025, 0.012), Vector3(0.3 + (k % 2) * 0.07, 1.3 - (k / 2) * 0.05, 0.411), P.mc(Color(0.55, 0.55, 0.52), "metal", 0.4))
	P.box(n, Vector3(0.05, 0.08, 0.012), Vector3(0.335, 0.98, 0.411), P.mc(Color(0.5, 0.5, 0.48), "metal", 0.6, {"gloss": 60.0, "spec": 0.3}))
	P.box(n, Vector3(0.5, 0.16, 0.02), Vector3(-0.085, 0.2, 0.402), blk)
	P.blob(n, Vector2(1.2, 1.0), Vector3.ZERO, 0.65)
	P.collider(n, Vector3(0.95, 1.85, 0.8), Vector3(0, 0.925, 0))
	var se := P.SoundEmitter.new()
	se.snd = "vending_hum"
	se.every = 0.0
	se.vol = -12.0
	se.max_dist = 14.0
	se.position = Vector3(0, 1.0, 0)
	n.add_child(se)
	return n


## Напольная колонка 80-х: корпус под орех с тёмными торцами, на ножках-шипах; у части снята решётка —
## видны бумажный диффузор с резиновым подвесом и колпачком, пищалка, фазоинвертор; у остальных — рамка,
## обтянутая тёмной тканью (сквозь неё едва видны кольца динамиков). Шнур уходит к усилителю в середину
static func speaker(rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var h := rng.randf_range(0.7, 1.05)
	var w := 0.44
	var dpt := 0.34
	var veneer := P.mc(Color(0.42, 0.29, 0.18), "wood", 0.85, {"gloss": 40.0, "spec": 0.08})
	var baffle := P.mc(Color(0.09, 0.085, 0.08), "metal", 0.3, {"gloss": 20.0, "spec": 0.05})
	var blk := P.m_black()
	P.box(n, Vector3(w, h, dpt), Vector3(0, h * 0.5 + 0.04, 0), veneer)
	P.box(n, Vector3(w - 0.02, h - 0.02, 0.012), Vector3(0, h * 0.5 + 0.04, dpt * 0.5 + 0.004), baffle)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			P.cyl(n, 0.012, 0.004, 0.04, Vector3(sx * (w * 0.5 - 0.04), 0.02, sz * (dpt * 0.5 - 0.04)), blk, Vector3.ZERO, 6)
	var fz := dpt * 0.5 + 0.012
	var woof_y := 0.04 + h * 0.36
	var mid_y := 0.04 + h * 0.66
	var tw_y := 0.04 + h * 0.86
	var grille := rng.randf() < 0.3
	var trim := P.mc(Color(0.55, 0.55, 0.52), "metal", 0.4, {"gloss": 80.0, "spec": 0.35})
	# динамики: подвес (тор), конус (усечённый конус вглубь), колпачок
	var cone_m := P.mc(Color(0.34, 0.33, 0.3), "paper", 0.7, {"gloss": 12.0, "spec": 0.03})
	var surr := P.mc(Color(0.03, 0.03, 0.03), "metal", 0.2, {"gloss": 50.0, "spec": 0.12})
	for spec in [[woof_y, 0.15], [mid_y, 0.075]]:
		var a: Array = spec
		var yy: float = a[0]
		var rr: float = a[1]
		var tor := TorusMesh.new()
		tor.inner_radius = rr - 0.018
		tor.outer_radius = rr + 0.004
		tor.rings = 28
		tor.ring_segments = 6
		P.mesh_node(n, tor, surr, Vector3(0, yy, fz - 0.004), Vector3(PI * 0.5, 0, 0), Vector3(1, 0.5, 1))
		var cone := CylinderMesh.new()
		cone.top_radius = rr - 0.012
		cone.bottom_radius = rr * 0.3
		cone.height = rr * 0.45
		cone.radial_segments = 24
		cone.rings = 1
		cone.cap_top = false
		P.mesh_node(n, cone, cone_m, Vector3(0, yy, fz - rr * 0.225 - 0.004), Vector3(PI * 0.5, 0, 0))
		P.sph(n, rr * 0.28, Vector3(0, yy, fz - rr * 0.33), surr, Vector3(1, 1, 0.45), 12)
		# алюминиевое кольцо-рамка динамика
		var ring := TorusMesh.new()
		ring.inner_radius = rr + 0.004
		ring.outer_radius = rr + 0.016
		ring.rings = 28
		ring.ring_segments = 4
		P.mesh_node(n, ring, trim, Vector3(0, yy, fz - 0.002), Vector3(PI * 0.5, 0, 0), Vector3(1, 0.4, 1))
	P.cyl(n, 0.035, 0.035, 0.01, Vector3(-0.1, tw_y, fz), surr, Vector3(PI * 0.5, 0, 0), 12)
	P.sph(n, 0.018, Vector3(-0.1, tw_y, fz + 0.002), P.mc(Color(0.4, 0.38, 0.33), "metal", 0.2, {"gloss": 70.0, "spec": 0.3}), Vector3(1, 1, 0.5), 10)
	P.cyl(n, 0.03, 0.03, 0.012, Vector3(0.12, tw_y, fz - 0.002), blk, Vector3(PI * 0.5, 0, 0), 12)
	if grille:
		# решётка: деревянная рамка, обтянутая тёмно-бурой тканью (просвечивает и видна с изнанки)
		var cloth := P.mc(Color(0.36, 0.33, 0.28), "fabric", 0.9, {"gloss": 8.0, "spec": 0.02})
		P.box(n, Vector3(w - 0.03, h - 0.04, 0.018), Vector3(0, h * 0.5 + 0.04, fz + 0.012), cloth)
		var badge := P.mc(Color(0.55, 0.52, 0.45), "metal", 0.2, {"gloss": 90.0, "spec": 0.4})
		P.box(n, Vector3(0.07, 0.018, 0.004), Vector3(0, 0.08, fz + 0.023), badge)
	else:
		# снятая решётка прислонена к колонке
		var gr := Node3D.new()
		n.add_child(gr)
		gr.position = Vector3(w * 0.5 + 0.04, 0.0, 0.05)
		gr.rotation = Vector3(0, PI * 0.5 + rng.randf_range(-0.3, 0.3), 0.18)
		P.box(gr, Vector3(w - 0.03, h - 0.04, 0.018), Vector3(0, (h - 0.04) * 0.5, 0), P.mc(Color(0.36, 0.33, 0.28), "fabric", 0.9))
	# шнур: из клемм сзади, вдоль бока и по полу к середине комнаты (колонка смотрит туда же, +z)
	var cord := P.m_black()
	var pts := PackedVector3Array([Vector3(0.05, 0.12, -dpt * 0.5 - 0.005), Vector3(0.1, 0.03, -dpt * 0.5 - 0.04), Vector3(w * 0.5 + 0.05, 0.006, -dpt * 0.5 - 0.02)])
	for i in 6:
		var t := float(i + 1) / 6.0
		pts.append(Vector3(w * 0.5 + 0.06 + sin(t * 5.0 + h * 9.0) * 0.1 * t, 0.006, -dpt * 0.5 + t * (dpt + 2.9)))
	var rr2 := PackedFloat32Array()
	for i in pts.size():
		rr2.append(0.005)
	P.mesh_node(n, P.loft(pts, rr2, rr2, 5), cord)
	P.blob(n, Vector2(0.62, 0.52), Vector3.ZERO, 0.5)
	P.collider(n, Vector3(w, h + 0.04, dpt), Vector3(0, (h + 0.04) * 0.5, 0))
	var se := P.SoundEmitter.new()
	se.snd = ["copy_whisper", "speaker_hiss", "tv_news"][rng.randi_range(0, 2)]
	se.every = 0.0 if se.snd != "copy_whisper" else 6.0
	se.vol = -12.0
	se.max_dist = 12.0
	se.position = Vector3(0, h * 0.6, 0.2)
	n.add_child(se)
	return n


## Середина комнаты колонок: стопка аппаратуры на полу (усилитель с горящими стрелками, катушечный магнитофон),
## к ней сходятся шнуры
static func speaker_hub(rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var alu := P.mc(Color(0.55, 0.55, 0.53), "metal", 0.5, {"gloss": 70.0, "spec": 0.3})
	var blk := P.m_black()
	# усилитель: серебристая панель, два окошка стрелочных индикаторов (подсветка от сети), ручки
	P.box(n, Vector3(0.44, 0.13, 0.34), Vector3(0, 0.065, 0), blk)
	P.box(n, Vector3(0.44, 0.13, 0.008), Vector3(0, 0.065, 0.174), alu)
	for sx in [-0.09, 0.09]:
		P.box(n, Vector3(0.11, 0.05, 0.004), Vector3(sx, 0.085, 0.18), P.m_emit(Color(1.0, 0.62, 0.25), 0.9, true))
		P.box(n, Vector3(0.002, 0.04, 0.003), Vector3(sx + rng.randf_range(-0.03, 0.02), 0.085, 0.183), blk, Vector3(0, 0, rng.randf_range(-0.5, 0.5)))
	for k in 4:
		P.cyl(n, 0.014, 0.014, 0.02, Vector3(-0.16 + k * 0.1 + (0.05 if k > 1 else 0.0), 0.035, 0.185), alu, Vector3(PI * 0.5, 0, 0), 10)
	# катушечник сверху: две бобины
	P.box(n, Vector3(0.4, 0.12, 0.32), Vector3(0, 0.19, -0.01), P.mc(Color(0.16, 0.16, 0.16), "metal", 0.4))
	for sx2 in [-0.1, 0.1]:
		P.cyl(n, 0.085, 0.085, 0.012, Vector3(sx2, 0.257, -0.01), P.mc(Color(0.6, 0.6, 0.58), "metal", 0.3, {"gloss": 80.0, "spec": 0.35}), Vector3.ZERO, 20)
		P.cyl(n, 0.05, 0.05, 0.014, Vector3(sx2, 0.258, -0.01), P.mc(Color(0.2, 0.13, 0.08), "metal", 0.3), Vector3.ZERO, 16)
	P.blob(n, Vector2(0.65, 0.55), Vector3.ZERO, 0.5)
	return n


# ------------------------------------------------------------ жилой угол пропавшего

static func residence(cx: Node3D, d: Dictionary, rng: RandomNumberGenerator, layer: int) -> Node3D:
	var n := Node3D.new()
	# матрас, подушка, одеяло
	P.box(n, Vector3(0.95, 0.16, 1.95), Vector3(0, 0.08, 0), P.mc(Color(0.72, 0.68, 0.6), "fabric", 0.8))
	P.blob(n, Vector2(1.15, 2.15), Vector3.ZERO, 0.45)
	P.box(n, Vector3(0.6, 0.1, 0.35), Vector3(0, 0.2, -0.75), P.mc(Color(0.85, 0.83, 0.78), "fabric", 0.7), Vector3(0.1, 0.1, 0))
	P.box(n, Vector3(1.0, 0.05, 1.1), Vector3(0.05, 0.19, 0.35), P.mc(Color(0.35, 0.18, 0.15), "fabric", 0.8), Vector3(0.05, 0.25, -0.05))
	var items := [["can_rusted", Vector3(0.8, 0, 0.6)], ["can_rusted", Vector3(0.92, 0, 0.5)], ["russian_food_cans_01", Vector3(0.75, 0, 0.9)],
		["plastic_bottle_gallon", Vector3(-0.75, 0, -0.6)], ["plastic_bottle_gallon", Vector3(-0.9, 0, -0.4)], ["portable_cassette_player", Vector3(0.6, 0.0, -0.8)],
		["vintage_suitcase", Vector3(-0.2, 0, 1.4)], ["long_life_food", Vector3(0.95, 0, 1.1)], ["alarm_clock_01", Vector3(0.7, 0, -1.0)]]
	for it in items:
		var a: Array = it
		P.model(n, String(a[0]), a[1], rng.randf() * TAU, 1.0, false)
	# лампочка — над центром клетки (узел сдвинут от него на (−0,4; −0,2)), там же её свет
	hang_bulb(n, Vector3(0.4, float(d.get("ceil", 2.7)), 0.2))
	var note := P.note(cx, {"key": "note.r01" if layer == 0 else "note.r02", "p": Vector3.ZERO})
	n.add_child(note)
	note.position = Vector3(-0.6, 0.0, 0.9)
	var se := P.SoundEmitter.new()
	se.snd = "clock_tick"
	se.every = 0.0
	se.vol = -16.0
	se.max_dist = 8.0
	se.position = Vector3(0.7, 0.1, -1.0)
	n.add_child(se)
	return n


# ------------------------------------------------------------ тело в плесени (Async нашла пропавших)

static func body(cx: Node3D, d: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var h := Human.make(["civ_d", "civ_h", "worker", "civ_f"][rng.randi_range(0, 3)], rng.randi(), true)
	n.add_child(h)
	h.pose("stand")
	h._r("hip_l", -0.4, 0, 0.2)
	h._r("kn_l", 0.8)
	h._r("sh_r", -0.5, 0, 0.6)
	h.rotation = Vector3(0, 0, PI * 0.5)
	h.position = Vector3(0.0, 0.18, 0)
	h.tune({"mold": 1.0, "pale": 0.2, "wet": 0.8})
	# лента 5 см: полосы по объектным метрам (плитка текстуры 4:1 — 20 × 5 см), а не растянуты на 2,6 м
	var tape := Mats.prop("hazard_tape", {"tex": "hazard", "tex_mix": 1.0, "box_uv": 1.0, "world_scale": Vector2(0.2, 0.05), "albedo_cap": 0.66, "ds": true})
	for k in 4:
		var a := k * PI * 0.5
		P.box(n, Vector3(2.6, 0.05, 0.004), Vector3(cos(a) * 1.3, 0.5, sin(a) * 1.3), tape, Vector3(0, -a + PI * 0.5, 0))
		P.rod(n, Vector3(cos(a + 0.785) * 1.84, 0, sin(a + 0.785) * 1.84), Vector3(cos(a + 0.785) * 1.84, 0.55, sin(a + 0.785) * 1.84), 0.02, P.m_iron(), 4)
	var lb := P.label(Loc.t("sign.dont_touch"), P.font_sign(), 0.0022, Color(0.85, 0.1, 0.08))
	lb.position = Vector3(0, 0.62, 1.31)
	n.add_child(lb)
	return n


# ------------------------------------------------------------ класс, магазин

static func chalkboard(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	if P.model(n, "standing_chalkboard_01", Vector3.ZERO, 0.0, Vector3(1.6, 1.2, 1.0)) == null:
		P.box(n, Vector3(1.4, 1.0, 0.04), Vector3(0, 1.3, 0), P.mc(Color(0.12, 0.2, 0.15), "noise", 0.3))
	var lb := P.label(Loc.t(String(d.get("key", "class.board1"))), P.font_hand(), 0.0016, Color(0.85, 0.85, 0.8), 0, 680.0)
	lb.position = Vector3(0, 1.22, 0.2)
	n.add_child(lb)
	return n


static func store_sign(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var y := float(d.get("y", 2.15))
	var bg := Color(0.85, 0.1, 0.08) if int(d.get("v", 0)) % 2 == 0 else Color(0.95, 0.8, 0.1)
	P.box(n, Vector3(1.8, 0.45, 0.03), Vector3(0, y, 0), P.mc(bg, "metal", 0.15))
	P.rod(n, Vector3(-0.8, y + 0.22, 0), Vector3(-0.8, 2.7, 0), 0.006, P.m_metal(), 3)
	P.rod(n, Vector3(0.8, y + 0.22, 0), Vector3(0.8, 2.7, 0), 0.006, P.m_metal(), 3)
	for side in [1.0, -1.0]:
		var lb := P.label(Loc.t(String(d.get("key", "store.s1"))), P.font_sign(), 0.0034, Color(1, 1, 1) if bg.g < 0.5 else Color(0.1, 0.08, 0.05))
		lb.position = Vector3(0, y, 0.018 * side)
		if side < 0:
			lb.rotation.y = PI
		n.add_child(lb)
	return n


## Ценник на хромированной стойке (узел — на высоте ценника, стойка — до пола)
static func price(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var h := float(d.get("h", 0.95))
	var chrome := P.mc(Color(0.55, 0.55, 0.54), "metal", 0.5, {"gloss": 90.0, "spec": 0.4})
	P.rod(n, Vector3(0, -h, 0), Vector3(0, -0.05, 0), 0.006, chrome, 6)
	P.cyl(n, 0.09, 0.1, 0.012, Vector3(0, -h + 0.006, 0), chrome, Vector3.ZERO, 14)
	var tag := Node3D.new()
	n.add_child(tag)
	tag.rotation.x = -0.35
	P.box(tag, Vector3(0.19, 0.13, 0.006), Vector3(0, 0, -0.004), P.m_black())
	P.box(tag, Vector3(0.18, 0.12, 0.004), Vector3(0, 0, 0), P.mc(Color(0.95, 0.9, 0.3), "paper", 0.6))
	var lb := P.label(String(d.get("text", "$0")), P.font_sign(), 0.0012, Color(0.6, 0.05, 0.05))
	lb.position = Vector3(0, 0, 0.0025)
	tag.add_child(lb)
	return n


# ------------------------------------------------------------ трубы, перегородки, лестницы

static func pipes(d: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var length := float(d.get("len", 4.8))
	var y := float(d.get("y", 2.35))
	var cols := [Color(0.45, 0.42, 0.38), Color(0.55, 0.35, 0.2), Color(0.3, 0.35, 0.3)]
	for k in rng.randi_range(2, 4):
		var r := rng.randf_range(0.04, 0.11)
		var off := -0.5 + k * 0.28
		var m := P.mc(cols[k % 3], "metal", 0.6, {"wet": 0.3})
		P.rod(n, Vector3(-length * 0.5, y - k * 0.06, off), Vector3(length * 0.5, y - k * 0.06, off), r, m, 8)
		if rng.randf() < 0.5:
			P.cyl(n, r * 1.6, r * 1.6, 0.06, Vector3(rng.randf_range(-length * 0.4, length * 0.4), y - k * 0.06, off), P.m_iron(), Vector3(0, 0, PI * 0.5), 8)
	for b in int(length / 1.6):
		P.box(n, Vector3(0.04, 0.4, 1.1), Vector3(-length * 0.5 + 0.8 + b * 1.6, y + 0.15, -0.1), P.m_iron())
	var se := P.SoundEmitter.new()
	se.snd = "pipe_knock"
	se.every = 18.0
	se.vol = -12.0
	se.position = Vector3(0, y, 0)
	n.add_child(se)
	return n


## Секция офисной перегородки от a до b (по полу, вдоль x или z), высота h: обтянутая твидом панель,
## снизу — тёмный цоколь-кабель-канал на регулируемых ножках, сверху — бежевый крашеный профиль-крышка,
## по торцам — вертикальные планки. Панель стоит на 2 см над полом
static func _panel(n: Node3D, a: Vector3, b: Vector3, h: float, fab: Material, trim: Material, base: Material) -> void:
	var c := (a + b) * 0.5
	var ln := a.distance_to(b)
	var along_x := absf(b.x - a.x) > absf(b.z - a.z)
	var sz := func(l: float, hh: float, t: float) -> Vector3: return Vector3(l, hh, t) if along_x else Vector3(t, hh, l)
	var off := func(t: float) -> Vector3: return Vector3(t, 0, 0) if along_x else Vector3(0, 0, t)
	P.box(n, sz.call(ln - 0.05, h - 0.13, 0.055), c + Vector3(0, 0.12 + (h - 0.13) * 0.5, 0), fab)
	P.box(n, sz.call(ln - 0.01, 0.1, 0.064), c + Vector3(0, 0.07, 0), base)
	P.box(n, sz.call(ln + 0.004, 0.03, 0.068), c + Vector3(0, h - 0.01, 0), trim)
	for s: float in [-1.0, 1.0]:
		P.box(n, sz.call(0.03, h - 0.02, 0.066), c + off.call(s * (ln * 0.5 - 0.015)) + Vector3(0, h * 0.5, 0), trim)
		P.cyl(n, 0.018, 0.022, 0.02, c + off.call(s * (ln * 0.5 - 0.08)) + Vector3(0, 0.01, 0), P.m_black(), Vector3.ZERO, 8)


static func cubicle(cx: Node3D, d: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	# сукно перегородок — серо-голубой твид (prop_cubicle: пёстрая пряжа, переплетение), профили — бежевая краска
	var pm: Material = P.mc(Color(0.4, 0.41, 0.44), "prop_cubicle", 1.0, {"nmap": Mats.tex("prop_cubicle_n"), "bump": 0.9, "gloss": 8.0, "spec": 0.02, "albedo_cap": 0.55}) \
		if Mats.has_tex("prop_cubicle") else P.mc(Color(0.3, 0.32, 0.37), "fabric", 0.8)
	var fr := P.mc(Color(0.66, 0.63, 0.56), "metal", 0.3, {"gloss": 40.0, "spec": 0.1})
	var bs := P.mc(Color(0.2, 0.2, 0.21), "metal", 0.3, {"gloss": 30.0, "spec": 0.06})
	# три стенки 1.4 м из секций по ~0,95 м, на стыках — общие торцевые планки
	var hh := 1.4
	_panel(n, Vector3(-0.95, 0, -0.95), Vector3(0.0, 0, -0.95), hh, pm, fr, bs)
	_panel(n, Vector3(0.0, 0, -0.95), Vector3(0.95, 0, -0.95), hh, pm, fr, bs)
	_panel(n, Vector3(-0.95, 0, -0.92), Vector3(-0.95, 0, 0.0), hh, pm, fr, bs)
	_panel(n, Vector3(-0.95, 0, 0.0), Vector3(-0.95, 0, 0.95), hh, pm, fr, bs)
	_panel(n, Vector3(0.95, 0, -0.92), Vector3(0.95, 0, 0.25), hh, pm, fr, bs)
	# угловые стойки
	for cp in [Vector3(-0.95, 0, -0.95), Vector3(0.95, 0, -0.95)]:
		P.box(n, Vector3(0.07, hh + 0.01, 0.07), cp + Vector3(0, (hh + 0.01) * 0.5, 0), fr)
	P.collider(n, Vector3(1.9, 1.4, 0.08), Vector3(0, 0.7, -0.95))
	P.collider(n, Vector3(0.08, 1.4, 1.9), Vector3(-0.95, 0.7, 0))
	P.collider(n, Vector3(0.08, 1.4, 1.2), Vector3(0.95, 0.7, -0.35))
	var desk := Node3D.new()
	n.add_child(desk)
	desk.position = Vector3(0, 0, -0.55)
	P._desk(desk)
	desk.scale = Vector3(0.85, 1.0, 0.8)
	P.blob_under(desk, 0.5)
	var top := P.desk_top()
	# монитор: бежевый кинескоп, иногда включён; клавиатура перед ним
	var mon := Node3D.new()
	n.add_child(mon)
	mon.position = Vector3(-0.1, top, -0.65)
	var beige := P.mc(Color(0.62, 0.58, 0.5), "metal", 0.3, {"gloss": 30.0, "spec": 0.08})
	P.box(mon, Vector3(0.38, 0.32, 0.36), Vector3(0, 0.18, 0), beige)
	P.box(mon, Vector3(0.2, 0.02, 0.2), Vector3(0, 0.01, 0), beige)
	var on := rng.randf() < 0.35
	P.quad(mon, Vector2(0.3, 0.22), Vector3(0, 0.2, 0.181), P.mc(Color(0.04, 0.06, 0.05), "noise", 0.3,
		{"emit": 0.6 if on else 0.0, "emit_color": Vector3(0.2, 0.9, 0.4), "powered": 1.0, "gloss": 90.0, "spec": 0.3}))
	P.box(mon, Vector3(0.42, 0.025, 0.15), Vector3(0, 0.0125, 0.3), beige)
	var ch := Node3D.new()
	n.add_child(ch)
	ch.position = Vector3(rng.randf_range(-0.2, 0.3), 0, 0.1)
	ch.rotation.y = PI + rng.randf_range(-0.6, 0.6)
	if rng.randf() < 0.2:
		ch.rotation.z = PI * 0.5
		ch.position.y = 0.25
	P._ochair(ch)
	if ch.position.y < 0.01:
		P.blob_under(ch, 0.35)
	if rng.randf() < 0.5:
		P.model(n, "office_notepads", Vector3(0.35, top, -0.55), rng.randf_range(-0.3, 0.3), 0.4, false)
	if rng.randf() < 0.3:
		var ph := Node3D.new()
		n.add_child(ph)
		ph.position = Vector3(0.45, top, -0.7)
		P._phone(ph)
	return n


## Лестница, уходящая в потолок: сплошной марш (под ним — короб, оклеенный теми же обоями, с плинтусом),
## закрытые косоуры по бокам, проступи с выносом и подступёнки, перила на столбах с балясинами.
## Марш идёт к −z от узла; верхние ступени и поручни уходят в потолок (ступени — до 2,8 м)
static func stairs(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var up := bool(d.get("up", true))
	var wd := P.mc(Color(0.5, 0.4, 0.3), "wood", 0.8)
	if not up:
		for k in 12:
			P.box(n, Vector3(1.1, 0.06, 0.28), Vector3(0, -(k + 1) * 0.2, -k * 0.27), wd)
		return n
	var tread := P.mc(Color(0.56, 0.42, 0.29), "wood", 0.9, {"nmap": Mats.tex("wood_n"), "bump": 0.6, "gloss": 40.0, "spec": 0.08})
	var paint := P.m_plastic(Color(0.86, 0.84, 0.78))
	var string_m := P.mc(Color(0.47, 0.35, 0.24), "wood", 0.9, {"gloss": 36.0, "spec": 0.06})
	var steps := 14
	var rise := 0.2
	var run := 0.27
	var z0 := 0.135
	var zb := z0 - steps * run
	var half := 0.5
	# короб марша: ступенчатый профиль до пола
	var prof := PackedVector2Array([Vector2(z0, 0.0)])
	for k in steps:
		var zf := z0 - k * run
		prof.append(Vector2(zf, (k + 1) * rise - 0.035))
		prof.append(Vector2(zf - run, (k + 1) * rise - 0.035))
	prof.append(Vector2(zb, 0.0))
	P.mesh_node(n, P.prism_x(prof, -half, half), P.m_wall())
	# проступи с выносом 3 см и подступёнки
	for k2 in steps:
		var zf2 := z0 - k2 * run
		P.box(n, Vector3(half * 2.0 - 0.01, 0.035, run + 0.03), Vector3(0, (k2 + 1) * rise - 0.0175, zf2 - run * 0.5 + 0.015), tread)
		P.box(n, Vector3(half * 2.0 - 0.02, rise - 0.035, 0.012), Vector3(0, k2 * rise + (rise - 0.035) * 0.5, zf2 - 0.006), paint)
	# косоуры: доска вдоль марша поверх кромки короба (линия выносов ступеней), низ упирается в пол
	var nos := func(z: float) -> float: return rise + (z0 - z) * (rise / run)
	var zfoot := z0 - (0.25 - rise) * run / rise
	var sp := PackedVector2Array([Vector2(z0 + 0.05, 0.0), Vector2(z0 + 0.05, float(nos.call(z0 + 0.05)) + 0.06),
		Vector2(zb, float(nos.call(zb)) + 0.06), Vector2(zb, float(nos.call(zb)) - 0.25), Vector2(zfoot, 0.0)])
	for sx: float in [-1.0, 1.0]:
		P.mesh_node(n, P.prism_x(sp, 0.0, 0.035), string_m, Vector3(sx * half - (0.035 if sx < 0.0 else 0.0), 0, 0))
		# плинтус по коробу под косоуром
		P.box(n, Vector3(0.014, 0.1, z0 - zb), Vector3(sx * (half + 0.006), 0.05, (z0 + zb) * 0.5), P.mc(Color(0.8, 0.77, 0.67), "baseboard", 0.8))
	# перила по обе стороны: столб внизу, балясины через ступень, поручень на 0,9 м над линией выносов
	for sx2: float in [-1.0, 1.0]:
		var x := sx2 * (half - 0.02)
		P.box(n, Vector3(0.08, 1.05, 0.08), Vector3(x, rise + 0.52, z0 - run * 0.5), string_m)
		P.box(n, Vector3(0.1, 0.03, 0.1), Vector3(x, rise + 1.06, z0 - run * 0.5), string_m)
		for k3 in range(1, steps, 2):
			var zc := z0 - k3 * run - run * 0.5
			var ytop := float(nos.call(zc)) + 0.9
			P.box(n, Vector3(0.028, ytop - (k3 + 1) * rise, 0.028), Vector3(x, ((k3 + 1) * rise + ytop) * 0.5, zc), paint)
		P.rod(n, Vector3(x, rise + 0.95, z0 - run * 0.5), Vector3(x, float(nos.call(zb)) + 0.9, zb), 0.028, string_m, 8)
	P.collider(n, Vector3(1.1, 0.2, steps * run * 1.25), Vector3(0, steps * rise * 0.5 - 0.05, (z0 + zb) * 0.5), 1, Vector3(atan2(rise, run), 0, 0))
	return n


static func panel(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var s: Vector3 = d.get("size", Vector3(0.3, 2.7, 2.4))
	P.box(n, s, Vector3(0, s.y * 0.5, 0), P.m_wall())
	P.box(n, Vector3(s.x + 0.02, 0.1, s.z), Vector3(0, 0.05, 0), P.mc(Color(0.8, 0.77, 0.67), "baseboard", 0.8))
	P.collider(n, s, Vector3(0, s.y * 0.5, 0))
	return n


static func giant(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	match String(d.get("what", "chair")):
		"chair":
			var c := Node3D.new()
			n.add_child(c)
			P._chair(c)
			c.scale = Vector3.ONE * 4.2
			P.collider(n, Vector3(2.6, 1.9, 2.5), Vector3(0, 0.95, 0))
		"outlet":
			var o := outlet()
			n.add_child(o)
			o.scale = Vector3.ONE * 9.0
		"table":
			var t := Node3D.new()
			n.add_child(t)
			P._desk(t)
			t.scale = Vector3.ONE * 3.6
			P.collider(n, Vector3(5.0, 2.7, 2.5), Vector3(0, 1.35, 0))
	return n


static func outlet() -> Node3D:
	var n := Node3D.new()
	P.box(n, Vector3(0.07, 0.115, 0.006), Vector3(0, 0, 0.003), P.m_plastic(Color(0.9, 0.88, 0.8)))
	P.box(n, Vector3(0.008, 0.016, 0.004), Vector3(-0.012, 0.022, 0.007), P.m_black())
	P.box(n, Vector3(0.008, 0.016, 0.004), Vector3(0.012, 0.022, 0.007), P.m_black())
	P.box(n, Vector3(0.008, 0.016, 0.004), Vector3(-0.012, -0.022, 0.007), P.m_black())
	P.box(n, Vector3(0.008, 0.016, 0.004), Vector3(0.012, -0.022, 0.007), P.m_black())
	return n


static func vent(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var m := P.m_plastic(Color(0.82, 0.8, 0.74))
	P.box(n, Vector3(0.5, 0.32, 0.02), Vector3(0, 0, 0.01), m)
	for k in 6:
		P.box(n, Vector3(0.44, 0.012, 0.03), Vector3(0, -0.12 + k * 0.048, 0.02), P.m_black(), Vector3(0.6, 0, 0))
	var se := P.SoundEmitter.new()
	se.snd = "vent_air"
	se.every = 0.0
	se.vol = -18.0
	se.max_dist = 7.0
	n.add_child(se)
	return n


static func peel(rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var under := P.mc(Color(0.55, 0.48, 0.32), "wall_under", 0.9)
	P.box(n, Vector3(0.6, 0.9, 0.004), Vector3(0, 0, 0.002), under)
	for k in rng.randi_range(2, 4):
		var strip := Node3D.new()
		n.add_child(strip)
		strip.position = Vector3(-0.25 + k * 0.16, 0.45, 0.01)
		strip.rotation.x = rng.randf_range(0.2, 0.7)
		P.box(strip, Vector3(0.15, rng.randf_range(0.4, 0.8), 0.004), Vector3(0, -0.3, 0), P.m_wall())
	return n


## Упавшие плиты потолка (над ними — тёмный проём L_HOLE): настоящая плита 0,6×0,6 с текстурой потолка,
## расколотая надвое — один кусок лежит лицом вверх, второй съехал и лёг на край первого или перевернулся
## изнанкой вверх; вокруг — крошка минваты и светлая пыль
static func tile_fallen(rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var mats := P.tile_mats()
	var th := 0.016
	for k in rng.randi_range(1, 2):
		var t := Node3D.new()
		n.add_child(t)
		t.position = Vector3(rng.randf_range(-0.35, 0.35), 0.0, rng.randf_range(-0.35, 0.35))
		t.rotation.y = rng.randf() * TAU
		var y0 := th * 0.5 + 0.002 + k * 0.004
		if rng.randf() < 0.2:
			# целая плита, чуть выгнутая
			var full := PackedVector2Array([Vector2(-0.3, -0.3), Vector2(0.3, -0.3), Vector2(0.3, 0.3), Vector2(-0.3, 0.3)])
			P.tile_node(t, full, th, mats, Vector3(0, y0, 0), Vector3(rng.randf_range(-0.02, 0.02), 0, rng.randf_range(-0.02, 0.02)))
			continue
		var hv := P.tile_halves(rng)
		P.tile_node(t, hv[0], th, mats, Vector3(0, y0, 0), Vector3(rng.randf_range(-0.015, 0.015), 0, rng.randf_range(-0.015, 0.015)))
		var b := Node3D.new()
		t.add_child(b)
		if rng.randf() < 0.4:
			# второй кусок перевернулся: лежит изнанкой вверх в стороне
			b.position = Vector3(rng.randf_range(-0.1, 0.1), y0, 0.18 + rng.randf_range(0.05, 0.2))
			b.rotation = Vector3(0, rng.randf_range(-0.6, 0.6), PI)
		else:
			# съехал: трещиной лёг на край первого куска, дальним краем — на пол
			b.position = Vector3(rng.randf_range(-0.05, 0.05), y0 + 0.012, 0.06 + rng.randf_range(0.0, 0.06))
			b.rotation = Vector3(rng.randf_range(0.03, 0.06), rng.randf_range(-0.25, 0.25), rng.randf_range(-0.03, 0.03))
		P.tile_node(b, hv[1], th, mats, Vector3.ZERO, Vector3.ZERO)
	# крошка и пыль
	var crumb := P.mc(Color(0.6, 0.57, 0.5), "fiber", 0.8, {"albedo_cap": 0.45})
	if P._crumbs.is_empty():
		for k3 in 4:
			P._crumbs.append(P.blob_mesh(1.0, 0.45, 77 + k3, Vector3(1.2, 0.6, 1.0), 8, 2.0))
	for k2 in rng.randi_range(8, 14):
		var r := rng.randf_range(0.01, 0.03)
		var a := rng.randf() * TAU
		var dd := rng.randf_range(0.15, 0.9)
		P.mesh_node(n, P._crumbs[k2 % P._crumbs.size()], crumb, Vector3(cos(a) * dd, r * 0.4, sin(a) * dd), Vector3(0, rng.randf() * TAU, 0), Vector3.ONE * r)
	var dust := P.decal_mat("debris_dust", {"radial": 1.0, "tint": Color(0.5, 0.48, 0.43, 0.22)})
	var dq := P.quad(n, Vector2(1.8, 1.8), Vector3(0, 0.005, 0), dust, Vector3(-PI * 0.5, 0, 0))
	dq.set_instance_shader_parameter("seed", rng.randf() * 10.0)
	return n


static func survey(cx: Node3D, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	P.model(n, "ladder_sectioned_01", Vector3(0, 0, 0), 0.3, 1.0, true)
	# брезент, на нём снятая плита и светильник
	P.box(n, Vector3(1.8, 0.01, 1.4), Vector3(1.4, 0.005, 0.4), P.mc(Color(0.2, 0.3, 0.5), "fabric", 0.6))
	# две снятые плиты потолка (настоящая текстура плиты, рыхлые торцы)
	var full := PackedVector2Array([Vector2(-0.3, -0.3), Vector2(0.3, -0.3), Vector2(0.3, 0.3), Vector2(-0.3, 0.3)])
	for tz in [0.1, 0.7]:
		P.tile_node(n, full, 0.016, P.tile_mats(), Vector3(1.1, 0.019, tz), Vector3(0, rng.randf_range(-0.05, 0.05), 0))
	P.box(n, Vector3(0.62, 0.1, 1.22), Vector3(1.8, 0.06, 0.4), P.mc(Color(0.62, 0.62, 0.6), "metal", 0.4, {"gloss": 40.0, "spec": 0.12}))
	# рассеиватель снятого светильника лежит вверх (текстура целиком на одной грани)
	P.quad(n, Vector2(0.56, 1.16), Vector3(1.8, 0.112, 0.4), P.mc(Color(0.6, 0.6, 0.58), "fixture", 1.0, {"gloss": 60.0, "spec": 0.15}), Vector3(-PI * 0.5, 0, 0))
	P.model(n, "measuring_tape_01", Vector3(1.4, 0.01, 1.0), 0.6, 1.0, false)
	P.model(n, "metal_toolbox", Vector3(-0.8, 0, 0.6), 0.2, 1.3)
	var note := P.note(cx, {"key": "note.a_survey", "p": Vector3.ZERO, "clip": true})
	n.add_child(note)
	note.position = Vector3(-0.4, 0.0, 1.0)
	return n


static func rat() -> Node3D:
	var r := RatNode.new()
	P.model(r, "street_rat", Vector3.ZERO, 0.0, 1.6, false)
	return r


static func drips(rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var se := P.SoundEmitter.new()
	se.snd = "drip"
	se.every = rng.randf_range(1.2, 3.0)
	se.vol = -8.0
	se.max_dist = 14.0
	se.position = Vector3(0, 0.1, 0)
	n.add_child(se)
	var st := P.stain({"wet": true, "s": 0.8, "p": Vector3.ZERO}, rng)
	n.add_child(st)
	return n


static func chairs(d: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var cols := int(d.get("cols", 6))
	var rows := int(d.get("rows", 6))
	for r in rows:
		var skip := false
		for c in cols:
			if skip:
				# место занято упавшим соседом
				skip = false
				continue
			if rng.randf() < 0.06:
				continue
			var ch := Node3D.new()
			n.add_child(ch)
			ch.position = Vector3((c - (cols - 1) * 0.5) * 0.85 + rng.randf_range(-0.04, 0.04), 0, (r - (rows - 1) * 0.5) * 0.9)
			ch.rotation.y = rng.randf_range(-0.05, 0.05)
			if rng.randf() < 0.03 and c < cols - 1:
				# упал на бок вдоль ряда — спинкой на место следующего стула (его нет), чуть выкатился в проход
				ch.rotation = Vector3(0, PI + rng.randf_range(-0.2, 0.2), PI * 0.5)
				ch.position += Vector3(0.05, 0.28, rng.randf_range(0.05, 0.2))
				skip = true
			P._chair(ch)
			if ch.position.y < 0.01:
				P.blob(ch, Vector2(0.72, 0.72), Vector3(0, 0, 0), 0.35)
	return n


class RatNode extends Node3D:
	## Крыса пробегает, когда герой близко, и прячется
	var _run := 0.0
	var _dir := Vector3.ZERO
	var _done := false

	func _process(dt: float) -> void:
		if _done:
			return
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		if _run <= 0.0:
			if cam.global_position.distance_to(global_position) < 5.0:
				_run = 1.2
				var away := global_position - cam.global_position
				away.y = 0
				_dir = away.normalized().rotated(Vector3.UP, randf_range(-0.8, 0.8))
				rotation.y = atan2(_dir.x, _dir.z)
				Snd.play_at("rat_squeak", global_position, get_parent(), -10.0, randf_range(0.9, 1.2), 12.0)
		else:
			_run -= dt
			global_position += _dir * dt * 3.2
			if _run <= 0.0:
				_done = true
				visible = false


# ------------------------------------------------------------ перила над провалами

## Перила длиной len вдоль локальной +x: стойки, поручень, средняя перекладина; иногда сломаны
static func railing(d: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var length := float(d.get("len", 2.4))
	var broken := bool(d.get("broken", false))
	var m := P.mc(Color(0.62, 0.6, 0.52), "metal", 0.5)
	var posts := int(round(length / 1.2))
	for k in posts + 1:
		var px := k * length / posts
		if broken and k == posts / 2 + 1:
			# стойка погнута и лежит
			P.box(n, Vector3(0.05, 1.0, 0.05), Vector3(px, 0.08, 0.35), m, Vector3(PI * 0.5, 0, 0.3))
			continue
		P.box(n, Vector3(0.045, 1.02, 0.045), Vector3(px, 0.51, 0), m)
	if broken:
		var cut := length * rng.randf_range(0.35, 0.65)
		P.box(n, Vector3(cut, 0.05, 0.05), Vector3(cut * 0.5, 1.0, 0), m)
		P.box(n, Vector3(length - cut - 0.3, 0.05, 0.05), Vector3(cut + 0.3 + (length - cut - 0.3) * 0.5, 0.92, 0.04), m, Vector3(0, 0, -0.12))
		P.collider(n, Vector3(cut, 1.05, 0.1), Vector3(cut * 0.5, 0.52, 0))
	else:
		P.box(n, Vector3(length, 0.05, 0.06), Vector3(length * 0.5, 1.02, 0), m)
		P.box(n, Vector3(length, 0.03, 0.03), Vector3(length * 0.5, 0.52, 0), m)
		P.collider(n, Vector3(length, 1.05, 0.1), Vector3(length * 0.5, 0.52, 0))
	return n


# ------------------------------------------------------------ находки

## Сотрудник Async в жёлтом костюме химзащиты: сидит у стены, уронив голову, или лежит ничком. Рядом — его вещи.
## Костюм — развёртка Rocketbox Fire_Male_01, перекрашенная в tools/tex/make_props.py (prop_hazmat): жёлтый
## прорезиненный материал со складками исходника (и карта нормалей складок), сварные швы, чёрные перчатки
## и сапоги, серая лента на стыках. Каска пожарного спрятана; капюшон — по форме головы, с эластичной
## кромкой вокруг панорамного стекла маски и юбкой до плеч; под телом — только мягкая тень и сырость
static func hazmat(cx: Node3D, d: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var h := Human.make("explorer", int(d.get("seed", rng.randi())), true)
	n.add_child(h)
	h.react = false
	_hazmat_suit(h)
	var pz := String(d.get("pose", ""))
	var lying := pz == "lie" or (pz == "" and rng.randf() < 0.4)
	if lying:
		h.pose("stand")
		h._r("sh_l", -0.3, 0, 0.5)
		h._r("sh_r", 0.4, 0, -0.3)
		h._r("hip_r", -0.3)
		h._r("kn_r", 0.6)
		# лежит вдоль стены (узел −z — к стене): голова влево или вправо, тело целиком в зале, а не в стене
		h.rotation = Vector3(-PI * 0.5, PI * 0.5 * (1.0 if rng.randf() < 0.5 else -1.0) + rng.randf_range(-0.3, 0.3), 0)
		h.position = Vector3(0, 0.11, 0.12)
	else:
		# сидит на полу, спиной к стене (узел −z — к стене): одна нога вытянута и завалилась наружу, другое
		# колено поднято; голова упала на грудь и набок, руки висят, кисти на полу
		h.pose("sit_ground")
		h._r("spine", -0.12)
		h._r("chest", 0.12)
		h._r("neck", 0.55, 0.2, 0.4)
		h._r("hip_l", -1.5, 0.0, 0.45)
		h._r("kn_l", 0.15)
		h._r("hip_r", -2.05, 0.0, -0.22)
		h._r("kn_r", 1.85)
		h._r("sh_l", -0.45, 0, 0.12)
		h._r("el_l", -0.95)
		h._r("sh_r", 0.1, 0, -0.32)
		h._r("el_r", -0.2)
		h.position = Vector3(0, 0, -0.18)
	var rub := P.mc(Color(0.8, 0.6, 0.13), "fabric", 0.55, {"wet": 0.2, "gloss": 36.0, "spec": 0.1, "albedo_cap": 0.58, "nmap": Mats.tex("fabric_n"), "bump": 1.0})
	var black := P.mc(Color(0.04, 0.042, 0.038), "metal", 0.3, {"gloss": 40.0, "spec": 0.1})
	var hf := h.head_frame()
	if hf != null:
		# капюшон: купол по голове чуть больше, книзу — юбка до плеч
		P.sph(hf, 0.15, Vector3(0, 0.09, -0.015), rub, Vector3(1.0, 1.2, 1.08), 18)
		var skirt := CylinderMesh.new()
		skirt.top_radius = 0.12
		skirt.bottom_radius = 0.2
		skirt.height = 0.16
		skirt.radial_segments = 18
		skirt.rings = 2
		skirt.cap_top = false
		skirt.cap_bottom = false
		P.mesh_node(hf, skirt, rub, Vector3(0, -0.06, -0.02), Vector3.ZERO, Vector3(1.0, 1.0, 0.9))
		# панорамное стекло маски: выпуклое, тёмное, в чёрной резиновой кромке
		var glass := P.mc(Color(0.09, 0.11, 0.11), "metal", 0.05, {"wet": 1.0, "gloss": 140.0, "spec": 0.6})
		P.sph(hf, 0.09, Vector3(0, 0.085, 0.085), glass, Vector3(1.05, 1.0, 0.55), 18)
		var rim := TorusMesh.new()
		rim.inner_radius = 0.083
		rim.outer_radius = 0.1
		rim.rings = 24
		rim.ring_segments = 6
		P.mesh_node(hf, rim, black, Vector3(0, 0.085, 0.1), Vector3(PI * 0.5 - 0.12, 0, 0), Vector3(1.05, 1.0, 1.0))
		# фильтр под стеклом
		P.cyl(hf, 0.035, 0.04, 0.05, Vector3(0, -0.005, 0.14), black, Vector3(PI * 0.5 + 0.4, 0, 0), 14)
		P.cyl(hf, 0.042, 0.042, 0.012, Vector3(0, -0.015, 0.165), P.mc(Color(0.3, 0.3, 0.28), "metal", 0.4), Vector3(PI * 0.5 + 0.4, 0, 0), 14)
	# рядом — кейс, фонарь, иногда планшет с запиской
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var case := P.model(n, "metal_toolbox", Vector3(0.7 * side, 0.0, 0.3), rng.randf() * 0.6, 1.1, false)
	if case == null:
		P.box(n, Vector3(0.45, 0.14, 0.32), Vector3(0.65 * side, 0.07, 0.25), P.mc(Color(0.2, 0.22, 0.2), "metal", 0.4), Vector3(0, rng.randf() * 0.6, 0))
	var fl := Node3D.new()
	n.add_child(fl)
	fl.position = Vector3(-0.5 * side, 0.03, 0.45)
	fl.rotation = Vector3(0, rng.randf() * TAU, PI * 0.5)
	P.cyl(fl, 0.025, 0.025, 0.2, Vector3.ZERO, P.mc(Color(0.12, 0.13, 0.12), "metal", 0.4, {"gloss": 40.0, "spec": 0.15}), Vector3.ZERO, 10)
	P.cyl(fl, 0.034, 0.027, 0.05, Vector3(0, 0.12, 0), P.mc(Color(0.12, 0.13, 0.12), "metal", 0.4), Vector3.ZERO, 10)
	P.cyl(fl, 0.03, 0.03, 0.004, Vector3(0, 0.146, 0), P.mc(Color(0.5, 0.5, 0.45), "metal", 0.0, {"gloss": 120.0, "spec": 0.5}), Vector3.ZERO, 10)
	if bool(d.get("note", false)):
		var note := P.note(cx, {"key": String(d.get("key", "note.a_hz1")), "p": Vector3.ZERO, "clip": true})
		n.add_child(note)
		note.position = Vector3(0.3 * side, 0.0, 0.6)
	# мягкая тень по телу и бледное сырое пятно (без резкого круга)
	P.blob(n, Vector2(0.9, 1.9) if lying else Vector2(0.95, 0.9), Vector3(0, 0, 0.1 if not lying else 0.0), 0.45)
	var st := P.stain({"wet": true, "s": 1.1}, rng)
	n.add_child(st)
	st.scale = Vector3(1.0, 1.0, 1.3)
	return n


static var _hz_mats := {}


## Материалы костюма на сетке Rocketbox: тело — prop_hazmat (+ карта нормалей), каска — скрыта, голова — как есть
static func _hazmat_suit(h: Human) -> void:
	var has_tex := Mats.has_tex("prop_hazmat")
	for part in h.parts:
		var mi := part as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var nm := src.resource_name.to_lower() if src != null else ""
			var cur := mi.get_surface_override_material(i) as ShaderMaterial
			if cur == null:
				continue
			var key := nm + str(cur.get_instance_id())
			if not _hz_mats.has(key):
				var m := cur.duplicate() as ShaderMaterial
				m.set_shader_parameter("pale", 0.0)
				m.set_shader_parameter("smear", 0.0)
				m.set_shader_parameter("face_smear", 0.0)
				if nm.contains("helmet"):
					# каску не рисуем: вырез по альфе отбрасывает всё
					m.set_shader_parameter("alpha_cut", 2.0)
				elif not nm.contains("head"):
					if has_tex:
						m.set_shader_parameter("tex", Mats.tex("prop_hazmat"))
						m.set_shader_parameter("tex_mix", 1.0)
						m.set_shader_parameter("color", Color(1, 1, 1))
						if Mats.has_tex("prop_hazmat_n"):
							m.set_shader_parameter("nmap", Mats.tex("prop_hazmat_n"))
							m.set_shader_parameter("bump", 1.2)
							m.set_shader_parameter("nmap_gl", 0.0)
					else:
						m.set_shader_parameter("tex_mix", 0.3)
						m.set_shader_parameter("color", Color(0.95, 0.7, 0.1))
					m.set_shader_parameter("wet", 0.2)
					m.set_shader_parameter("gloss", 36.0)
					m.set_shader_parameter("spec", 0.12)
					m.set_shader_parameter("albedo_cap", 0.62)
				_hz_mats[key] = m
			mi.set_surface_override_material(i, _hz_mats[key])


static var _cloth_mesh := {}


## Сложенная вещь: мягкий «пирожок» — лофт со скруглёнными краями, верх чуть выпуклый, по краю — сгиб
static func _folded(w: float, d: float, th: float) -> ArrayMesh:
	var key := "%.3f_%.3f_%.3f" % [w, d, th]
	if not _cloth_mesh.has(key):
		var secs := []
		for i in 7:
			var t := float(i) / 6.0
			var z := lerpf(d * 0.5, -d * 0.5, t)
			var bulge := sin(t * PI)
			var e := 1.0 - 0.25 * pow(absf(t - 0.5) * 2.0, 8.0)
			secs.append([z, w * 0.5 * e, w * 0.5 * (0.96 + 0.03 * bulge) * e, 0.0, th * (0.85 + 0.15 * bulge) * e + 0.004, th * 0.3])
		_cloth_mesh[key] = P.section_loft(secs)
	return _cloth_mesh[key]


## Ботинок: лофт вдоль z от пятки к носку — подошва с каблуком, верх с вырезом (тёмная «дыра» сверху)
static func _shoe_mesh() -> ArrayMesh:
	if not _cloth_mesh.has("shoe"):
		_cloth_mesh["shoe"] = P.section_loft([[-0.13, 0.03, 0.025, 0.0, 0.07, 0.02], [-0.11, 0.04, 0.035, 0.0, 0.1, 0.025],
			[-0.03, 0.045, 0.04, 0.0, 0.11, 0.03], [0.04, 0.05, 0.045, 0.0, 0.085, 0.03], [0.1, 0.048, 0.04, 0.0, 0.06, 0.025],
			[0.135, 0.035, 0.025, 0.0, 0.045, 0.018]])
	return _cloth_mesh["shoe"]


## Аккуратно сложенная одежда и ботинки — человека нет: джинсы, рубашка/свитер стопкой (мягкие, со сгибами
## и фактурой ткани), сверху иногда часы; рядом — пара ботинок со шнурками, носки в одном из них
static func clothes(rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var denim := P.mc(Color(0.2, 0.27, 0.42), "fabric", 1.0, {"nmap": Mats.tex("fabric_n"), "bump": 1.2, "gloss": 10.0, "spec": 0.02})
	var cols := [Color(0.62, 0.57, 0.47), Color(0.15, 0.15, 0.17), Color(0.52, 0.19, 0.17), Color(0.75, 0.74, 0.7), Color(0.3, 0.38, 0.3)]
	var y := 0.0
	var cnt := rng.randi_range(2, 4)
	for k in cnt:
		var th := rng.randf_range(0.03, 0.05)
		var w := 0.36 - k * 0.025 + rng.randf_range(-0.02, 0.02)
		var dd := 0.28 - k * 0.015
		var m: Material = denim if k == 0 else P.mc(cols[rng.randi_range(0, cols.size() - 1)], "fabric", 1.0, {"nmap": Mats.tex("fabric_n"), "bump": 1.0, "gloss": 8.0, "spec": 0.02})
		var g := P.mesh_node(n, _folded(w, dd, th), m, Vector3(rng.randf_range(-0.015, 0.015), y, rng.randf_range(-0.015, 0.015)), Vector3(0, rng.randf_range(-0.1, 0.1), 0))
		# сгиб посередине (тонкая тёмная складка) и, у рубашки, воротник
		P.box(n, Vector3(w * 0.9, 0.004, 0.006), Vector3(0, y + th * 0.95 + 0.003, 0), P.mc(Color(0.08, 0.08, 0.08), "fabric", 0.3), Vector3(0, g.rotation.y, 0))
		if k == cnt - 1 and k > 0:
			P.mesh_node(n, _folded(0.14, 0.06, 0.018), m, Vector3(0, y + th * 0.9, -dd * 0.36), Vector3(0, g.rotation.y, 0))
		y += th * 0.92
	var leather := P.mc(Color(0.16, 0.1, 0.06), "fabric", 0.5, {"gloss": 50.0, "spec": 0.12})
	var sole := P.mc(Color(0.06, 0.05, 0.045), "metal", 0.3)
	for sx in [-0.07, 0.07]:
		var sh := P.mesh_node(n, _shoe_mesh(), leather, Vector3(sx, 0.0, 0.42 + rng.randf_range(-0.02, 0.02)), Vector3(0, rng.randf_range(-0.12, 0.12), 0))
		P.box(sh, Vector3(0.095, 0.012, 0.27), Vector3(0, 0.006, 0.0), sole)
		# вырез сверху и шнурки
		var hole := P.cyl(sh, 0.032, 0.032, 0.004, Vector3(0, 0.111, -0.06), P.m_black(), Vector3(0.1, 0, 0), 12)
		hole.scale = Vector3(0.9, 1.0, 1.6)
		for k2 in 3:
			P.box(sh, Vector3(0.05, 0.004, 0.006), Vector3(0, 0.1 - k2 * 0.008, -0.01 + k2 * 0.025), P.m_plastic(Color(0.6, 0.58, 0.5)), Vector3(0.25, 0, 0))
	if rng.randf() < 0.5:
		# наручные часы на стопке
		P.cyl(n, 0.018, 0.018, 0.008, Vector3(0.05, y + 0.006, 0.02), P.mc(Color(0.55, 0.55, 0.52), "metal", 0.4, {"gloss": 90.0, "spec": 0.4}), Vector3.ZERO, 16)
		P.box(n, Vector3(0.016, 0.004, 0.16), Vector3(0.05, y + 0.003, 0.02), P.mc(Color(0.1, 0.08, 0.06), "fabric", 0.5))
	P.blob(n, Vector2(0.55, 0.85), Vector3(0, 0, 0.15), 0.3)
	return n


## Видеокамера на штативе снимает стену; огонёк записи горит. Штатив: три двухколенные алюминиевые ноги
## с зажимами и резиновыми пятками, распорка, центральная колонна, панорамная головка с ручкой, площадка
static func tripod_cam(rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var alu := P.mc(Color(0.4, 0.4, 0.4), "metal", 0.4, {"gloss": 60.0, "spec": 0.25})
	var blk := P.mc(Color(0.05, 0.05, 0.05), "metal", 0.3, {"gloss": 40.0, "spec": 0.1})
	var top := Vector3(0, 1.05, 0)
	for k in 3:
		var a := k * TAU / 3.0 + rng.randf_range(-0.12, 0.12)
		var foot := Vector3(cos(a) * 0.42, 0.012, sin(a) * 0.42)
		var mid := top.lerp(foot, 0.52)
		P.rod(n, top + Vector3(cos(a) * 0.035, 0, sin(a) * 0.035), mid, 0.011, alu, 8)
		P.rod(n, mid, foot, 0.008, alu, 8)
		# зажим колена и пятка
		P.rod(n, mid.lerp(top, 0.04), mid.lerp(foot, 0.06), 0.015, blk, 8)
		P.cyl(n, 0.014, 0.012, 0.025, foot, blk, Vector3.ZERO, 8)
		# распорка к колонне
		P.rod(n, Vector3(0, 0.55, 0), top.lerp(foot, 0.45), 0.004, blk, 4)
	# корона ног, колонна, головка
	P.cyl(n, 0.045, 0.05, 0.05, top, blk, Vector3.ZERO, 12)
	P.rod(n, Vector3(0, 0.5, 0), top + Vector3(0, 0.16, 0), 0.012, alu, 8)
	P.cyl(n, 0.035, 0.035, 0.04, top + Vector3(0, 0.18, 0), blk, Vector3.ZERO, 12)
	P.box(n, Vector3(0.06, 0.02, 0.1), top + Vector3(0, 0.21, 0), blk)
	P.rod(n, top + Vector3(0, 0.2, -0.03), top + Vector3(0.05, 0.14, -0.32), 0.008, blk, 6)
	P.cyl(n, 0.012, 0.012, 0.08, top + Vector3(0.055, 0.135, -0.36), P.mc(Color(0.08, 0.08, 0.08), "fabric", 0.4), Vector3(0.6, 0, 0), 8)
	# камера на площадке, объективом в стену (+z)
	var cam := Node3D.new()
	n.add_child(cam)
	cam.position = top + Vector3(0, 0.22, -0.01)
	var rec := P.camcorder(cam)
	rec.set_meta("blink", true)
	var se := P.SoundEmitter.new()
	se.snd = "engine_tick"
	se.every = 0.0
	se.vol = -24.0
	se.max_dist = 4.0
	se.position = Vector3(0, 1.36, 0)
	n.add_child(se)
	return n


## Следы волочения: тёмная полоса уходит прямо в стену
static func drag(rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var mat := P.decal_mat("drag", {"stripes": 1.0, "tint": Color(0.16, 0.025, 0.015, 0.55)})
	var q := P.quad(n, Vector2(0.55, 2.3), Vector3(0, 0.006, -1.15), mat, Vector3(-PI * 0.5, 0, 0))
	q.set_instance_shader_parameter("seed", rng.randf() * 10.0)
	var hm := P.decal_mat("hand", {"radial": 1.0, "tint": Color(0.18, 0.03, 0.02, 0.6)})
	P.quad(n, Vector2(0.14, 0.18), Vector3(0.12, 0.007, -0.3), hm, Vector3(-PI * 0.5, 0, 0.3))
	return n


## Дверь в раме посреди зала: открывается — за ней тот же зал
## Филёнчатое полотно двери (шесть филёнок, как у дверей тех лет) в узле h: петли по x = 0, полотно — к +x.
## Обвязка — плоская доска, филёнки — приподнятые панели с фасками, ручка-шар с розеткой на обеих сторонах
static func _door_leaf(h: Node3D, leaf: Material, hw: Material) -> void:
	var w := 0.92
	var hh := 2.08
	var t := 0.045
	P.box(h, Vector3(w, hh, t), Vector3(w * 0.5, hh * 0.5 + 0.01, 0), leaf)
	# филёнки: 2 ряда × 3 (верхние короче), приподняты на 6 мм с фаской (две ступени)
	var rows := [[1.62, 0.6], [0.95, 0.62], [0.3, 0.46]]
	for side: float in [1.0, -1.0]:
		for rw in rows:
			var r: Array = rw
			for cx in [0.24, 0.68]:
				var pc := Vector3(cx, float(r[0]) + 0.01, side * (t * 0.5 + 0.002))
				# тень-канавка вокруг филёнки (тонкая тёмная рамка — видна при любом свете)
				P.box(h, Vector3(0.352, float(r[1]) + 0.012, 0.002), pc - Vector3(0, 0, side * 0.0012), P.mc(Color(0.06, 0.05, 0.04), "wood", 0.3))
				P.box(h, Vector3(0.34, float(r[1]), 0.004), pc, leaf)
				P.box(h, Vector3(0.28, float(r[1]) - 0.06, 0.004), pc + Vector3(0, 0, side * 0.004), leaf)
		# ручка: розетка, шейка, шар
		var kz := side * (t * 0.5)
		P.cyl(h, 0.028, 0.028, 0.008, Vector3(0.84, 0.98, kz + side * 0.004), hw, Vector3(PI * 0.5, 0, 0), 14)
		P.cyl(h, 0.01, 0.012, 0.05, Vector3(0.84, 0.98, kz + side * 0.03), hw, Vector3(PI * 0.5, 0, 0), 10)
		P.sph(h, 0.027, Vector3(0.84, 0.98, kz + side * 0.065), hw, Vector3(1, 1, 0.85), 14)
	# петли
	for hy in [0.25, 1.05, 1.85]:
		P.cyl(h, 0.008, 0.008, 0.1, Vector3(0.0, hy, 0.0), hw, Vector3.ZERO, 8)


static func lone_door(rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var frame := P.m_plastic(Color(0.84, 0.82, 0.76))
	var leafc := Color(0.55, 0.42, 0.3) if rng.randf() < 0.5 else Color(0.78, 0.76, 0.7)
	var leafm: Material = P.mc(leafc, "wood", 0.85, {"nmap": Mats.tex("wood_n"), "bump": 0.5, "gloss": 40.0, "spec": 0.08}) if leafc.r < 0.6 \
		else P.mc(leafc, "wood", 0.25, {"gloss": 45.0, "spec": 0.09, "wash": 0.2})
	var brass := P.mc(Color(0.55, 0.42, 0.18), "metal", 0.4, {"gloss": 90.0, "spec": 0.4})
	# коробка и наличники с обеих сторон (профиль: плоский наличник 7 см с выступом по краю), порог
	P.box(n, Vector3(0.05, 2.12, 0.12), Vector3(-0.485, 1.06, 0), frame)
	P.box(n, Vector3(0.05, 2.12, 0.12), Vector3(0.485, 1.06, 0), frame)
	P.box(n, Vector3(1.02, 0.05, 0.12), Vector3(0, 2.125, 0), frame)
	for side in [1.0, -1.0]:
		for sx in [-1.0, 1.0]:
			P.box(n, Vector3(0.07, 2.19, 0.014), Vector3(sx * 0.545, 1.095, side * 0.067), frame)
			P.box(n, Vector3(0.012, 2.19, 0.02), Vector3(sx * 0.575, 1.095, side * 0.07), frame)
		P.box(n, Vector3(1.19, 0.08, 0.014), Vector3(0, 2.19, side * 0.067), frame)
		P.box(n, Vector3(1.19, 0.012, 0.02), Vector3(0, 2.224, side * 0.07), frame)
	P.box(n, Vector3(1.0, 0.012, 0.16), Vector3(0, 0.006, 0), P.mc(Color(0.45, 0.35, 0.24), "wood", 0.8))
	var hinge := Node3D.new()
	hinge.position = Vector3(-0.46, 0, 0)
	n.add_child(hinge)
	_door_leaf(hinge, leafm, brass)
	var col := P.collider(hinge, Vector3(0.92, 2.08, 0.06), Vector3(0.46, 1.05, 0))
	P.collider(n, Vector3(0.1, 2.2, 0.14), Vector3(-0.5, 1.1, 0))
	P.collider(n, Vector3(0.1, 2.2, 0.14), Vector3(0.5, 1.1, 0))
	var opened := [false]
	P.interactable(n, Vector3(1.0, 2.0, 0.4), Vector3(0, 1.0, 0), "ui.door", func() -> void:
		if opened[0]:
			return
		opened[0] = true
		Snd.play("door_open", -4.0, randf_range(0.95, 1.05))
		var tw := n.create_tween()
		tw.tween_property(hinge, "rotation:y", -1.6, 1.4).set_trans(Tween.TRANS_SINE)
		col.collision_layer = 0)
	return n


## Чья-то ночёвка: одеяло, пустые банки, фонарик без батареек, зарубки на стене
## Узел смотрит +z в стену; стена — в 0,95 м. Одеяло вдоль стены, банки — со стороны зала, зарубки — на стене у изголовья
static func lost_camp(cx: Node3D, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var wall_z := 0.95
	# спальник вдоль стены: стёганый (валики поперёк), объёмный, верх у изголовья отвёрнут — видна фланелевая
	# подкладка; под головой — свёрнутая куртка
	var bag_m: Material = P.mc(Color(0.85, 0.9, 1.0), "prop_sleepbag", 1.0, {"nmap": Mats.tex("prop_sleepbag_n"), "bump": 1.0, "gloss": 30.0, "spec": 0.06}) \
		if Mats.has_tex("prop_sleepbag") else P.m_cloth(Color(0.2, 0.24, 0.4))
	var lining := P.mc(Color(0.55, 0.36, 0.25), "fabric", 0.9, {"nmap": Mats.tex("fabric_n"), "bump": 0.8, "gloss": 8.0, "spec": 0.02})
	var bag := Node3D.new()
	n.add_child(bag)
	bag.position = Vector3(0.05, 0, wall_z - 0.48)
	bag.rotation.y = PI * 0.5 + rng.randf_range(-0.06, 0.06)
	var secs := []
	for i in 9:
		var t := float(i) / 8.0
		var z := lerpf(0.95, -0.95, t)
		var wdt := 0.36 - 0.06 * t + 0.02 * sin(t * 9.0)
		var hgt := 0.085 + 0.03 * sin(t * PI) - (0.03 if t < 0.2 else 0.0)
		secs.append([z, wdt, wdt * 0.82, 0.0, hgt, hgt * 0.45])
	P.mesh_node(bag, P.section_loft(secs), bag_m)
	# отвёрнутый угол: подкладкой вверх
	P.mesh_node(bag, _folded(0.5, 0.42, 0.025), lining, Vector3(0.06, 0.07, 0.62), Vector3(0.0, 0.5, 0.04))
	P.mesh_node(bag, _folded(0.4, 0.2, 0.06), P.mc(Color(0.36, 0.38, 0.27), "fabric", 0.9, {"nmap": Mats.tex("fabric_n"), "bump": 1.0}),
		Vector3(0.0, 0.065, 0.88), Vector3(0.1, 0.0, 0.0))
	P.blob(n, Vector2(2.2, 1.0), Vector3(0, 0, wall_z - 0.5), 0.35)
	# пустые банки: часть стоит, часть лежит; фонарик
	for k in rng.randi_range(4, 7):
		var lying := rng.randf() < 0.5
		var cp := Vector3(rng.randf_range(-0.9, 1.0), 0.048 if lying else 0.0, rng.randf_range(-0.75, -0.15))
		var cn := P.model(n, "can_rusted", cp, rng.randf() * TAU, 0.8, false)
		if cn == null:
			P.cyl(n, 0.035, 0.035, 0.11, cp + Vector3(0, 0.055, 0), P.m_metal(), Vector3.ZERO, 8)
		elif lying:
			cn.rotation.x = PI * 0.5
	var fl := Node3D.new()
	n.add_child(fl)
	fl.position = Vector3(0.55, 0.024, -0.3)
	fl.rotation = Vector3(0, 0.4, PI * 0.5)
	P.cyl(fl, 0.022, 0.022, 0.16, Vector3.ZERO, P.mc(Color(0.12, 0.13, 0.12), "metal", 0.4, {"gloss": 40.0, "spec": 0.15}), Vector3.ZERO, 10)
	P.cyl(fl, 0.03, 0.023, 0.045, Vector3(0, 0.1, 0), P.mc(Color(0.12, 0.13, 0.12), "metal", 0.4), Vector3.ZERO, 10)
	P.cyl(fl, 0.026, 0.026, 0.004, Vector3(0, 0.123, 0), P.mc(Color(0.5, 0.5, 0.45), "metal", 0.0, {"gloss": 120.0, "spec": 0.5}), Vector3.ZERO, 10)
	# зарубки: рисунок «от руки» плоской наклейкой на обоях, на высоте лежащего
	var tname := "graf_tally2_%s" % ("en" if Loc.is_en("graf.tally2") else "ru")
	if Mats.has_tex(tname):
		var tx := Mats.tex(tname)
		var mat := P.decal_mat(tname, {"tex": tname, "tex_color": 1.0, "tint": Color(1, 1, 1, 0.94)})
		var q := P.quad(n, Vector2(tx.get_width(), tx.get_height()) * 0.0011, Vector3(-0.45, 0.62, wall_z - 0.012), mat, Vector3(0, PI, rng.randf_range(-0.05, 0.05)))
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


# ------------------------------------------------------------ обжитые и странные места

## Надпись/табличка: ключ текста, цвет, размер; plate — подложка
static func text(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var col: Color = d.get("color", Color(0.08, 0.08, 0.1))
	var txt := String(d.get("txt", "")) if d.has("txt") else Loc.t(String(d.get("key", "sign.exit")))
	# glow — светящееся табло (от сети)
	var lb := P.label(txt, P.font_hand() if bool(d.get("hand", false)) else P.font_sign(), float(d.get("px", 0.004)), col, 0, 0.0, float(d.get("glow", 0.0)))
	var z := 0.008
	if bool(d.get("plate", false)):
		# табличка не меньше надписи (шрифт системный, ширина строки зависит от языка)
		var ps: Vector2 = d.get("plate_size", Vector2(0.9, 0.35))
		var lm := lb as MeshInstance3D
		if lm != null and lm.mesh is QuadMesh:
			var qs := (lm.mesh as QuadMesh).size
			ps = Vector2(maxf(ps.x, qs.x + 0.08), maxf(ps.y, qs.y + 0.04))
		var pc: Color = d.get("plate_color", Color(0.05, 0.05, 0.05))
		P.box(n, Vector3(ps.x, ps.y, 0.03), Vector3(0, 0, 0.015), P.mc(pc, "metal", 0.2, {"gloss": 40.0, "spec": 0.1}))
		z = 0.0315
	lb.position = Vector3(0, 0, z)
	n.add_child(lb)
	return n


class Spinner extends Node3D:
	var speed := 1.0
	var axis := Vector3.UP

	func _process(dt: float) -> void:
		rotate_object_local(axis, speed * dt)


## Модель, которая медленно крутится (потолочный вентилятор)
static func spin(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var id := String(d.get("id", "ceiling_fan"))
	var sp := Spinner.new()
	sp.speed = float(d.get("speed", 1.5))
	n.add_child(sp)
	if bool(d.get("on_ceiling", false)):
		var bb := Models.aabb(id)
		sp.position.y = float(d.get("ceil", 2.7)) - bb.size.y - bb.position.y
	P.model(sp, id, Vector3.ZERO, 0.0, 1.0, false)
	return n


## Торт со свечами на круглом столе, колпаки, тарелки
static func cake(rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	# у модели столешница на 1 м (барная высота) — для детского праздника ниже, ~0,74 м
	var sy := 0.74
	P.model(n, "round_wooden_table_01", Vector3.ZERO, 0.0, Vector3(1.0, sy, 1.0))
	var top := P.top_of("round_wooden_table_01", sy)
	if top < 0.3:
		top = 0.75
	P.blob(n, Vector2(1.6, 1.6), Vector3.ZERO, 0.4)
	P.cyl(n, 0.17, 0.17, 0.13, Vector3(0, top + 0.065, 0), P.mc(Color(0.96, 0.92, 0.86), "fabric", 0.6))
	P.cyl(n, 0.175, 0.175, 0.025, Vector3(0, top + 0.14, 0), P.mc(Color(0.92, 0.48, 0.62), "fabric", 0.5))
	for k in 5:
		var a := k * TAU / 5.0
		P.cyl(n, 0.006, 0.006, 0.07, Vector3(cos(a) * 0.1, top + 0.19, sin(a) * 0.1), P.mc(Color(0.4, 0.6, 0.95), "metal", 0.2), Vector3.ZERO, 5)
	var hats := [Color(0.9, 0.2, 0.3), Color(0.2, 0.5, 0.9), Color(0.95, 0.8, 0.2)]
	for k in 3:
		var a2 := rng.randf() * TAU
		P.cyl(n, 0.0, 0.07, 0.17, Vector3(cos(a2) * 0.45, top + 0.085, sin(a2) * 0.45), P.mc(hats[k], "fabric", 0.3), Vector3.ZERO, 10)
		P.cyl(n, 0.09, 0.09, 0.01, Vector3(cos(a2 + 1.0) * 0.38, top + 0.005, sin(a2 + 1.0) * 0.38), P.m_plastic(Color(0.95, 0.95, 0.93)), Vector3.ZERO, 14)
	return n


## Проектор на столе (top — высота столешницы) светит в стену: мягкий пыльный луч и светлый кадр на обоях
static func projector(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var dist := float(d.get("dist", 4.0))
	var on: Array = d.get("on", [])
	var y := (P.top_of(String(on[0]), float(on[1])) if on.size() > 1 else 0.76) + 0.072
	var body := P.mc(Color(0.22, 0.22, 0.24), "metal", 0.4, {"gloss": 40.0, "spec": 0.12})
	P.box(n, Vector3(0.3, 0.12, 0.26), Vector3(0, y, 0), body)
	for sx in [-0.11, 0.11]:
		P.cyl(n, 0.012, 0.012, 0.012, Vector3(sx, y - 0.066, -0.09), P.m_black(), Vector3.ZERO, 6)
	P.cyl(n, 0.04, 0.04, 0.06, Vector3(0, y + 0.01, -0.15), P.m_black(), Vector3(PI * 0.5, 0, 0), 12)
	# стекло объектива светится
	P.cyl(n, 0.03, 0.03, 0.004, Vector3(0, y + 0.01, -0.181), P.m_emit(Color(0.85, 0.9, 1.0), 3.0, true), Vector3(PI * 0.5, 0, 0), 12)
	var lens := Vector3(0, y + 0.01, -0.183)
	var pic := Vector3(0, 1.55, -dist)
	var half := Vector2(0.85, 0.575)
	var spot := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = half * 2.0 * 1.06
	spot.mesh = qm
	var sm := ShaderMaterial.new()
	sm.shader = SPOT_SHADER
	spot.material_override = sm
	spot.position = pic + Vector3(0, 0, 0.006)
	spot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(spot)
	var beam := MeshInstance3D.new()
	beam.mesh = _frustum(lens, Vector2(0.06, 0.05), pic + Vector3(0, 0, 0.02), half * 1.2)
	var bm := ShaderMaterial.new()
	bm.shader = BEAM_SHADER
	bm.set_shader_parameter("noise_tex", Mats.tex("noise"))
	bm.set_shader_parameter("axis_a", lens)
	bm.set_shader_parameter("axis_b", pic)
	bm.set_shader_parameter("r_a", Vector2(0.03, 0.022))
	bm.set_shader_parameter("r_b", half)
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.extra_cull_margin = 0.5
	n.add_child(beam)
	var se := P.SoundEmitter.new()
	se.snd = "vending_hum"
	se.every = 0.0
	se.vol = -24.0
	se.max_dist = 6.0
	se.position = Vector3(0, y, 0)
	n.add_child(se)
	return n


## Оболочка луча: усечённая пирамида без торцов между прямоугольниками (в плоскости XY) с центрами a и b.
## Нормали — наружу (шейдер луча рисует только дальние грани)
static func _frustum(a: Vector3, ra: Vector2, b: Vector3, rb: Vector2) -> ArrayMesh:
	var ca := [a + Vector3(-ra.x, -ra.y, 0), a + Vector3(ra.x, -ra.y, 0), a + Vector3(ra.x, ra.y, 0), a + Vector3(-ra.x, ra.y, 0)]
	var cb := [b + Vector3(-rb.x, -rb.y, 0), b + Vector3(rb.x, -rb.y, 0), b + Vector3(rb.x, rb.y, 0), b + Vector3(-rb.x, rb.y, 0)]
	var mid := (a + b) * 0.5
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	for i in 4:
		var j := (i + 1) % 4
		var p0: Vector3 = ca[i]
		var p1: Vector3 = ca[j]
		var p2: Vector3 = cb[j]
		var p3: Vector3 = cb[i]
		var nn := (p1 - p0).cross(p3 - p0).normalized()
		if nn.dot((p0 + p2) * 0.5 - mid) < 0.0:
			nn = -nn
		for p in [p0, p1, p2, p0, p2, p3]:
			vs.append(p)
			ns.append(nn)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Лифт: створки, табло «—», кнопка вызова. Позвонишь — звенит, но двери не откроются
static func elevator(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	# шлифованная сталь створок, тёмная рама, порог; табло и кнопка — от сети
	var steel := P.mc(Color(0.5, 0.5, 0.49), "metal", 0.75, {"gloss": 70.0, "spec": 0.35})
	var frame := P.mc(Color(0.28, 0.28, 0.3), "metal", 0.5, {"gloss": 40.0, "spec": 0.15})
	P.box(n, Vector3(1.45, 2.35, 0.08), Vector3(0, 1.175, 0.04), frame)
	P.box(n, Vector3(0.6, 2.12, 0.03), Vector3(-0.305, 1.06, 0.095), steel)
	P.box(n, Vector3(0.6, 2.12, 0.03), Vector3(0.305, 1.06, 0.095), steel)
	P.box(n, Vector3(0.012, 2.12, 0.035), Vector3(0, 1.06, 0.1), P.m_black())
	P.box(n, Vector3(1.3, 0.012, 0.12), Vector3(0, 0.006, 0.12), P.mc(Color(0.42, 0.42, 0.4), "metal", 0.7, {"gloss": 50.0, "spec": 0.25}))
	P.box(n, Vector3(0.5, 0.18, 0.04), Vector3(0, 2.5, 0.05), P.m_black())
	var lb := P.label("—", P.font_sign(), 0.0045, Color(1.0, 0.25, 0.08), 0, 0.0, 2.2)
	lb.position = Vector3(0, 2.5, 0.0705)
	n.add_child(lb)
	P.box(n, Vector3(0.12, 0.24, 0.03), Vector3(0.95, 1.1, 0.02), steel)
	var btn := P.sph(n, 0.026, Vector3(0.95, 1.14, 0.04), P.m_emit(Color(1.0, 0.82, 0.4), 2.0, true))
	P.collider(n, Vector3(1.45, 2.35, 0.2), Vector3(0, 1.175, 0.05))
	var se := P.SoundEmitter.new()
	se.snd = "elev_ding"
	se.every = 55.0
	se.vol = -6.0
	se.max_dist = 20.0
	se.position = Vector3(0, 2.4, 0.1)
	n.add_child(se)
	var busy := [false]
	P.interactable(n, Vector3(0.3, 0.4, 0.3), Vector3(0.95, 1.12, 0.1), "ui.call", func() -> void:
		if busy[0]:
			return
		busy[0] = true
		Snd.play("ui_click", -6.0)
		btn.scale = Vector3.ONE * 1.25
		n.get_tree().create_timer(5.5).timeout.connect(func() -> void:
			if is_instance_valid(n):
				Snd.play_at("elev_ding", n.global_position + Vector3(0, 2.4, 0), n, -2.0, 1.0, 20.0, 3.0)
				busy[0] = false))
	return n


## Манекен витрины: гладкий стеклопластик (не человек в одежде) — обтекаемый торс, яйцо-голова без черт лица,
## руки и ноги — гладкие сужающиеся трубы, кисти-«лопатки», тонкие тёмные швы разъёмов на плечах, запястьях
## и талии; стоит на хромированном штыре в икре на стеклянном диске. Лак — белый, кремовый или серый,
## с атласным бликом. «watch» — тот, что поворачивает голову к камере, пока на него не смотрят
static var _mq := {}


static func _mq_mesh(key: String) -> ArrayMesh:
	if _mq.has(key):
		return _mq[key]
	var m: ArrayMesh
	match key:
		"torso":
			var ys := [0.79, 0.84, 0.91, 1.0, 1.08, 1.18, 1.27, 1.35, 1.415, 1.455, 1.485, 1.53, 1.6, 1.63]
			var rx := [0.07, 0.135, 0.165, 0.152, 0.124, 0.134, 0.152, 0.163, 0.17, 0.13, 0.07, 0.047, 0.043, 0.0]
			var rz := [0.06, 0.1, 0.112, 0.102, 0.088, 0.094, 0.104, 0.096, 0.08, 0.07, 0.055, 0.047, 0.043, 0.0]
			var cz := [0.0, -0.01, -0.016, -0.004, 0.006, 0.012, 0.02, 0.012, -0.004, -0.008, -0.006, 0.004, 0.012, 0.014]
			var pts := PackedVector3Array()
			var a := PackedFloat32Array()
			var b := PackedFloat32Array()
			for i in ys.size():
				pts.append(Vector3(0, ys[i], cz[i]))
				a.append(rx[i])
				b.append(rz[i])
			m = P.loft(pts, a, b, 20)
		"head":
			m = P.blob_mesh(0.1, 0.0, 1, Vector3(0.8, 1.12, 0.93), 24)
		"uparm":
			m = _mq_limb([0.0, -0.05, -0.15, -0.27, -0.3], [0.047, 0.046, 0.04, 0.036, 0.034])
		"forearm":
			m = _mq_limb([0.0, -0.03, -0.12, -0.22, -0.255], [0.035, 0.036, 0.031, 0.025, 0.024])
		"hand":
			var pts2 := PackedVector3Array()
			var w := PackedFloat32Array()
			var t := PackedFloat32Array()
			var prof := [[0.0, 0.024, 0.017], [-0.04, 0.038, 0.018], [-0.09, 0.041, 0.015], [-0.14, 0.034, 0.011], [-0.17, 0.02, 0.008], [-0.18, 0.0, 0.0]]
			for q in prof:
				var qa: Array = q
				pts2.append(Vector3(0, qa[0], 0))
				w.append(qa[1])
				t.append(qa[2])
			m = P.loft(pts2, t, w, 14, Vector3(1, 0, 0))
		"thigh":
			m = _mq_limb([0.0, -0.06, -0.2, -0.36, -0.44], [0.074, 0.075, 0.064, 0.05, 0.047])
		"calf":
			m = _mq_limb([0.0, -0.05, -0.14, -0.28, -0.39, -0.425], [0.046, 0.05, 0.054, 0.04, 0.03, 0.029])
		"foot":
			var pts3 := PackedVector3Array()
			var fw := PackedFloat32Array()
			var fh := PackedFloat32Array()
			var fp := [[-0.05, 0.0, 0.0, 0.0], [-0.045, 0.03, 0.03, 0.028], [0.0, 0.035, 0.04, 0.035], [0.08, 0.025, 0.045, 0.024], [0.15, 0.018, 0.04, 0.016], [0.185, 0.014, 0.025, 0.01], [0.195, 0.012, 0.0, 0.0]]
			for q in fp:
				var qa2: Array = q
				pts3.append(Vector3(0, qa2[1], qa2[0]))
				fw.append(qa2[2])
				fh.append(qa2[3])
			m = P.loft(pts3, fw, fh, 14, Vector3(1, 0, 0))
	_mq[key] = m
	return m


## Гладкая конечность вниз по −y: ys — отметки, rs — радиусы
static func _mq_limb(ys: Array, rs: Array) -> ArrayMesh:
	var pts := PackedVector3Array()
	var r := PackedFloat32Array()
	for i in ys.size():
		pts.append(Vector3(0, ys[i], 0))
		r.append(rs[i])
	# закруглить концы: короткий купол сверху и снизу
	var top := pts[0]
	var bot := pts[pts.size() - 1]
	var r0: float = rs[0]
	var r1: float = rs[rs.size() - 1]
	var p2 := PackedVector3Array([top + Vector3(0, r0 * 0.9, 0), top + Vector3(0, r0 * 0.6, 0)])
	var q2 := PackedFloat32Array([0.0, r0 * 0.8])
	p2.append_array(pts)
	q2.append_array(r)
	p2.append(bot - Vector3(0, r1 * 0.6, 0))
	p2.append(bot - Vector3(0, r1 * 0.9, 0))
	q2.append(r1 * 0.8)
	q2.append(0.0)
	return P.loft(p2, q2, q2, 16)


static func mannequin(d: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var n := MannequinNode.new()
	n.watch = bool(d.get("watch", false))
	var tones := [Color(0.84, 0.83, 0.8), Color(0.84, 0.83, 0.8), Color(0.8, 0.74, 0.64), Color(0.56, 0.56, 0.55)]
	var tone: Color = tones[rng.randi_range(0, tones.size() - 1)]
	var fg := P.mc(tone, "plaster", 0.12, {"gloss": 64.0, "spec": 0.26, "albedo_cap": 0.6})
	var seam := P.mc(Color(0.12, 0.12, 0.12), "metal", 0.0)
	var body := Node3D.new()
	n.add_child(body)
	body.rotation.y = rng.randf_range(-0.15, 0.15)
	P.mesh_node(body, _mq_mesh("torso"), fg)
	# шов талии — эллипс: тор, сжатый по z
	var waist := TorusMesh.new()
	waist.inner_radius = 0.1225
	waist.outer_radius = 0.1255
	waist.rings = 32
	waist.ring_segments = 4
	P.mesh_node(body, waist, seam, Vector3(0, 1.08, 0.006), Vector3.ZERO, Vector3(1.0, 1.0, 0.71))
	# голова-яйцо, чуть наклонена
	var neck := Node3D.new()
	body.add_child(neck)
	neck.position = Vector3(0, 1.55, 0.008)
	n.head = neck
	P.mesh_node(neck, _mq_mesh("head"), fg, Vector3(0, 0.125, 0.012), Vector3(rng.randf_range(-0.12, 0.05), 0, rng.randf_range(-0.08, 0.08)))
	n.head_rest = rng.randf_range(-0.25, 0.25)
	n._yaw = n.head_rest
	neck.rotation.y = n.head_rest
	# руки: плечо — шарнир, предплечье, кисть; три позы
	var pose := rng.randi_range(0, 2)
	for sd in [-1.0, 1.0]:
		var sh := Node3D.new()
		body.add_child(sh)
		sh.position = Vector3(sd * 0.168, 1.4, -0.008)
		sh.rotation = Vector3(rng.randf_range(-0.12, 0.08), 0, sd * rng.randf_range(0.08, 0.16))
		P.mesh_node(sh, _mq_mesh("uparm"), fg)
		var cut := TorusMesh.new()
		cut.inner_radius = 0.0435
		cut.outer_radius = 0.0465
		cut.rings = 20
		cut.ring_segments = 4
		P.mesh_node(sh, cut, seam, Vector3(0, -0.07, 0))
		var el := Node3D.new()
		sh.add_child(el)
		el.position = Vector3(0, -0.3, 0)
		el.rotation.x = -rng.randf_range(0.08, 0.25)
		P.mesh_node(el, _mq_mesh("forearm"), fg)
		var wr := Node3D.new()
		el.add_child(wr)
		wr.position = Vector3(0, -0.255, 0)
		wr.rotation = Vector3(-0.1, sd * -0.35, 0)
		var cut2 := TorusMesh.new()
		cut2.inner_radius = 0.0225
		cut2.outer_radius = 0.0255
		cut2.rings = 16
		cut2.ring_segments = 4
		P.mesh_node(wr, cut2, seam, Vector3(0, 0.004, 0))
		P.mesh_node(wr, _mq_mesh("hand"), fg)
		P.mesh_node(wr, P.horn(Vector3(sd * -0.012, -0.03, 0.02), Vector3(sd * -0.02, -0.085, 0.045), 0.012, Vector3(0, 0, 0.01), 8, 5), fg)
		if pose == 1 and sd > 0.0:
			# рука на бедре
			sh.rotation = Vector3(-0.1, 0, sd * 0.55)
			el.rotation = Vector3(-1.4, 0, -sd * 0.9)
		elif pose == 2 and sd < 0.0:
			# рука чуть вперёд, кисть повёрнута ладонью вниз
			sh.rotation = Vector3(-0.45, 0, sd * 0.1)
			el.rotation.x = -0.35
	# ноги: бедро, голень, стопа; вес на одной ноге
	var lean := rng.randf_range(0.03, 0.08) * (1.0 if rng.randf() < 0.5 else -1.0)
	for sd2 in [-1.0, 1.0]:
		var hp := Node3D.new()
		body.add_child(hp)
		hp.position = Vector3(sd2 * 0.085, 0.86, -0.005)
		hp.rotation = Vector3(0, 0, sd2 * 0.02 + lean * 0.5)
		P.mesh_node(hp, _mq_mesh("thigh"), fg)
		var kn := Node3D.new()
		hp.add_child(kn)
		kn.position = Vector3(0, -0.44, 0)
		kn.rotation.x = 0.02
		P.mesh_node(kn, _mq_mesh("calf"), fg)
		var an := Node3D.new()
		kn.add_child(an)
		an.position = Vector3(0, -0.425, 0.0)
		an.rotation.y = sd2 * 0.12
		P.mesh_node(an, _mq_mesh("foot"), fg, Vector3(0, -0.028, -0.01))
	body.position.y = 0.075
	# подставка: стеклянный диск на ножках, хромированный штырь в икру
	var chrome := P.mc(Color(0.6, 0.6, 0.58), "metal", 0.2, {"gloss": 120.0, "spec": 0.55})
	var glass_d := P.mc(Color(0.18, 0.2, 0.2), "metal", 0.0, {"gloss": 140.0, "spec": 0.5})
	P.cyl(n, 0.24, 0.24, 0.015, Vector3(0, 0.02, 0), glass_d, Vector3.ZERO, 28)
	P.cyl(n, 0.035, 0.04, 0.012, Vector3(0, 0.006, 0), chrome, Vector3.ZERO, 12)
	P.rod(n, Vector3(0.0, 0.02, 0.0), Vector3(0.085, 0.3, -0.03), 0.008, chrome, 8)
	P.blob(n, Vector2(0.75, 0.75), Vector3.ZERO, 0.45)
	P.collider(n, Vector3(0.5, 1.8, 0.4), Vector3(0, 0.9, 0))
	return n


class MannequinNode extends Node3D:
	## «watch»: голова медленно поворачивается к камере, только пока на манекен не смотрят
	var watch := false
	var head: Node3D = null
	var head_rest := 0.0
	var _yaw := 0.0

	func _process(dt: float) -> void:
		if not watch or head == null:
			return
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var to_me := global_position + Vector3(0, 1.6, 0) - cam.global_position
		var seen := (-cam.global_basis.z).dot(to_me.normalized()) > 0.55
		if seen:
			return
		var loc := to_local(cam.global_position)
		var want := clampf(atan2(loc.x, loc.z), -1.25, 1.25) if loc.length() < 12.0 else head_rest
		_yaw = move_toward(_yaw, want, dt * 0.6)
		head.rotation.y = _yaw


## Холодильник: белый шкаф, гудит
static func fridge() -> Node3D:
	var n := Node3D.new()
	# эмаль цвета слоновой кости, щель между дверцами, ручки, решётка внизу
	var w := P.m_plastic(Color(0.92, 0.9, 0.84))
	P.box(n, Vector3(0.7, 1.75, 0.65), Vector3(0, 0.875, 0), w)
	P.box(n, Vector3(0.02, 0.5, 0.03), Vector3(0.28, 1.0, 0.34), P.m_metal())
	P.box(n, Vector3(0.02, 0.22, 0.03), Vector3(0.28, 1.48, 0.34), P.m_metal())
	P.box(n, Vector3(0.68, 0.012, 0.01), Vector3(0, 1.32, 0.33), P.m_black())
	P.box(n, Vector3(0.6, 0.08, 0.01), Vector3(0, 0.06, 0.33), P.m_black())
	P.blob(n, Vector2(0.95, 0.9), Vector3.ZERO, 0.6)
	P.collider(n, Vector3(0.7, 1.75, 0.65), Vector3(0, 0.875, 0))
	var se := P.SoundEmitter.new()
	se.snd = "fridge_hum"
	se.every = 0.0
	se.vol = -14.0
	se.max_dist = 10.0
	se.position = Vector3(0, 1.0, 0)
	n.add_child(se)
	return n


## Большой вентилятор в стене: рама, решётка, лопасти крутятся
static func fan_big() -> Node3D:
	var n := Node3D.new()
	var dark := P.mc(Color(0.18, 0.18, 0.19), "metal", 0.5)
	var s := 1.0
	P.box(n, Vector3(2.1, 0.12, 0.2), Vector3(0, s, 0.1), dark)
	P.box(n, Vector3(2.1, 0.12, 0.2), Vector3(0, -s, 0.1), dark)
	P.box(n, Vector3(0.12, 2.1, 0.2), Vector3(s, 0, 0.1), dark)
	P.box(n, Vector3(0.12, 2.1, 0.2), Vector3(-s, 0, 0.1), dark)
	P.quad(n, Vector2(1.9, 1.9), Vector3(0, 0, 0.02), P.m_black())
	var sp := Spinner.new()
	sp.axis = Vector3(0, 0, 1)
	sp.speed = 4.0
	sp.position = Vector3(0, 0, 0.12)
	n.add_child(sp)
	var bl := P.mc(Color(0.5, 0.5, 0.48), "metal", 0.4)
	for k in 5:
		var a := k * TAU / 5.0
		P.box(sp, Vector3(0.22, 0.85, 0.02), Vector3(sin(a) * 0.45, cos(a) * 0.45, 0), bl, Vector3(0.35, 0, -a))
	P.sph(sp, 0.12, Vector3.ZERO, dark)
	for k in 9:
		P.rod(n, Vector3(-0.95, -0.9 + k * 0.225, 0.2), Vector3(0.95, -0.9 + k * 0.225, 0.2), 0.008, dark, 4)
	var se := P.SoundEmitter.new()
	se.snd = "fan_big"
	se.every = 0.0
	se.vol = -6.0
	se.max_dist = 20.0
	n.add_child(se)
	return n


class Shaker extends Node3D:
	var t := 0.0

	func _process(dt: float) -> void:
		t += dt
		position = Vector3(sin(t * 37.0) * 0.004, absf(sin(t * 23.0)) * 0.003, cos(t * 29.0) * 0.004)


## Стиральная машина; одна из ряда крутится и трясётся
static func washer(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var body: Node3D = n
	if bool(d.get("running", false)):
		var sh := Shaker.new()
		n.add_child(sh)
		body = sh
		var se := P.SoundEmitter.new()
		se.snd = "washer"
		se.every = 0.0
		se.vol = -8.0
		se.max_dist = 14.0
		se.position = Vector3(0, 0.5, 0)
		n.add_child(se)
	var white := P.m_plastic(Color(0.9, 0.9, 0.87))
	P.box(body, Vector3(0.6, 0.85, 0.6), Vector3(0, 0.425, 0), white)
	P.cyl(body, 0.23, 0.23, 0.02, Vector3(0, 0.45, 0.3), P.m_metal(), Vector3(PI * 0.5, 0, 0), 18)
	# стекло люка: тёмное, с бликом ламп
	P.cyl(body, 0.19, 0.19, 0.03, Vector3(0, 0.45, 0.31), P.mc(Color(0.06, 0.07, 0.08), "metal", 0.1, {"gloss": 120.0, "spec": 0.5}), Vector3(PI * 0.5, 0, 0), 18)
	P.box(body, Vector3(0.56, 0.12, 0.02), Vector3(0, 0.76, 0.3), P.mc(Color(0.6, 0.6, 0.58), "metal", 0.3))
	for k in 3:
		P.cyl(body, 0.022, 0.022, 0.02, Vector3(0.12 + k * 0.07, 0.76, 0.315), P.m_black(), Vector3(PI * 0.5, 0, 0), 10)
	P.box(body, Vector3(0.14, 0.05, 0.005), Vector3(-0.15, 0.76, 0.311), P.m_black())
	P.blob(n, Vector2(0.85, 0.85), Vector3.ZERO, 0.55)
	P.collider(n, Vector3(0.6, 0.85, 0.6), Vector3(0, 0.425, 0))
	return n


## Постамент с экспонатом
static func pedestal(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var id := String(d.get("id", "marble_bust_01"))
	# крашеный МДФ: матовый светло-серый, ширина — по экспонату (чемодан не свисает)
	var w := 0.5
	if Models.has(id):
		var bb := Models.aabb(id)
		w = clampf(maxf(bb.size.x, bb.size.z) + 0.12, 0.5, 0.85)
	var mdf := P.mc(Color(0.5, 0.49, 0.46), "plaster", 0.55, {"gloss": 18.0, "spec": 0.05, "albedo_cap": 0.5})
	P.box(n, Vector3(w, 1.0, w), Vector3(0, 0.5, 0), mdf)
	P.box(n, Vector3(w + 0.02, 0.06, w + 0.02), Vector3(0, 0.03, 0), P.mc(Color(0.2, 0.2, 0.2), "metal", 0.3))
	P.blob(n, Vector2(w + 0.35, w + 0.35), Vector3.ZERO, 0.5)
	P.collider(n, Vector3(w, 1.0, w), Vector3(0, 0.5, 0))
	P.model(n, id, Vector3(0, 1.0, 0), PI, 1.0, false)
	return n


## Столбики с бархатной верёвкой (квадрат вокруг экспоната)
static func ropes(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var s := float(d.get("len", 1.6))
	# латунь: тёплый блик; бархатный канат — тёмно-бордовый, провисает между столбиками
	var brass := P.mc(Color(0.48, 0.36, 0.15), "metal", 0.6, {"gloss": 70.0, "spec": 0.45})
	var red := P.mc(Color(0.3, 0.035, 0.045), "fabric", 0.6)
	var pts := [Vector3(0, 0, 0), Vector3(s, 0, 0), Vector3(s, 0, -s), Vector3(0, 0, -s)]
	for k in 4:
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[(k + 1) % 4]
		P.cyl(n, 0.025, 0.025, 0.9, a + Vector3(0, 0.45, 0), brass, Vector3.ZERO, 8)
		P.cyl(n, 0.1, 0.1, 0.03, a + Vector3(0, 0.015, 0), brass, Vector3.ZERO, 12)
		P.blob(n, Vector2(0.32, 0.32), a, 0.35)
		P.sph(n, 0.035, a + Vector3(0, 0.92, 0), brass, Vector3.ONE, 8)
		if k != 0:
			var m := (a + b) * 0.5 + Vector3(0, 0.72, 0)
			P.rod(n, a + Vector3(0, 0.86, 0), m, 0.016, red, 6)
			P.rod(n, m, b + Vector3(0, 0.86, 0), 0.016, red, 6)
	return n


## Дождь с потолка над комнатой
static func rain(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var sz: Vector2 = d.get("size", Vector2(6, 6))
	var ch := float(d.get("ceil", 3.0))
	var gp := GPUParticles3D.new()
	gp.amount = 700
	gp.lifetime = 0.55
	gp.position = Vector3(0, ch - 0.05, 0)
	gp.visibility_aabb = AABB(Vector3(-sz.x, -ch - 1.0, -sz.y), Vector3(sz.x * 2.0, ch + 2.0, sz.y * 2.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(sz.x * 0.5, 0.05, sz.y * 0.5)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 2.0
	pm.initial_velocity_min = 5.0
	pm.initial_velocity_max = 6.5
	pm.gravity = Vector3(0, -9.8, 0)
	gp.process_material = pm
	# черта капли: освещена лампами в точке капли, в тумане тает (fx_rain.gdshader)
	var q := QuadMesh.new()
	q.size = Vector2(0.024, 0.28)
	var qm := ShaderMaterial.new()
	qm.shader = RAIN_SHADER
	q.material = qm
	gp.draw_pass_1 = q
	n.add_child(gp)
	var se := P.SoundEmitter.new()
	se.snd = "rain_room"
	se.every = 0.0
	se.vol = -4.0
	se.max_dist = 22.0
	se.position = Vector3(0, 1.0, 0)
	n.add_child(se)
	return n


## Разводы протечки на потолке: бледные жёлто-бурые «приливы» — несколько неровных колец с тёмной кромкой
## и чуть подкрашенной серединой (prop_tide_*). Над сырыми местами — заметнее, но не тёмная клякса
static func ceil_stain(d: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var s := float(d.get("s", 1.2))
	var y := float(d.get("y", 3.2)) - 0.006
	var dark := bool(d.get("dark", false))
	var v := rng.randi_range(0, 2)
	var tname := "prop_tide_%s" % "abc"[v]
	if not Mats.has_tex(tname):
		var m1 := P.decal_mat("ceil_stain_a", {"radial": 1.0, "tint": Color(0.45, 0.29, 0.09, 0.4)})
		P.quad(n, Vector2(s, s), Vector3(0, y, 0), m1, Vector3(PI * 0.5, 0, 0)).set_instance_shader_parameter("seed", rng.randf() * 10.0)
		return n
	var m := P.decal_mat("tide_%s_%d" % [tname, int(dark)], {"tex": tname, "tex_color": 1.0, "tint": Color(1.0, 0.97, 0.93, 0.72 if dark else 0.5)})
	var q := P.quad(n, Vector2(s, s * rng.randf_range(0.75, 1.2)), Vector3(0, y, 0), m, Vector3(PI * 0.5, 0, 0))
	q.rotation.y = rng.randf() * TAU
	return n


## Потёк по обоям от потолка вниз
static func streak(d: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var length := float(d.get("len", 1.4))
	var top := float(d.get("y", 3.2))
	var m := P.decal_mat("wall_streak", {"stripes": 1.0, "tint": Color(0.32, 0.22, 0.08, 0.5)})
	var q := P.quad(n, Vector2(rng.randf_range(0.25, 0.5), length), Vector3(0, top - length * 0.5, 0.013), m)
	q.set_instance_shader_parameter("seed", rng.randf() * 10.0)
	return n
