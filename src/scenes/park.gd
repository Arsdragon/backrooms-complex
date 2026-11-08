extends Node3D
## Парк в Сан-Хосе, 14 июля 1990, около 16:12. Солнце, люди, мороженое.
## Через минуту-полторы что-то идёт не так: стихают птицы, проступает гул ламп — и земля исчезает.

const Props := preload("res://src/world/props.gd")

var player: Player
var t := 0.0
var fall_at := 85.0
var wrong := 0.0
var falling := false
var path_pts: PackedVector3Array
var people: Array = []          # [Human, kind, data]
var spot := Vector3(-16, 0, 30) # место, где «тонко»
var _std_cache := {}
var _env: Environment
var _sun: DirectionalLight3D
var _birds_cd := 1.0


func _ready() -> void:
	Props.park_mode = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 140790
	if Cfg.has_arg("fall_at"):
		fall_at = float(Cfg.arg("fall_at"))
	_environment()
	_ground(rng)
	_path()
	_tufts(rng)
	_trees(rng)
	_furniture(rng)
	_people(rng)
	_skyline(rng)
	player = Player.new()
	add_child(player)
	player.global_position = path_pts[0] + Vector3(0, 0.1, 0)
	var dir := path_pts[3] - path_pts[0]
	player.set_look(atan2(-dir.x, -dir.z), -0.05)
	if Cfg.has_arg("pos"):
		var pp := Cfg.arg("pos").split(",")
		player.global_position = Vector3(float(pp[0]), float(pp[1]), float(pp[2]))
		player.set_look(float(Cfg.arg("yaw", "0")), float(Cfg.arg("pitch", "0")))
	player.surface_fn = func(p: Vector3) -> String:
		return "path" if _near_path(p) < 1.4 else "grass"
	Snd.set_reverb(0.2, 0.05)
	Snd.loop("park_amb", "park_ambience", 0.85, 2.0)
	Snd.loop("park_wind", "wind_trees", 0.5, 2.0)
	_subs_intro()


func _subs_intro() -> void:
	await get_tree().create_timer(2.5).timeout
	Game.say("sub.park1")
	await get_tree().create_timer(4.0).timeout
	Game.say("sub.park2")


# ------------------------------------------------------------ окружение

func _environment() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.26, 0.47, 0.82)
	sm.sky_horizon_color = Color(0.78, 0.8, 0.8)
	sm.ground_horizon_color = Color(0.7, 0.7, 0.66)
	sm.ground_bottom_color = Color(0.35, 0.33, 0.28)
	sm.sun_angle_max = 20.0
	sm.sky_curve = 0.12
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.7
	e.ambient_light_sky_contribution = 0.55
	e.ambient_light_color = Color(0.75, 0.72, 0.65)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.05
	e.glow_enabled = true
	e.glow_intensity = 0.4
	e.glow_bloom = 0.05
	e.fog_enabled = true
	e.fog_light_color = Color(0.72, 0.76, 0.8)
	e.fog_density = 0.004
	e.fog_aerial_perspective = 0.6
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.05
	e.adjustment_contrast = 1.05
	we.environment = e
	_env = e
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation = Vector3(deg_to_rad(-34.0), deg_to_rad(-128.0), 0)
	_sun.light_color = Color(1.0, 0.93, 0.8)
	_sun.light_energy = 1.35
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 45.0
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.shadow_blur = 1.5
	add_child(_sun)


func _ground(rng: RandomNumberGenerator) -> void:
	var size := 260.0
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	pm.subdivide_width = 60
	pm.subdivide_depth = 60
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = Mats.tex("grass")
	gm.uv1_scale = Vector3(size / 4.0, size / 4.0, 1)
	gm.roughness = 1.0
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = gm
	add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(size, 1.0, size)
	cs.shape = sh
	cs.position.y = -0.5
	body.add_child(cs)
	add_child(body)
	body.set_meta("ground", true)
	# невидимые стены по краю парка
	for k in 4:
		var w := StaticBody3D.new()
		var c2 := CollisionShape3D.new()
		var b2 := BoxShape3D.new()
		b2.size = Vector3(120 if k < 2 else 1, 6, 1 if k < 2 else 120)
		c2.shape = b2
		w.add_child(c2)
		w.position = [Vector3(0, 3, -58), Vector3(0, 3, 58), Vector3(-58, 3, 0), Vector3(58, 3, 0)][k]
		add_child(w)


