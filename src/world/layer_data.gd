class_name LayerData
extends RefCounted
## Данные одного слоя Комплекса: сетка клеток N×N (2.4 м), замкнутая «тором» — мир бесшовно бесконечен.
## Стены лежат на рёбрах клеток. Здесь же — расстановка особых комнат, кабелей Async и декора.

const N := 384
const C := 2.4
const CHUNK := 12
const NCH := N / CHUNK

# рёбра
const E_OPEN := 0
const E_WALL := 1
const E_DOOR := 2      # узкий дверной проём с перемычкой
const E_ARCH := 3      # широкий проём с перемычкой
const E_WINDOW := 4    # окно (не пройти)
# пол
const F_FLOOR := 0
const F_PIT := 1
const F_SOLID := 2     # нет клетки (пустота / сплошное)
# зоны
const Z_YELLOW := 0
const Z_DARK := 1
const Z_OLD := 2
const Z_CONCRETE := 3
const Z_ASYNC := 4
const Z_HOUSE := 5
const Z_STRETCH := 6
const Z_TILE := 7
const Z_SKY := 8
const Z_PITS := 9
const Z_CELLAR := 10
# светильники
const L_NONE := 0
const L_ON := 1
const L_FLICK := 2
const L_DEAD := 3
const L_RED := 4
const L_HOLE := 5
const L_ASYNC := 6
const L_BULB := 7
const L_GREEN := 8

const DIRS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

var layer := 0
var seed := 0
var floor_y := 0.0
var wall_e := PackedByteArray()
var wall_s := PackedByteArray()
var flo := PackedByteArray()
var zone := PackedByteArray()
var light := PackedByteArray()
var ceil_h := PackedByteArray()     # дециметры
var post := PackedByteArray()       # 1 — колонна в СЗ-углу клетки
var cable := PackedByteArray()      # биты направлений кабеля
var cable_par := PackedInt32Array() # для меток: куда вести к станции (индекс направления+1)
var cable_dist := PackedInt32Array()
var reach := PackedByteArray()
var deco := {}                      # ключ чанка -> Array[Dictionary]
var places := {}                    # именованные точки: "outpost", "spawn", "null_0"...
var rng := RandomNumberGenerator.new()


static func idx(x: int, z: int) -> int:
	return posmod(z, N) * N + posmod(x, N)


static func chunk_key(cx: int, cz: int) -> int:
	return posmod(cz, NCH) * NCH + posmod(cx, NCH)


static func cell_center(x: int, z: int) -> Vector2:
	return Vector2((x + 0.5) * C, (z + 0.5) * C)


func edge(x: int, z: int, d: int) -> int:
	match d:
		0: return wall_e[idx(x, z)]
		1: return wall_s[idx(x, z)]
		2: return wall_e[idx(x - 1, z)]
		_: return wall_s[idx(x, z - 1)]


func set_edge(x: int, z: int, d: int, v: int) -> void:
	match d:
		0: wall_e[idx(x, z)] = v
		1: wall_s[idx(x, z)] = v
		2: wall_e[idx(x - 1, z)] = v
		_: wall_s[idx(x, z - 1)] = v


static func edge_passable(v: int) -> bool:
	return v == E_OPEN or v == E_DOOR or v == E_ARCH


static func edge_solid(v: int) -> bool:
	return v == E_WALL or v == E_WINDOW


func walkable(x: int, z: int) -> bool:
	return flo[idx(x, z)] == F_FLOOR


func can_step(x: int, z: int, d: int) -> bool:
	if not edge_passable(edge(x, z, d)):
		return false
	var o: Vector2i = DIRS[d]
	return flo[idx(x + o.x, z + o.y)] == F_FLOOR


func height_m(x: int, z: int) -> float:
	return ceil_h[idx(x, z)] * 0.1


