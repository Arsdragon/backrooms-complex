extends RefCounted
## Начинка «странных комнат»: двери в стену, телевизоры, телефон, автоматы, жилой угол, класс, магазин, трубы…

const P := preload("res://src/world/props.gd")
const TV_SHADER := preload("res://src/shaders/tv_screen.gdshader")

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
		"residence": return residence(cx, rng, layer)
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
	return null


# ------------------------------------------------------------ общее

static func model(d: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var sc: Variant = d.get("s", 1.0)
	var m := P.model(n, String(d.get("id", "cardboard_box_01")), Vector3(0, float(d.get("y", 0.0)), 0), 0.0, sc, bool(d.get("collide", true)))
	if m == null:
		return null
	if d.has("tilt"):
		m.rotation += d.tilt
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
		root.rotation.x = -PI * 0.5
		root.position = Vector3(0, float(d.get("ceil", 2.7)) - 0.02, 0.0)
	var frame := P.m_plastic(Color(0.86, 0.84, 0.78))
	var leafc := Color(0.55, 0.42, 0.3) if rng_pick(d) < 0.5 else Color(0.72, 0.7, 0.64)
	var leafm := Mats.col(leafc, "wood", 0.7)
	P.box(root, Vector3(0.08, 2.18, 0.08), Vector3(-0.5, 1.09, 0.03), frame)
	P.box(root, Vector3(0.08, 2.18, 0.08), Vector3(0.5, 1.09, 0.03), frame)
	P.box(root, Vector3(1.08, 0.08, 0.08), Vector3(0, 2.14, 0.03), frame)
	# за дверью — та же стена, только темнее (проёма нет)
	P.box(root, Vector3(0.92, 2.1, 0.01), Vector3(0, 1.05, 0.005), Mats.col(Color(0.35, 0.32, 0.2), "wall_yellow", 0.8))
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
	P.box(n, Vector3(0.42, 0.18, 0.08), Vector3(0, 0, 0.04), P.m_plastic(Color(0.9, 0.9, 0.86)))
	P.box(n, Vector3(0.38, 0.14, 0.01), Vector3(0, 0, 0.085), P.m_emit(Color(0.2, 0.9, 0.35), 1.6))
	var lb := P.label(Loc.t("sign.exit"), P.font_sign(), 0.0016, Color(0.95, 1.0, 0.95))
	lb.position = Vector3(0, 0, 0.092)
	lb.set_meta("ink", Color(4, 4, 4))
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
		P.box(t, Vector3(0.6, 0.5, 0.55), Vector3(0, 0.25, 0), Mats.col(Color(0.2, 0.19, 0.18), "metal", 0.3))
	var q := P.quad(t, Vector2(0.4, 0.3), Vector3(0, 0.29, 0.166), tv_mat(cx, ch))
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return t


static func tv_on(cx: Node3D, d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var ch := String(d.get("ch", "static"))
	P.box(n, Vector3(0.7, 0.5, 0.5), Vector3(0, 0.25, 0), Mats.col(Color(0.35, 0.25, 0.18), "wood", 0.7))
	_crt(n, cx, ch, Vector3(0, 0.5, 0))
	var se := P.SoundEmitter.new()
	se.snd = {"news": "tv_news", "async_ad": "tv_jingle", "home": "tv_home", "explorers": "tv_static"}.get(ch, "tv_static")
	se.every = 0.0
	se.vol = -15.0
	se.max_dist = 16.0
	se.position = Vector3(0, 0.8, 0)
	n.add_child(se)
	P.collider(n, Vector3(0.7, 0.95, 0.55), Vector3(0, 0.47, 0))
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
	return n


# ------------------------------------------------------------ звонящий телефон

static func phone_ring(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	P._desk(n)
	var ph := Node3D.new()
	n.add_child(ph)
	ph.position = Vector3(0.1, 0.76, 0.05)
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

static func vending(rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var bodyc: Color = [Color(0.65, 0.12, 0.1), Color(0.15, 0.25, 0.55), Color(0.85, 0.82, 0.75)][rng.randi_range(0, 2)]
	P.box(n, Vector3(0.95, 1.85, 0.8), Vector3(0, 0.925, 0), Mats.col(bodyc, "metal", 0.3))
	P.box(n, Vector3(0.62, 1.3, 0.02), Vector3(-0.1, 1.05, 0.405), Mats.col(Color(0.7, 0.75, 0.8), "metal", 0.0, {"emit": 0.9, "emit_color": Vector3(0.85, 0.9, 1.0)}))
	for r in 5:
		for c in 4:
			var pc := Color.from_hsv(rng.randf(), 0.6, 0.8)
			P.box(n, Vector3(0.1, 0.16, 0.05), Vector3(-0.33 + c * 0.155, 0.55 + r * 0.24, 0.39), Mats.col(pc, "metal", 0.0, {"emit": 0.4, "emit_color": Vector3(pc.r, pc.g, pc.b)}))
	P.box(n, Vector3(0.2, 0.5, 0.02), Vector3(0.33, 1.1, 0.405), P.m_black())
	P.box(n, Vector3(0.55, 0.15, 0.04), Vector3(-0.1, 0.22, 0.41), P.m_black())
	P.collider(n, Vector3(0.95, 1.85, 0.8), Vector3(0, 0.925, 0))
	var se := P.SoundEmitter.new()
	se.snd = "vending_hum"
	se.every = 0.0
	se.vol = -12.0
	se.max_dist = 14.0
	se.position = Vector3(0, 1.0, 0)
	n.add_child(se)
	return n


static func speaker(rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var h := rng.randf_range(0.6, 1.1)
	P.box(n, Vector3(0.45, h, 0.4), Vector3(0, h * 0.5, 0), Mats.col(Color(0.12, 0.1, 0.09), "wood", 0.4))
	P.cyl(n, 0.15, 0.15, 0.02, Vector3(0, h * 0.62, 0.205), Mats.col(Color(0.05, 0.05, 0.05), "fabric", 0.8), Vector3(PI * 0.5, 0, 0), 14)
	P.cyl(n, 0.07, 0.07, 0.02, Vector3(0, h * 0.25, 0.205), Mats.col(Color(0.05, 0.05, 0.05), "fabric", 0.8), Vector3(PI * 0.5, 0, 0), 10)
	var se := P.SoundEmitter.new()
	se.snd = ["copy_whisper", "speaker_hiss", "tv_news"][rng.randi_range(0, 2)]
	se.every = 0.0 if se.snd != "copy_whisper" else 6.0
	se.vol = -12.0
	se.max_dist = 12.0
	se.position = Vector3(0, h * 0.6, 0.2)
	n.add_child(se)
	return n


# ------------------------------------------------------------ жилой угол пропавшего

static func residence(cx: Node3D, rng: RandomNumberGenerator, layer: int) -> Node3D:
	var n := Node3D.new()
	# матрас, подушка, одеяло
	P.box(n, Vector3(0.95, 0.16, 1.95), Vector3(0, 0.08, 0), Mats.col(Color(0.72, 0.68, 0.6), "fabric", 0.8))
	P.box(n, Vector3(0.6, 0.1, 0.35), Vector3(0, 0.2, -0.75), Mats.col(Color(0.85, 0.83, 0.78), "fabric", 0.7), Vector3(0.1, 0.1, 0))
	P.box(n, Vector3(1.0, 0.05, 1.1), Vector3(0.05, 0.19, 0.35), Mats.col(Color(0.35, 0.18, 0.15), "fabric", 0.8), Vector3(0.05, 0.25, -0.05))
	var items := [["can_rusted", Vector3(0.8, 0, 0.6)], ["can_rusted", Vector3(0.92, 0, 0.5)], ["russian_food_cans_01", Vector3(0.75, 0, 0.9)],
		["plastic_bottle_gallon", Vector3(-0.75, 0, -0.6)], ["plastic_bottle_gallon", Vector3(-0.9, 0, -0.4)], ["portable_cassette_player", Vector3(0.6, 0.0, -0.8)],
		["vintage_suitcase", Vector3(-0.2, 0, 1.4)], ["long_life_food", Vector3(0.95, 0, 1.1)], ["alarm_clock_01", Vector3(0.7, 0, -1.0)]]
	for it in items:
		var a: Array = it
		P.model(n, String(a[0]), a[1], rng.randf() * TAU, 1.0, false)
	P.model(n, "pull_chain_light_socket", Vector3(0, 2.55, 0), 0.0, 1.0, false)
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
	var tape := Mats.prop("hazard_tape", {"tex": "hazard", "tex_mix": 1.0, "uv_scale": Vector2(6, 1)})
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
		P.box(n, Vector3(1.4, 1.0, 0.04), Vector3(0, 1.3, 0), Mats.col(Color(0.12, 0.2, 0.15), "noise", 0.3))
	var lb := P.label(Loc.t(String(d.get("key", "class.board1"))), P.font_hand(), 0.0016, Color(0.92, 0.92, 0.88))
	lb.position = Vector3(0, 1.22, 0.2)
	lb.width = 680.0
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.add_child(lb)
	return n


static func store_sign(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var y := float(d.get("y", 2.15))
	var bg := Color(0.85, 0.1, 0.08) if int(d.get("v", 0)) % 2 == 0 else Color(0.95, 0.8, 0.1)
	P.box(n, Vector3(1.8, 0.45, 0.03), Vector3(0, y, 0), Mats.col(bg, "metal", 0.15))
	P.rod(n, Vector3(-0.8, y + 0.22, 0), Vector3(-0.8, 2.7, 0), 0.006, P.m_metal(), 3)
	P.rod(n, Vector3(0.8, y + 0.22, 0), Vector3(0.8, 2.7, 0), 0.006, P.m_metal(), 3)
	for side in [1.0, -1.0]:
		var lb := P.label(Loc.t(String(d.get("key", "store.s1"))), P.font_sign(), 0.0034, Color(1, 1, 1) if bg.g < 0.5 else Color(0.1, 0.08, 0.05))
		lb.position = Vector3(0, y, 0.018 * side)
		if side < 0:
			lb.rotation.y = PI
		n.add_child(lb)
	return n


static func price(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	P.box(n, Vector3(0.18, 0.12, 0.004), Vector3(0, 0, 0), Mats.col(Color(0.95, 0.9, 0.3), "paper", 0.6))
	var lb := P.label(String(d.get("text", "$0")), P.font_sign(), 0.0012, Color(0.6, 0.05, 0.05))
	lb.position = Vector3(0, 0, 0.004)
	n.add_child(lb)
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
		var m := Mats.col(cols[k % 3], "metal", 0.6, {"wet": 0.3})
		P.rod(n, Vector3(-length * 0.5, y - k * 0.06, off), Vector3(length * 0.5, y - k * 0.06, off), r, m, 8)
		if rng.randf() < 0.5:
			P.cyl(n, r * 1.6, r * 1.6, 0.06, Vector3(rng.randf_range(-length * 0.4, length * 0.4), y - k * 0.06, off), P.m_iron(), Vector3(0, 0, PI * 0.5), 8)
	for b in int(length / 1.6):
		P.box(n, Vector3(0.04, 0.4, 1.1), Vector3(-length * 0.5 + 0.8 + b * 1.6, y + 0.15, -0.1), P.m_iron())
	if rng.randf() < 0.4:
		P.model(n, "modular_industrial_pipes_01", Vector3(0, 0.0, 0.6), 0.0, 1.0, false)
	var se := P.SoundEmitter.new()
	se.snd = "pipe_knock"
	se.every = 18.0
	se.vol = -12.0
	se.position = Vector3(0, y, 0)
	n.add_child(se)
	return n


static func cubicle(cx: Node3D, d: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var pm := Mats.col(Color(0.5, 0.5, 0.55), "fabric", 0.8)
	var fr := Mats.col(Color(0.75, 0.74, 0.7), "metal", 0.3)
	# три стенки 1.4 м
	P.box(n, Vector3(1.9, 1.4, 0.06), Vector3(0, 0.7, -0.95), pm)
	P.box(n, Vector3(0.06, 1.4, 1.9), Vector3(-0.95, 0.7, 0), pm)
	P.box(n, Vector3(0.06, 1.4, 1.2), Vector3(0.95, 0.7, -0.35), pm)
	P.box(n, Vector3(1.92, 0.04, 0.08), Vector3(0, 1.42, -0.95), fr)
	P.collider(n, Vector3(1.9, 1.4, 0.08), Vector3(0, 0.7, -0.95))
	P.collider(n, Vector3(0.08, 1.4, 1.9), Vector3(-0.95, 0.7, 0))
	P.collider(n, Vector3(0.08, 1.4, 1.2), Vector3(0.95, 0.7, -0.35))
	var desk := Node3D.new()
	n.add_child(desk)
	desk.position = Vector3(0, 0, -0.55)
	P._desk(desk)
	desk.scale = Vector3(0.85, 1.0, 0.8)
	# монитор: бежевый кинескоп, иногда включён
	var mon := Node3D.new()
	n.add_child(mon)
	mon.position = Vector3(-0.1, 0.77, -0.65)
	P.box(mon, Vector3(0.38, 0.32, 0.36), Vector3(0, 0.18, 0), Mats.col(Color(0.82, 0.79, 0.7), "metal", 0.3))
	var on := rng.randf() < 0.35
	P.box(mon, Vector3(0.3, 0.22, 0.01), Vector3(0, 0.2, 0.185), Mats.col(Color(0.15, 0.4, 0.2), "noise", 1.0, {"emit": 0.6 if on else 0.0, "emit_color": Vector3(0.2, 0.9, 0.4)}))
	P.box(mon, Vector3(0.42, 0.03, 0.15), Vector3(0, 0.0, 0.3), Mats.col(Color(0.82, 0.79, 0.7), "metal", 0.3))
	var ch := Node3D.new()
	n.add_child(ch)
	ch.position = Vector3(rng.randf_range(-0.2, 0.3), 0, 0.1)
	ch.rotation.y = PI + rng.randf_range(-0.6, 0.6)
	if rng.randf() < 0.2:
		ch.rotation.z = PI * 0.5
		ch.position.y = 0.25
	P._ochair(ch)
	if rng.randf() < 0.5:
		P.model(n, "office_notepads", Vector3(0.35, 0.77, -0.55), rng.randf_range(-0.3, 0.3), 0.4, false)
	if rng.randf() < 0.3:
		var ph := Node3D.new()
		n.add_child(ph)
		ph.position = Vector3(0.45, 0.77, -0.7)
		P._phone(ph)
	return n


static func stairs(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var up := bool(d.get("up", true))
	var wd := Mats.col(Color(0.5, 0.4, 0.3), "wood", 0.8)
	var steps := 12
	for k in steps:
		var y := (k + 1) * 0.2 if up else -(k + 1) * 0.2
		P.box(n, Vector3(1.1, 0.06 if not up else 0.2, 0.28), Vector3(0, y - (0.1 if up else 0.0), -k * 0.27), wd)
	P.rod(n, Vector3(0.55, 1.0, 0.2), Vector3(0.55, 1.0 + (2.4 if up else -2.4), -3.0), 0.025, P.m_metal(), 6)
	if up:
		P.collider(n, Vector3(1.1, 0.2, 3.6), Vector3(0, 1.2, -1.5), 1, Vector3(-0.64, 0, 0))
	return n


static func panel(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var s: Vector3 = d.get("size", Vector3(0.3, 2.7, 2.4))
	P.box(n, s, Vector3(0, s.y * 0.5, 0), P.m_wall())
	P.box(n, Vector3(s.x + 0.02, 0.1, s.z), Vector3(0, 0.05, 0), Mats.col(Color(0.8, 0.77, 0.67), "baseboard", 0.8))
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
	var under := Mats.col(Color(0.55, 0.48, 0.32), "wall_under", 0.9)
	P.box(n, Vector3(0.6, 0.9, 0.004), Vector3(0, 0, 0.002), under)
	for k in rng.randi_range(2, 4):
		var strip := Node3D.new()
		n.add_child(strip)
		strip.position = Vector3(-0.25 + k * 0.16, 0.45, 0.01)
		strip.rotation.x = rng.randf_range(0.2, 0.7)
		P.box(strip, Vector3(0.15, rng.randf_range(0.4, 0.8), 0.004), Vector3(0, -0.3, 0), P.m_wall())
	return n


static func tile_fallen(rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var tm := Mats.col(Color(0.86, 0.84, 0.78), "ceiling_tile", 0.8)
	for k in rng.randi_range(1, 3):
		P.box(n, Vector3(0.6, 0.015, 1.2) * rng.randf_range(0.4, 1.0), Vector3(rng.randf_range(-0.5, 0.5), 0.01 + k * 0.012, rng.randf_range(-0.5, 0.5)), tm,
			Vector3(rng.randf_range(-0.08, 0.08), rng.randf() * TAU, rng.randf_range(-0.08, 0.08)))
	for k2 in 8:
		P.box(n, Vector3(0.05, 0.03, 0.04), Vector3(rng.randf_range(-0.8, 0.8), 0.015, rng.randf_range(-0.8, 0.8)), tm)
	return n


static func survey(cx: Node3D, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	P.model(n, "ladder_sectioned_01", Vector3(0, 0, 0), 0.3, 1.0, true)
	# брезент, на нём снятая плита и светильник
	P.box(n, Vector3(1.8, 0.01, 1.4), Vector3(1.4, 0.005, 0.4), Mats.col(Color(0.2, 0.3, 0.5), "fabric", 0.6))
	P.box(n, Vector3(0.6, 0.016, 1.2), Vector3(1.1, 0.02, 0.4), Mats.col(Color(0.86, 0.84, 0.78), "ceiling_tile", 0.8))
	P.box(n, Vector3(0.62, 0.1, 1.22), Vector3(1.8, 0.06, 0.4), Mats.col(Color(0.8, 0.8, 0.78), "metal", 0.4))
	P.box(n, Vector3(0.56, 0.01, 1.16), Vector3(1.8, 0.115, 0.4), Mats.col(Color(0.9, 0.9, 0.88), "fixture", 1.0))
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
		for c in cols:
			if rng.randf() < 0.06:
				continue
			var ch := Node3D.new()
			n.add_child(ch)
			ch.position = Vector3((c - (cols - 1) * 0.5) * 0.85 + rng.randf_range(-0.04, 0.04), 0, (r - (rows - 1) * 0.5) * 0.9)
			ch.rotation.y = rng.randf_range(-0.05, 0.05)
			if rng.randf() < 0.03:
				ch.rotation = Vector3(0, rng.randf() * TAU, PI * 0.5)
				ch.position.y = 0.3
			P._chair(ch)
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
	var m := Mats.col(Color(0.62, 0.6, 0.52), "metal", 0.5)
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

## Сотрудник Async в жёлтом костюме химзащиты: сидит у стены, уронив голову, или лежит ничком. Рядом — его вещи
static func hazmat(cx: Node3D, d: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var h := Human.make("explorer", int(d.get("seed", rng.randi())), true)
	n.add_child(h)
	h.react = false
	# костюм — ровный жёлтый прорезинённый, текстуры пожарного чуть проступают
	h.tune({"pale": 0.0, "smear": 0.0, "tex_mix": 0.2, "color": Vector3(0.95, 0.7, 0.1), "wet": 0.25})
	var pz := String(d.get("pose", ""))
	var lying := pz == "lie" or (pz == "" and rng.randf() < 0.4)
	if lying:
		h.pose("stand")
		h._r("sh_l", -0.3, 0, 0.5)
		h._r("sh_r", 0.4, 0, -0.3)
		h._r("hip_r", -0.3)
		h._r("kn_r", 0.6)
		h.rotation = Vector3(-PI * 0.5, rng.randf() * TAU, 0)
		h.position = Vector3(0, 0.11, 0)
	else:
		# сидит на полу, спиной к стене; голова завалилась набок, руки опущены
		h.pose("sit_ground")
		h._r("spine", -0.18)
		h._r("neck", 0.3, 0.25, 0.55)
		h._r("sh_l", 0.25, 0, 0.3)
		h._r("sh_r", 0.25, 0, -0.3)
		h._r("el_l", -0.05)
		h._r("el_r", -0.05)
		h.position = Vector3(0, 0, -0.18)
	# капюшон, тёмное стекло маски, фильтр
	var rub := Mats.col(Color(0.95, 0.72, 0.12), "fabric", 0.35, {"wet": 0.3})
	var hf := h.head_frame()
	if hf != null:
		P.sph(hf, 0.15, Vector3(0, 0.07, -0.01), rub, Vector3(1.0, 1.18, 1.08), 12)
		# широкое тёмное стекло в чёрной рамке и два фильтра по бокам
		P.box(hf, Vector3(0.21, 0.13, 0.03), Vector3(0, 0.075, 0.14), P.m_black(), Vector3(-0.12, 0, 0))
		P.box(hf, Vector3(0.18, 0.1, 0.01), Vector3(0, 0.076, 0.157), Mats.col(Color(0.12, 0.16, 0.16), "metal", 0.05, {"wet": 1.0}), Vector3(-0.12, 0, 0))
		for sx in [-0.075, 0.075]:
			P.cyl(hf, 0.04, 0.04, 0.05, Vector3(sx, -0.02, 0.14), P.m_black(), Vector3(PI * 0.5, sx * 4.0, 0), 10)
	# рядом — кейс, фонарь, иногда планшет с запиской
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	P.box(n, Vector3(0.45, 0.14, 0.32), Vector3(0.65 * side, 0.07, 0.25), Mats.col(Color(0.2, 0.22, 0.2), "metal", 0.4), Vector3(0, rng.randf() * 0.6, 0))
	P.cyl(n, 0.025, 0.025, 0.22, Vector3(-0.5 * side, 0.03, 0.45), P.m_black(), Vector3(0, rng.randf() * TAU, PI * 0.5), 8)
	if bool(d.get("note", false)):
		var note := P.note(cx, {"key": String(d.get("key", "note.a_hz1")), "p": Vector3.ZERO, "clip": true})
		n.add_child(note)
		note.position = Vector3(0.3 * side, 0.0, 0.6)
	var st := P.stain({"wet": true, "s": 1.6}, rng)
	n.add_child(st)
	return n


## Аккуратно сложенная одежда и ботинки — человека нет
static func clothes(rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var cols := [Color(0.25, 0.3, 0.45), Color(0.6, 0.55, 0.45), Color(0.15, 0.15, 0.17), Color(0.55, 0.2, 0.18)]
	var y := 0.0
	for k in rng.randi_range(2, 4):
		var th := rng.randf_range(0.03, 0.06)
		P.box(n, Vector3(0.42 - k * 0.03, th, 0.32 - k * 0.02), Vector3(0, y + th * 0.5, 0), P.m_cloth(cols[rng.randi_range(0, cols.size() - 1)]), Vector3(0, rng.randf_range(-0.08, 0.08), 0))
		y += th
	for sx in [-0.1, 0.1]:
		P.box(n, Vector3(0.1, 0.09, 0.27), Vector3(sx, 0.045, 0.42), Mats.col(Color(0.12, 0.08, 0.06), "metal", 0.3))
	if rng.randf() < 0.5:
		P.box(n, Vector3(0.08, 0.02, 0.14), Vector3(0.05, y + 0.01, 0.02), Mats.col(Color(0.1, 0.1, 0.1), "metal", 0.5))
	return n


## Видеокамера на штативе снимает стену; огонёк записи горит
static func tripod_cam(rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var blk := P.m_black()
	for k in 3:
		var a := k * TAU / 3.0
		P.rod(n, Vector3(0, 1.25, 0), Vector3(cos(a) * 0.38, 0, sin(a) * 0.38), 0.012, blk, 4)
	P.box(n, Vector3(0.12, 0.13, 0.28), Vector3(0, 1.36, 0.02), Mats.col(Color(0.16, 0.16, 0.17), "metal", 0.3))
	P.cyl(n, 0.045, 0.045, 0.09, Vector3(0, 1.37, 0.2), blk, Vector3(PI * 0.5, 0, 0), 10)
	var rec := P.sph(n, 0.01, Vector3(0.04, 1.44, 0.14), P.m_emit(Color(1, 0.05, 0.05), 3.0))
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
static func lone_door(rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var frame := P.m_plastic(Color(0.84, 0.82, 0.76))
	var leafc := Color(0.55, 0.42, 0.3) if rng.randf() < 0.5 else Color(0.72, 0.7, 0.64)
	P.box(n, Vector3(0.08, 2.15, 0.12), Vector3(-0.5, 1.075, 0), frame)
	P.box(n, Vector3(0.08, 2.15, 0.12), Vector3(0.5, 1.075, 0), frame)
	P.box(n, Vector3(1.08, 0.08, 0.12), Vector3(0, 2.15, 0), frame)
	var hinge := Node3D.new()
	hinge.position = Vector3(-0.46, 0, 0)
	n.add_child(hinge)
	P.box(hinge, Vector3(0.92, 2.08, 0.045), Vector3(0.46, 1.05, 0), Mats.col(leafc, "wood", 0.5))
	P.sph(hinge, 0.03, Vector3(0.84, 1.0, 0.04), P.m_metal())
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
static func lost_camp(cx: Node3D, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	P.box(n, Vector3(0.9, 0.05, 1.9), Vector3(0, 0.025, 0), P.m_cloth(Color(0.35, 0.28, 0.22)), Vector3(0, rng.randf_range(-0.2, 0.2), 0))
	P.box(n, Vector3(0.5, 0.12, 0.3), Vector3(0, 0.08, -0.75), P.m_cloth(Color(0.5, 0.45, 0.4)))
	for k in rng.randi_range(4, 8):
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.7, 1.3)
		var lying := rng.randf() < 0.5
		P.cyl(n, 0.035, 0.035, 0.11, Vector3(cos(a) * r, 0.035 if lying else 0.055, sin(a) * r), P.m_metal(), Vector3(PI * 0.5 if lying else 0.0, rng.randf() * TAU, 0), 8)
	P.cyl(n, 0.022, 0.022, 0.18, Vector3(0.6, 0.022, 0.5), P.m_black(), Vector3(0, 0.4, PI * 0.5), 8)
	var lb := P.label("|||| |||| |||| |||| |||| ||", P.font_hand(), 0.0035, Color(0.12, 0.1, 0.08))
	lb.position = Vector3(0, 0.75, -1.08)
	n.add_child(lb)
	return n


# ------------------------------------------------------------ обжитые и странные места

## Надпись/табличка: ключ текста, цвет, размер; plate — подложка
static func text(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	if bool(d.get("plate", false)):
		var ps: Vector2 = d.get("plate_size", Vector2(0.9, 0.35))
		var pc: Color = d.get("plate_color", Color(0.05, 0.05, 0.05))
		P.box(n, Vector3(ps.x, ps.y, 0.03), Vector3(0, 0, 0.015), Mats.col(pc, "metal", 0.2))
	var col: Color = d.get("color", Color(0.08, 0.08, 0.1))
	var txt := String(d.get("txt", "")) if d.has("txt") else Loc.t(String(d.get("key", "sign.exit")))
	var lb := P.label(txt, P.font_hand() if bool(d.get("hand", false)) else P.font_sign(), float(d.get("px", 0.004)), col)
	lb.position = Vector3(0, 0, 0.036)
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
	P.model(n, "round_wooden_table_01")
	var top := Models.aabb("round_wooden_table_01").size.y
	if top < 0.3:
		top = 0.75
	P.cyl(n, 0.17, 0.17, 0.13, Vector3(0, top + 0.065, 0), Mats.col(Color(0.96, 0.92, 0.86), "fabric", 0.6))
	P.cyl(n, 0.175, 0.175, 0.025, Vector3(0, top + 0.14, 0), Mats.col(Color(0.92, 0.48, 0.62), "fabric", 0.5))
	for k in 5:
		var a := k * TAU / 5.0
		P.cyl(n, 0.006, 0.006, 0.07, Vector3(cos(a) * 0.1, top + 0.19, sin(a) * 0.1), Mats.col(Color(0.4, 0.6, 0.95), "metal", 0.2), Vector3.ZERO, 5)
	var hats := [Color(0.9, 0.2, 0.3), Color(0.2, 0.5, 0.9), Color(0.95, 0.8, 0.2)]
	for k in 3:
		var a2 := rng.randf() * TAU
		P.cyl(n, 0.0, 0.07, 0.17, Vector3(cos(a2) * 0.45, top + 0.085, sin(a2) * 0.45), Mats.col(hats[k], "fabric", 0.3), Vector3.ZERO, 10)
		P.cyl(n, 0.09, 0.09, 0.01, Vector3(cos(a2 + 1.0) * 0.38, top + 0.005, sin(a2 + 1.0) * 0.38), P.m_plastic(Color(0.95, 0.95, 0.93)), Vector3.ZERO, 14)
	return n


## Проектор на столе светит в стену: луч и белый квадрат
static func projector(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var dist := float(d.get("dist", 4.0))
	var y := 0.82
	P.box(n, Vector3(0.3, 0.12, 0.26), Vector3(0, y, 0), Mats.col(Color(0.22, 0.22, 0.24), "metal", 0.4))
	P.cyl(n, 0.04, 0.04, 0.06, Vector3(0, y + 0.01, -0.15), P.m_black(), Vector3(PI * 0.5, 0, 0), 10)
	var screen := P.quad(n, Vector2(1.7, 1.15), Vector3(0, 1.55, -dist), P.m_emit(Color(0.86, 0.9, 1.0), 1.3))
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.75
	cm.height = dist - 0.15
	cm.radial_segments = 4
	beam.mesh = cm
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.albedo_color = Color(0.6, 0.65, 0.75, 0.05)
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = bm
	beam.rotation = Vector3(PI * 0.5, PI * 0.25, 0)
	beam.position = Vector3(0, (y + 1.55) * 0.5, -0.15 - (dist - 0.15) * 0.5)
	beam.rotation.x = PI * 0.5 - atan2(1.55 - y, dist)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(beam)
	var se := P.SoundEmitter.new()
	se.snd = "vending_hum"
	se.every = 0.0
	se.vol = -24.0
	se.max_dist = 6.0
	se.position = Vector3(0, y, 0)
	n.add_child(se)
	return n


## Лифт: створки, табло «—», кнопка вызова. Позвонишь — звенит, но двери не откроются
static func elevator(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var steel := Mats.col(Color(0.66, 0.66, 0.64), "metal", 0.7)
	var frame := Mats.col(Color(0.32, 0.32, 0.34), "metal", 0.5)
	P.box(n, Vector3(1.45, 2.35, 0.08), Vector3(0, 1.175, 0.04), frame)
	P.box(n, Vector3(0.6, 2.12, 0.03), Vector3(-0.305, 1.06, 0.095), steel)
	P.box(n, Vector3(0.6, 2.12, 0.03), Vector3(0.305, 1.06, 0.095), steel)
	P.box(n, Vector3(0.012, 2.12, 0.035), Vector3(0, 1.06, 0.1), P.m_black())
	P.box(n, Vector3(0.5, 0.18, 0.04), Vector3(0, 2.5, 0.05), P.m_black())
	var lb := P.label("—", P.font_sign(), 0.0045, Color(1.0, 0.25, 0.08))
	lb.position = Vector3(0, 2.5, 0.075)
	n.add_child(lb)
	P.box(n, Vector3(0.12, 0.24, 0.03), Vector3(0.95, 1.1, 0.02), steel)
	var btn := P.sph(n, 0.026, Vector3(0.95, 1.14, 0.04), P.m_emit(Color(1.0, 0.82, 0.4), 2.0))
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


## Манекен: белая гипсовая фигура на подставке. «watch» — тот, что смотрит
static func mannequin(d: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var who: String = ["civ_a", "civ_e", "civ_g", "suit", "civ_b", "civ_f"][rng.randi_range(0, 5)]
	var h := Human.make(who, int(d.get("seed", rng.randi())), true)
	n.add_child(h)
	h.react = bool(d.get("watch", false))
	h.tune({"pale": 0.0, "smear": 0.0, "tex_mix": 0.0, "color": Vector3(0.9, 0.88, 0.84)})
	h.pose("stand")
	h._r("sh_l", 0.0, 0, 0.18)
	h._r("sh_r", 0.0, 0, -0.18)
	h._r("neck", 0.08)
	P.cyl(n, 0.2, 0.24, 0.04, Vector3(0, 0.02, 0), Mats.col(Color(0.14, 0.14, 0.14), "metal", 0.4), Vector3.ZERO, 16)
	P.collider(n, Vector3(0.5, 1.8, 0.4), Vector3(0, 0.9, 0))
	return n


## Холодильник: белый шкаф, гудит
static func fridge() -> Node3D:
	var n := Node3D.new()
	var w := P.m_plastic(Color(0.92, 0.91, 0.87))
	P.box(n, Vector3(0.7, 1.75, 0.65), Vector3(0, 0.875, 0), w)
	P.box(n, Vector3(0.02, 0.5, 0.03), Vector3(0.28, 1.15, 0.34), P.m_metal())
	P.box(n, Vector3(0.68, 0.012, 0.01), Vector3(0, 1.32, 0.33), Mats.col(Color(0.6, 0.6, 0.58), "metal", 0.3))
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
	var dark := Mats.col(Color(0.18, 0.18, 0.19), "metal", 0.5)
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
	var bl := Mats.col(Color(0.5, 0.5, 0.48), "metal", 0.4)
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
	P.cyl(body, 0.19, 0.19, 0.03, Vector3(0, 0.45, 0.31), Mats.col(Color(0.12, 0.15, 0.17), "metal", 0.1, {"wet": 1.0}), Vector3(PI * 0.5, 0, 0), 18)
	P.box(body, Vector3(0.56, 0.12, 0.02), Vector3(0, 0.76, 0.3), Mats.col(Color(0.78, 0.78, 0.75), "metal", 0.3))
	P.collider(n, Vector3(0.6, 0.85, 0.6), Vector3(0, 0.425, 0))
	return n


## Постамент с экспонатом
static func pedestal(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	P.box(n, Vector3(0.5, 1.0, 0.5), Vector3(0, 0.5, 0), P.m_plastic(Color(0.92, 0.91, 0.88)))
	P.collider(n, Vector3(0.5, 1.0, 0.5), Vector3(0, 0.5, 0))
	P.model(n, String(d.get("id", "marble_bust_01")), Vector3(0, 1.0, 0), PI, 1.0, false)
	return n


## Столбики с бархатной верёвкой (квадрат вокруг экспоната)
static func ropes(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var s := float(d.get("len", 1.6))
	var brass := Mats.col(Color(0.75, 0.6, 0.3), "metal", 0.7)
	var red := Mats.col(Color(0.5, 0.06, 0.08), "fabric", 0.5)
	var pts := [Vector3(0, 0, 0), Vector3(s, 0, 0), Vector3(s, 0, -s), Vector3(0, 0, -s)]
	for k in 4:
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[(k + 1) % 4]
		P.cyl(n, 0.025, 0.025, 0.9, a + Vector3(0, 0.45, 0), brass, Vector3.ZERO, 8)
		P.cyl(n, 0.1, 0.1, 0.03, a + Vector3(0, 0.015, 0), brass, Vector3.ZERO, 12)
		if k != 0:
			P.rod(n, a + Vector3(0, 0.82, 0), b + Vector3(0, 0.82, 0), 0.015, red, 5)
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
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.22)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	qm.albedo_color = Color(0.75, 0.78, 0.8, 0.35)
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


## Разводы протечки на потолке: рыжее кольцо с тёмным краем
static func ceil_stain(d: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var s := float(d.get("s", 1.2))
	var y := float(d.get("y", 3.2)) - 0.006
	var dark := bool(d.get("dark", false))
	var m1 := P.decal_mat("ceil_stain_a", {"radial": 1.0, "tint": Color(0.45, 0.29, 0.09, 0.58)})
	var m2 := P.decal_mat("ceil_stain_b", {"radial": 1.0, "tint": Color(0.3, 0.19, 0.07, 0.7)})
	var q1 := P.quad(n, Vector2(s, s * rng.randf_range(0.7, 1.2)), Vector3(0, y, 0), m1 if not dark else m2, Vector3(PI * 0.5, 0, 0))
	q1.set_instance_shader_parameter("seed", rng.randf() * 10.0)
	var q2 := P.quad(n, Vector2(s * 0.55, s * 0.5), Vector3(rng.randf_range(-0.15, 0.15), y - 0.002, rng.randf_range(-0.15, 0.15)), m2, Vector3(PI * 0.5, 0, 0))
	q2.set_instance_shader_parameter("seed", rng.randf() * 10.0)
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