func _path() -> void:
	# петля дорожки вокруг площади с фонтаном
	var ctrl := [Vector3(0, 0, 44), Vector3(22, 0, 34), Vector3(34, 0, 10), Vector3(30, 0, -18), Vector3(12, 0, -34),
		Vector3(-14, 0, -32), Vector3(-32, 0, -14), Vector3(-34, 0, 12), Vector3(-22, 0, 32)]
	path_pts = PackedVector3Array()
	var n := ctrl.size()
	for i in n:
		var p0: Vector3 = ctrl[(i - 1 + n) % n]
		var p1: Vector3 = ctrl[i]
		var p2: Vector3 = ctrl[(i + 1) % n]
		var p3: Vector3 = ctrl[(i + 2) % n]
		for k in 12:
			var tt := k / 12.0
			path_pts.append(_catmull(p0, p1, p2, p3, tt))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 1.4
	var m := path_pts.size()
	var acc := 0.0
	for i in m:
		var a := path_pts[i]
		var b := path_pts[(i + 1) % m]
		var d := (b - a)
		var side := d.cross(Vector3.UP).normalized() * w
		var na := path_pts[(i + 1) % m]
		var nb := path_pts[(i + 2) % m]
		var side2 := (nb - na).cross(Vector3.UP).normalized() * w
		var l := d.length()
		var y := 0.02
		var v0 := Vector3(a.x, y, a.z) - side
		var v1 := Vector3(a.x, y, a.z) + side
		var v2 := Vector3(b.x, y, b.z) + side2
		var v3 := Vector3(b.x, y, b.z) - side2
		for vv in [[v0, Vector2(0, acc)], [v2, Vector2(1, acc + l)], [v1, Vector2(1, acc)], [v0, Vector2(0, acc)], [v3, Vector2(0, acc + l)], [v2, Vector2(1, acc + l)]]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(vv[1].x * 1.4, vv[1].y / 2.8))
			st.add_vertex(vv[0])
		acc += l
	var pm := StandardMaterial3D.new()
	pm.albedo_texture = Mats.tex("path")
	pm.roughness = 0.95
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = pm
	add_child(mi)
	# площадь у фонтана
	var plaza := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 9.0
	cm.bottom_radius = 9.0
	cm.height = 0.04
	cm.radial_segments = 32
	plaza.mesh = cm
	plaza.material_override = pm
	plaza.position = Vector3(0, 0.01, 0)
	add_child(plaza)
	# дорожки-спицы от петли к площади
	for k in 3:
		var a2: Vector3 = ctrl[k * 3]
		var dir := (Vector3.ZERO - a2)
		var spoke := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.4, 0.03, dir.length() - 8.0)
		spoke.mesh = bm
		spoke.material_override = pm
		spoke.position = a2 + dir * 0.5 - dir.normalized() * 4.0 + Vector3(0, 0.015, 0)
		spoke.rotation.y = atan2(dir.x, dir.z)
		add_child(spoke)


func _tufts(rng: RandomNumberGenerator) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := QuadMesh.new()
	q.size = Vector2(0.45, 0.3)
	q.center_offset = Vector3(0, 0.15, 0)
	var tm := StandardMaterial3D.new()
	tm.albedo_texture = Mats.tex("grass_tuft")
	tm.albedo_color = Color(1.0, 1.0, 1.0)
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	tm.alpha_scissor_threshold = 0.5
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	tm.roughness = 1.0
	q.material = tm
	mm.mesh = q
	mm.instance_count = 2600
	for i in mm.instance_count:
		var p := Vector3(rng.randf_range(-55, 55), 0, rng.randf_range(-55, 55))
		while _near_path(p) < 1.9:
			p = Vector3(rng.randf_range(-55, 55), 0, rng.randf_range(-55, 55))
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.6, 1.3))
		mm.set_instance_transform(i, Transform3D(b, p))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


func _near_path(p: Vector3) -> float:
	var best := 1e9
	for i in range(0, path_pts.size(), 2):
		best = minf(best, Vector2(p.x - path_pts[i].x, p.z - path_pts[i].z).length())
	if Vector2(p.x, p.z).length() < 9.0:
		best = 0.0
	return best


