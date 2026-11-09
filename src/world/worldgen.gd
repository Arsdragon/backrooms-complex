class_name WorldGen
extends RefCounted
## Генерация двух слоёв Комплекса для одного забега.
## Слой 0 — «Коридоры» (жёлтые комнаты). Слой 1 — нижние секции (темнота, бетон, плитка), куда падают через ямы.

const LD := preload("res://src/world/layer_data.gd")
const Rooms := preload("res://src/world/worldgen_rooms.gd")

const GRAF_COUNT := 36
const NOTES_L0 := ["note.n01", "note.n02", "note.n03", "note.n04", "note.n05", "note.n06", "note.n07", "note.n08"]
const NOTES_L1 := ["note.u01", "note.u02", "note.u03", "note.u04", "note.u05"]
# кто из парка «скопирован» и как именно криво
const PARK_PEOPLE := ["jogger", "mother", "kid", "oldman", "couple", "suit", "vendor", "teen"]
const OTHER_PEOPLE := ["civ_a", "civ_b", "civ_c", "civ_d", "civ_e", "civ_f", "civ_g", "civ_h", "civ_i", "civ_j", "civ_k", "civ_l",
	"civ_m", "civ_n", "civ_o", "civ_p", "worker", "explorer"]
const WRONG := ["wall", "stretch", "twist", "ceiling", "sunk", "flat", "corner", "arms", "hstretch", "seated_air", "none", "fused_floor", "back"]
const OBJECTS := ["bench", "lamp", "bin", "chair", "desk", "cabinet", "cooler", "ochair", "boxes", "tv", "stroller", "phone", "shelf", "balloon", "sign_park",
	"wetsign", "wetsign", "wetsign", "wheelchair", "hydrant", "trashbag", "tyre", "utilitybox", "crate", "chair"]
const OBJ_WRONG := ["wall", "stretch", "ceiling", "stack", "sink", "wallpaper", "row", "none", "tilt"]


static func generate(seed: int) -> Array:
	var t0 := Time.get_ticks_msec()
	var l0 := layer0(seed)
	var l1 := layer1(seed, l0)
	print("Комплекс сгенерирован за %d мс" % (Time.get_ticks_msec() - t0))
	return [l0, l1]


static var _pt := 0


static func _prof(what: String) -> void:
	var now := Time.get_ticks_msec()
	if OS.get_cmdline_user_args().has("--gen_prof"):
		print("GEN %5d ms  %s" % [now - _pt, what])
	_pt = now


static func _centered(v: int) -> int:
	return v if v < LD.N / 2 else v - LD.N


static func _dist0(x: int, z: int) -> float:
	return Vector2(_centered(posmod(x, LD.N)), _centered(posmod(z, LD.N))).length()


# ======================================================================= слой 0

static func layer0(seed: int) -> LayerData:
	var L := LD.new()
	L.layer = 0
	L.seed = seed
	L.floor_y = 0.0
	L.rng.seed = seed
	L.init_arrays()
	var nz := FastNoiseLite.new()
	nz.seed = seed
	nz.frequency = 0.03
	nz.fractal_octaves = 2
	for z in LD.N:
		for x in LD.N:
			var n := nz.get_noise_2d(x, z)
			var i := z * LD.N + x
			if n < -0.4:
				L.zone[i] = LD.Z_DARK
			elif n > 0.45:
				L.zone[i] = LD.Z_OLD
	L.divide(0, 0, LD.N, LD.N, 0.25)
	_prof("L.divide(0, 0, LD.N, LD.N, 0.25)")
	L.open_random_walls(0.05)
	_prof("L.open_random_walls(0.05)")
	# старт: спокойная освещённая зона
	for z in range(-12, 13):
		for x in range(-12, 13):
			if x * x + z * z <= 144:
				L.zone[LD.idx(x, z)] = LD.Z_YELLOW
	L.stamp_room(-2, -2, 5, 5, LD.Z_YELLOW, 3, LD.E_ARCH)
	L.places["spawn"] = Vector3(LD.C * 0.5, 0.0, LD.C * 0.5)

	# --- станция Async с Порогом
	var o := L.pick_spot(0, 0, 95, 125, 9, 8)
	_outpost(L, o.x, o.y)
	# --- комнаты с ямами (14D): две «асинковские» с лебёдкой и три обычные
	var pa := L.pick_spot(o.x + 4, o.y + 4, 11, 18, 7, 6)
	_pitroom(L, pa.x, pa.y, 7, 6, 0)
	var pb := L.pick_spot(0, 0, 44, 62, 7, 6)
	_pitroom(L, pb.x, pb.y, 7, 6, 1)
	var plain_pits := [[17, 27], [42, 66], [72, 100]]
	for k in plain_pits.size():
		var r: Array = plain_pits[k]
		var pp := L.pick_spot(0, 0, int(r[0]), int(r[1]), 6, 6)
		_pitroom(L, pp.x, pp.y, 6, 6, -1)
	# --- лагерь пропавшей группы (рация, записка, конец кабеля)
	var cp := L.pick_spot(0, 0, 26, 38, 5, 4)
	_camp(L, cp.x, cp.y)
	# --- нулевые зоны (случайные выходы)
	for k in 2:
		var np := L.pick_spot(0, 0, 62, 118, 3, 3)
		_nullroom(L, np.x, np.y, "null_%d" % k)
	# --- растянутая комната
	var sp := L.pick_spot(0, 0, 46, 86, 8, 5)
	_stretch(L, sp.x, sp.y)
	# --- кривые копии парка
	var park := [["benches", 12, 22, 5, 4], ["tree", 18, 32, 5, 5], ["icecream", 22, 44, 4, 4], ["joggers", 20, 48, 2, 9],
		["fountain", 32, 58, 5, 5], ["lamps", 28, 60, 2, 10], ["playground", 40, 74, 6, 5], ["car", 48, 88, 5, 4],
		["picnic", 54, 96, 4, 4], ["stroller_room", 35, 80, 3, 3]]
	for e in park:
		var pe: Array = e
		var w: int = pe[3]
		var h: int = pe[4]
		var ps := L.pick_spot(0, 0, int(pe[1]), int(pe[2]), w, h)
		_park_room(L, ps.x, ps.y, w, h, String(pe[0]))
	Rooms.place_all(L, 0, Vector2i(0, 0))
	_prof("Rooms.place_all(L, 0, Vector2i(0, 0))")

	L.place_lights(0.0)
	_prof("L.place_lights(0.0)")
	for z in range(-10, 11):
		for x in range(-10, 11):
			var i := LD.idx(x, z)
			if L.light[i] == LD.L_DEAD or L.light[i] == LD.L_HOLE or L.light[i] == LD.L_FLICK:
				L.light[i] = LD.L_ON
	L.fix_connectivity(0, 0)
	_prof("L.fix_connectivity(0, 0)")

	# --- кабели Async: от станции к лагерю, к комнате-яме B и к дальним концам
	var ox: int = int(L.places["outpost_cell"].x)
	var oz: int = int(L.places["outpost_cell"].y)
	var ends := [L.places["camp_cell"], L.places["winch_cell_1"], L.places["winch_cell_0"]]
	for k in 5:
		var a := L.rng.randf() * TAU
		var r2 := L.rng.randf_range(55, 95)
		var ex := ox + int(cos(a) * r2)
		var ez := oz + int(sin(a) * r2)
		ends.append(L.find_cell_near(ex, ez, 12, func(x: int, z: int) -> bool: return L.is_plain(x, z)))
	L.lay_cables(ox, oz, ends)
	_prof("L.lay_cables(ox, oz, ends)")
	_cable_tags(L)
	_prof("_cable_tags(L)")
	_scatter(L, 0)
	_prof("_scatter(L, 0)")
	Rooms.sprinkle(L, 0, Vector2i(0, 0))
	_prof("Rooms.sprinkle(L, 0, Vector2i(0, 0))")
	return L


