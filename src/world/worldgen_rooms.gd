extends RefCounted
## Каталог «странных комнат» Комплекса. Всего понемногу: большая часть мира — пустые жёлтые коридоры.

const LD := preload("res://src/world/layer_data.gd")

## [тип, слой (0/1/-1 оба), сколько, rmin, rmax, w, h]
const PLAN := [
	["pillar_hall", 0, 2, 14, 120, 12, 12], ["megahall", 0, 1, 40, 130, 16, 16], ["lightpool", 0, 1, 30, 110, 9, 9],
	["crawl", -1, 2, 16, 100, 1, 7], ["giant", 0, 1, 45, 120, 8, 7], ["narrow", 0, 1, 25, 110, 2, 9],
	["doors", 0, 1, 20, 100, 5, 5], ["chairs", 0, 1, 25, 110, 6, 6], ["flip", 0, 1, 35, 120, 5, 4],
	["side", 0, 1, 30, 115, 4, 4], ["cubicles", 0, 2, 18, 110, 7, 6], ["classroom", 0, 1, 30, 110, 6, 5],
	["residence", -1, 1, 35, 120, 4, 4], ["store", 0, 1, 50, 125, 10, 8], ["survey", 0, 1, 20, 90, 3, 3],
	["tvroom", -1, 1, 25, 110, 4, 4], ["phone", 0, 1, 30, 115, 5, 5], ["vending", 0, 1, 20, 100, 1, 6],
	["repeat", 0, 1, 30, 110, 9, 3], ["stairs", -1, 1, 20, 110, 2, 4], ["flooded", -1, 2, 25, 110, 8, 7],
	["exit", 0, 2, 15, 100, 2, 2], ["storage", -1, 1, 25, 115, 6, 5], ["body", 1, 1, 20, 70, 4, 4],
	["speakers", 1, 1, 25, 80, 5, 5], ["pool", 1, 1, 30, 80, 8, 6],
	# перепады высот: залы, провалы, лестницы, пандусы, дыры
	["sunken", -1, 2, 14, 100, 14, 12], ["terrace", 0, 2, 18, 110, 12, 11], ["chasm", -1, 1, 22, 110, 12, 9],
	["stairwell", -1, 2, 12, 100, 2, 9], ["ramp", -1, 2, 12, 100, 2, 12], ["holes", -1, 2, 15, 100, 8, 8],
	["atrium", 0, 1, 26, 120, 12, 12], ["tall_hall", 0, 2, 20, 120, 20, 16], ["well", -1, 1, 30, 120, 12, 12],
	# обжитые и странные места — по одному
	["waiting", 0, 1, 16, 110, 8, 6], ["lounge", 0, 1, 20, 115, 9, 7], ["party", -1, 1, 25, 110, 6, 6],
	["conference", 0, 1, 18, 110, 8, 5], ["archive", 0, 1, 24, 115, 9, 8], ["elevators", 0, 1, 16, 110, 6, 4],
	["mannequins", -1, 1, 28, 115, 7, 7], ["kitchen", 0, 1, 18, 110, 5, 5], ["bedroom", -1, 1, 30, 120, 10, 10],
	["fans", -1, 1, 24, 110, 8, 6], ["laundry", 0, 1, 18, 110, 6, 5], ["pillar_forest", -1, 1, 24, 115, 14, 14],
	["windows", 0, 1, 24, 115, 9, 9], ["museum", 0, 1, 28, 120, 8, 6], ["rain", -1, 1, 24, 110, 7, 6],
	["lowmaze", 0, 1, 24, 115, 12, 10],
	# спуски и странные коридоры
	["hotel", 0, 2, 14, 110, 1, 24], ["descent", -1, 2, 16, 110, 2, 22], ["funnel", 0, 1, 24, 115, 12, 12],
	["slope_hall", -1, 1, 20, 110, 10, 8], ["amphitheater", 0, 1, 26, 115, 10, 9], ["drop_end", -1, 2, 14, 110, 2, 12],
	["stairs_door", 0, 1, 16, 110, 5, 5], ["water_stairs", -1, 1, 22, 110, 6, 10], ["updown", -1, 2, 14, 110, 1, 20],
	["ceiling_doors", 0, 1, 20, 110, 6, 6], ["split_level", 0, 1, 20, 110, 10, 8], ["crooked", -1, 2, 14, 110, 2, 16],
]


static func place_all(L: LayerData, lay: int, origin: Vector2i) -> void:
	for e in PLAN:
		var p: Array = e
		var ly: int = p[1]
		if ly != -1 and ly != lay:
			continue
		var n: int = p[2]
		if lay == 1 and ly == -1:
			n = maxi(1, n - 1)
		for k in n:
			var w: int = p[5]
			var h: int = p[6]
			if (w == 1 or h == 1 or String(p[0]) in ["repeat", "stairwell", "ramp", "descent", "drop_end", "crooked"]) and L.rng.randf() < 0.5:
				var t := w
				w = h
				h = t
			var s := L.pick_spot(origin.x, origin.y, int(p[3]) if lay == 0 else int(p[3]) / 2, int(p[4]) if lay == 0 else int(p[4]) * 2 / 3, w, h)
			if not L.area_free(s.x, s.y, w, h):
				continue
			call_room(String(p[0]), L, s.x, s.y, w, h, lay)
			var c := LD.cell_center(s.x + w / 2, s.y + h / 2)
			L.places["room_%s_%d" % [p[0], k]] = Vector3(c.x, L.floor_y, c.y)
			L.places["room_%s_%d_c" % [p[0], k]] = Vector3(c.x, L.floor_y + L.fh[LD.idx(s.x + w / 2, s.y + h / 2)] * 0.1, c.y)
			# у конструкций с перепадом — точка на верхнем краю, у входа
			if L.places.has("_entry"):
				L.places["room_%s_%d" % [p[0], k]] = L.places["_entry"]
				L.places.erase("_entry")
	sprinkle_holes(L, lay, origin)
	sprinkle_finds(L, lay, origin)
	sprinkle_stains(L, lay, origin)


static func call_room(t: String, L: LayerData, x: int, z: int, w: int, h: int, lay: int) -> void:
	match t:
		"pillar_hall": pillar_hall(L, x, z, w, h)
		"megahall": megahall(L, x, z, w, h)
		"lightpool": lightpool(L, x, z, w, h)
		"crawl": crawl(L, x, z, w, h)
		"giant": giant(L, x, z, w, h)
		"narrow": narrow(L, x, z, w, h)
		"doors": doors(L, x, z, w, h)
		"chairs": chairs(L, x, z, w, h)
		"flip": flip(L, x, z, w, h)
		"side": side(L, x, z, w, h)
		"cubicles": cubicles(L, x, z, w, h)
		"classroom": classroom(L, x, z, w, h)
		"residence": residence(L, x, z, w, h, lay)
		"store": store(L, x, z, w, h)
		"survey": survey(L, x, z, w, h)
		"tvroom": tvroom(L, x, z, w, h)
		"phone": phone(L, x, z, w, h)
		"vending": vending(L, x, z, w, h)
		"repeat": repeat(L, x, z, w, h)
		"stairs": stairs(L, x, z, w, h)
		"flooded": flooded(L, x, z, w, h)
		"exit": exit_alcove(L, x, z, w, h)
		"storage": storage(L, x, z, w, h)
		"body": body(L, x, z, w, h)
		"speakers": speakers(L, x, z, w, h)
		"pool": pool(L, x, z, w, h)
		"sunken": sunken(L, x, z, w, h)
		"terrace": terrace(L, x, z, w, h)
		"chasm": chasm(L, x, z, w, h)
		"stairwell": stairwell(L, x, z, w, h)
		"ramp": ramp_room(L, x, z, w, h)
		"holes": holes(L, x, z, w, h)
		"atrium": atrium(L, x, z, w, h)
		"tall_hall": tall_hall(L, x, z, w, h)
		"well": well(L, x, z, w, h)
		"waiting": waiting(L, x, z, w, h)
		"lounge": lounge(L, x, z, w, h)
		"party": party(L, x, z, w, h)
		"conference": conference(L, x, z, w, h)
		"archive": archive(L, x, z, w, h)
		"elevators": elevators(L, x, z, w, h)
		"mannequins": mannequins(L, x, z, w, h)
		"kitchen": kitchen(L, x, z, w, h)
		"bedroom": bedroom(L, x, z, w, h)
		"fans": fans(L, x, z, w, h)
		"laundry": laundry(L, x, z, w, h)
		"pillar_forest": pillar_forest(L, x, z, w, h)
		"windows": windows(L, x, z, w, h)
		"museum": museum(L, x, z, w, h)
		"rain": rain_room(L, x, z, w, h)
		"lowmaze": lowmaze(L, x, z, w, h)
		"hotel": hotel(L, x, z, w, h)
		"descent": descent(L, x, z, w, h)
		"funnel": funnel(L, x, z, w, h)
		"slope_hall": slope_hall(L, x, z, w, h)
		"amphitheater": amphitheater(L, x, z, w, h)
		"drop_end": drop_end(L, x, z, w, h)
		"stairs_door": stairs_door(L, x, z, w, h)
		"water_stairs": water_stairs(L, x, z, w, h)
		"updown": updown(L, x, z, w, h)
		"ceiling_doors": ceiling_doors(L, x, z, w, h)
		"split_level": split_level(L, x, z, w, h)
		"crooked": crooked(L, x, z, w, h)


# ------------------------------------------------------------ помощники

## Масштаб potted_plant_04 (у модели 27 см — настольный цветок): напольный фикус ~0,95 м
const PLANT_S := 3.5


static func _c(L: LayerData, x: int, z: int) -> Vector3:
	var c := LD.cell_center(x, z)
	return Vector3(c.x, L.floor_y, c.y)


static func _mid(L: LayerData, x: int, z: int, w: int, h: int) -> Vector3:
	return Vector3((x + w * 0.5) * LD.C, L.floor_y, (z + h * 0.5) * LD.C)


static func _lights(L: LayerData, x: int, z: int, w: int, h: int, state: int, checker := true, dense := false) -> void:
	for i in w:
		for j in h:
			var ci := LD.idx(x + i, z + j)
			L.used[ci] = 2
			if dense or not checker or (x + i + z + j) % 2 == 0:
				L.light[ci] = state
			else:
				L.light[ci] = LD.L_NONE


static func _open(L: LayerData, x: int, z: int, w: int, h: int, n: int, kind := LD.E_ARCH) -> void:
	for k in n:
		L._open_border(x, z, w, h, k % 4 if n >= 4 else L.rng.randi_range(0, 3), kind)


static func _graf(L: LayerData, x: int, z: int, side: int, key: String, y := 1.4, along := 0.0) -> void:
	L.add_deco({"k": "graf", "key": key, "p": L.wall_point(x, z, side, 0.0) + Vector3(0, y, 0), "r": LD.dir_yaw(side), "along": along})


## Модель в мир. ex — доп. ключи описания: "on": [id опоры, масштаб опоры по y] — поставить на верх опоры
## (p — на полу под ней), "ground": true — низом на пол, "price": "…" — ценник на стойке рядом
static func _model(L: LayerData, id: String, p: Vector3, r: float, s: Variant = 1.0, collide := true, y := 0.0, ex := {}) -> void:
	var d := {"k": "model", "id": id, "p": p, "r": r, "s": s, "collide": collide, "y": y}
	d.merge(ex)
	L.add_deco(d)


# ------------------------------------------------------------ комнаты