func _trees(rng: RandomNumberGenerator) -> void:
	var placed := 0
	var guard := 0
	while placed < 46 and guard < 500:
		guard += 1
		var p := Vector3(rng.randf_range(-54, 54), 0, rng.randf_range(-54, 54))
		if _near_path(p) < 4.0 or Vector2(p.x, p.z).length() < 12.0:
			continue
		if p.distance_to(Vector3(-24, 0, -6)) < 9.0 or p.distance_to(Vector3(20, 0, -10)) < 6.0:
			continue
		var n := Node3D.new()
		add_child(n)
		n.position = p
		n.rotation.y = rng.randf() * TAU
		var kind := rng.randf()
		if kind < 0.22:
			_palm(n, rng)
		else:
			Props._tree(n, rng)
			n.scale = Vector3.ONE * rng.randf_range(1.2, 1.9)
		_to_std(n)
		placed += 1
	# «тонкое место» — старый дуб, у которого гудит
	var sp := Node3D.new()
	add_child(sp)
	sp.position = spot + Vector3(2.5, 0, 1.5)
	Props._tree(sp, rng)
	sp.scale = Vector3.ONE * 2.1
	_to_std(sp)


func _palm(n: Node3D, rng: RandomNumberGenerator) -> void:
	var bark := StandardMaterial3D.new()
	bark.albedo_texture = Mats.tex("bark")
	bark.albedo_color = Color(0.85, 0.78, 0.65)
	var h := rng.randf_range(8.0, 13.0)
	var lean := Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8))
	var prev := Vector3.ZERO
	for k in 6:
		var t := float(k + 1) / 6.0
		var p := Vector3(0, h * t, 0) + lean * t * t
		var seg := Props.rod(n, prev, p, 0.2 - t * 0.06, bark, 8)
		seg.material_override = bark
		prev = p
	var fr := StandardMaterial3D.new()
	fr.albedo_color = Color(0.32, 0.45, 0.2)
	fr.albedo_texture = Mats.tex("fabric")
	fr.roughness = 0.9
	fr.cull_mode = BaseMaterial3D.CULL_DISABLED
	var crown := MeshInstance3D.new()
	var cs := SphereMesh.new()
	cs.radius = 0.35
	cs.height = 0.6
	crown.mesh = cs
	crown.material_override = bark
	crown.position = prev
	n.add_child(crown)
	for k in 14:
		var a := k * TAU / 14.0 + rng.randf_range(-0.1, 0.1)
		var fj := Node3D.new()
		n.add_child(fj)
		fj.position = prev
		fj.rotation = Vector3(0, a, 0)
		var pitch := deg_to_rad(rng.randf_range(-25.0, 15.0))
		var p0 := Vector3.ZERO
		for sgi in 6:
			var ln := 0.55
			pitch += deg_to_rad(14.0 + sgi * 4.0)
			var dir := Vector3(0, -sin(pitch), cos(pitch))
			var w := 0.55 - sgi * 0.08
			var seg := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(w, 0.02, ln)
			seg.mesh = bm
			seg.material_override = fr
			seg.position = p0 + dir * ln * 0.5
			seg.rotation.x = pitch
			fj.add_child(seg)
			p0 += dir * ln