static func _outpost(L: LayerData, x: int, z: int) -> void:
	L.stamp_room(x, z, 9, 8, LD.Z_ASYNC, 0)
	for side in [0, 1, 2]:
		L._open_border(x, z, 9, 8, side, LD.E_ARCH)
	L._open_border(x, z, 9, 8, 1, LD.E_OPEN)
	for i in 9:
		for j in 8:
			var c := LD.idx(x + i, z + j)
			L.light[c] = LD.L_DEAD if (i + j) % 2 == 0 else LD.L_NONE
	var lamps := [Vector2i(2, 2), Vector2i(6, 2), Vector2i(2, 5), Vector2i(6, 5)]
	for lp in lamps:
		var v: Vector2i = lp
		L.light[LD.idx(x + v.x, z + v.y)] = LD.L_ASYNC
		var c2 := LD.cell_center(x + v.x, z + v.y)
		L.add_deco({"k": "async", "what": "lamp_stand", "p": Vector3(c2.x + 0.6, 0, c2.y - 0.5), "r": L.rng.randf() * TAU})
	# Порог — в северной стене
	var tx := x + 4
	L.wall_e[LD.idx(tx - 1, z)] = LD.E_OPEN
	L.wall_e[LD.idx(tx, z)] = LD.E_OPEN
	var tp := L.wall_point(tx, z, 3, 0.0)
	L.add_deco({"k": "threshold", "p": tp, "r": LD.dir_yaw(3)})
	L.places["outpost"] = tp + Vector3(0, 0, 1.2)
	L.places["outpost_cell"] = Vector2i(tx, z + 1)
	L.light[LD.idx(tx, z)] = LD.L_GREEN
	# снаряжение
	var items := [["table", 1, 6], ["case", 7, 1], ["case", 7, 2], ["case", 0, 3], ["spool", 3, 6], ["spool", 8, 7],
		["generator", 7, 6], ["board", 4, 7], ["crate", 0, 7], ["crate", 1, 7], ["rover", 5, 3], ["cones", 3, 1], ["cones", 5, 1]]
	for it in items:
		var a: Array = it
		var c3 := LD.cell_center(x + int(a[1]), z + int(a[2]))
		L.add_deco({"k": "async", "what": String(a[0]), "p": Vector3(c3.x + L.rng.randf_range(-0.4, 0.4), 0, c3.y + L.rng.randf_range(-0.4, 0.4)),
			"r": L.rng.randf_range(-0.3, 0.3) + (PI if int(a[2]) > 4 else 0.0)})
	for bi in 3:
		var cb := LD.cell_center(x + 2 + bi * 2, z + 7)
		L.add_deco({"k": "async", "what": "barrier", "p": Vector3(cb.x, 0, cb.y + 0.7), "r": L.rng.randf_range(-0.15, 0.15)})
	L.add_deco({"k": "note", "key": "note.a_memo", "p": Vector3(LD.cell_center(x + 1, z + 6).x, 0.78, LD.cell_center(x + 1, z + 6).y), "r": 0.3})
	var mc := L.wall_point(x, z + 3, 2, 0.0)
	L.add_deco({"k": "async", "what": "motioncam", "p": mc + Vector3(0, 2.35, 0), "r": LD.dir_yaw(2)})
	L.add_deco({"k": "sign", "key": "sign.station", "p": L.wall_point(x + 1, z, 3, 0.0) + Vector3(0, 1.6, 0), "r": LD.dir_yaw(3), "size": 1.0})