func add_deco(d: Dictionary) -> void:
	# d.p — мировые метры (на «основной» копии тора)
	var p: Vector3 = d.p
	var span := N * C
	p.x = fposmod(p.x, span)
	p.z = fposmod(p.z, span)
	d.p = p
	var cx := clampi(int(floor(p.x / (C * CHUNK))), 0, NCH - 1)
	var cz := clampi(int(floor(p.z / (C * CHUNK))), 0, NCH - 1)
	var key := cz * NCH + cx
	if not deco.has(key):
		deco[key] = []
	(deco[key] as Array).append(d)


func deco_for(cx: int, cz: int) -> Array:
	var arr: Array = deco.get(chunk_key(cx, cz), [])
	var out := []
	var wx := posmod(cx, NCH)
	var wz := posmod(cz, NCH)
	var off := Vector3((cx - wx) * C * CHUNK, 0, (cz - wz) * C * CHUNK)
	for d in arr:
		var e: Dictionary = (d as Dictionary).duplicate()
		e.p = (d.p as Vector3) + off
		out.append(e)
	return out


# ---------------------------------------------------------------- генерация

func init_arrays() -> void:
	var nn := N * N
	wall_e.resize(nn)
	wall_s.resize(nn)
	flo.resize(nn)
	zone.resize(nn)
	light.resize(nn)
	ceil_h.resize(nn)
	post.resize(nn)
	cable.resize(nn)
	reach.resize(nn)
	cable_par.resize(nn)
	cable_dist.resize(nn)
	wall_e.fill(0)
	wall_s.fill(0)
	flo.fill(F_FLOOR)
	zone.fill(Z_YELLOW)
	light.fill(L_NONE)
	ceil_h.fill(27)
	post.fill(0)
	cable.fill(0)
	reach.fill(0)
	cable_par.fill(-1)
	cable_dist.fill(-1)


## Рекурсивное деление: комнаты внутри комнат с проёмами — как офисный лабиринт Комплекса
func divide(x0: int, z0: int, w: int, h: int, openness: float) -> void:
	var stack: Array = [[x0, z0, w, h]]
	while not stack.is_empty():
		var r: Array = stack.pop_back()
		var x: int = r[0]
		var z: int = r[1]
		var ww: int = r[2]
		var hh: int = r[3]
		if ww <= 1 or hh <= 1:
			continue
		var area := ww * hh
		var stop := 0.0
		if area <= 4:
			stop = 1.0
		elif area <= 9:
			stop = 0.55
		elif area <= 20:
			stop = 0.28
		elif area <= 48:
			stop = 0.1
		elif area <= 110:
			stop = 0.03 + openness * 0.05
		if rng.randf() < stop:
			_room_extras(x, z, ww, hh)
			continue
		var vertical: bool
		if ww > hh * 1.4:
			vertical = true
		elif hh > ww * 1.4:
			vertical = false
		else:
			vertical = rng.randf() < 0.5
		if vertical:
			var s := x + rng.randi_range(1, ww - 1)
			_wall_line(s - 1, z, hh, true, openness)
			stack.append([x, z, s - x, hh])
			stack.append([s, z, x + ww - s, hh])
		else:
			var s2 := z + rng.randi_range(1, hh - 1)
			_wall_line(x, s2 - 1, ww, false, openness)
			stack.append([x, z, ww, s2 - z])
			stack.append([x, s2, ww, z + hh - s2])


func _wall_line(x: int, z: int, length: int, vertical: bool, openness: float) -> void:
	var r := rng.randf()
	if r < 0.05 + openness * 0.1:
		return
	var a := 0
	var b := length
	if r < 0.22 + openness * 0.15 and length >= 3:
		var seg := maxi(1, int(length * rng.randf_range(0.3, 0.75)))
		a = rng.randi_range(0, length - seg)
		b = a + seg
	for i in range(a, b):
		if vertical:
			wall_e[idx(x, z + i)] = E_WALL
		else:
			wall_s[idx(x + i, z)] = E_WALL
	if b - a < length:
		return
	var holes := 1 + (rng.randi_range(0, length / 6) if length >= 6 else 0)
	for k in holes:
		var p := rng.randi_range(0, length - 1)
		var t := rng.randf()
		var v := E_ARCH
		var wdt := 1
		if t < 0.32:
			v = E_DOOR
		elif t < 0.55:
			v = E_OPEN
			wdt = rng.randi_range(1, 2)
		for j in wdt:
			var q := clampi(p + j, 0, length - 1)
			if vertical:
				wall_e[idx(x, z + q)] = v
			else:
				wall_s[idx(x + q, z)] = v