func _furniture(rng: RandomNumberGenerator) -> void:
	var m := path_pts.size()
	# скамейки и фонари вдоль дорожки
	for k in 10:
		var i := (k * m / 10 + 3) % m
		var a := path_pts[i]
		var b := path_pts[(i + 1) % m]
		var side := (b - a).cross(Vector3.UP).normalized()
		var out := 1.0 if k % 2 == 0 else -1.0
		var bench := Node3D.new()
		add_child(bench)
		Props._bench(bench)
		bench.position = a + side * 2.2 * out
		bench.rotation.y = atan2(-side.x * out, -side.z * out)
		_to_std(bench)
		var lamp := Node3D.new()
		add_child(lamp)
		Props._lamp(lamp)
		lamp.position = path_pts[(i + m / 20) % m] - side * 2.0 * out
		_to_std(lamp)
		if k % 3 == 0:
			var bin := Node3D.new()
			add_child(bin)
			Props._bin(bin)
			bin.position = a + side * 2.2 * out + (b - a).normalized() * 1.6
			_to_std(bin)
	# фонтан в центре (с настоящей водой)
	var f := Node3D.new()
	add_child(f)
	Props._fountain(f)
	_to_std(f)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.22, 0.36, 0.4)
	wm.roughness = 0.04
	wm.metallic = 0.4
	for ch in f.get_children():
		if ch.has_meta("water"):
			(ch as MeshInstance3D).material_override = wm
			(ch as MeshInstance3D).position.y -= 0.04
	var wl := Props.SoundEmitter.new()
	wl.snd = "water_loop"
	wl.every = 0.0
	wl.vol = -8.0
	wl.max_dist = 30.0
	wl.position = Vector3(0, 1.0, 0)
	add_child(wl)
	# детская площадка
	var pg := Node3D.new()
	add_child(pg)
	pg.position = Vector3(-24, 0, -6)
	var sl := Node3D.new()
	pg.add_child(sl)
	Props._slide(sl)
	sl.position = Vector3(-2, 0, 0)
	var sw := Node3D.new()
	pg.add_child(sw)
	Props._swing(sw, false)
	sw.position = Vector3(3, 0, 1)
	_to_std(pg)
	# тележка с мороженым
	var cart := Node3D.new()
	add_child(cart)
	Props._cart(cart)
	cart.position = Vector3(7.5, 0, 6.5)
	cart.rotation.y = -0.7
	_to_std(cart)
	var jingle := Props.SoundEmitter.new()
	jingle.snd = "jingle"
	jingle.every = 0.0
	jingle.vol = -9.0
	jingle.max_dist = 40.0
	jingle.position = Vector3(0, 1.2, 0)
	cart.add_child(jingle)
	# плед для пары
	var bl := Node3D.new()
	add_child(bl)
	Props._blanket(bl)
	bl.position = Vector3(20, 0.0, -10)
	bl.rotation.y = 0.4
	_to_std(bl)
	# табличка у входа
	var sg := Node3D.new()
	add_child(sg)
	Props._sign_park(sg)
	var s0 := path_pts[2]
	var sdir := (path_pts[3] - path_pts[1]).normalized()
	var sside := sdir.cross(Vector3.UP).normalized()
	sg.position = s0 + sside * 2.4
	var to_start := path_pts[0] - sg.position
	sg.rotation.y = atan2(to_start.x, to_start.z)
	_to_std(sg)