static func _pitroom(L: LayerData, x: int, z: int, w: int, h: int, async_id: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_PITS, 0)
	var doors := []
	for k in 3:
		var side := k if k < 2 else L.rng.randi_range(2, 3)
		doors.append(L._open_border(x, z, w, h, side, LD.E_ARCH if L.rng.randf() < 0.6 else LD.E_DOOR))
	# тропа между входами
	var safe := {}
	for dd in doors:
		var d: Vector2i = dd
		safe[d] = true
	var center := Vector2i(x + w / 2, z + h / 2)
	for dd in doors:
		var p: Vector2i = dd
		var q := p
		var guard := 0
		while q != center and guard < 40:
			guard += 1
			safe[q] = true
			if q.x != center.x and (L.rng.randf() < 0.5 or q.y == center.y):
				q.x += signi(center.x - q.x)
			else:
				q.y += signi(center.y - q.y)
		safe[center] = true
	for i in w:
		for j in h:
			var c := Vector2i(x + i, z + j)
			if safe.has(c):
				continue
			var border := i == 0 or j == 0 or i == w - 1 or j == h - 1
			if L.rng.randf() < (0.45 if border else 0.72):
				L.flo[LD.idx(c.x, c.y)] = LD.F_PIT
	# свет: тусклее обычного
	for i in w:
		for j in h:
			var ci := LD.idx(x + i, z + j)
			if (x + i + z + j) % 2 == 0:
				var r := L.rng.randf()
				L.light[ci] = LD.L_ON if r < 0.55 else (LD.L_FLICK if r < 0.75 else LD.L_DEAD)
	if async_id >= 0:
		# лебёдка над одной из ям, мостки, метки
		var pit := Vector2i(-1, -1)
		for i in range(1, w - 1):
			for j in range(1, h - 1):
				if L.flo[LD.idx(x + i, z + j)] == LD.F_PIT and pit.x < 0:
					pit = Vector2i(x + i, z + j)
		if pit.x < 0:
			pit = Vector2i(x + 1, z + 1)
			L.flo[LD.idx(pit.x, pit.y)] = LD.F_PIT
		var c2 := LD.cell_center(pit.x, pit.y)
		L.add_deco({"k": "async", "what": "winch", "p": Vector3(c2.x, 0, c2.y), "r": 0.0})
		L.places["winch_%d" % async_id] = Vector3(c2.x, 0, c2.y)
		# клетка рядом с ямой, куда приходит кабель
		var near := L.find_cell_near(pit.x, pit.y, 3, func(xx: int, zz: int) -> bool: return L.flo[LD.idx(xx, zz)] == LD.F_FLOOR and L.zone[LD.idx(xx, zz)] == LD.Z_PITS)
		L.places["winch_cell_%d" % async_id] = near
		L.add_deco({"k": "sign", "key": "sign.room14", "p": L.wall_point(x, z, 3, 0.0) + Vector3(0, 1.7, 0), "r": LD.dir_yaw(3), "size": 0.9})
		var c3 := LD.cell_center(near.x, near.y)
		L.add_deco({"k": "async", "what": "case", "p": Vector3(c3.x + 0.5, 0, c3.y + 0.3), "r": 0.4})
	else:
		L.add_deco({"k": "graf", "key": "graf.pits", "p": L.wall_point(x, z, 3, 0.0) + Vector3(0, 1.5, 0), "r": LD.dir_yaw(3)})
	var pc := LD.cell_center(x + w / 2, z + h / 2)
	if not L.places.has("pits"):
		L.places["pits"] = []
	(L.places["pits"] as Array).append(Vector2i(x + w / 2, z + h / 2))


static func _camp(L: LayerData, x: int, z: int) -> void:
	L.stamp_room(x, z, 5, 4, LD.Z_YELLOW, 2)
	for i in 5:
		for j in 4:
			L.light[LD.idx(x + i, z + j)] = LD.L_DEAD if (i + j) % 2 == 0 else LD.L_NONE
	L.light[LD.idx(x + 3, z + 1)] = LD.L_FLICK
	var c := LD.cell_center(x + 2, z + 2)
	L.add_deco({"k": "async", "what": "radio", "p": Vector3(c.x - 0.6, 0, c.y + 0.2), "r": 0.6})
	L.add_deco({"k": "async", "what": "tripod", "p": Vector3(c.x + 0.8, 0, c.y - 0.8), "r": 2.3})
	L.add_deco({"k": "async", "what": "case_open", "p": Vector3(c.x + 0.4, 0, c.y + 0.9), "r": -0.4})
	L.add_deco({"k": "async", "what": "lamp_stand_off", "p": Vector3(c.x - 1.5, 0, c.y - 1.0), "r": 1.3, "fallen": true})
	L.add_deco({"k": "async", "what": "spool", "p": Vector3(c.x + 1.6, 0, c.y + 0.6), "r": 0.0})
	L.add_deco({"k": "note", "key": "note.a_field", "p": Vector3(c.x - 0.2, 0.02, c.y - 0.3), "r": 1.1, "clip": true})
	L.add_deco({"k": "async", "what": "gasmask", "p": Vector3(c.x + 1.1, 0, c.y - 0.2), "r": 2.0})
	L.add_deco({"k": "stain", "p": Vector3(c.x + 0.2, 0, c.y + 0.1), "r": 0.0, "s": 1.6})
	L.places["camp_cell"] = Vector2i(x + 2, z + 2)
	L.places["camp"] = Vector3(c.x, 0, c.y)


static func _nullroom(L: LayerData, x: int, z: int, name: String) -> void:
	L.stamp_room(x, z, 3, 3, LD.Z_DARK, 2, LD.E_ARCH)
	for i in 3:
		for j in 3:
			L.light[LD.idx(x + i, z + j)] = LD.L_DEAD if (i + j) % 2 == 0 else LD.L_NONE
	L.light[LD.idx(x + 1, z + 1)] = LD.L_GREEN
	var c := LD.cell_center(x + 1, z + 1)
	var p := Vector3(c.x, L.floor_y, c.y)
	L.add_deco({"k": "null", "p": p, "r": 0.0, "id": name})
	L.places[name] = p
	# следы: обгоревший ковёр, «рулетка» прошлого исследователя
	L.add_deco({"k": "stain", "p": p + Vector3(0.3, 0, -0.2), "r": 0.0, "s": 2.4, "burn": true})


static func _stretch(L: LayerData, x: int, z: int) -> void:
	L.stamp_room(x, z, 8, 5, LD.Z_STRETCH, 0)
	var door := L._open_border(x, z, 8, 5, 1, LD.E_DOOR)
	for i in 8:
		for j in 5:
			L.ceil_h[LD.idx(x + i, z + j)] = 74
	# зелёная лампа над дверью снаружи
	var out := door + Vector2i(0, 1)
	L.light[LD.idx(out.x, out.y)] = LD.L_GREEN
	var c := LD.cell_center(x + 4, z + 2)
	L.add_deco({"k": "obj", "what": "hill_chair", "p": Vector3(c.x - 1.2, 0, c.y), "r": 0.4, "wrong": "none"})
	L.add_deco({"k": "obj", "what": "desk", "p": Vector3(c.x + 2.5, -0.45, c.y - 1.5), "r": 0.2, "wrong": "sink"})
	L.add_deco({"k": "obj", "what": "ochair", "p": L.wall_point(x + 1, z + 1, 2, -0.25), "r": LD.dir_yaw(2) + 0.3, "wrong": "wall"})
	L.add_deco({"k": "obj", "what": "cabinet", "p": L.wall_point(x + 6, z, 3, -0.3), "r": LD.dir_yaw(3), "wrong": "wall"})
	L.add_deco({"k": "obj", "what": "chair", "p": Vector3(c.x + 4.0, 3.4, c.y + 0.5), "r": 1.0, "wrong": "ceiling"})
	L.add_deco({"k": "copy", "who": "civ_b", "wrong": "hstretch", "p": L.wall_point(x + 3, z + 4, 1, 0.05), "r": LD.dir_yaw(1), "seed": L.rng.randi()})
	L.add_deco({"k": "sound", "snd": "screech_far", "p": Vector3(c.x, 3.0, c.y), "every": 40.0})
	L.places["stretch"] = Vector3(c.x, 0, c.y)