func _room_extras(x: int, z: int, w: int, h: int) -> void:
	# колонны в больших залах
	if w >= 5 and h >= 5 and rng.randf() < 0.55:
		var step := 2 if rng.randf() < 0.6 else 3
		for i in range(step, w, step):
			for j in range(step, h, step):
				post[idx(x + i, z + j)] = 1
	# обрывки стен посреди больших комнат
	if w * h >= 16 and rng.randf() < 0.45:
		var n := rng.randi_range(1, 3)
		for k in n:
			var cx := x + rng.randi_range(1, w - 2)
			var cz := z + rng.randi_range(1, h - 2)
			if rng.randf() < 0.5:
				wall_e[idx(cx, cz)] = E_WALL
				if rng.randf() < 0.5:
					wall_e[idx(cx, cz + 1)] = E_WALL
			else:
				wall_s[idx(cx, cz)] = E_WALL
				if rng.randf() < 0.5:
					wall_s[idx(cx + 1, cz)] = E_WALL


func open_random_walls(p: float) -> void:
	for i in N * N:
		if wall_e[i] == E_WALL and rng.randf() < p:
			wall_e[i] = E_ARCH if rng.randf() < 0.6 else E_OPEN
		if wall_s[i] == E_WALL and rng.randf() < p:
			wall_s[i] = E_ARCH if rng.randf() < 0.6 else E_OPEN


## Прямоугольная комната-«штамп»: чистит внутренние стены, ставит внешние и проёмы
func stamp_room(x0: int, z0: int, w: int, h: int, z_id: int, openings := 2, open_kind := E_ARCH) -> void:
	for i in w:
		for j in h:
			var x := x0 + i
			var z := z0 + j
			zone[idx(x, z)] = z_id
			flo[idx(x, z)] = F_FLOOR
			post[idx(x, z)] = 0
			if i < w - 1:
				wall_e[idx(x, z)] = E_OPEN
			if j < h - 1:
				wall_s[idx(x, z)] = E_OPEN
	for i in w:
		wall_s[idx(x0 + i, z0 - 1)] = E_WALL
		wall_s[idx(x0 + i, z0 + h - 1)] = E_WALL
	for j in h:
		wall_e[idx(x0 - 1, z0 + j)] = E_WALL
		wall_e[idx(x0 + w - 1, z0 + j)] = E_WALL
	for k in openings:
		_open_border(x0, z0, w, h, rng.randi_range(0, 3), open_kind)


func _open_border(x0: int, z0: int, w: int, h: int, side: int, kind: int) -> Vector2i:
	match side:
		0:
			var j := rng.randi_range(0, h - 1)
			wall_e[idx(x0 + w - 1, z0 + j)] = kind
			return Vector2i(x0 + w - 1, z0 + j)
		1:
			var i := rng.randi_range(0, w - 1)
			wall_s[idx(x0 + i, z0 + h - 1)] = kind
			return Vector2i(x0 + i, z0 + h - 1)
		2:
			var j2 := rng.randi_range(0, h - 1)
			wall_e[idx(x0 - 1, z0 + j2)] = kind
			return Vector2i(x0, z0 + j2)
		_:
			var i2 := rng.randi_range(0, w - 1)
			wall_s[idx(x0 + i2, z0 - 1)] = kind
			return Vector2i(x0 + i2, z0)


func fill_lights_rect(x0: int, z0: int, w: int, h: int, state: int, checker := true) -> void:
	for i in w:
		for j in h:
			var x := x0 + i
			var z := z0 + j
			if checker and (x + z) % 2 != 0:
				light[idx(x, z)] = L_NONE
			else:
				light[idx(x, z)] = state