func _people(rng: RandomNumberGenerator) -> void:
	var m := path_pts.size()
	var jog := Human.make("jogger", 11, false)
	add_child(jog)
	jog.pose_name = "run"
	people.append([jog, "loop", {"i": float(m / 3), "speed": 3.2}])
	var mom := Human.make("mother", 12, false)
	add_child(mom)
	var st := Node3D.new()
	Props._stroller(st)
	_to_std(st)
	mom.add_child(st)
	st.position = Vector3(0, 0, 0.75)
	st.rotation.y = PI
	mom.pose_name = "walk"
	mom.anim_speed = 0.7
	people.append([mom, "loop", {"i": float(m * 2 / 3), "speed": -0.95, "push": true}])
	var kid := Human.make("kid", 13, false)
	add_child(kid)
	kid.position = Vector3(-20, 0, -3)
	kid.rotation.y = 2.6
	var bal := Node3D.new()
	Props._balloon(bal)
	_to_std(bal)
	kid.hold(bal, "r", Vector3(0, 0.2, 0))
	kid.pose("hold_up")
	people.append([kid, "idle", {}])
	var old := Human.make("oldman", 14, false)
	add_child(old)
	var b0 := path_pts[(3 + m * 4 / 10) % m]
	var b1 := path_pts[(4 + m * 4 / 10) % m]
	var side := (b1 - b0).cross(Vector3.UP).normalized()
	old.position = b0 + side * 2.2
	old.rotation.y = atan2(-side.x, -side.z)
	old.pose("read")
	var paper := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(0.45, 0.32, 0.01)
	paper.mesh = pb
	var pmat := StandardMaterial3D.new()
	pmat.albedo_texture = Mats.tex("paper")
	paper.material_override = pmat
	old.hand("l").add_child(paper)
	paper.position = Vector3(0.15, -0.12, 0.08)
	people.append([old, "idle", {}])
	var couple_a := Human.make("couple", 15, false)
	add_child(couple_a)
	couple_a.position = Vector3(19.5, 0, -10.2)
	couple_a.rotation.y = 0.9
	couple_a.pose("sit_ground")
	var couple_b := Human.make("civ_b", 16, false)
	add_child(couple_b)
	couple_b.position = Vector3(20.5, 0, -9.6)
	couple_b.rotation.y = -2.1
	couple_b.pose("sit_ground")
	people.append([couple_a, "idle", {}])
	people.append([couple_b, "idle", {}])
	var suit := Human.make("suit", 17, false)
	add_child(suit)
	suit.pose_name = "walk"
	var bc := MeshInstance3D.new()
	var bcm := BoxMesh.new()
	bcm.size = Vector3(0.42, 0.3, 0.09)
	bc.mesh = bcm
	var bcmat := StandardMaterial3D.new()
	bcmat.albedo_color = Color(0.25, 0.14, 0.07)
	bc.material_override = bcmat
	suit.hand("r").add_child(bc)
	bc.position = Vector3(0, -0.2, 0)
	people.append([suit, "cross", {"a": Vector3(-50, 0, 20), "b": Vector3(50, 0, -25), "t": 0.3, "speed": 1.35}])
	var vendor := Human.make("vendor", 18, false)
	add_child(vendor)
	vendor.position = Vector3(8.6, 0, 7.4)
	vendor.rotation.y = 2.4
	vendor.pose("stand")
	people.append([vendor, "idle", {}])
	var teen := Human.make("teen", 19, false)
	add_child(teen)
	var t0 := path_pts[(3 + m * 7 / 10) % m]
	var t1 := path_pts[(4 + m * 7 / 10) % m]
	var side2 := (t1 - t0).cross(Vector3.UP).normalized()
	teen.position = t0 - side2 * 2.2
	teen.rotation.y = atan2(side2.x, side2.z)
	teen.pose("sit")
	people.append([teen, "idle", {}])


func _skyline(rng: RandomNumberGenerator) -> void:
	var far := StandardMaterial3D.new()
	far.albedo_color = Color(0.62, 0.66, 0.72)
	far.roughness = 1.0
	for k in 22:
		var a := rng.randf_range(-0.6, 0.6) + PI * 0.5
		var r := rng.randf_range(160, 220)
		var h := rng.randf_range(15, 60)
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(rng.randf_range(12, 30), h, rng.randf_range(12, 30))
		b.mesh = bm
		b.material_override = far
		b.position = Vector3(cos(a) * r, h * 0.5, -sin(a) * r)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(b)
	var hill := StandardMaterial3D.new()
	hill.albedo_color = Color(0.66, 0.58, 0.38)
	for k2 in 8:
		var a2 := k2 * TAU / 8.0 + 0.3
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		s.mesh = sm
		s.material_override = hill
		s.scale = Vector3(rng.randf_range(90, 140), rng.randf_range(25, 45), rng.randf_range(60, 90))
		s.position = Vector3(cos(a2) * 330, -8, sin(a2) * 330)
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s)