static func _park_room(L: LayerData, x: int, z: int, w: int, h: int, kind: String) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 2 if w * h > 6 else 1)
	if w == 2 or h == 2:
		# коридоры: открыть оба торца
		if w == 2:
			L.wall_s[LD.idx(x, z - 1)] = LD.E_OPEN
			L.wall_s[LD.idx(x + 1, z + h - 1)] = LD.E_ARCH
		else:
			L.wall_e[LD.idx(x - 1, z)] = LD.E_OPEN
			L.wall_e[LD.idx(x + w - 1, z + 1)] = LD.E_ARCH
	var c := LD.cell_center(x + w / 2, z + h / 2)
	var cx := c.x - (LD.C * 0.5 if w % 2 == 0 else 0.0)
	var cz := c.y - (LD.C * 0.5 if h % 2 == 0 else 0.0)
	var ctr := Vector3(cx, 0, cz)
	var rr := L.rng
	match kind:
		"benches":
			L.add_deco({"k": "obj", "what": "bench", "p": L.wall_point(x + 1, z, 3, -0.35), "r": LD.dir_yaw(3), "wrong": "wall"})
			L.add_deco({"k": "obj", "what": "bench", "p": L.wall_point(x + 3, z, 3, -0.1) + Vector3(0, 1.3, 0), "r": LD.dir_yaw(3), "wrong": "wall"})
			L.add_deco({"k": "obj", "what": "bench", "p": ctr + Vector3(0, 0, 0.6), "r": PI * 0.5, "wrong": "stretch"})
			L.add_deco({"k": "copy", "who": "oldman", "wrong": "melt_bench", "p": L.wall_point(x + w - 1, z + h - 1, 1, 0.3), "r": LD.dir_yaw(1), "seed": rr.randi()})
			L.add_deco({"k": "obj", "what": "bin", "p": ctr + Vector3(-1.6, 0, -0.8), "r": 0.0, "wrong": "stack"})
		"tree":
			L.add_deco({"k": "obj", "what": "tree", "p": ctr, "r": rr.randf() * TAU, "wrong": "wallpaper"})
			L.add_deco({"k": "grass", "p": ctr, "r": 0.0, "s": 3.2})
			L.add_deco({"k": "copy", "who": "kid", "wrong": "corner", "p": L.wall_point(x, z + h - 1, 2, 0.35), "r": LD.dir_yaw(2) + PI, "seed": rr.randi()})
			L.add_deco({"k": "sound", "snd": "birds_wrong", "p": ctr + Vector3(0, 2.3, 0), "every": 0.0})
		"icecream":
			L.add_deco({"k": "obj", "what": "cart", "p": L.wall_point(x + 1, z + 1, 2, -0.55), "r": LD.dir_yaw(2) + PI * 0.5, "wrong": "wall"})
			L.add_deco({"k": "copy", "who": "vendor", "wrong": "stretch", "p": ctr + Vector3(0.4, 0, -0.3), "r": LD.dir_yaw(0), "seed": rr.randi()})
			L.add_deco({"k": "sound", "snd": "jingle_wrong", "p": L.wall_point(x + 1, z + 1, 2, 0.2) + Vector3(0, 1, 0), "every": 0.0})
		"joggers":
			for k in 5:
				var cz2 := z + 1 + k * 2 if h > w else z
				var cx2 := x if h > w else x + 1 + k * 2
				var cc := LD.cell_center(cx2, cz2)
				L.add_deco({"k": "copy", "who": "jogger", "wrong": ["none", "stretch", "twist", "arms", "flat"][k], "p": Vector3(cc.x + 0.6, 0, cc.y),
					"r": 0.0 if h > w else PI * 0.5, "seed": rr.randi(), "pose": "run", "phase": k * 0.21})
		"fountain":
			L.add_deco({"k": "obj", "what": "fountain", "p": ctr, "r": 0.0, "wrong": "none"})
			L.add_deco({"k": "copy", "who": "kid", "wrong": "sunk", "p": ctr + Vector3(0.6, 0.35, 0.2), "r": 2.0, "seed": rr.randi()})
			L.add_deco({"k": "sound", "snd": "water_loop", "p": ctr + Vector3(0, 0.5, 0), "every": 0.0})
		"lamps":
			for k in 4:
				var cc2 := LD.cell_center(x + (k % 2), z + 1 + k * 2) if h > w else LD.cell_center(x + 1 + k * 2, z + (k % 2))
				L.add_deco({"k": "obj", "what": "lamp", "p": Vector3(cc2.x, 0, cc2.y), "r": rr.randf() * TAU, "wrong": ["tilt", "ceiling", "none", "stretch"][k]})
		"playground":
			L.add_deco({"k": "obj", "what": "slide", "p": L.wall_point(x + 2, z, 3, -0.6), "r": LD.dir_yaw(3) + PI, "wrong": "wall"})
			L.add_deco({"k": "obj", "what": "swing", "p": ctr + Vector3(1.5, 0, 0.5), "r": 0.3, "wrong": "ceiling"})
			L.add_deco({"k": "obj", "what": "balloon", "p": ctr + Vector3(-1.4, 2.45, -0.8), "r": 0.0, "wrong": "ceiling"})
			L.add_deco({"k": "copy", "who": "kid", "wrong": "stretch", "p": ctr + Vector3(-1.4, 0, -0.8), "r": 1.2, "seed": rr.randi()})
			L.add_deco({"k": "copy", "who": "kid", "wrong": "back", "p": ctr + Vector3(0.2, 0, 1.4), "r": -2.0, "seed": rr.randi()})
			L.add_deco({"k": "grass", "p": ctr, "r": 0.0, "s": 4.0})
		"car":
			L.add_deco({"k": "obj", "what": "car", "p": L.wall_point(x + 2, z, 3, 1.4), "r": LD.dir_yaw(3) + PI + 0.25, "wrong": "wall"})
			L.add_deco({"k": "stain", "p": ctr + Vector3(0.6, 0, 0.8), "r": 0.0, "s": 2.0, "tire": true})
			L.add_deco({"k": "sound", "snd": "engine_tick", "p": L.wall_point(x + 2, z, 3, 1.4) + Vector3(0, 0.6, 0), "every": 0.0})
		"picnic":
			L.add_deco({"k": "obj", "what": "blanket", "p": ctr, "r": rr.randf() * TAU, "wrong": "none"})
			L.add_deco({"k": "copy", "who": "couple", "wrong": "fused", "p": ctr + Vector3(0, 0, 0.2), "r": rr.randf() * TAU, "seed": rr.randi()})
		"stroller_room":
			L.add_deco({"k": "copy", "who": "mother", "wrong": "stroller_fused", "p": ctr, "r": rr.randf() * TAU, "seed": rr.randi()})
			L.add_deco({"k": "sound", "snd": "music_box", "p": ctr + Vector3(0, 0.8, 0), "every": 0.0})
	L.places["park_" + kind] = ctr