## Ставит светильники по зонам
func place_lights(dark_bias: float) -> void:
	for z in N:
		for x in N:
			var i := z * N + x
			var zn := zone[i]
			if flo[i] != F_FLOOR and flo[i] != F_PIT:
				light[i] = L_NONE
				continue
			if light[i] != L_NONE:
				continue
			var r := rng.randf()
			match zn:
				Z_YELLOW, Z_PITS, Z_STRETCH:
					if (x + z) % 2 != 0:
						continue
					if r < 0.86 - dark_bias:
						light[i] = L_ON
					elif r < 0.91 - dark_bias * 0.5:
						light[i] = L_FLICK
					elif r < 0.985:
						light[i] = L_DEAD
					else:
						light[i] = L_HOLE
				Z_DARK:
					if (x + z) % 2 != 0:
						continue
					if r < 0.06:
						light[i] = L_ON
					elif r < 0.17:
						light[i] = L_FLICK
					elif r < 0.95:
						light[i] = L_DEAD
					else:
						light[i] = L_HOLE
				Z_OLD:
					if (x + z) % 2 != 0:
						continue
					light[i] = L_ON if r < 0.8 else (L_FLICK if r < 0.9 else L_DEAD)
				Z_CONCRETE:
					if x % 3 == 0 and z % 3 == 0:
						light[i] = L_RED if r < 0.5 else (L_FLICK if r < 0.6 else L_NONE)
				Z_TILE:
					if (x + z) % 2 == 0:
						light[i] = L_ON if r < 0.55 else (L_FLICK if r < 0.7 else L_DEAD)


## Достижимость от клетки старта; недостижимые области вскрываются проёмами
func fix_connectivity(sx: int, sz: int) -> void:
	reach.fill(0)
	var q := PackedInt32Array()
	q.append(idx(sx, sz))
	reach[idx(sx, sz)] = 1
	_bfs_expand(q)
	for pass_i in 3:
		for z in N:
			for x in N:
				var i := z * N + x
				if reach[i] or flo[i] != F_FLOOR:
					continue
				for d in 4:
					var o: Vector2i = DIRS[d]
					var j := idx(x + o.x, z + o.y)
					if reach[j] and flo[j] == F_FLOOR and edge(x, z, d) != E_WINDOW and zone[i] != Z_HOUSE:
						if not edge_passable(edge(x, z, d)):
							set_edge(x, z, d, E_ARCH)
						reach[i] = 1
						var q2 := PackedInt32Array()
						q2.append(i)
						_bfs_expand(q2)
						break


func _bfs_expand(q: PackedInt32Array) -> void:
	var head := 0
	while head < q.size():
		var i := q[head]
		head += 1
		var x := i % N
		var z := i / N
		for d in 4:
			if not can_step(x, z, d):
				continue
			var o: Vector2i = DIRS[d]
			var j := idx(x + o.x, z + o.y)
			if reach[j]:
				continue
			reach[j] = 1
			q.append(j)


## BFS от точки по проходимым клеткам: расстояния (в клетках) и направление «назад к источнику»
func bfs_from(sx: int, sz: int, max_d := 100000) -> Array:
	var dist := PackedInt32Array()
	dist.resize(N * N)
	dist.fill(-1)
	var par := PackedByteArray()
	par.resize(N * N)
	par.fill(255)
	var q := PackedInt32Array()
	var s := idx(sx, sz)
	dist[s] = 0
	q.append(s)
	var head := 0
	while head < q.size():
		var i := q[head]
		head += 1
		var dd := dist[i]
		if dd >= max_d:
			continue
		var x := i % N
		var z := i / N
		for d in 4:
			if not can_step(x, z, d):
				continue
			var o: Vector2i = DIRS[d]
			var j := idx(x + o.x, z + o.y)
			if dist[j] >= 0:
				continue
			dist[j] = dd + 1
			par[j] = (d + 2) % 4   # направление обратно к источнику
			q.append(j)
	return [dist, par]


