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
			if (w == 1 or h == 1 or String(p[0]) == "repeat") and L.rng.randf() < 0.5:
				var t := w
				w = h
				h = t
			var s := L.pick_spot(origin.x, origin.y, int(p[3]) if lay == 0 else int(p[3]) / 2, int(p[4]) if lay == 0 else int(p[4]) * 2 / 3, w, h)
			if not L.area_free(s.x, s.y, w, h):
				continue
			call_room(String(p[0]), L, s.x, s.y, w, h, lay)
			var c := LD.cell_center(s.x + w / 2, s.y + h / 2)
			L.places["room_%s_%d" % [p[0], k]] = Vector3(c.x, L.floor_y, c.y)


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


# ------------------------------------------------------------ помощники

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


static func _model(L: LayerData, id: String, p: Vector3, r: float, s: Variant = 1.0, collide := true, y := 0.0) -> void:
	L.add_deco({"k": "model", "id": id, "p": p, "r": r, "s": s, "collide": collide, "y": y})


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
	L._open_border(x, z, w, h, 0, LD.E_DOOR)
	_lights(L, x, z, w, h, LD.L_NONE)
	# свет «с боковой стены»: невидимый источник на высоте у восточной стены
	for j in range(1, h - 1):
		L.light[LD.idx(x + w - 1, z + j)] = LD.L_ASYNC
	var m := _mid(L, x, z, w, h)
	L.add_deco({"k": "side_room", "p": m, "r": 0.0, "w": w * LD.C, "h": h * LD.C})


## Офис из перегородок: ряды «кабинок», мониторы, телефоны
static func cubicles(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_OLD, 0)
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
			_model(L, id, p, L.rng.randf_range(-0.3, 0.3) + (PI if j % 4 == 1 else 0.0))
			L.add_deco({"k": "price", "p": p + Vector3(0.35, 0.95, 0.35), "r": L.rng.randf() * TAU, "text": "$%d.99" % L.rng.randi_range(19, 399)})
			if (i + j) % 4 == 2:
				L.add_deco({"k": "store_sign", "p": p + Vector3(0, 0, 0.0), "r": L.rng.randf_range(-0.2, 0.2) + (PI * 0.5 if si % 2 else 0.0), "key": signs[si % signs.size()], "v": si})
				si += 1
	var cc := _c(L, x + w - 2, z + 1)
	_model(L, "metal_office_desk", cc, 0.0, Vector3(0.8, 1.2, 0.7))
	_model(L, "CashRegister_01", cc + Vector3(0, 0.95, 0), PI, 1.0, false)
	L.add_deco({"k": "sound", "snd": "store_muzak", "p": _mid(L, x, z, w, h) + Vector3(0, 2.3, 0), "every": 0.0})
	L.add_deco({"k": "copy", "who": "civ_g", "wrong": "corner", "p": L.wall_point(x, z + h - 1, 2, 0.35), "r": LD.dir_yaw(2) + PI, "seed": L.rng.randi()})


## Место «Обследования света и плит» Async: стремянка, снятая плита и светильник
static func survey(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_YELLOW, 2)
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
	L.stamp_room(x, z, w, h, LD.Z_CONCRETE, 0)
	_open(L, x, z, w, h, 2, LD.E_OPEN)
	_lights(L, x, z, w, h, LD.L_FLICK)
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
	L.stamp_room(x, z, w, h, LD.Z_CONCRETE, 2, LD.E_DOOR)
	_lights(L, x, z, w, h, LD.L_RED)
	var m := _mid(L, x, z, w, h)
	for k in 7:
		var a := k * TAU / 7.0
		var p := m + Vector3(cos(a) * 3.6, 0, sin(a) * 3.6)
		L.add_deco({"k": "speaker", "p": p, "r": atan2(-cos(a), -sin(a)) + PI, "seed": L.rng.randi()})


## Бассейный зал: белая плитка, вода по щиколотку, колонны
static func pool(L: LayerData, x: int, z: int, w: int, h: int) -> void:
	L.stamp_room(x, z, w, h, LD.Z_TILE, 3, LD.E_ARCH)
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