static func _cable_tags(L: LayerData) -> void:
	for z in LD.N:
		for x in LD.N:
			var i := z * LD.N + x
			var d := L.cable_dist[i]
			if d <= 0 or d % 9 != 4:
				continue
			var pd := L.cable_par[i]
			if pd < 0:
				continue
			var c := LD.cell_center(x, z)
			var sides := L.wall_sides(x, z)
			if sides.is_empty():
				L.add_deco({"k": "tag", "p": Vector3(c.x, L.floor_y, c.y), "r": LD.dir_yaw(pd), "dist": int(d * LD.C), "floor": true})
			else:
				var s: int = sides[0]
				L.add_deco({"k": "tag", "p": L.wall_point(x, z, s, 0.0) + Vector3(0, 1.25, 0), "r": LD.dir_yaw(s), "dist": int(d * LD.C), "dir": pd, "side": s})


## Россыпь: надписи, копии, кривые предметы, лужи, плесень, бумаги, записки
static func _scatter(L: LayerData, lay: int) -> void:
	var rr := L.rng
	var notes: Array = NOTES_L0 if lay == 0 else NOTES_L1
	var note_spots := []
	for k in notes.size():
		var a := rr.randf() * TAU
		var r := 9.0 + k * (14.0 if lay == 0 else 11.0) + rr.randf_range(0, 8)
		note_spots.append(Vector2i(int(cos(a) * r), int(sin(a) * r)))
	var origin := Vector2i(0, 0)
	if lay == 1 and L.places.has("drop_center"):
		origin = L.places["drop_center"]
	for k in notes.size():
		var s: Vector2i = note_spots[k] + origin
		var cell := L.find_cell_near(s.x, s.y, 10, func(x: int, z: int) -> bool: return L.is_plain(x, z) and L.light[LD.idx(x, z)] != LD.L_NONE)
		var c := LD.cell_center(cell.x, cell.y)
		L.add_deco({"k": "note", "key": notes[k], "p": Vector3(c.x + rr.randf_range(-0.6, 0.6), L.floor_y + 0.01, c.y + rr.randf_range(-0.6, 0.6)), "r": rr.randf() * TAU})
	var first_graf := ["graf.g01", "graf.g02", "graf.g03", "graf.g04"]
	var fg := 0
	for z in LD.N:
		for x in LD.N:
			var i := z * LD.N + x
			if L.flo[i] != LD.F_FLOOR:
				continue
			var zn := L.zone[i]
			if not (zn == LD.Z_YELLOW or zn == LD.Z_DARK or zn == LD.Z_OLD or zn == LD.Z_CONCRETE or zn == LD.Z_TILE):
				continue
			var dist := _dist0(x, z)
			if lay == 1 and L.places.has("drop_center"):
				var dc: Vector2i = L.places["drop_center"]
				dist = Vector2(_centered(posmod(x - dc.x, LD.N)), _centered(posmod(z - dc.y, LD.N))).length()
			var cx := _centered(x)
			var cz := _centered(z)
			var c := LD.cell_center(cx, cz)
			var r := rr.randf()
			# надписи на стенах
			var gp := 1.0 / 260.0
			if lay == 0 and dist < 30.0 and dist > 3.0:
				gp = 1.0 / 70.0
			if r < gp:
				var sides := L.wall_sides(cx, cz)
				if not sides.is_empty():
					var s: int = sides[rr.randi_range(0, sides.size() - 1)]
					var key := "graf.g%02d" % rr.randi_range(5, GRAF_COUNT)
					if lay == 0 and dist < 30.0 and fg < first_graf.size():
						key = first_graf[fg]
						fg += 1
					elif lay == 1 and rr.randf() < 0.5:
						key = "graf.u%02d" % rr.randi_range(1, 10)
					L.add_deco({"k": "graf", "key": key, "p": L.wall_point(cx, cz, s, 0.0) + Vector3(0, rr.randf_range(1.1, 1.7), 0),
						"r": LD.dir_yaw(s), "along": rr.randf_range(-0.5, 0.5)})
				continue
			r -= gp
			# стрелки
			if r < 1.0 / 240.0:
				var sides2 := L.wall_sides(cx, cz)
				if not sides2.is_empty():
					var s2: int = sides2[0]
					L.add_deco({"k": "graf", "key": "graf.arrow", "p": L.wall_point(cx, cz, s2, 0.0) + Vector3(0, rr.randf_range(0.9, 1.5), 0),
						"r": LD.dir_yaw(s2), "flip": rr.randf() < 0.5})
				continue
			r -= 1.0 / 240.0
			# копии людей
			var cp := 1.0 / 560.0 if dist < 150 else 1.0 / 1400.0
			if lay == 1:
				cp = 1.0 / 650.0
			# в особых комнатах своя обстановка — копии и кривые предметы туда не ставим
			if r < cp and dist > 7.0 and L.used[i] == 0:
				var who: String
				if lay == 0 and rr.randf() < 0.7:
					who = PARK_PEOPLE[rr.randi_range(0, PARK_PEOPLE.size() - 1)]
				else:
					who = OTHER_PEOPLE[rr.randi_range(0, OTHER_PEOPLE.size() - 1)]
				var wrong: String = WRONG[rr.randi_range(0, WRONG.size() - 1)]
				var p := Vector3(c.x + rr.randf_range(-0.6, 0.6), L.floor_y, c.y + rr.randf_range(-0.6, 0.6))
				var rot := rr.randf() * TAU
				var sides3 := L.wall_sides(cx, cz)
				if (wrong == "wall" or wrong == "flat" or wrong == "corner") and not sides3.is_empty():
					var s3: int = sides3[0]
					var inset := -0.18 if wrong == "wall" else (0.06 if wrong == "flat" else 0.35)
					p = L.wall_point(cx, cz, s3, inset)
					rot = LD.dir_yaw(s3) + (PI if wrong == "corner" else 0.0)
				elif wrong == "wall" or wrong == "flat" or wrong == "corner":
					wrong = "stretch"
				L.add_deco({"k": "copy", "who": who, "wrong": wrong, "p": p, "r": rot, "seed": rr.randi(), "mold": lay == 1, "react": rr.randf() < 0.35})
				continue
			r -= cp
			# кривые предметы
			if r < 1.0 / 520.0 and dist > 5.0 and L.used[i] == 0:
				var what: String = OBJECTS[rr.randi_range(0, OBJECTS.size() - 1)]
				var ow: String = OBJ_WRONG[rr.randi_range(0, OBJ_WRONG.size() - 1)]
				var p2 := Vector3(c.x + rr.randf_range(-0.5, 0.5), L.floor_y, c.y + rr.randf_range(-0.5, 0.5))
				var rot2 := rr.randf() * TAU
				var sides4 := L.wall_sides(cx, cz)
				if ow == "wall":
					if sides4.is_empty():
						ow = "tilt"
					else:
						var s4: int = sides4[0]
						p2 = L.wall_point(cx, cz, s4, -0.3)
						rot2 = LD.dir_yaw(s4) + PI + rr.randf_range(-0.3, 0.3)
				L.add_deco({"k": "obj", "what": what, "p": p2, "r": rot2, "wrong": ow})
				continue
			r -= 1.0 / 520.0
			# лужи и пятна
			var pud := 1.0 / 22.0 if zn == LD.Z_DARK else 1.0 / 110.0
			if r < pud:
				L.add_deco({"k": "stain", "p": Vector3(c.x + rr.randf_range(-0.8, 0.8), L.floor_y, c.y + rr.randf_range(-0.8, 0.8)), "r": rr.randf() * TAU,
					"s": rr.randf_range(0.8, 2.2), "wet": zn == LD.Z_DARK or rr.randf() < 0.4})
				continue
			r -= pud
			# плесень на стенах
			var mp := 1.0 / 14.0 if (zn == LD.Z_DARK and lay == 1) else (1.0 / 45.0 if zn == LD.Z_DARK else 1.0 / 400.0)
			if r < mp:
				var sides5 := L.wall_sides(cx, cz)
				if not sides5.is_empty():
					var s5: int = sides5[rr.randi_range(0, sides5.size() - 1)]
					L.add_deco({"k": "mold", "p": L.wall_point(cx, cz, s5, 0.0) + Vector3(0, rr.randf_range(0.2, 1.6), 0), "r": LD.dir_yaw(s5),
						"along": rr.randf_range(-0.7, 0.7), "s": rr.randf_range(0.6, 1.8)})
				continue
			r -= mp
			# бумаги, мусор, офисная мебель
			if r < 1.0 / 160.0:
				L.add_deco({"k": "papers", "p": Vector3(c.x + rr.randf_range(-0.8, 0.8), L.floor_y, c.y + rr.randf_range(-0.8, 0.8)), "r": rr.randf() * TAU})
				continue
			r -= 1.0 / 160.0
			if zn == LD.Z_OLD and r < 1.0 / 30.0:
				var oo: String = ["chair", "desk", "cabinet", "ochair", "boxes", "shelf", "wetsign", "crate"][rr.randi_range(0, 7)]
				L.add_deco({"k": "obj", "what": oo, "p": Vector3(c.x + rr.randf_range(-0.5, 0.5), L.floor_y, c.y + rr.randf_range(-0.5, 0.5)),
					"r": rr.randf() * TAU, "wrong": "none" if rr.randf() < 0.7 else "tilt"})