## Кабели Async от станции (sx, sz): несколько линий до дальних концов
func lay_cables(sx: int, sz: int, ends: Array) -> void:
	var res := bfs_from(sx, sz)
	var dist: PackedInt32Array = res[0]
	var par: PackedByteArray = res[1]
	for e in ends:
		var ep: Vector2i = e
		var i := idx(ep.x, ep.y)
		if dist[i] < 0:
			continue
		var x := ep.x
		var z := ep.y
		var steps := 0
		while (posmod(x, N) != posmod(sx, N) or posmod(z, N) != posmod(sz, N)) and steps < 4000:
			var ci := idx(x, z)
			var d := par[ci]
			if d == 255:
				break
			cable[ci] |= (1 << d)
			cable_par[ci] = d
			cable_dist[ci] = dist[ci]
			var o: Vector2i = DIRS[d]
			x += o.x
			z += o.y
			cable[idx(x, z)] |= (1 << ((d + 2) % 4))
			steps += 1


## Ближайшая к цели клетка, удовлетворяющая условию (поиск по кольцам)
func find_cell_near(tx: int, tz: int, radius: int, cond: Callable) -> Vector2i:
	for r in range(0, radius + 1):
		for k in range(-r, r + 1):
			for c in [Vector2i(tx + k, tz - r), Vector2i(tx + k, tz + r), Vector2i(tx - r, tz + k), Vector2i(tx + r, tz + k)]:
				if cond.call(c.x, c.y):
					return c
	return Vector2i(tx, tz)


func is_plain(x: int, z: int) -> bool:
	var i := idx(x, z)
	return flo[i] == F_FLOOR and (zone[i] == Z_YELLOW or zone[i] == Z_DARK or zone[i] == Z_OLD or zone[i] == Z_CONCRETE or zone[i] == Z_TILE)


## Свободна ли прямоугольная область под штамп (нет уже поставленных особых комнат)
func area_free(x0: int, z0: int, w: int, h: int) -> bool:
	for i in range(-1, w + 1):
		for j in range(-1, h + 1):
			var zi := zone[idx(x0 + i, z0 + j)]
			if zi == Z_ASYNC or zi == Z_HOUSE or zi == Z_STRETCH or zi == Z_SKY or zi == Z_PITS or zi == Z_CELLAR:
				return false
			if flo[idx(x0 + i, z0 + j)] == F_SOLID:
				return false
	return true


## Точка на кольце расстояний [rmin, rmax] от (cx, cz) со свободным местом w×h
func pick_spot(cx: int, cz: int, rmin: int, rmax: int, w: int, h: int, tries := 60) -> Vector2i:
	for t in tries:
		var a := rng.randf() * TAU
		var r := rng.randf_range(rmin, rmax)
		var x := cx + int(cos(a) * r) - w / 2
		var z := cz + int(sin(a) * r) - h / 2
		if area_free(x, z, w, h):
			return Vector2i(x, z)
	var a2 := rng.randf() * TAU
	return Vector2i(cx + int(cos(a2) * rmax), cz + int(sin(a2) * rmax))


## Стена-сторона клетки, пригодная для надписи/предмета у стены
func wall_sides(x: int, z: int) -> Array:
	var out := []
	for d in 4:
		if edge(x, z, d) == E_WALL:
			out.append(d)
	return out


## Позиция у стены (центр стороны d клетки), отступ внутрь клетки
func wall_point(x: int, z: int, d: int, inset: float, along := 0.0) -> Vector3:
	var c := cell_center(x, z)
	var o: Vector2i = DIRS[d]
	var t := Vector2(-o.y, o.x)
	var p := c + Vector2(o) * (C * 0.5 - 0.1 - inset) + t * along
	return Vector3(p.x, floor_y, p.y)


static func dir_yaw(d: int) -> float:
	# yaw, при котором локальная -Z смотрит в направлении d
	var o: Vector2i = DIRS[d]
	return atan2(-float(o.x), -float(o.y))