## Материалы предметов (шейдер Комплекса) → обычные освещаемые
func _to_std(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var sm := mi.material_override as ShaderMaterial
		if sm != null:
			if not _std_cache.has(sm):
				var m := StandardMaterial3D.new()
				var c: Variant = sm.get_shader_parameter("color")
				var col := Color(1, 1, 1)
				if c is Vector3:
					col = Color((c as Vector3).x, (c as Vector3).y, (c as Vector3).z)
				elif c is Color:
					col = c
				m.albedo_color = col
				var tm: Variant = sm.get_shader_parameter("tex_mix")
				var tx: Variant = sm.get_shader_parameter("tex")
				if tm != null and float(tm) > 0.3 and tx is Texture2D:
					m.albedo_texture = tx
				var ac: Variant = sm.get_shader_parameter("alpha_cut")
				if ac != null and float(ac) > 0.0:
					m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					m.alpha_scissor_threshold = float(ac)
					m.cull_mode = BaseMaterial3D.CULL_DISABLED
				var em: Variant = sm.get_shader_parameter("emit")
				if em != null and float(em) > 0.0:
					m.emission_enabled = true
					var ec: Variant = sm.get_shader_parameter("emit_color")
					m.emission = Color((ec as Vector3).x, (ec as Vector3).y, (ec as Vector3).z) if ec is Vector3 else col
					m.emission_energy_multiplier = float(em) * 0.5
				m.roughness = 0.85
				var uvs: Variant = sm.get_shader_parameter("uv_scale")
				if uvs is Vector2:
					m.uv1_scale = Vector3((uvs as Vector2).x, (uvs as Vector2).y, 1)
				_std_cache[sm] = m
			mi.material_override = _std_cache[sm]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for ch in n.get_children():
		_to_std(ch)


# ------------------------------------------------------------ кадр

func _process(dt: float) -> void:
	t += dt
	var m := path_pts.size()
	for e in people:
		var h: Human = e[0]
		var kind: String = e[1]
		var d: Dictionary = e[2]
		if kind == "loop":
			var sp: float = d.speed
			d.i = fposmod(float(d.i) + sp * dt * 0.62 * (1.0 - wrong * 0.85), float(m))
			var i0 := int(d.i)
			var f := float(d.i) - i0
			var a := path_pts[i0 % m]
			var b := path_pts[(i0 + 1) % m]
			var p := a.lerp(b, f)
			var side := (b - a).cross(Vector3.UP).normalized()
			h.position = p + side * (0.55 if sp > 0 else -0.55)
			var dir := (b - a) * signf(sp)
			h.rotation.y = atan2(dir.x, dir.z)
			h.anim_speed = (1.0 if sp > 0 else 0.7) * (1.0 - wrong * 0.9)
		elif kind == "cross":
			d.t = fposmod(float(d.t) + dt * float(d.speed) / 110.0 * (1.0 - wrong * 0.9), 1.0)
			var pa: Vector3 = d.a
			var pb: Vector3 = d.b
			h.position = pa.lerp(pb, float(d.t))
			var dir2 := pb - pa
			h.rotation.y = atan2(dir2.x, dir2.z)
			h.anim_speed = 1.0 - wrong * 0.9
	# «что-то не так»: после минуты стихают птицы, проступает гул ламп
	var near_spot := player.global_position.distance_to(spot) if player != null else 99.0
	var ramp_start := fall_at - 25.0
	wrong = clampf((t - ramp_start) / 25.0, 0.0, 1.0)
	wrong = maxf(wrong, clampf(1.0 - (near_spot - 2.0) / 14.0, 0.0, 1.0) * 0.9)
	Snd.loop_vol("park_amb", 0.85 * (1.0 - wrong * 0.85), 0.5)
	Snd.loop("park_hum", "hum_fluor", wrong * 0.55, 0.5)
	_birds_cd -= dt
	if _birds_cd <= 0.0 and wrong < 0.5:
		_birds_cd = randf_range(1.5, 5.0)
		Snd.play("bird", randf_range(-22.0, -12.0), randf_range(0.9, 1.15), "Amb")
	if Game.main != null and not falling:
		Game.main.interference = wrong * 0.25
		if randf() < wrong * dt * 0.8:
			Game.main.burst(0.3 + wrong * 0.5)
	if _env != null:
		_env.adjustment_saturation = 1.05 - wrong * 0.35
	if not falling and Game.gen_ready() and (t >= fall_at or (near_spot < 1.6 and t > 8.0)):
		_fall()


func _fall() -> void:
	falling = true
	Game.say("sub.fall")
	Snd.play("glitch", -2.0)
	if Game.main != null:
		Game.main.burst(1.0)
	await get_tree().create_timer(0.6).timeout
	# земля «кончается»: игрок проходит сквозь неё
	player.collision_mask = 0
	player.velocity = Vector3(0, -2.0, 0)
	Snd.loop_vol("park_amb", 0.0, 0.2)
	Snd.loop_vol("park_wind", 0.0, 0.2)
	Snd.stop_loop("park_hum", 0.3)
	Snd.play("fall_whoosh", 0.0)
	await get_tree().create_timer(0.9).timeout
	Game.main.set_fade(Color(0, 0, 0, 1))
	Snd.stop_loop("park_amb", 0.1)
	Snd.stop_loop("park_wind", 0.1)
	Snd.set_reverb(0.55, 0.18)
	await get_tree().create_timer(0.6).timeout
	Game.fall_from_park()