# ======================================================================= слой 1

static func layer1(seed: int, l0: LayerData) -> LayerData:
	var L := LD.new()
	L.layer = 1
	L.seed = seed + 7919
	L.floor_y = -10.0
	L.rng.seed = seed + 7919
	L.init_arrays()
	var nz := FastNoiseLite.new()
	nz.seed = seed + 31
	nz.frequency = 0.028
	nz.fractal_octaves = 2
	for z in LD.N:
		for x in LD.N:
			var n := nz.get_noise_2d(x, z)
			var i := z * LD.N + x
			if n < -0.18:
				L.zone[i] = LD.Z_CONCRETE
				L.ceil_h[i] = 25
			elif n > 0.42:
				L.zone[i] = LD.Z_TILE
				L.ceil_h[i] = 28
			else:
				L.zone[i] = LD.Z_DARK
	L.divide(0, 0, LD.N, LD.N, 0.18)
	_prof("L.divide(0, 0, LD.N, LD.N, 0.18)")
	L.open_random_walls(0.04)
	# под ямами верхнего слоя — шахты и места падения
	var pits: Array = l0.places.get("pits", [])
	var first := Vector2i(0, 0)
	if not pits.is_empty():
		first = pits[0]
	L.places["drop_center"] = first
	for z in LD.N:
		for x in LD.N:
			var i := z * LD.N + x
			if l0.flo[i] != LD.F_PIT:
				continue
			L.flo[i] = LD.F_FLOOR
			L.ceil_h[i] = 0
			L.post[i] = 0
			for d in 4:
				var o: Vector2i = LD.DIRS[d]
				if l0.flo[LD.idx(x + o.x, z + o.y)] == LD.F_PIT:
					L.set_edge(x, z, d, LD.E_OPEN)
			if L.rng.randf() < 0.3:
				var c := LD.cell_center(_centered(x), _centered(z))
				L.add_deco({"k": "obj", "what": "debris", "p": Vector3(c.x, L.floor_y, c.y), "r": L.rng.randf() * TAU, "wrong": "none"})
	# комнаты под ямами — расчистить стены вокруг мест падения (3×3)
	for pp in pits:
		var pc: Vector2i = pp
		for dz in range(-4, 5):
			for dx in range(-4, 5):
				var xx := pc.x + dx
				var zz := pc.y + dz
				if absi(dx) < 4:
					L.wall_e[LD.idx(xx, zz)] = LD.E_OPEN if absi(dz) < 4 else L.wall_e[LD.idx(xx, zz)]
				if absi(dz) < 4:
					L.wall_s[LD.idx(xx, zz)] = LD.E_OPEN if absi(dx) < 4 else L.wall_s[LD.idx(xx, zz)]
				L.zone[LD.idx(xx, zz)] = LD.Z_DARK
				if L.ceil_h[LD.idx(xx, zz)] != 0:
					L.ceil_h[LD.idx(xx, zz)] = 27
	# лестницы Async под лебёдками
	for k in 2:
		var key := "winch_%d" % k
		if not l0.places.has(key):
			continue
		var wp: Vector3 = l0.places[key]
		var wc := Vector2i(int(floor(wp.x / LD.C)), int(floor(wp.z / LD.C)))
		var lp := Vector3(wp.x, L.floor_y, wp.z)
		L.add_deco({"k": "async", "what": "ladder", "p": lp, "r": 0.0, "to": key})
		L.places["ladder_%d" % k] = lp
		L.places["ladder_cell_%d" % k] = wc
		var c2 := LD.cell_center(wc.x + 1, wc.y)
		L.add_deco({"k": "async", "what": "lamp_stand", "p": Vector3(c2.x, L.floor_y, c2.y), "r": 0.5})
		L.light[LD.idx(wc.x + 1, wc.y)] = LD.L_ASYNC
	# особые места
	var sk := L.pick_spot(first.x, first.y, 24, 46, 24, 3)
	_skywalk(L, sk.x, sk.y)
	var hs := L.pick_spot(first.x, first.y, 30, 60, 8, 6)
	_house(L, hs.x, hs.y)
	var me := L.pick_spot(first.x, first.y, 40, 75, 3, 3)
	_selfroom(L, me.x, me.y)
	for k in 2:
		var ns := L.pick_spot(first.x, first.y, 18 + k * 25, 40 + k * 25, 4, 4)
		_nest(L, ns.x, ns.y, k)
	var nidx := 0
	for pp in pits:
		var pc2: Vector2i = pp
		var q := L.pick_spot(pc2.x, pc2.y, 18, 42, 3, 3)
		_nullroom(L, q.x, q.y, "null_%d" % nidx)
		nidx += 1
	var q2 := L.pick_spot(first.x, first.y, 40, 80, 3, 3)
	_nullroom(L, q2.x, q2.y, "null_%d" % nidx)
	for k in 3:
		var ss := L.pick_spot(first.x, first.y, 20 + k * 12, 40 + k * 15, 2, 2)
		L.places["stalker_%d" % k] = Vector3(LD.cell_center(ss.x, ss.y).x, L.floor_y, LD.cell_center(ss.x, ss.y).y)
	Rooms.place_all(L, 1, first)
	_prof("Rooms.place_all(L, 1, first)")
	L.place_lights(0.0)
	L.fix_connectivity(first.x, first.y)
	_prof("L.fix_connectivity(first.x, first.y)")
	# кабели от лестниц
	for k in 2:
		var key2 := "ladder_cell_%d" % k
		if not L.places.has(key2):
			continue
		var lc: Vector2i = L.places[key2]
		var ends := []
		for j in 4:
			var a := L.rng.randf() * TAU
			var r2 := L.rng.randf_range(30, 70)
			ends.append(L.find_cell_near(lc.x + int(cos(a) * r2), lc.y + int(sin(a) * r2), 10, func(x: int, z: int) -> bool: return L.is_plain(x, z)))
		L.lay_cables(lc.x, lc.y, ends)
	_cable_tags(L)
	_scatter(L, 1)
	_prof("_scatter(L, 1)")
	Rooms.sprinkle(L, 1, first)
	_prof("Rooms.sprinkle(L, 1, first)")
	return L