## Бесконечный зал колонн: пусто, ровный свет, гул
static func pillar_hall(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_open(L, x, z, w, h, 4, LD.E_OPEN)
	_open(L, x, z, w, h, 2, LD.E_ARCH)
	for i in range(2, w - 1, 2):
		for j in range(2, h - 1, 2):
			L.post[LD.idx(x + i, z + j)] = 1
	_lights(L, x, z, w, h, LD.L_ON)
	if L.rng.randf() < 0.6:
		L.add_deco({"k": "obj", "what": "chair", "p": _c(L, x + w / 2, z + h / 2 + 1), "r": L.rng.randf() * TAU, "wrong": "none"})


## Огромный пустой зал с низким потолком: почти без стен, редкий свет
static func megahall(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	for k in 6:
		L._open_border(x, z, w, h, k % 4, LD.E_OPEN)
	for i in w:
		for j in h:
			L.ceil_h[LD.idx(x + i, z + j)] = 24
	for i in range(4, w - 1, 4):
		for j in range(4, h - 1, 4):
			L.post[LD.idx(x + i, z + j)] = 1
	for i in w:
		for j in h:
			var ci := LD.idx(x + i, z + j)
			L.used[ci] = 2
			L.light[ci] = LD.L_ON if (i % 3 == 0 and j % 3 == 0) else (LD.L_DEAD if (i + j) % 4 == 0 else LD.L_NONE)


## Тёмный зал, единственная лампа над стулом посередине
static func lightpool(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_DARK, 0)
	_open(L, x, z, w, h, 2, LD.E_ARCH)
	_lights(L, x, z, w, h, LD.L_DEAD)
	L.light[LD.idx(x + w / 2, z + h / 2)] = LD.L_ON
	L.add_deco({"k": "obj", "what": "chair", "p": _c(L, x + w / 2, z + h / 2), "r": L.rng.randf() * TAU, "wrong": "none"})


## Низкий лаз: потолок 1.3 м, пролезть только пригнувшись (Сущность туда не пролезает)
static func crawl(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	var horiz := w > h
	if horiz:
		L.wall_e[LD.idx(x - 1, z)] = LD.E_OPEN
		L.wall_e[LD.idx(x + w - 1, z)] = LD.E_OPEN
	else:
		L.wall_s[LD.idx(x, z - 1)] = LD.E_OPEN
		L.wall_s[LD.idx(x, z + h - 1)] = LD.E_OPEN
	var n := maxi(w, h)
	for k in n:
		var cx := x + (k if horiz else 0)
		var cz := z + (0 if horiz else k)
		var ci := LD.idx(cx, cz)
		L.used[ci] = 2
		if k > 0 and k < n - 1:
			L.ceil_h[ci] = 13
		L.light[ci] = LD.L_ON if k % 2 == 1 else LD.L_NONE
	var side := 1 if horiz else 0
	_graf(L, x, z, side, "graf.crawl", 0.9)


## Огромная комната: потолок 9 м, предметы великанского размера
static func giant(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	L._open_border(x, z, w, h, 1, LD.E_DOOR)
	L._open_border(x, z, w, h, 2, LD.E_DOOR)
	for i in w:
		for j in h:
			L.ceil_h[LD.idx(x + i, z + j)] = 90
	_lights(L, x, z, w, h, LD.L_ON)
	var m := _mid(L, x, z, w, h)
	L.add_deco({"k": "giant", "what": "chair", "p": m + Vector3(-2.5, 0, 1.0), "r": 0.4})
	L.add_deco({"k": "giant", "what": "table", "p": m + Vector3(3.0, 0, -2.5), "r": -0.2})
	L.add_deco({"k": "giant", "what": "outlet", "p": L.wall_point(x + w / 2, z, 3, 0.0) + Vector3(0, 1.1, 0), "r": LD.dir_yaw(3)})
	L.add_deco({"k": "door", "kind": "giant", "p": L.wall_point(x, z + h / 2, 2, 0.0), "r": LD.dir_yaw(2)})
	L.add_deco({"k": "door", "kind": "tiny", "p": L.wall_point(x + w - 1, z + 2, 0, 0.0), "r": LD.dir_yaw(0)})


## Коридор, который сужается, а в конце — крошечная дверь
static func narrow(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_ceil_all(L, x, z, w, h, 27)
	var along_z := h > w
	if along_z:
		L.wall_s[LD.idx(x, z - 1)] = LD.E_OPEN
		L.wall_s[LD.idx(x + 1, z - 1)] = LD.E_OPEN
	else:
		L.wall_e[LD.idx(x - 1, z)] = LD.E_OPEN
		L.wall_e[LD.idx(x - 1, z + 1)] = LD.E_OPEN
	var n := maxi(w, h)
	_lights(L, x, z, w, h, LD.L_ON, false)
	for k in range(2, n):
		var th := 0.25 + (k - 2) * 0.27
		var c := _mid(L, x, z, w, h)
		var t := (k + 0.5) * LD.C
		for s in [-1.0, 1.0]:
			var off: float = (LD.C - th * 0.5 - 0.1) * float(s)
			var p := Vector3(x * LD.C + LD.C + off, L.floor_y, z * LD.C + t) if along_z else Vector3(x * LD.C + t, L.floor_y, z * LD.C + LD.C + off)
			L.add_deco({"k": "panel", "p": p, "r": 0.0 if along_z else PI * 0.5, "size": Vector3(th, 2.7, LD.C + 0.02)})
	var end_side := 1 if along_z else 0
	L.add_deco({"k": "door", "kind": "tiny", "p": L.wall_point(x + (0 if along_z else n - 1), z + (n - 1 if along_z else 0), end_side, 0.0, LD.C * 0.5), "r": LD.dir_yaw(end_side)})


## Комната дверей: все открываются в стену
static func doors(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	L._open_border(x, z, w, h, L.rng.randi_range(0, 3), LD.E_ARCH)
	_lights(L, x, z, w, h, LD.L_ON)
	for side in 4:
		var len := w if side % 2 == 1 else h
		for k in range(0, len, 1):
			if L.rng.randf() < 0.55:
				var cx := x + (k if side % 2 == 1 else (w - 1 if side == 0 else 0))
				var cz := z + (k if side % 2 == 0 else (h - 1 if side == 1 else 0))
				if L.edge(cx, cz, side) != LD.E_WALL:
					continue
				L.add_deco({"k": "door", "kind": "small" if L.rng.randf() < 0.15 else "wall", "p": L.wall_point(cx, cz, side, 0.0, L.rng.randf_range(-0.4, 0.4)), "r": LD.dir_yaw(side)})
	L.add_deco({"k": "door", "kind": "ceiling", "p": _c(L, x + w / 2, z + h / 2), "r": 0.0})
	_late_light(L, x + w / 2, z + h / 2, LD.L_NONE)
	_graf(L, x + 1, z, 3, "graf.doors", 1.95)


## Комната стульев: все смотрят в один угол
static func chairs(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	L._open_border(x, z, w, h, 1, LD.E_ARCH)
	L._open_border(x, z, w, h, 0, LD.E_DOOR)
	_lights(L, x, z, w, h, LD.L_ON)
	var m := _mid(L, x, z, w, h)
	L.add_deco({"k": "chairs", "p": m + Vector3(0, 0, 0.6), "r": PI * 0.25, "cols": 7, "rows": 7})
	L.add_deco({"k": "copy", "who": "civ_e", "wrong": "seated_air", "p": m + Vector3(0.6, 0, 0.6), "r": PI * 0.25, "seed": L.rng.randi(), "react": false})


## Перевёртыш: ковёр на потолке, лампы на полу, мебель стоит на потолке
static func flip(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_FLIP, 0)
	_ceil_all(L, x, z, w, h, 27)
	L._open_border(x, z, w, h, 1, LD.E_DOOR)
	L._open_border(x, z, w, h, 3, LD.E_ARCH)
	_lights(L, x, z, w, h, LD.L_ON)
	var m := _mid(L, x, z, w, h)
	L.add_deco({"k": "obj", "what": "desk", "p": m + Vector3(-0.8, 0, -0.6), "r": 0.3, "wrong": "ceiling"})
	L.add_deco({"k": "obj", "what": "ochair", "p": m + Vector3(-0.7, 0, 0.4), "r": 2.8, "wrong": "ceiling"})
	L.add_deco({"k": "obj", "what": "cabinet", "p": L.wall_point(x + 2, z, 3, 0.4), "r": LD.dir_yaw(3) + PI, "wrong": "ceiling"})
	L.add_deco({"k": "obj", "what": "wetsign", "p": m + Vector3(1.6, 0, 0.6), "r": 1.0, "wrong": "ceiling"})
	L.add_deco({"k": "copy", "who": "civ_h", "wrong": "ceiling", "p": m + Vector3(1.0, 0, -0.9), "r": 1.8, "seed": L.rng.randi()})


## Боковая комната: «пол» на стене, мебель стоит на стене
static func side(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_ceil_all(L, x, z, w, h, 27)
	L._open_border(x, z, w, h, 0, LD.E_DOOR)
	_lights(L, x, z, w, h, LD.L_NONE)
	# свет «с боковой стены»: невидимый источник на высоте у восточной стены
	for j in range(1, h - 1):
		L.light[LD.idx(x + w - 1, z + j)] = LD.L_ASYNC
	var m := _mid(L, x, z, w, h)
	L.add_deco({"k": "side_room", "p": m, "r": 0.0, "w": w * LD.C, "h": h * LD.C})


## Офис из перегородок: ряды «кабинок», мониторы, телефоны
static func cubicles(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_open(L, x, z, w, h, 3, LD.E_ARCH)
	_lights(L, x, z, w, h, LD.L_ON, false, true)
	for i in w:
		for j in h:
			if L.rng.randf() < 0.1:
				L.light[LD.idx(x + i, z + j)] = LD.L_FLICK
	var copy_at := L.rng.randi_range(0, 5)
	var k := 0
	for i in range(0, w):
		for j in range(0, h, 2):
			if i == w / 2:
				continue
			var p := _c(L, x + i, z + j)
			L.add_deco({"k": "cubicle", "p": p, "r": 0.0 if j % 4 == 0 else PI, "seed": L.rng.randi()})
			if k == copy_at:
				L.add_deco({"k": "copy", "who": "worker", "wrong": "seated_air", "p": p + Vector3(0, 0, 0.0), "r": PI, "seed": L.rng.randi(), "react": true})
			k += 1


## Школьный класс (как у Рави в Found Footage #3)
static func classroom(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_CLASS, 0)
	L._open_border(x, z, w, h, 1, LD.E_DOOR)
	_lights(L, x, z, w, h, LD.L_ON, false, true)
	var m := _mid(L, x, z, w, h)
	L.add_deco({"k": "chalkboard", "p": L.wall_point(x + w / 2, z, 3, 0.55), "r": LD.dir_yaw(3), "key": "class.board" + str(L.rng.randi_range(1, 3))})
	_model(L, "WoodenTable_01", L.wall_point(x + 1, z, 3, 1.4), LD.dir_yaw(3) + PI, Vector3(0.7, 1.35, 1.0))
	_model(L, "wall_clock", L.wall_point(x + w - 2, z, 3, 0.0) + Vector3(0, 2.2, 0), LD.dir_yaw(3), 1.0, false)
	var kids := 0
	for r in 4:
		for c in 4:
			var p := m + Vector3(-2.7 + c * 1.8, 0, -0.6 + r * 1.4)
			_model(L, "SchoolDesk_01", p, PI, 1.0)
			_model(L, "SchoolChair_01", p + Vector3(0, 0, 0.55), PI, 0.9, false)
			if kids < 3 and L.rng.randf() < 0.18:
				kids += 1
				L.add_deco({"k": "copy", "who": ["civ_l", "civ_m", "kid"][kids % 3], "wrong": "seated_air", "p": p + Vector3(0, 0.06, 0.55), "r": PI, "seed": L.rng.randi(), "react": true})


## Жилой угол пропавшего: матрас, консервы, бутылки, записки, зарубки
static func residence(L: LayerData, x: int, z: int, w: int, h: int, lay: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_DARK if lay == 1 else LD.Z_YELLOW, 0)
	L._open_border(x, z, w, h, L.rng.randi_range(0, 3), LD.E_DOOR)
	_lights(L, x, z, w, h, LD.L_DEAD)
	L.light[LD.idx(x + 1, z + 1)] = LD.L_BULB
	L.add_deco({"k": "residence", "p": _c(L, x + 1, z + 1) + Vector3(-0.4, 0, -0.2), "r": 0.0})
	_graf(L, x, z + 1, 2, "graf.g11", 1.2)
	_graf(L, x, z + 2, 2, "graf.tally2", 1.0)
	_graf(L, x + 2, z, 3, "graf.home", 1.5)


## Мебельный магазин-копия (Kelowna Branch): «ВСЁ ДОЛЖНО УЙТИ»
static func store(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_STORE, 0)
	_open(L, x, z, w, h, 2, LD.E_OPEN)
	_lights(L, x, z, w, h, LD.L_ON, false, true)
	var goods := ["Sofa_01", "sofa_02", "sofa_03", "ArmChair_01", "GreenChair_01", "mid_century_lounge_chair", "Ottoman_01", "CoffeeTable_01",
		"modern_coffee_table_01", "coffee_table_round_01", "side_table_01", "ClassicNightstand_01", "wooden_bookshelf_worn", "painted_wooden_sofa",
		"Rockingchair_01", "round_wooden_table_01", "drawer_cabinet", "bar_chair_round_01"]
	var signs := ["store.s1", "store.s2", "store.s3", "store.s1"]
	var si := 0
	for i in range(1, w - 1, 2):
		for j in range(1, h - 1, 2):
			var p := _c(L, x + i, z + j) + Vector3(L.rng.randf_range(-0.3, 0.3), 0, L.rng.randf_range(-0.3, 0.3))
			var id: String = goods[L.rng.randi_range(0, goods.size() - 1)]
			var yaw := L.rng.randf_range(-0.3, 0.3) + (PI if j % 4 == 1 else 0.0)
			L.rng.randf()
			_model(L, id, p, yaw, 1.0, true, 0.0, {"price": "$%d.99" % L.rng.randi_range(19, 399)})
			if (i + j) % 4 == 2:
				L.add_deco({"k": "store_sign", "p": p + Vector3(0, 0, 0.0), "r": L.rng.randf_range(-0.2, 0.2) + (PI * 0.5 if si % 2 else 0.0), "key": signs[si % signs.size()], "v": si})
				si += 1
	var cc := _c(L, x + w - 2, z + 1)
	_model(L, "metal_office_desk", cc, 0.0, Vector3(0.8, 1.2, 0.7))
	_model(L, "CashRegister_01", cc, PI, 1.0, false, 0.0, {"on": ["metal_office_desk", 1.2]})
	L.add_deco({"k": "sound", "snd": "store_muzak", "p": _mid(L, x, z, w, h) + Vector3(0, 2.3, 0), "every": 0.0})
	L.add_deco({"k": "copy", "who": "civ_g", "wrong": "corner", "p": L.wall_point(x, z + h - 1, 2, 0.35), "r": LD.dir_yaw(2) + PI, "seed": L.rng.randi()})


## Место «Обследования света и плит» Async: стремянка, снятая плита и светильник
static func survey(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 2)
	_ceil_all(L, x, z, w, h, 27)
	_lights(L, x, z, w, h, LD.L_ON)
	L.light[LD.idx(x + 1, z + 1)] = LD.L_HOLE
	L.add_deco({"k": "survey", "p": _c(L, x + 1, z + 1) + Vector3(0.3, 0, -0.3), "r": 0.0})


## Комната телевизоров: стопка кинескопов, кресло перед ними, в кресле — копия
static func tvroom(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	L._open_border(x, z, w, h, 1, LD.E_DOOR)
	_lights(L, x, z, w, h, LD.L_DEAD)
	L.light[LD.idx(x + w - 1, z + h - 1)] = LD.L_FLICK
	L.add_deco({"k": "tv_stack", "p": L.wall_point(x + w / 2, z, 3, 0.35), "r": LD.dir_yaw(3)})
	var p := _c(L, x + w / 2, z + 2)
	_model(L, "ArmChair_01", p, LD.dir_yaw(1))
	L.add_deco({"k": "copy", "who": "civ_i", "wrong": "seated_air", "p": p + Vector3(0, 0.05, 0), "r": LD.dir_yaw(1), "seed": L.rng.randi(), "react": false})


## Пустой зал, посередине стол, на столе звонит телефон
static func phone(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_open(L, x, z, w, h, 2, LD.E_ARCH)
	_lights(L, x, z, w, h, LD.L_ON)
	L.add_deco({"k": "phone_ring", "p": _c(L, x + w / 2, z + h / 2), "r": L.rng.randf() * TAU})


## Коридор с торговыми автоматами
static func vending(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	var horiz := w > h
	if horiz:
		L.wall_e[LD.idx(x - 1, z)] = LD.E_OPEN
		L.wall_e[LD.idx(x + w - 1, z)] = LD.E_ARCH
	else:
		L.wall_s[LD.idx(x, z - 1)] = LD.E_OPEN
		L.wall_s[LD.idx(x, z + h - 1)] = LD.E_ARCH
	_lights(L, x, z, w, h, LD.L_FLICK)
	var n := maxi(w, h)
	var side := 1 if horiz else 0
	for k in range(1, n - 1):
		if L.rng.randf() < 0.7:
			var cx := x + (k if horiz else 0)
			var cz := z + (0 if horiz else k)
			L.add_deco({"k": "vending", "p": L.wall_point(cx, cz, side, 0.42), "r": LD.dir_yaw(side), "seed": L.rng.randi()})


## Три одинаковые комнаты подряд
static func repeat(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	var horiz := w > h
	var seed := L.rng.randi()
	for k in 3:
		var rx := x + (k * 3 if horiz else 0)
		var rz := z + (0 if horiz else k * 3)
		L.stamp_room(rx, rz, 3, 3, LD.Z_YELLOW, 0)
		_lights(L, rx, rz, 3, 3, LD.L_ON)
		L.light[LD.idx(rx + 2, rz + 2)] = LD.L_FLICK
		if horiz:
			L.wall_e[LD.idx(rx + 2, rz + 1)] = LD.E_DOOR
			if k == 0:
				L.wall_e[LD.idx(rx - 1, rz + 1)] = LD.E_DOOR
		else:
			L.wall_s[LD.idx(rx + 1, rz + 2)] = LD.E_DOOR
			if k == 0:
				L.wall_s[LD.idx(rx + 1, rz - 1)] = LD.E_DOOR
		var rr := RandomNumberGenerator.new()
		rr.seed = seed
		var p := _c(L, rx + 1, rz + 1)
		L.add_deco({"k": "obj", "what": "chair", "p": p + Vector3(rr.randf_range(-0.6, 0.6), 0, rr.randf_range(-0.6, 0.6)), "r": rr.randf() * TAU, "wrong": "tilt" if k == 2 else "none"})
		L.add_deco({"k": "stain", "p": p + Vector3(-0.7, 0, 0.6), "r": 0.0, "s": 1.4, "wet": true, "seed": seed})
		var side := 3 if horiz else 2
		_graf(L, rx + (1 if horiz else 0), rz + (0 if horiz else 1), side, "graf.repeat3" if k == 2 else "graf.repeat1", 1.45)


## Лестница, уходящая в потолок
static func stairs(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_ceil_all(L, x, z, w, h, 27)
	var horiz := w > h
	if horiz:
		L.wall_e[LD.idx(x - 1, z)] = LD.E_ARCH
	else:
		L.wall_s[LD.idx(x, z + h - 1)] = LD.E_ARCH
	_lights(L, x, z, w, h, LD.L_ON)
	var p := _mid(L, x, z, w, h)
	L.add_deco({"k": "stairs", "p": p + (Vector3(-1.2, 0, 0) if horiz else Vector3(0, 0, 1.2)), "r": (-PI * 0.5 if horiz else 0.0), "up": true})


## Затопленный зал: вода по щиколотку, капли
static func flooded(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_DARK, 0)
	_open(L, x, z, w, h, 3, LD.E_ARCH)
	for i in w:
		for j in h:
			var ci := LD.idx(x + i, z + j)
			L.water[ci] = 1
			L.used[ci] = 2
			var r := L.rng.randf()
			L.light[ci] = (LD.L_ON if r < 0.25 else (LD.L_FLICK if r < 0.4 else LD.L_DEAD)) if (x + i + z + j) % 2 == 0 else LD.L_NONE
	for k in 4:
		L.add_deco({"k": "drips", "p": _c(L, x + L.rng.randi_range(0, w - 1), z + L.rng.randi_range(0, h - 1)), "r": 0.0})
	L.add_deco({"k": "sound", "snd": "water_amb", "p": _mid(L, x, z, w, h) + Vector3(0, 1, 0), "every": 0.0})


## Тупичок со знаком «ВЫХОД» над дверью, за которой стена
static func exit_alcove(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	var side := L.rng.randi_range(0, 3)
	L._open_border(x, z, w, h, side, LD.E_ARCH)
	_lights(L, x, z, w, h, LD.L_FLICK)
	var back := (side + 2) % 4
	var cx := x + (w - 1 if back == 0 else 0)
	var cz := z + (h - 1 if back == 1 else 0)
	L.add_deco({"k": "door", "kind": "wall", "p": L.wall_point(cx, cz, back, 0.0), "r": LD.dir_yaw(back)})
	L.add_deco({"k": "exit_sign", "p": L.wall_point(cx, cz, back, 0.0) + Vector3(0, 2.45, 0), "r": LD.dir_yaw(back)})


## Склад: стеллажи, коробки, тележки
static func storage(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_open(L, x, z, w, h, 2, LD.E_OPEN)
	_lights(L, x, z, w, h, LD.L_ON)
	for j in range(1, h, 2):
		for i in range(1, w - 1, 2):
			var p := _c(L, x + i, z + j) + Vector3(0.6, 0, 0)
			_model(L, "steel_frame_shelves_03" if L.rng.randf() < 0.5 else "worn_metal_rack", p, 0.0)
			if L.rng.randf() < 0.5:
				L.add_deco({"k": "obj", "what": "boxes", "p": p + Vector3(0, 0, 1.0), "r": L.rng.randf() * TAU, "wrong": "none", "seed": L.rng.randi()})
	_model(L, "hand_truck", _c(L, x, z), 0.5)
	_model(L, "barrel_03", _c(L, x + w - 1, z + h - 1), 0.0)
	_model(L, "metal_tool_chest", _c(L, x + w - 1, z), 1.0)


## Нижний слой: тело в чёрной плесени, огорожено лентой Async
static func body(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_DARK, 2, LD.E_ARCH)
	_lights(L, x, z, w, h, LD.L_DEAD)
	L.light[LD.idx(x + 3, z + 3)] = LD.L_FLICK
	L.add_deco({"k": "body", "p": _mid(L, x, z, w, h), "r": L.rng.randf() * TAU, "seed": L.rng.randi()})
	for k in 5:
		var s := k % 4
		L.add_deco({"k": "mold", "p": L.wall_point(x + (k % w), z + (k % h), s, 0.0) + Vector3(0, L.rng.randf_range(0.3, 1.8), 0), "r": LD.dir_yaw(s), "along": 0.0, "s": L.rng.randf_range(1.0, 2.0)})


## Комната громкоговорителей: шёпот и шипение из колонок
static func speakers(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_DARK, 2, LD.E_DOOR)
	_lights(L, x, z, w, h, LD.L_RED)
	# у каждой красной лампы — светильник: основание на потолке, колба в клетке
	for i in w:
		for j in h:
			if L.light[LD.idx(x + i, z + j)] == LD.L_RED:
				L.add_deco({"k": "red_lamp", "p": _c(L, x + i, z + j), "r": 0.0})
	var m := _mid(L, x, z, w, h)
	for k in 7:
		var a := k * TAU / 7.0
		var p := m + Vector3(cos(a) * 3.6, 0, sin(a) * 3.6)
		# лицом (динамиками) — к середине комнаты, где стоит слушающий
		L.add_deco({"k": "speaker", "p": p, "r": atan2(-cos(a), -sin(a)), "seed": L.rng.randi()})
	# в середине — усилитель с магнитофоном, к нему сходятся шнуры колонок
	# (без вызовов L.rng: порядок случайных чисел генерации мира не меняется)
	L.add_deco({"k": "speaker_hub", "p": m, "r": 0.6})


## Бассейный зал: белая плитка, вода по щиколотку, колонны
static func pool(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 3, LD.E_ARCH)
	for i in w:
		for j in h:
			var ci := LD.idx(x + i, z + j)
			L.water[ci] = 1
			L.used[ci] = 2
			L.ceil_h[ci] = 40
			L.light[ci] = LD.L_ON if (i + j) % 2 == 0 else LD.L_NONE
	for i in range(2, w - 1, 2):
		for j in range(2, h - 1, 2):
			L.post[LD.idx(x + i, z + j)] = 1
	L.add_deco({"k": "sound", "snd": "water_amb", "p": _mid(L, x, z, w, h) + Vector3(0, 1, 0), "every": 0.0})
	for k in 3:
		L.add_deco({"k": "drips", "p": _c(L, x + L.rng.randi_range(0, w - 1), z + L.rng.randi_range(0, h - 1)), "r": 0.0})


## Разбросанное по миру понемногу: розетки, вентиляция, отслоившиеся обои, упавшие плиты, крысы,
## огнетушители, пожарные датчики, трубы в техзонах, редкие телевизоры
static func sprinkle(L: LayerData, lay: int, origin: Vector2i) -> void:
	var rr := L.rng
	var tv_left := 3 if lay == 0 else 1
	var chans := ["news", "async_ad", "bars", "explorers", "weather", "home", "static"]
	for z in LD.N:
		for x in LD.N:
			var i := z * LD.N + x
			if L.flo[i] != LD.F_FLOOR or L.used[i] != 0:
				continue
			var zn := L.zone[i]
			var cx := x if x < LD.N / 2 else x - LD.N
			var cz := z if z < LD.N / 2 else z - LD.N
			var dist := Vector2(cx - origin.x, cz - origin.y).length()
			if dist > 150:
				continue
			var r := rr.randf()
			if r > 0.046 and L.light[i] != LD.L_HOLE and zn != LD.Z_CONCRETE:
				continue
			var sides := L.wall_sides(cx, cz)
			if L.light[i] == LD.L_HOLE and r < 0.5:
				L.add_deco({"k": "tile_fallen", "p": _c(L, cx, cz), "r": rr.randf() * TAU})
				continue
			if sides.is_empty():
				if zn == LD.Z_CONCRETE and r < 0.06:
					L.add_deco({"k": "pipes", "p": _c(L, cx, cz) + Vector3(0, 0, 0), "r": 0.0 if rr.randf() < 0.5 else PI * 0.5, "len": LD.C, "y": L.height_m(cx, cz) - 0.3})
				elif r < 0.002 and dist > 12:
					L.add_deco({"k": "rat", "p": _c(L, cx, cz), "r": rr.randf() * TAU})
				continue
			var s: int = sides[rr.randi_range(0, sides.size() - 1)]
			if r < 0.02:
				L.add_deco({"k": "outlet", "p": L.wall_point(cx, cz, s, 0.0, rr.randf_range(-0.8, 0.8)) + Vector3(0, 0.32, 0), "r": LD.dir_yaw(s)})
			elif r < 0.03:
				L.add_deco({"k": "vent", "p": L.wall_point(cx, cz, s, 0.0, rr.randf_range(-0.6, 0.6)) + Vector3(0, L.height_m(cx, cz) - 0.45, 0), "r": LD.dir_yaw(s)})
			elif r < 0.036 and zn != LD.Z_CONCRETE and zn != LD.Z_TILE:
				L.add_deco({"k": "peel", "p": L.wall_point(cx, cz, s, 0.0, rr.randf_range(-0.6, 0.6)) + Vector3(0, rr.randf_range(1.2, 2.1), 0), "r": LD.dir_yaw(s)})
			elif r < 0.039:
				_model(L, "fire_alarm", L.wall_point(cx, cz, s, 0.0) + Vector3(0, 1.9, 0), LD.dir_yaw(s), 1.0, false)
			elif r < 0.041 and zn == LD.Z_OLD:
				_model(L, "korean_fire_extinguisher_01", L.wall_point(cx, cz, s, 0.2), LD.dir_yaw(s), 1.0, false)
			elif r < 0.0425 and dist > 8 and lay == 0:
				L.add_deco({"k": "exit_sign", "p": L.wall_point(cx, cz, s, 0.0) + Vector3(0, 2.4, 0), "r": LD.dir_yaw(s)})
			elif r < 0.044 and zn == LD.Z_CONCRETE:
				L.add_deco({"k": "pipes", "p": L.wall_point(cx, cz, s, 0.6), "r": LD.dir_yaw(s) + PI * 0.5, "len": LD.C, "y": L.height_m(cx, cz) - 0.3})
			elif tv_left > 0 and r < 0.0446 and dist > 20 and zn != LD.Z_CONCRETE:
				tv_left -= 1
				L.add_deco({"k": "tv_on", "p": L.wall_point(cx, cz, s, 0.4), "r": LD.dir_yaw(s), "ch": chans[rr.randi_range(0, chans.size() - 1)]})


# ------------------------------------------------------------ перепады высот

## Центр клетки на высоте её пола
static func _cf(L: LayerData, x: int, z: int) -> Vector3:
	var c := LD.cell_center(x, z)
	return Vector3(c.x, L.floor_y + L.fh[LD.idx(x, z)] * 0.1, c.y)


## Пандус/лестница из клеток cells (по направлению d): высота первой — start (дм), дальше шаг step
static func _slope(L: LayerData, cells: Array, d: int, start: int, step: int, stairs: bool) -> void:
	for k in cells.size():
		var c: Vector2i = cells[k]
		var i := LD.idx(c.x, c.y)
		L.fh[i] = start + k * step
		L.ramp[i] = (d + 5) if stairs else (d + 1)


## Перила вдоль ребра клетки (x, z) со стороны d, на высоте её пола
static func _rail(L: LayerData, x: int, z: int, d: int, broken := false) -> void:
	var y := L.floor_y + L.fh[LD.idx(x, z)] * 0.1
	var a: Vector3
	var yaw := 0.0
	match d:
		0:
			a = Vector3((x + 1) * LD.C - 0.08, y, z * LD.C)
			yaw = -PI * 0.5
		1:
			a = Vector3(x * LD.C, y, (z + 1) * LD.C - 0.08)
		2:
			a = Vector3(x * LD.C + 0.08, y, z * LD.C)
			yaw = -PI * 0.5
		_:
			a = Vector3(x * LD.C, y, z * LD.C + 0.08)
	L.add_deco({"k": "railing", "p": a, "r": yaw, "len": LD.C, "broken": broken})


## Отметить точку входа (на ровном полу у края) — туда ведёт полигон
static func _entry(L: LayerData, x: int, z: int, dx := 0.0, dz := 0.0) -> void:
	L.places["_entry"] = _cf(L, x, z) + Vector3(dx, 0, dz)


static func _ceil_all(L: LayerData, x: int, z: int, w: int, h: int, v: int) -> void:
	for i in w:
		for j in h:
			L.ceil_h[LD.idx(x + i, z + j)] = v


## Котлован: огромный зал, середина провалена на 2,4–3,6 м; вниз ведут пандус и лестница, на дне — вода или стул
static func sunken(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_open(L, x, z, w, h, 4, LD.E_ARCH)
	_open(L, x, z, w, h, 2, LD.E_OPEN)
	_ceil_all(L, x, z, w, h, 45)
	var deep: int = [-24, -30, -36][L.rng.randi_range(0, 2)]
	var flooded := L.rng.randf() < 0.45
	for i in w:
		for j in h:
			var ci := LD.idx(x + i, z + j)
			var pit := i >= 2 and i < w - 2 and j >= 2 and j < h - 2
			if pit:
				L.fh[ci] = deep
				if flooded:
					L.water[ci] = 1
			L.used[ci] = 2
			if pit:
				L.light[ci] = LD.L_ON if (i + j) % 3 == 0 else (LD.L_FLICK if (i * 7 + j) % 11 == 0 else LD.L_NONE)
			else:
				L.light[ci] = LD.L_ON if (i + j) % 2 == 0 else LD.L_NONE
	# пандус (2 клетки шириной) с севера и узкая лестница с юга
	var rx := x + w / 2 - 1
	for col in [rx, rx + 1]:
		var cl := []
		for k in 3:
			cl.append(Vector2i(col, z + 2 + k))
			L.water[LD.idx(col, z + 2 + k)] = 0
		_slope(L, cl, 1, 0, deep / 3, false)
	var sx := x + w - 4
	var st := []
	for k in 3:
		st.append(Vector2i(sx, z + h - 3 - k))
		L.water[LD.idx(sx, z + h - 3 - k)] = 0
	_slope(L, st, 3, 0, deep / 3, true)
	# колонны со дна
	for i in range(4, w - 3, 3):
		for j in range(4, h - 3, 3):
			if L.ramp[LD.idx(x + i, z + j)] == 0 and L.ramp[LD.idx(x + i - 1, z + j - 1)] == 0:
				L.post[LD.idx(x + i, z + j)] = 1
	if flooded:
		L.add_deco({"k": "drips", "p": _cf(L, x + w / 2 + 2, z + h / 2), "r": 0.0})
	else:
		L.add_deco({"k": "obj", "what": "chair", "p": _cf(L, x + w / 2 + 1, z + h / 2 + 1), "r": L.rng.randf() * TAU, "wrong": "none"})
	L.add_deco({"k": "obj", "what": "wetsign", "p": _cf(L, x + 1, z + 1) + Vector3(0.4, 0, 0.6), "r": 0.6, "wrong": "none"})
	_entry(L, rx, z + 1)


## Зал с террасой: задняя половина поднята на 2,4 м, к ней — широкая лестница; наверху двери в стену
static func terrace(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_ceil_all(L, x, z, w, h, 62)
	for i in w:
		for j in h:
			var ci := LD.idx(x + i, z + j)
			if j < 4:
				L.fh[ci] = 24
			L.used[ci] = 2
			L.light[ci] = LD.L_ON if (i + j) % 2 == 0 else LD.L_NONE
	var s0 := x + w / 2 - 1
	for col in range(s0, s0 + 3):
		_slope(L, [Vector2i(col, z + 6), Vector2i(col, z + 5), Vector2i(col, z + 4)], 3, 0, 8, true)
	# входы — только внизу
	L.set_edge(x + 2, z + h - 1, 1, LD.E_ARCH)
	L.set_edge(x + w - 3, z + h - 1, 1, LD.E_ARCH)
	L.set_edge(x + w / 2, z + h - 1, 1, LD.E_OPEN)
	L.set_edge(x + w - 1, z + 7 + L.rng.randi_range(0, h - 9), 0, LD.E_DOOR)
	L.set_edge(x, z + 7 + L.rng.randi_range(0, h - 9), 2, LD.E_DOOR)
	# перила по краю террасы
	for i in w:
		if x + i < s0 or x + i > s0 + 2:
			_rail(L, x + i, z + 3, 1, L.rng.randf() < 0.12)
	# наверху — двери в стену и одинокий стул лицом к ним
	for k in 3:
		var dx := x + 2 + k * ((w - 4) / 2)
		L.add_deco({"k": "door", "kind": "wall", "p": L.wall_point(dx, z, 3, 0.0) + Vector3(0, 2.4, 0), "r": LD.dir_yaw(3)})
	L.add_deco({"k": "obj", "what": "ochair", "p": _cf(L, x + w / 2, z + 1), "r": PI, "wrong": "none"})
	_entry(L, x + w / 2, z + h - 2)


## Мост над пропастью: поперёк зала провал в 15 м, через него — узкая полоса пола
static func chasm(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_ceil_all(L, x, z, w, h, 40)
	var bx := x + w / 2 + L.rng.randi_range(-2, 2)
	for i in w:
		for j in h:
			var ci := LD.idx(x + i, z + j)
			L.used[ci] = 2
			var gap := j >= 2 and j < h - 2
			if gap and x + i != bx:
				L.fh[ci] = -150
				L.light[ci] = LD.L_NONE
			elif gap:
				L.light[ci] = LD.L_FLICK if j % 2 == 0 else LD.L_NONE
			else:
				L.light[ci] = LD.L_ON if (i + j) % 2 == 0 else LD.L_NONE
	L.set_edge(x + w / 2, z, 3, LD.E_ARCH)
	L.set_edge(x, z + 1, 2, LD.E_OPEN)
	L.set_edge(x + w / 2 - 1, z + h - 1, 1, LD.E_ARCH)
	L.set_edge(x + w - 1, z + h - 2, 0, LD.E_DOOR)
	L.add_deco({"k": "tile_fallen", "p": _cf(L, bx - 1, z + 1) + Vector3(0.3, 0, 0.5), "r": 0.4})
	_graf(L, x + 1, z, 3, "graf.dont_look", 1.5)
	_entry(L, bx, z, 0.0, 0.6)


## Лестница вниз: узкий бетонный пролёт на 6 м вниз, внизу — тупик и находка
static func stairwell(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_ceil_all(L, x, z, w, h, LD.CEIL)
	var along_z := h > w
	var d := 1 if along_z else 0
	var n := maxi(w, h)
	for side in 2:
		var cl := []
		for k in range(1, 7):
			cl.append(Vector2i(x + (side if along_z else k), z + (k if along_z else side)))
		_slope(L, cl, d, 0, -10, true)
		for k in range(7, n):
			L.fh[LD.idx(x + (side if along_z else k), z + (k if along_z else side))] = -60
	for k in n:
		for side in 2:
			var ci := LD.idx(x + (side if along_z else k), z + (k if along_z else side))
			L.used[ci] = 2
			L.light[ci] = LD.L_NONE
	var lc := func(k: int) -> int: return LD.idx(x + (0 if along_z else k), z + (k if along_z else 0))
	L.light[lc.call(0)] = LD.L_ON
	L.light[lc.call(3)] = LD.L_FLICK
	L.light[lc.call(n - 1)] = LD.L_BULB
	# вход только сверху
	if along_z:
		L.set_edge(x, z, 3, LD.E_ARCH)
		L.set_edge(x + 1, z, 3, LD.E_ARCH)
	else:
		L.set_edge(x, z, 2, LD.E_ARCH)
		L.set_edge(x, z + 1, 2, LD.E_ARCH)
	var bot := Vector2i(x + (1 if along_z else n - 1), z + (n - 1 if along_z else 1))
	if L.rng.randf() < 0.5:
		L.add_deco({"k": "hazmat", "p": _cf(L, bot.x, bot.y), "r": LD.dir_yaw(d), "pose": "slump", "seed": L.rng.randi()})
	else:
		L.add_deco({"k": "obj", "what": "chair", "p": _cf(L, bot.x, bot.y), "r": LD.dir_yaw(d) + PI, "wrong": "none"})
		_graf(L, bot.x, bot.y, d, "graf.down", 1.3 - 6.0)
	_entry(L, x + (1 if along_z else 0), z + (0 if along_z else 1))


## Пандус: бетонный съезд вниз на 3 м, низина (иногда в воде) и подъём обратно — как пустая парковка
static func ramp_room(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_ceil_all(L, x, z, w, h, LD.CEIL)
	var along_z := h > w
	var d := 1 if along_z else 0
	var n := maxi(w, h)
	var wet := L.rng.randf() < 0.6
	for side in 2:
		var cell := func(k: int) -> Vector2i: return Vector2i(x + (side if along_z else k), z + (k if along_z else side))
		_slope(L, [cell.call(2), cell.call(3), cell.call(4)], d, 0, -10, false)
		for k in [5, 6]:
			var c2: Vector2i = cell.call(k)
			L.fh[LD.idx(c2.x, c2.y)] = -30
			if wet:
				L.water[LD.idx(c2.x, c2.y)] = 1
		_slope(L, [cell.call(7), cell.call(8), cell.call(9)], d, -30, 10, false)
		for k in n:
			var c3: Vector2i = cell.call(k)
			var ci := LD.idx(c3.x, c3.y)
			L.used[ci] = 2
			L.light[ci] = LD.L_NONE
	var lc := func(k: int) -> int: return LD.idx(x + (0 if along_z else k), z + (k if along_z else 0))
	L.light[lc.call(0)] = LD.L_ON
	L.light[lc.call(3)] = LD.L_FLICK
	L.light[lc.call(6)] = LD.L_ON
	L.light[lc.call(n - 1)] = LD.L_ON
	if along_z:
		L.set_edge(x, z, 3, LD.E_OPEN)
		L.set_edge(x + 1, z, 3, LD.E_OPEN)
		L.set_edge(x, z + n - 1, 1, LD.E_OPEN)
		L.set_edge(x + 1, z + n - 1, 1, LD.E_OPEN)
	else:
		L.set_edge(x, z, 2, LD.E_OPEN)
		L.set_edge(x, z + 1, 2, LD.E_OPEN)
		L.set_edge(x + n - 1, z, 0, LD.E_OPEN)
		L.set_edge(x + n - 1, z + 1, 0, LD.E_OPEN)
	if wet:
		L.add_deco({"k": "drips", "p": _cf(L, x + (0 if along_z else 5), z + (5 if along_z else 0)), "r": 0.0})
	_entry(L, x + (1 if along_z else 0), z + (0 if along_z else 1))


## Комната с дырами: в полу провалы — неглубокие и такие, у которых не видно дна
static func holes(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_open(L, x, z, w, h, 4, LD.E_ARCH)
	_lights(L, x, z, w, h, LD.L_ON)
	var made := 0
	for t in 40:
		if made >= 6:
			break
		var i := L.rng.randi_range(1, w - 2)
		var j := L.rng.randi_range(1, h - 2)
		var ci := LD.idx(x + i, z + j)
		if L.fh[ci] != 0:
			continue
		var r := L.rng.randf()
		# по колено (вылезти можно) или без дна; средних, из которых не выбраться, нет
		L.fh[ci] = (-10 - L.rng.randi_range(0, 2) * 2) if r < 0.5 else -140
		L.light[ci] = LD.L_NONE
		if L.rng.randf() < 0.5:
			L.add_deco({"k": "tile_fallen", "p": _cf(L, x + i, z + j) + Vector3(0, 0.0, 0), "r": L.rng.randf() * TAU})
			# плита упала с потолка над дырой — там тёмный проём
			_late_light(L, x + i, z + j, LD.L_HOLE)
		made += 1
	_graf(L, x, z + h / 2, 2, "graf.mind_gap", 1.4)
	_entry(L, x + w / 2, z + 0)


## Зал с балконами: кольцо на высоте 3,2 м вокруг пустого двусветного зала; вход снизу, на балконы — лестница
static func atrium(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_ceil_all(L, x, z, w, h, 72)
	var px0 := x + w / 2 - 1
	for i in w:
		for j in h:
			var ci := LD.idx(x + i, z + j)
			var ring := i < 2 or i >= w - 2 or j < 2 or j >= h - 2
			var passage := j >= h - 2 and (x + i == px0 or x + i == px0 + 1)
			if ring and not passage:
				L.fh[ci] = 32
			L.used[ci] = 2
			L.light[ci] = LD.L_ON if (i + j) % 2 == 0 else (LD.L_DEAD if (i * 3 + j) % 7 == 0 else LD.L_NONE)
	var stx := x + w / 2 + 2
	_slope(L, [Vector2i(stx, z + 5), Vector2i(stx, z + 4), Vector2i(stx, z + 3), Vector2i(stx, z + 2)], 3, 0, 8, true)
	L.set_edge(px0, z + h - 1, 1, LD.E_ARCH)
	L.set_edge(px0 + 1, z + h - 1, 1, LD.E_ARCH)
	# перила по внутреннему краю балконов
	for i in w:
		for j in h:
			var ci := LD.idx(x + i, z + j)
			if L.fh[ci] != 32 or L.ramp[ci] != 0:
				continue
			for dd in 4:
				var o: Vector2i = LD.DIRS[dd]
				var nj := LD.idx(x + i + o.x, z + j + o.y)
				var inside := i + o.x >= 0 and i + o.x < w and j + o.y >= 0 and j + o.y < h
				if inside and L.fh[nj] == 0 and L.ramp[nj] == 0 and L.flo[nj] == LD.F_FLOOR:
					_rail(L, x + i, z + j, dd, L.rng.randf() < 0.1)
	for k in 4:
		var side: int = [0, 2, 3, 3][k]
		var cx2 := x + (w - 1 if side == 0 else (0 if side == 2 else 3 + k * 2))
		var cz2 := z + (h / 2 if side != 3 else 0)
		L.add_deco({"k": "door", "kind": "wall", "p": L.wall_point(cx2, cz2, side, 0.0) + Vector3(0, 3.2, 0), "r": LD.dir_yaw(side)})
	L.add_deco({"k": "obj", "what": "chair", "p": _cf(L, x + w / 2, z + h / 2), "r": L.rng.randf() * TAU, "wrong": "none"})
	_entry(L, px0, z + h - 1)


## Высокий зал: 20×16 клеток, потолок 7 м, редкие колонны и редкий свет — пусто и гулко
static func tall_hall(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	for k in 6:
		L._open_border(x, z, w, h, k % 4, LD.E_OPEN)
	_ceil_all(L, x, z, w, h, 70)
	for i in range(3, w - 2, 3):
		for j in range(3, h - 2, 3):
			L.post[LD.idx(x + i, z + j)] = 1
	for i in w:
		for j in h:
			var ci := LD.idx(x + i, z + j)
			L.used[ci] = 2
			L.light[ci] = LD.L_ON if (i % 3 == 1 and j % 3 == 1) else (LD.L_DEAD if (i + j * 2) % 9 == 0 else LD.L_NONE)
	if L.rng.randf() < 0.5:
		L.add_deco({"k": "vending", "p": _cf(L, x + w - 2, z + h / 2) + Vector3(0.6, 0, 0), "r": LD.dir_yaw(2)})
	else:
		L.add_deco({"k": "obj", "what": "ochair", "p": _cf(L, x + w / 2, z + h / 2), "r": L.rng.randf() * TAU, "wrong": "none"})


## Колодец: в середине тёмного зала квадратная дыра без дна, перила местами сломаны
static func well(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_DARK, 0)
	_open(L, x, z, w, h, 4, LD.E_ARCH)
	_ceil_all(L, x, z, w, h, 50)
	var c0 := Vector2i(x + w / 2 - 2, z + h / 2 - 2)
	for i in w:
		for j in h:
			var ci := LD.idx(x + i, z + j)
			L.used[ci] = 2
			var inw := x + i >= c0.x and x + i < c0.x + 4 and z + j >= c0.y and z + j < c0.y + 4
			if inw:
				L.fh[ci] = -220
				L.light[ci] = LD.L_NONE
			else:
				var ring := x + i >= c0.x - 1 and x + i <= c0.x + 4 and z + j >= c0.y - 1 and z + j <= c0.y + 4
				L.light[ci] = LD.L_ON if (ring and (i + j) % 2 == 0) else (LD.L_DEAD if (i + j) % 5 == 0 else LD.L_NONE)
	for i in range(-1, 5):
		for j in range(-1, 5):
			var gx := c0.x + i
			var gz := c0.y + j
			var ci2 := LD.idx(gx, gz)
			if L.fh[ci2] != 0:
				continue
			for dd in 4:
				var o: Vector2i = LD.DIRS[dd]
				if L.fh[LD.idx(gx + o.x, gz + o.y)] == -220 and L.rng.randf() < 0.8:
					_rail(L, gx, gz, dd, L.rng.randf() < 0.25)
	_entry(L, x + w / 2, z + 1)


## Редкие провалы пола в обычных коридорах: где-то по колено, где-то — без дна
static func sprinkle_holes(L: LayerData, lay: int, origin: Vector2i) -> void:
	var want := 9 if lay == 0 else 6
	var made := 0
	for t in 600:
		if made >= want:
			break
		var a := L.rng.randf() * TAU
		var r := L.rng.randf_range(14.0, 110.0)
		var cx := origin.x + int(cos(a) * r)
		var cz := origin.y + int(sin(a) * r)
		var ci := LD.idx(cx, cz)
		if L.flo[ci] != LD.F_FLOOR or L.used[ci] != 0 or not L.flat0(ci) or L.ceil_h[ci] < 24:
			continue
		var zn := L.zone[ci]
		if zn != LD.Z_YELLOW and zn != LD.Z_DARK and zn != LD.Z_OLD and zn != LD.Z_CONCRETE:
			continue
		# не перегораживать узкие проходы: вокруг не больше одной стены и соседи — ровный пол
		if L.wall_sides(cx, cz).size() > 1:
			continue
		var ok := true
		for d in 4:
			var o: Vector2i = LD.DIRS[d]
			var nj := LD.idx(cx + o.x, cz + o.y)
			if L.flo[nj] != LD.F_FLOOR or not L.flat0(nj) or L.used[nj] != 0:
				ok = false
		if not ok:
			continue
		var open_d := []
		for d2 in 4:
			if LD.edge_passable(L.edge(cx, cz, d2)):
				open_d.append(d2)
		if open_d.is_empty():
			continue
		var o2: Vector2i = LD.DIRS[open_d[L.rng.randi_range(0, open_d.size() - 1)]]
		var deep := L.rng.randf() < 0.45
		L.fh[ci] = (-130 - L.rng.randi_range(0, 3) * 10) if deep else (-9 - L.rng.randi_range(0, 3) * 2)
		L.used[ci] = 1
		L.light[ci] = LD.L_NONE
		L.add_deco({"k": "tile_fallen", "p": _c(L, cx + o2.x, cz + o2.y), "r": L.rng.randf() * TAU})
		L.places["hole_%d" % made] = _c(L, cx + o2.x, cz + o2.y)
		L.places["hole_%d_c" % made] = _c(L, cx, cz)
		made += 1


## Свет клетки, который ставится только в конце генерации слоя (finish_lights): place_lights, _scatter
## и sprinkle смотрят на свет клеток и тянут L.rng — поменяй его раньше, и сдвинулся бы весь мир сида
static func _late_light(L: LayerData, x: int, z: int, k: int) -> void:
	var lst: Array = L.get_meta("late_light", [])
	lst.append([LD.idx(x, z), k])
	L.set_meta("late_light", lst)


## Конец генерации слоя: отложенный свет клеток (двери в потолке — без светильника, плиты над дырами), и над
## упавшими у провалов плитами в потолке — тёмный проём (L_HOLE), а не целый потолок (клетки — места hole_<k>,
## туда sprinkle_holes кладёт tile_fallen)
static func finish_lights(L: LayerData) -> void:
	for e in L.get_meta("late_light", []):
		var a: Array = e
		L.light[int(a[0])] = int(a[1])
	L.remove_meta("late_light")
	for key in L.places.keys():
		var ks := String(key)
		if not ks.begins_with("hole_") or ks.ends_with("_c"):
			continue
		var p: Vector3 = L.places[key]
		L.light[LD.idx(int(floor(p.x / LD.C)), int(floor(p.z / LD.C)))] = LD.L_HOLE


## Находки по миру — понемногу: сотрудники Async в химзащите (чаще в тупиках), чужие вещи, камера на штативе,
## следы волочения в стену, дверь посреди зала, брошенная ночёвка
static func sprinkle_finds(L: LayerData, lay: int, origin: Vector2i) -> void:
	var want := {"hazmat": 4 if lay == 0 else 3, "clothes": 3, "tripod_cam": 2, "drag": 2, "lone_door": 2, "lost_camp": 2}
	var notes := ["note.a_hz1", "note.a_hz2", "note.a_hz3"]
	var note_i := 0 if lay == 0 else 1
	for kind in want.keys():
		var made := 0
		for t in 900:
			if made >= int(want[kind]):
				break
			var a := L.rng.randf() * TAU
			var r := L.rng.randf_range(16.0, 115.0)
			var cx := origin.x + int(cos(a) * r)
			var cz := origin.y + int(sin(a) * r)
			var ci := LD.idx(cx, cz)
			if L.flo[ci] != LD.F_FLOOR or L.used[ci] != 0 or not L.flat0(ci) or L.ceil_h[ci] < 24 or L.water[ci] != 0:
				continue
			var sides := L.wall_sides(cx, cz)
			var p := _c(L, cx, cz)
			match kind:
				"hazmat":
					# у стены; тупик (три стены) — лучше всего
					if sides.is_empty() or (sides.size() < 3 and L.rng.randf() < 0.6):
						continue
					var sd: int = sides[0]
					var wp := L.wall_point(cx, cz, sd, 0.35)
					# лицом в зал, спиной к стене (−z узла смотрит в стену): сидящий виден целиком, а не ногами вдоль стены
					var d := {"k": "hazmat", "p": wp, "r": LD.dir_yaw(sd), "seed": L.rng.randi(), "pose": "slump" if L.rng.randf() < 0.6 else "lie"}
					if made < 2:
						d["note"] = true
						d["key"] = notes[note_i % notes.size()]
						note_i += 1
					L.add_deco(d)
				"clothes":
					L.add_deco({"k": "clothes", "p": p + Vector3(L.rng.randf_range(-0.5, 0.5), 0, L.rng.randf_range(-0.5, 0.5)), "r": L.rng.randf() * TAU})
				"tripod_cam":
					if sides.is_empty():
						continue
					var sd2: int = sides[0]
					# смотрит в стену с метра
					L.add_deco({"k": "tripod_cam", "p": L.wall_point(cx, cz, sd2, 1.0), "r": LD.dir_yaw(sd2) + PI})
				"drag":
					if sides.is_empty():
						continue
					var sd3: int = sides[0]
					L.add_deco({"k": "drag", "p": L.wall_point(cx, cz, sd3, 0.0), "r": LD.dir_yaw(sd3) + PI})
				"lone_door":
					if not sides.is_empty():
						continue
					L.add_deco({"k": "lone_door", "p": p, "r": L.rng.randi_range(0, 3) * PI * 0.5})
				"lost_camp":
					if sides.is_empty():
						continue
					var sd4: int = sides[0]
					L.add_deco({"k": "lost_camp", "p": L.wall_point(cx, cz, sd4, 0.95), "r": LD.dir_yaw(sd4) + PI})
			L.used[ci] = 1
			L.places["find_%s_%d" % [kind, made]] = p
			made += 1


# ------------------------------------------------------------ обжитые и странные места

## Точка у стены d клетки (x, z) на высоте y, повёрнутая в комнату
static func _wall(L: LayerData, x: int, z: int, d: int, y: float, inset := 0.0, along := 0.0) -> Vector3:
	return L.wall_point(x, z, d, inset, along) + Vector3(0, y, 0)


## Комната ожидания: ряды стульев смотрят на телевизор, на табло номер, который никто не вызовет
static func waiting(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_open(L, x, z, w, h, 2, LD.E_ARCH)
	_lights(L, x, z, w, h, LD.L_ON, false)
	var cxw := x + w / 2
	L.add_deco({"k": "tv_on", "p": _wall(L, cxw, z, 3, 0.0, 0.45), "r": LD.dir_yaw(3), "ch": "static" if L.rng.randf() < 0.5 else "news"})
	L.add_deco({"k": "text", "key": "sign.ticket", "p": _wall(L, cxw - 2, z, 3, 2.15), "r": LD.dir_yaw(3), "color": Color(1.0, 0.18, 0.08),
		"px": 0.0032, "plate": true, "plate_size": Vector2(0.95, 0.42), "glow": 1.3})
	L.add_deco({"k": "chairs", "p": _mid(L, x, z, w, h) + Vector3(0, 0, 1.2), "r": LD.dir_yaw(3), "cols": 6, "rows": 3})
	L.add_deco({"k": "obj", "what": "cooler", "p": _wall(L, x, z + h - 1, 2, 0.0, 0.4), "r": LD.dir_yaw(2), "wrong": "none"})
	_model(L, "potted_plant_04", _wall(L, x + w - 1, z, 0, 0.0, 0.4), 0.0, PLANT_S)
	_model(L, "wall_clock", _wall(L, x + w - 1, z + h / 2, 0, 2.1), LD.dir_yaw(0), 1.0, false)
	L.add_deco({"k": "sound", "p": _wall(L, x + w - 1, z + h / 2, 0, 2.0), "snd": "clock_tick", "every": 0.0, "vol": -14.0, "max_dist": 10.0})
	if L.rng.randf() < 0.6:
		L.add_deco({"k": "copy", "who": "civ_f", "wrong": "seated_air", "p": _mid(L, x, z, w, h) + Vector3(0.85, 0, 1.2), "r": LD.dir_yaw(1), "seed": L.rng.randi(), "react": true})


## Холл отеля: диваны, столики, цветы, под потолком медленно крутятся вентиляторы
static func lounge(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_open(L, x, z, w, h, 3, LD.E_ARCH)
	_lights(L, x, z, w, h, LD.L_ON)
	var m := _mid(L, x, z, w, h)
	var sofas := ["sofa_02", "sofa_03", "Sofa_01"]
	for k in 2:
		var c := m + Vector3(-2.6 + k * 5.2, 0, 0)
		_model(L, sofas[L.rng.randi_range(0, 2)], c + Vector3(0, 0, -1.3), 0.0)
		_model(L, "modern_coffee_table_01" if k == 0 else "CoffeeTable_01", c, 0.0)
		_model(L, "ArmChair_01" if k == 0 else "modern_arm_chair_01", c + Vector3(1.4, 0, 0.3), -PI * 0.5)
	for corner in [Vector2i(x, z), Vector2i(x + w - 1, z + h - 1)]:
		var into := Vector3(-0.55, 0, -0.55) if corner.x == x else Vector3(0.55, 0, 0.55)
		_model(L, "potted_plant_04", _c(L, corner.x, corner.y) + into, L.rng.randf() * TAU, PLANT_S)
	for k in 2:
		L.add_deco({"k": "spin", "id": "ceiling_fan", "p": m + Vector3(-2.6 + k * 5.2, 0, 0), "r": 0.0, "speed": 1.6 + k * 0.4, "on_ceiling": true})
	_model(L, "hanging_picture_frame_01", _wall(L, x + w / 2, z, 3, 1.6), LD.dir_yaw(3), 1.0, false)
	L.add_deco({"k": "sound", "p": m + Vector3(0, 2.4, 0), "snd": "store_muzak", "every": 0.0, "vol": -22.0, "max_dist": 14.0})


## Детский праздник: стол с тортом, шарики, колпаки, магнитофон играет поплывшую мелодию. Гостей нет
static func party(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_open(L, x, z, w, h, 2, LD.E_DOOR)
	_lights(L, x, z, w, h, LD.L_ON, false)
	L.light[LD.idx(x + w - 1, z + h - 1)] = LD.L_FLICK
	var m := _mid(L, x, z, w, h)
	L.add_deco({"k": "cake", "p": m, "r": 0.0})
	for k in 6:
		var a := k * TAU / 6.0
		_model(L, "plastic_monobloc_chair_01", m + Vector3(cos(a) * 1.25, 0, sin(a) * 1.25), -a - PI * 0.5, 0.85)
	# гелиевые шарики упёрлись в потолок, ленточки висят
	for k in 6:
		var bx := x + L.rng.randi_range(0, w - 1)
		var bz := z + L.rng.randi_range(0, h - 1)
		# разброс — своим генератором, чтобы не сдвигать общий (раскладка мира по сиду та же)
		var hr := RandomNumberGenerator.new()
		hr.seed = hash(Vector3i(bx, bz, k))
		var bp := _c(L, bx, bz) + Vector3(hr.randf_range(-0.6, 0.6), L.height_m(bx, bz) - 0.01, hr.randf_range(-0.6, 0.6))
		L.add_deco({"k": "obj", "what": "balloon", "p": bp, "r": hr.randf() * TAU, "wrong": "none"})
	L.add_deco({"k": "text", "key": "sign.party", "p": _wall(L, x + w / 2, z, 3, 2.05), "r": LD.dir_yaw(3), "color": Color(0.85, 0.15, 0.35),
		"px": 0.0055, "hand": true})
	_model(L, "boombox", _wall(L, x, z + h / 2, 2, 0.0, 0.3), LD.dir_yaw(2), 1.0, false)
	L.add_deco({"k": "sound", "p": _wall(L, x, z + h / 2, 2, 0.3, 0.3), "snd": "jingle_wrong", "every": 0.0, "vol": -10.0, "max_dist": 16.0})


## Переговорная: длинный стол, стулья, проектор светит в стену белым квадратом
static func conference(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	L._open_border(x, z, w, h, 1, LD.E_DOOR)
	L._open_border(x, z, w, h, 3, LD.E_DOOR)
	_lights(L, x, z, w, h, LD.L_DEAD)
	L.light[LD.idx(x + w - 2, z + h / 2)] = LD.L_FLICK
	var m := _mid(L, x, z, w, h)
	var tsy := 0.86
	for k in 2:
		_model(L, "dining_table", m + Vector3(-1.1 + k * 2.2, 0, 0), PI * 0.5, Vector3(1.0, tsy, 1.0))
	for k in 4:
		for sd in [-1.0, 1.0]:
			_model(L, "dining_chair_02", m + Vector3(-2.4 + k * 1.6, 0, 0.85 * sd), PI if sd > 0.0 else 0.0)
	# проектор на краю стола смотрит на западную стену; кадр — на ней
	L.add_deco({"k": "projector", "p": m + Vector3(1.45, 0, 0), "r": LD.dir_yaw(2), "dist": w * 0.5 * LD.C + 1.45 - 0.13, "on": ["dining_table", tsy]})
	_model(L, "classic_laptop", m + Vector3(-0.5, 0, 0.1), 0.6, 0.55, false, 0.0, {"on": ["dining_table", tsy]})
	_model(L, "clipboard", m + Vector3(0.6, 0, -0.2), 1.2, 1.0, false, 0.0, {"on": ["dining_table", tsy]})
	_model(L, "plastic_bottle_gallon", _wall(L, x + w - 1, z, 0, 0.0, 0.4), 0.0)


## Архив: проходы между стеллажами, бумаги на полу, у стены стол с лампой
static func archive(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_open(L, x, z, w, h, 2, LD.E_ARCH)
	_lights(L, x, z, w, h, LD.L_FLICK)
	for i in range(1, w - 1, 2):
		for j in range(1, h - 1):
			var shelf := "wooden_bookshelf_worn" if (i + j) % 3 == 0 else "steel_frame_shelves_03"
			_model(L, shelf, _c(L, x + i, z + j) + Vector3(0, 0, 0), PI * 0.5)
	for k in 5:
		L.add_deco({"k": "papers", "p": _c(L, x + L.rng.randi_range(0, w - 1), z + L.rng.randi_range(0, h - 1)), "r": L.rng.randf() * TAU})
	_model(L, "drawer_cabinet", _wall(L, x, z, 3, 0.0, 0.35), LD.dir_yaw(3))
	L.add_deco({"k": "obj", "what": "desk", "p": _wall(L, x + w - 1, z + h - 1, 1, 0.0, 0.5), "r": LD.dir_yaw(1), "wrong": "none"})
	_model(L, "office_notepads", _wall(L, x + w - 1, z + h - 1, 1, 0.0, 0.6), 0.3, 0.4, false, 0.0, {"on": ["metal_office_desk", 1.0]})


## Лифтовой холл: три лифта, кнопка вызова горит; лифт иногда звенит, но двери не открываются
static func elevators(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	L._open_border(x, z, w, h, 1, LD.E_ARCH)
	L._open_border(x, z, w, h, 0, LD.E_OPEN)
	_lights(L, x, z, w, h, LD.L_ON, false)
	for k in 3:
		var ex := x + 1 + k * 2 if w >= 6 else x + k
		L.add_deco({"k": "elevator", "p": _wall(L, ex, z, 3, 0.0), "r": LD.dir_yaw(3), "seed": L.rng.randi()})
	_model(L, "modular_street_seating", _wall(L, x + w / 2, z + h - 1, 1, 0.0, 0.5), LD.dir_yaw(1))
	_model(L, "potted_plant_04", _c(L, x, z + h - 1) + Vector3(-0.6, 0, 0.6), 0.0, PLANT_S)


## Манекены: белые фигуры стоят лицом к стенам. Одна — нет
static func mannequins(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_open(L, x, z, w, h, 2, LD.E_ARCH)
	_lights(L, x, z, w, h, LD.L_DEAD)
	L.light[LD.idx(x + w / 2, z + h / 2)] = LD.L_ON
	L.light[LD.idx(x + 1, z + 1)] = LD.L_FLICK
	var placed := 0
	for i in w:
		for j in h:
			var sides := L.wall_sides(x + i, z + j)
			if sides.is_empty() or L.rng.randf() < 0.55 or placed >= 8:
				continue
			var sd: int = sides[0]
			# лицом к стене, в полуметре от неё
			L.add_deco({"k": "mannequin", "p": L.wall_point(x + i, z + j, sd, 0.45), "r": LD.dir_yaw(sd) + PI, "seed": L.rng.randi()})
			placed += 1
	var m := _mid(L, x, z, w, h)
	L.add_deco({"k": "mannequin", "p": m + Vector3(0.3, 0, 0.8), "r": L.rng.randf() * TAU, "seed": L.rng.randi(), "watch": true})


## Кухня: плита, микроволновка, стол, банки, гудит холодильник
static func kitchen(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_open(L, x, z, w, h, 1, LD.E_DOOR)
	_lights(L, x, z, w, h, LD.L_ON)
	_model(L, "electric_stove", _wall(L, x + 1, z, 3, 0.0, 0.4), LD.dir_yaw(3))
	L.add_deco({"k": "fridge", "p": _wall(L, x + 3, z, 3, 0.0, 0.4), "r": LD.dir_yaw(3)})
	var m := _mid(L, x, z, w, h)
	var ts := Vector3(1.0, 1.35, 1.1)
	_model(L, "WoodenTable_01", m + Vector3(0, 0, 0.8), 0.0, ts)
	_model(L, "vintage_microwave", m + Vector3(-0.35, 0, 0.78), 0.25, 0.5, false, 0.0, {"on": ["WoodenTable_01", ts.y]})
	_model(L, "russian_food_cans_01", m + Vector3(0.45, 0, 0.92), 0.4, 1.0, false, 0.0, {"on": ["WoodenTable_01", ts.y]})
	_model(L, "can_rusted", m + Vector3(0.62, 0, 0.7), 1.3, 1.0, false, 0.0, {"on": ["WoodenTable_01", ts.y]})
	for k in 3:
		_model(L, "can_rusted", m + Vector3(L.rng.randf_range(-1.5, 1.5), 0, L.rng.randf_range(-1.0, 2.0)), L.rng.randf() * TAU, 1.0, false)
	_model(L, "metal_trash_can", _wall(L, x + w - 1, z + h - 1, 0, 0.0, 0.35), 0.0)
	_model(L, "folding_wooden_stool", m + Vector3(0.9, 0, 1.5), 0.7)


## Спальня посреди огромного тёмного зала: кровать, тумбочка, будильник, лампочка на шнуре
static func bedroom(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_DARK, 0)
	_open(L, x, z, w, h, 3, LD.E_OPEN)
	for i in w:
		for j in h:
			var ci := LD.idx(x + i, z + j)
			L.used[ci] = 2
			L.light[ci] = LD.L_NONE
	var m := _mid(L, x, z, w, h)
	var cc := Vector2i(x + w / 2, z + h / 2)
	L.light[LD.idx(cc.x, cc.y)] = LD.L_BULB
	_model(L, "old_bed_frame", m, L.rng.randf_range(-0.3, 0.3))
	_model(L, "ClassicNightstand_01", m + Vector3(1.2, 0, -0.6), 0.0)
	_model(L, "alarm_clock_01", m + Vector3(1.2, 0, -0.62), 0.3, 1.0, false, 0.0, {"on": ["ClassicNightstand_01", 1.0]})
	# лампочка на шнуре — над той клеткой, где источник L_BULB
	L.add_deco({"k": "bulb", "p": _c(L, cc.x, cc.y), "r": 0.0})
	L.add_deco({"k": "sound", "p": m + Vector3(1.2, 0.7, -0.6), "snd": "clock_tick", "every": 0.0, "vol": -12.0, "max_dist": 9.0})


## Вентиляторная: большой вентилятор в стене, наружные блоки, воздуховоды, ровный ветер
static func fans(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_open(L, x, z, w, h, 2, LD.E_ARCH)
	_lights(L, x, z, w, h, LD.L_FLICK)
	L.add_deco({"k": "fan_big", "p": _wall(L, x + w / 2, z, 3, 1.4, 0.0), "r": LD.dir_yaw(3)})
	for k in 3:
		_model(L, "exterior_aircon_unit", _wall(L, x + 1 + k * 2, z + h - 1, 1, 0.0, 0.4), LD.dir_yaw(1))
	L.add_deco({"k": "pipes", "p": _c(L, x + w / 2, z + h / 2), "r": 0.0, "len": (w - 1) * LD.C, "y": L.height_m(x, z) - 0.35})
	L.add_deco({"k": "drips", "p": _c(L, x + w - 2, z + 1), "r": 0.0})


## Прачечная: ряд стиральных машин, одна крутится
static func laundry(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_open(L, x, z, w, h, 2, LD.E_DOOR)
	_lights(L, x, z, w, h, LD.L_ON)
	var run := L.rng.randi_range(0, w - 1)
	for i in w:
		L.add_deco({"k": "washer", "p": _wall(L, x + i, z, 3, 0.0, 0.35), "r": LD.dir_yaw(3), "running": i == run})
	_model(L, "plastic_container", _c(L, x + 1, z + h - 2), 0.4)
	_model(L, "metal_stool_02", _c(L, x + w - 2, z + h - 2), 0.0)


## Лес колонн: колонны в каждой клетке, редкий свет — как бетонный лес
static func pillar_forest(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	for k in 6:
		L._open_border(x, z, w, h, k % 4, LD.E_OPEN)
	for i in range(1, w):
		for j in range(1, h):
			if L.rng.randf() < 0.82:
				L.post[LD.idx(x + i, z + j)] = 1
	for i in w:
		for j in h:
			var ci := LD.idx(x + i, z + j)
			L.used[ci] = 2
			L.light[ci] = LD.L_ON if (i % 4 == 1 and j % 4 == 1) else (LD.L_DEAD if (i + j) % 5 == 0 else LD.L_NONE)


## Комнаты за стеклом: решётка комнат через окна; в каждой своё — и не во всякую можно войти
static func windows(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_open(L, x, z, w, h, 2, LD.E_ARCH)
	_lights(L, x, z, w, h, LD.L_ON)
	# стены-окна между квадратами 3×3
	for i in w:
		for j in h:
			if i % 3 == 2 and i < w - 1:
				L.set_edge(x + i, z + j, 0, LD.E_WINDOW)
			if j % 3 == 2 and j < h - 1:
				L.set_edge(x + i, z + j, 1, LD.E_WINDOW)
	# пара проходов, чтобы попасть внутрь
	L.set_edge(x + 2, z + 1, 0, LD.E_DOOR)
	L.set_edge(x + 4, z + 5, 1, LD.E_DOOR)
	var things := ["chair", "tv", "desk", "cabinet", "balloon", "wheelchair"]
	for bi in 3:
		for bj in 3:
			var c := _c(L, x + bi * 3 + 1, z + bj * 3 + 1)
			var r := L.rng.randf()
			if r < 0.15:
				L.add_deco({"k": "mannequin", "p": c, "r": L.rng.randf() * TAU, "seed": L.rng.randi()})
			elif r < 0.85:
				L.add_deco({"k": "obj", "what": things[L.rng.randi_range(0, things.size() - 1)], "p": c, "r": L.rng.randf() * TAU, "wrong": "none"})


## Выставка: бюст и кошка на постаментах за верёвками, картины без картин
static func museum(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_open(L, x, z, w, h, 2, LD.E_ARCH)
	_lights(L, x, z, w, h, LD.L_ON, false)
	var m := _mid(L, x, z, w, h)
	var items := ["marble_bust_01", "concrete_cat_statue", "vintage_suitcase", "rubber_duck_toy"]
	for k in 3:
		var p := m + Vector3(-2.4 + k * 2.4, 0, -0.6)
		L.add_deco({"k": "pedestal", "p": p, "r": 0.0, "id": items[(k + L.rng.randi_range(0, 3)) % items.size()]})
		L.add_deco({"k": "ropes", "p": p + Vector3(-0.8, 0, 0.8), "r": 0.0, "len": 1.6})
	for k in 3:
		_model(L, "hanging_picture_frame_01", _wall(L, x + 1 + k * 3, z, 3, 1.6), LD.dir_yaw(3), 1.0, false)
	L.add_deco({"k": "text", "key": "sign.museum", "p": _wall(L, x, z + h / 2, 2, 1.5), "r": LD.dir_yaw(2), "color": Color(0.1, 0.1, 0.12),
		"px": 0.0028, "plate": true, "plate_color": Color(0.88, 0.86, 0.8), "plate_size": Vector2(0.7, 0.3)})
	_model(L, "modular_street_seating", m + Vector3(0, 0, 1.8), PI)


## Комната, где идёт дождь: с потолка льёт, пол в воде
static func rain_room(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_DARK, 0)
	_open(L, x, z, w, h, 2, LD.E_ARCH)
	_lights(L, x, z, w, h, LD.L_FLICK, false)
	for i in w:
		for j in h:
			L.water[LD.idx(x + i, z + j)] = 1
	L.add_deco({"k": "rain", "p": _mid(L, x, z, w, h), "r": 0.0, "size": Vector2(w * LD.C - 0.4, h * LD.C - 0.4)})


## Лабиринт низких перегородок посреди зала: над ними видно весь зал, а пройти — не сразу
static func lowmaze(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_open(L, x, z, w, h, 4, LD.E_OPEN)
	_lights(L, x, z, w, h, LD.L_ON)
	for i in range(1, w - 1):
		for j in range(1, h - 1):
			var c := _c(L, x + i, z + j)
			if L.rng.randf() < 0.42:
				L.add_deco({"k": "panel", "p": c + Vector3(LD.C * 0.5, 0, 0), "r": 0.0, "size": Vector3(0.12, 1.25, LD.C + 0.06)})
			if L.rng.randf() < 0.42:
				L.add_deco({"k": "panel", "p": c + Vector3(0, 0, LD.C * 0.5), "r": PI * 0.5, "size": Vector3(0.12, 1.25, LD.C + 0.06)})


## Рыжие разводы протечек на потолочных плитах и потёки по обоям от потолка — по всему миру, но редко
static func sprinkle_stains(L: LayerData, lay: int, origin: Vector2i) -> void:
	var rr := L.rng
	for z in range(origin.y - 150, origin.y + 151):
		for x in range(origin.x - 150, origin.x + 151):
			var i := LD.idx(x, z)
			if L.flo[i] != LD.F_FLOOR or not L.flat0(i) or L.used[i] == 2:
				continue
			var hh := L.height_m(x, z)
			if hh < 2.3 or hh > 5.0:
				continue
			var r := rr.randf()
			var wet := L.zone[i] == LD.Z_DARK or lay == 1
			if r < (0.07 if wet else 0.035):
				var c := _c(L, x, z)
				L.add_deco({"k": "ceil_stain", "p": c + Vector3(rr.randf_range(-0.7, 0.7), 0, rr.randf_range(-0.7, 0.7)), "r": rr.randf() * TAU,
					"s": rr.randf_range(0.7, 2.0), "y": hh, "dark": wet})
			elif r < (0.1 if wet else 0.05):
				var sides := L.wall_sides(x, z)
				if sides.is_empty():
					continue
				var sd: int = sides[rr.randi_range(0, sides.size() - 1)]
				L.add_deco({"k": "streak", "p": L.wall_point(x, z, sd, 0.0, rr.randf_range(-0.8, 0.8)), "r": LD.dir_yaw(sd), "y": hh,
					"len": rr.randf_range(0.8, 2.2)})


# ------------------------------------------------------------ спуски и странные коридоры

## Клетка коридора: k — вдоль, side — поперёк (для коридоров, повёрнутых по x или по z)
static func _ccell(x: int, z: int, along_z: bool, k: int, side := 0) -> Vector2i:
	return Vector2i(x + (side if along_z else k), z + (k if along_z else side))


## Открыть торец коридора (k = 0 или последний) на всю ширину
static func _open_end(L: LayerData, x: int, z: int, along_z: bool, k: int, width: int, last: bool, kind := LD.E_OPEN) -> void:
	for side in width:
		var c := _ccell(x, z, along_z, k, side)
		var d := (1 if along_z else 0) if last else (3 if along_z else 2)
		L.set_edge(c.x, c.y, d, kind)


## Профиль высот вдоль коридора: каждая клетка — своя высота; между разными — пандус или лестница
static func _profile(L: LayerData, x: int, z: int, along_z: bool, width: int, prof: Array, stairs_down: bool) -> void:
	var n := prof.size()
	var d := 1 if along_z else 0
	for side in width:
		for k in n:
			var c := _ccell(x, z, along_z, k, side)
			var ci := LD.idx(c.x, c.y)
			var hk: int = prof[k]
			L.fh[ci] = hk
			L.ramp[ci] = 0
			if k < n - 1 and int(prof[k + 1]) != hk:
				var down := int(prof[k + 1]) < hk
				L.ramp[ci] = (d + 5) if (down == stairs_down) else (d + 1)


## Коридор отеля: длинный, тесный, на дверях номера; двери открываются в стену
static func hotel(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_ceil_all(L, x, z, w, h, 27)
	var along_z := h > w
	var n := maxi(w, h)
	_open_end(L, x, z, along_z, 0, 1, false)
	_open_end(L, x, z, along_z, n - 1, 1, true)
	var sides := [0, 2] if along_z else [1, 3]
	var num := 100 * L.rng.randi_range(1, 6) + 1
	for k in n:
		var c := _ccell(x, z, along_z, k)
		var ci := LD.idx(c.x, c.y)
		L.used[ci] = 2
		L.light[ci] = LD.L_BULB if k % 2 == 0 else LD.L_NONE
		if k % 7 == 4:
			L.light[ci] = LD.L_FLICK
		if L.light[ci] == LD.L_BULB:
			# плафон молочного стекла вместо плоского пятна на потолке
			L.add_deco({"k": "dome", "p": _c(L, c.x, c.y), "r": 0.0})
		if k % 2 == 1 and k < n - 1:
			for sd in sides:
				var s2: int = sd
				L.add_deco({"k": "door", "kind": "wall", "p": L.wall_point(c.x, c.y, s2, 0.0), "r": LD.dir_yaw(s2)})
				L.add_deco({"k": "text", "txt": str(num), "p": L.wall_point(c.x, c.y, s2, 0.0) + Vector3(0, 2.2, 0), "r": LD.dir_yaw(s2),
					"px": 0.0024, "color": Color(0.85, 0.7, 0.35), "plate": true, "plate_color": Color(0.14, 0.09, 0.05), "plate_size": Vector2(0.24, 0.1)})
				num += 1
	if L.rng.randf() < 0.5:
		var mid := _ccell(x, z, along_z, n / 2)
		# под потолком 2,7 м в коридоре шириной в клетку зонт сложен
		L.add_deco({"k": "obj", "what": "cart", "p": _c(L, mid.x, mid.y), "r": 0.12 + (PI * 0.5 if along_z else 0.0), "wrong": "none", "parasol": "closed"})


## Спуск: длинный коридор уходит пандусами и лестницей на 9 м вниз; внизу высокая тёмная щель
static func descent(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	var along_z := h > w
	var n := maxi(w, h)
	var prof := []
	for k in n:
		var v := 0
		if k >= 3 and k <= 5:
			v = -10 * (k - 2)
		elif k >= 6 and k <= 6:
			v = -30
		elif k >= 7 and k <= 9:
			v = -30 - 10 * (k - 6)
		elif k >= 10 and k <= 11:
			v = -60
		elif k >= 12 and k <= 14:
			v = -60 - 10 * (k - 11)
		elif k >= 15:
			v = -90
		prof.append(v)
	_profile(L, x, z, along_z, 2, prof, true)
	# пандусы на первом и третьем участке, лестница — посередине
	for side in 2:
		for k in n:
			var c := _ccell(x, z, along_z, k, side)
			var ci := LD.idx(c.x, c.y)
			if L.ramp[ci] >= 5 and (k < 6 or k > 9):
				L.ramp[ci] -= 4
			L.used[ci] = 2
			L.light[ci] = LD.L_NONE
	var lights := {0: LD.L_ON, 4: LD.L_ON, 8: LD.L_FLICK, 12: LD.L_ON, 17: LD.L_DEAD, n - 1: LD.L_BULB}
	for k in lights.keys():
		var c2 := _ccell(x, z, along_z, mini(int(k), n - 1))
		L.light[LD.idx(c2.x, c2.y)] = int(lights[k])
	_open_end(L, x, z, along_z, 0, 2, false, LD.E_ARCH)
	var bot := _ccell(x, z, along_z, n - 1, 1)
	if L.rng.randf() < 0.5:
		L.add_deco({"k": "hazmat", "p": _cf(L, bot.x, bot.y), "r": LD.dir_yaw(1 if along_z else 0), "pose": "lie", "seed": L.rng.randi(), "note": true, "key": "note.a_hz3"})
	else:
		L.add_deco({"k": "lone_door", "p": _cf(L, bot.x, bot.y), "r": 0.0 if along_z else PI * 0.5})
	var top := _ccell(x, z, along_z, 0)
	_entry(L, top.x, top.y)


## Воронка: концентрические ступени по 0,9 м сходятся к середине; вниз ведёт одна лестница
static func funnel(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_open(L, x, z, w, h, 4, LD.E_ARCH)
	_ceil_all(L, x, z, w, h, 45)
	var rmax := mini(w, h) / 2 - 1
	for i in w:
		for j in h:
			var ci := LD.idx(x + i, z + j)
			var r := mini(mini(i, j), mini(w - 1 - i, h - 1 - j))
			L.fh[ci] = -9 * mini(r, rmax)
			L.used[ci] = 2
			L.light[ci] = LD.L_ON if ((i + j) % 2 == 0 and r <= 2) else LD.L_NONE
	var sx := x + w / 2
	var st := []
	for r in rmax:
		st.append(Vector2i(sx, z + h - 1 - r))
	_slope(L, st, 3, 0, -9, true)
	var cc := Vector2i(x + w / 2, z + h / 2)
	L.light[LD.idx(cc.x, cc.y)] = LD.L_BULB
	L.add_deco({"k": "tv_on", "p": _cf(L, cc.x, cc.y) + Vector3(-0.6, 0, -0.6), "r": PI * 0.25, "ch": "static"})
	_entry(L, sx, z + h - 1)


## Наклонный зал: пол целиком уходит вниз; кресла скатились к нижней стене
static func slope_hall(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_ceil_all(L, x, z, w, h, 45)
	L.set_edge(x + 2, z, 3, LD.E_ARCH)
	L.set_edge(x + w - 3, z, 3, LD.E_ARCH)
	for i in w:
		for j in h:
			var ci := LD.idx(x + i, z + j)
			L.used[ci] = 2
			L.light[ci] = LD.L_ON if (i + j) % 2 == 0 else LD.L_NONE
			if j == 0:
				continue
			if j == h - 1:
				L.fh[ci] = -6 * (h - 2)
			else:
				L.fh[ci] = -6 * (j - 1)
				L.ramp[ci] = 2
	for k in 4:
		L.add_deco({"k": "obj", "what": "ochair", "p": _cf(L, x + 1 + k * 2, z + h - 1) + Vector3(0, 0, 0.5), "r": L.rng.randf() * TAU, "wrong": "none"})
	L.add_deco({"k": "papers", "p": _cf(L, x + w / 2, z + h - 1), "r": 0.0})
	_entry(L, x + 2, z)


## Амфитеатр: ряды-ступени с креслами спускаются к сцене; на сцене стул под одной лампой
static func amphitheater(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_ceil_all(L, x, z, w, h, 52)
	L.set_edge(x + w / 2, z, 3, LD.E_ARCH)
	L.set_edge(x + 1, z, 3, LD.E_DOOR)
	var ax := x + w / 2
	for i in w:
		for j in h:
			var ci := LD.idx(x + i, z + j)
			L.fh[ci] = -6 * mini(j, 5)
			L.used[ci] = 2
			L.light[ci] = LD.L_DEAD if j < 6 else LD.L_NONE
			if j < 6 and (i + j) % 3 == 0:
				L.light[ci] = LD.L_ON
	var st := []
	for j in 5:
		st.append(Vector2i(ax, z + j))
	_slope(L, st, 1, 0, -6, true)
	for j in range(1, 5):
		for half in 2:
			var cxh := x + (w / 4 if half == 0 else w * 3 / 4)
			L.add_deco({"k": "chairs", "p": _cf(L, cxh, z + j) + Vector3(0, 0, -0.3), "r": LD.dir_yaw(1), "cols": 4, "rows": 1})
	var stage := Vector2i(ax, z + h - 2)
	L.light[LD.idx(stage.x, stage.y)] = LD.L_BULB
	L.add_deco({"k": "obj", "what": "chair", "p": _cf(L, stage.x, stage.y), "r": LD.dir_yaw(1) + PI, "wrong": "none"})
	_entry(L, ax, z)


## Обрыв: коридор просто кончается пропастью
static func drop_end(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	var along_z := h > w
	var n := maxi(w, h)
	for side in 2:
		for k in n:
			var c := _ccell(x, z, along_z, k, side)
			var ci := LD.idx(c.x, c.y)
			L.used[ci] = 2
			L.light[ci] = LD.L_NONE
			if k >= n - 3:
				L.fh[ci] = -200
	for k in range(0, n - 3, 2):
		var c2 := _ccell(x, z, along_z, k)
		L.light[LD.idx(c2.x, c2.y)] = LD.L_ON if k < n - 6 else LD.L_FLICK
	_open_end(L, x, z, along_z, 0, 2, false, LD.E_ARCH)
	var g := _ccell(x, z, along_z, n - 4)
	_graf(L, g.x, g.y, 2 if along_z else 3, "graf.dont_look", 1.4)
	var top := _ccell(x, z, along_z, 0)
	_entry(L, top.x, top.y)


## Лестница к двери: ступени ведут вверх, к площадке с дверью в стене — она открывается в стену
static func stairs_door(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_ceil_all(L, x, z, w, h, 56)
	L.set_edge(x + w / 2, z + h - 1, 1, LD.E_ARCH)
	L.set_edge(x + w - 1, z + h - 2, 0, LD.E_DOOR)
	_lights(L, x, z, w, h, LD.L_ON)
	var sx := x + w / 2
	for i in range(1, w - 1):
		L.fh[LD.idx(x + i, z)] = 24
	_slope(L, [Vector2i(sx, z + 2), Vector2i(sx, z + 1)], 3, 0, 12, true)
	for i in range(1, w - 1):
		if x + i != sx:
			_rail(L, x + i, z, 1)
	L.add_deco({"k": "door", "kind": "wall", "p": L.wall_point(sx, z, 3, 0.0) + Vector3(0, 2.4, 0), "r": LD.dir_yaw(3)})
	_entry(L, sx, z + h - 1)


## Спуск в воду: широкая лестница уходит в тёмный затопленный зал
static func water_stairs(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_DARK, 0)
	L.set_edge(x + w / 2, z, 3, LD.E_ARCH)
	L.set_edge(x + 1, z, 3, LD.E_ARCH)
	for i in w:
		for j in h:
			var ci := LD.idx(x + i, z + j)
			L.used[ci] = 2
			L.light[ci] = LD.L_NONE
			if j >= 6:
				L.fh[ci] = -30
				L.water[ci] = 1
		_slope(L, [Vector2i(x + i, z + 3), Vector2i(x + i, z + 4), Vector2i(x + i, z + 5)], 1, 0, -10, true)
	L.light[LD.idx(x + w / 2, z + 1)] = LD.L_ON
	L.light[LD.idx(x + 1, z + 4)] = LD.L_FLICK
	L.light[LD.idx(x + w / 2, z + h - 2)] = LD.L_DEAD
	L.add_deco({"k": "drips", "p": _cf(L, x + w / 2, z + 7), "r": 0.0})
	L.add_deco({"k": "sound", "p": _cf(L, x + w / 2, z + 8) + Vector3(0, 1, 0), "snd": "water_amb", "every": 0.0, "vol": -10.0, "max_dist": 18.0})
	_entry(L, x + w / 2, z)


## Коридор-«горки»: лестницы то вниз, то вверх
static func updown(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	var along_z := h > w
	var n := maxi(w, h)
	var base := [0, 0, -10, -20, -20, -10, 0, 0, -10, -20, -30, -30, -20, -10, 0, 0, -10, -10, 0, 0]
	var prof := []
	for k in n:
		prof.append(base[k % base.size()] if k < n - 2 else 0)
	_profile(L, x, z, along_z, 1, prof, L.rng.randf() < 0.5)
	for k in n:
		var c := _ccell(x, z, along_z, k)
		var ci := LD.idx(c.x, c.y)
		L.used[ci] = 2
		L.light[ci] = LD.L_ON if k % 3 == 0 else LD.L_NONE
	_open_end(L, x, z, along_z, 0, 1, false)
	_open_end(L, x, z, along_z, n - 1, 1, true)
	var top := _ccell(x, z, along_z, 0)
	_entry(L, top.x, top.y)


## Двери в потолке
static func ceiling_doors(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_ceil_all(L, x, z, w, h, 27)
	_open(L, x, z, w, h, 2, LD.E_ARCH)
	_lights(L, x, z, w, h, LD.L_ON)
	# дверь лежит в своей клетке (по центру, светильника там нет); занятая или соседняя с занятой клетка —
	# ищется ближайшая свободная (без новых обращений к L.rng: те же четыре числа на дверь, что и раньше)
	var taken := {}
	for k in 5:
		var i := L.rng.randi_range(0, w - 1)
		var j := L.rng.randi_range(0, h - 1)
		var jit := L.rng.randf_range(-0.3, 0.3)
		var rot := L.rng.randi_range(0, 3) * PI * 0.5
		var cell := _free_cell(Vector2i(i, j), w, h, taken)
		if cell.x < 0:
			continue
		taken[cell] = true
		_late_light(L, x + cell.x, z + cell.y, LD.L_NONE)
		L.add_deco({"k": "door", "kind": "ceiling", "p": _c(L, x + cell.x, z + cell.y) + Vector3(jit * 0.15, 0, 0), "r": rot})


## Ближайшая к want клетка комнаты w×h, не занятая и без занятых соседей по стороне (иначе — просто не занятая);
## (−1, −1) — свободных нет
static func _free_cell(want: Vector2i, w: int, h: int, taken: Dictionary) -> Vector2i:
	for strict in [true, false]:
		for r in maxi(w, h):
			for dj in range(-r, r + 1):
				for di in range(-r, r + 1):
					if maxi(absi(di), absi(dj)) != r:
						continue
					var c := want + Vector2i(di, dj)
					if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h or taken.has(c):
						continue
					var ok := true
					if strict:
						for o: Vector2i in LD.DIRS:
							if taken.has(c + o):
								ok = false
					if ok:
						return c
	return Vector2i(-1, -1)


## Разноуровневый офис: островки пола выше на 0,6–1,2 м, к каждому — ступеньки; на островках столы
static func split_level(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	_ceil_all(L, x, z, w, h, 42)
	_open(L, x, z, w, h, 3, LD.E_ARCH)
	_lights(L, x, z, w, h, LD.L_ON)
	var plats := [[Vector2i(1, 1), Vector2i(3, 2), 6], [Vector2i(6, 1), Vector2i(3, 3), 9], [Vector2i(2, 5), Vector2i(4, 2), 12]]
	for pl in plats:
		var o: Vector2i = pl[0]
		var sz: Vector2i = pl[1]
		var hh: int = pl[2]
		if o.x + sz.x >= w or o.y + sz.y >= h:
			continue
		for i in sz.x:
			for j in sz.y:
				L.fh[LD.idx(x + o.x + i, z + o.y + j)] = hh
		# ступени снизу к середине островка (с юга, если там пол, иначе с севера)
		var mx := x + o.x + sz.x / 2
		if o.y + sz.y < h - 1:
			_slope(L, [Vector2i(mx, z + o.y + sz.y)], 3, 0, hh, true)
		else:
			_slope(L, [Vector2i(mx, z + o.y - 1)], 1, 0, hh, true)
		L.add_deco({"k": "obj", "what": "desk", "p": _cf(L, x + o.x, z + o.y) + Vector3(0.6, 0, 0.6), "r": L.rng.randf() * TAU, "wrong": "none"})
		L.add_deco({"k": "obj", "what": "ochair", "p": _cf(L, x + o.x + sz.x - 1, z + o.y) + Vector3(0, 0, 0.6), "r": L.rng.randf() * TAU, "wrong": "none"})


## Кривой коридор: стены выпирают кусками разной толщины, потолок то ниже, то выше
static func crooked(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 0)
	var along_z := h > w
	var n := maxi(w, h)
	_open_end(L, x, z, along_z, 0, 2, false)
	_open_end(L, x, z, along_z, n - 1, 2, true)
	var ch := [24, 27, 32, 29, 25, 36]
	for k in n:
		var hv: int = ch[L.rng.randi_range(0, ch.size() - 1)]
		for side in 2:
			var c := _ccell(x, z, along_z, k, side)
			var ci := LD.idx(c.x, c.y)
			L.used[ci] = 2
			L.ceil_h[ci] = hv
			L.light[ci] = LD.L_ON if (k % 2 == 0 and side == 0) else LD.L_NONE
		if k == 0 or k == n - 1:
			continue
		for sd in [-1.0, 1.0]:
			if L.rng.randf() < 0.35:
				continue
			var th := L.rng.randf_range(0.15, 0.85)
			var off: float = (LD.C - th * 0.5 - 0.1) * sd
			var t := (k + 0.5) * LD.C
			var p := Vector3(x * LD.C + LD.C + off, L.floor_y, z * LD.C + t) if along_z else Vector3(x * LD.C + t, L.floor_y, z * LD.C + LD.C + off)
			L.add_deco({"k": "panel", "p": p, "r": 0.0 if along_z else PI * 0.5, "size": Vector3(th, float(hv) * 0.1 - 0.02, LD.C * L.rng.randf_range(0.5, 1.0))})
	var top := _ccell(x, z, along_z, 0)
	_entry(L, top.x, top.y)