static func _skywalk(L: LayerData, x: int, z: int) -> void:
	# переход: 24×2 клетки, на севере — окна на «Красный город», за ними пустота
	var w := 24
	for i in range(-2, w + 2):
		for j in range(-34, 0):
			var ci := LD.idx(x + i, z + j)
			L.flo[ci] = LD.F_SOLID
			L.zone[ci] = LD.Z_SKY
			L.light[ci] = LD.L_NONE
			L.post[ci] = 0
	L.stamp_room(x, z, w, 2, LD.Z_SKY, 0)
	for i in w:
		L.wall_s[LD.idx(x + i, z - 1)] = LD.E_WINDOW
		L.ceil_h[LD.idx(x + i, z)] = 30
		L.ceil_h[LD.idx(x + i, z + 1)] = 30
		L.light[LD.idx(x + i, z + 1)] = (LD.L_ON if i % 3 == 0 else (LD.L_FLICK if i % 3 == 1 else LD.L_NONE))
	# граница пустоты — глухие стены
	for i in range(-3, w + 3):
		for j in range(-35, 1):
			var a := LD.idx(x + i, z + j)
			for d in 4:
				var o: Vector2i = LD.DIRS[d]
				var b := LD.idx(x + i + o.x, z + j + o.y)
				if (L.flo[a] == LD.F_SOLID) != (L.flo[b] == LD.F_SOLID):
					var cur := L.edge(x + i, z + j, d)
					if cur != LD.E_WINDOW:
						L.set_edge(x + i, z + j, d, LD.E_WALL)
	for k in 3:
		L.wall_s[LD.idx(x + 3 + k * 8, z + 1)] = LD.E_DOOR
	L.wall_e[LD.idx(x - 1, z + 1)] = LD.E_ARCH
	L.wall_e[LD.idx(x + w - 1, z)] = LD.E_ARCH
	var c := LD.cell_center(x + w / 2, z - 17)
	L.add_deco({"k": "red_city", "p": Vector3(c.x, L.floor_y, c.y), "r": 0.0, "w": (w + 4) * LD.C, "d": 34 * LD.C})
	L.places["skywalk"] = Vector3(LD.cell_center(x + w / 2, z).x, L.floor_y, LD.cell_center(x + w / 2, z).y)


static func _house(L: LayerData, x: int, z: int) -> void:
	L.stamp_room(x, z, 6, 5, LD.Z_HOUSE, 0)
	for i in 6:
		for j in 5:
			L.ceil_h[LD.idx(x + i, z + j)] = 26
			L.light[LD.idx(x + i, z + j)] = LD.L_NONE
	# перегородки: гостиная (3×5 запад) | кухня (3×3 СВ) / прихожая с лестницей (3×2 ЮВ)
	for j in 5:
		L.wall_e[LD.idx(x + 2, z + j)] = LD.E_WALL
	L.wall_e[LD.idx(x + 2, z + 1)] = LD.E_DOOR
	L.wall_e[LD.idx(x + 2, z + 3)] = LD.E_DOOR
	for i in range(3, 6):
		L.wall_s[LD.idx(x + i, z + 2)] = LD.E_WALL
	L.wall_s[LD.idx(x + 4, z + 2)] = LD.E_DOOR
	# входы из Комплекса
	L.wall_e[LD.idx(x - 1, z + 2)] = LD.E_DOOR
	L.wall_s[LD.idx(x + 4, z + 4)] = LD.E_DOOR
	L.light[LD.idx(x + 1, z + 1)] = LD.L_BULB
	L.light[LD.idx(x + 1, z + 3)] = LD.L_FLICK
	L.light[LD.idx(x + 4, z + 1)] = LD.L_BULB
	L.light[LD.idx(x + 4, z + 3)] = LD.L_NONE
	# запертая комнатка за стеной (2×2), без дверей
	for i in 2:
		for j in 2:
			var ci := LD.idx(x + 6 + i, z + 1 + j)
			L.zone[ci] = LD.Z_HOUSE
			L.light[ci] = LD.L_NONE
	for i in 2:
		L.wall_s[LD.idx(x + 6 + i, z)] = LD.E_WALL
		L.wall_s[LD.idx(x + 6 + i, z + 2)] = LD.E_WALL
	for j in 2:
		L.wall_e[LD.idx(x + 5, z + 1 + j)] = LD.E_WALL
		L.wall_e[LD.idx(x + 7, z + 1 + j)] = LD.E_WALL
	L.wall_e[LD.idx(x + 6, z + 1)] = LD.E_OPEN
	L.wall_e[LD.idx(x + 6, z + 2)] = LD.E_OPEN
	L.wall_s[LD.idx(x + 6, z + 1)] = LD.E_OPEN
	L.wall_s[LD.idx(x + 7, z + 1)] = LD.E_OPEN
	var lv := LD.cell_center(x + 1, z + 2)
	var kt := LD.cell_center(x + 4, z + 1)
	var hl := LD.cell_center(x + 4, z + 3)
	var y := L.floor_y
	L.add_deco({"k": "house", "what": "sofa", "p": Vector3(lv.x - 1.6, y, lv.y + 0.3), "r": PI * 0.5})
	L.add_deco({"k": "house", "what": "armchair", "p": Vector3(lv.x + 0.8, y, lv.y + 2.6), "r": PI * 1.2})
	L.add_deco({"k": "house", "what": "tv", "p": Vector3(lv.x + 1.6, y, lv.y + 0.2), "r": -PI * 0.5})
	L.add_deco({"k": "house", "what": "rug", "p": Vector3(lv.x, y, lv.y + 0.2), "r": 0.0})
	L.add_deco({"k": "house", "what": "floorlamp", "p": Vector3(lv.x - 1.7, y, lv.y - 2.2), "r": 0.0})
	L.add_deco({"k": "house", "what": "frame", "p": L.wall_point(x, z + 1, 2, 0.0) + Vector3(0, 1.55, 0), "r": LD.dir_yaw(2)})
	L.add_deco({"k": "house", "what": "counter", "p": L.wall_point(x + 4, z, 3, 0.35), "r": LD.dir_yaw(3) + PI})
	L.add_deco({"k": "house", "what": "fridge", "p": L.wall_point(x + 5, z, 3, 0.4), "r": LD.dir_yaw(3) + PI})
	L.add_deco({"k": "house", "what": "table", "p": Vector3(kt.x, y, kt.y + 1.4), "r": 0.0})
	L.add_deco({"k": "house", "what": "stairs", "p": Vector3(hl.x + 1.1, y, hl.y - 0.3), "r": 0.0})
	L.add_deco({"k": "house", "what": "clock", "p": L.wall_point(x + 1, z + 4, 1, 0.0) + Vector3(0, 1.9, 0), "r": LD.dir_yaw(1)})
	L.add_deco({"k": "house", "what": "stove", "p": L.wall_point(x + 3, z, 3, 0.35), "r": LD.dir_yaw(3) + PI})
	L.add_deco({"k": "house", "what": "microwave", "p": L.wall_point(x + 4, z, 3, 0.3) + Vector3(0.4, 0.94, 0), "r": LD.dir_yaw(3) + PI})
	L.add_deco({"k": "house", "what": "phone", "p": L.wall_point(x + 3, z + 4, 1, 0.1) + Vector3(0, 1.2, 0), "r": LD.dir_yaw(1)})
	L.add_deco({"k": "voice_wall", "p": L.wall_point(x + 5, z + 1, 0, 0.0) + Vector3(0, 1.3, 0), "r": LD.dir_yaw(0)})
	L.places["house"] = Vector3(lv.x, y, lv.y)


static func _selfroom(L: LayerData, x: int, z: int) -> void:
	L.stamp_room(x, z, 3, 3, LD.Z_YELLOW, 0)
	var door := L._open_border(x, z, 3, 3, 1, LD.E_DOOR)
	for i in 3:
		for j in 3:
			L.light[LD.idx(x + i, z + j)] = LD.L_NONE
	L.light[LD.idx(x + 1, z + 1)] = LD.L_ON
	var c := LD.cell_center(x + 1, z)
	L.add_deco({"k": "copy_self", "p": Vector3(c.x, L.floor_y, c.y + 0.35), "r": LD.dir_yaw(3)})
	L.places["self"] = Vector3(c.x, L.floor_y, c.y)


static func _nest(L: LayerData, x: int, z: int, k: int) -> void:
	L.stamp_room(x, z, 4, 4, LD.Z_DARK, 2, LD.E_OPEN)
	for i in 4:
		for j in 4:
			L.light[LD.idx(x + i, z + j)] = LD.L_DEAD if (i + j) % 2 == 0 else LD.L_NONE
	var c := LD.cell_center(x + 2, z + 2)
	var p := Vector3(c.x - LD.C * 0.5, L.floor_y, c.y - LD.C * 0.5)
	L.add_deco({"k": "nest", "p": p, "r": L.rng.randf() * TAU})
	for m in 6:
		var side := m % 4
		L.add_deco({"k": "mold", "p": L.wall_point(x + (m % 3), z + (m % 4), side, 0.0) + Vector3(0, L.rng.randf_range(0.3, 2.0), 0), "r": LD.dir_yaw(side),
			"along": L.rng.randf_range(-0.6, 0.6), "s": L.rng.randf_range(1.2, 2.4)})
	L.places["nest_%d" % k] = p
