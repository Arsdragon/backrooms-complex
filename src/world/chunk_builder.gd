class_name ChunkBuilder
extends RefCounted
## Строит геометрию чанка (12×12 клеток) из LayerData. Работает в фоновом потоке: только массивы, без узлов.
## Свет «запекается» в цвет вершин: r — ровный свет ламп, g — мигающий, b — красный аварийный,
## a — номер группы мигания (0..7, 7 — зелёный свет нулевой зоны); UV2.x — затенение углов (AO).

const L := preload("res://src/world/layer_data.gd")

# материалы
const M_WALL_Y := 0
const M_WALL_OLD := 1
const M_WALL_CONC := 2
const M_WALL_TILE := 3
const M_WALL_HOUSE := 4
const M_WALL_STRETCH := 5
const M_BASE := 6
const M_CARPET := 7
const M_CARPET_OLD := 8
const M_FLOOR_CONC := 9
const M_FLOOR_TILE := 10
const M_FLOOR_WOOD := 11
const M_CEIL_TILE := 12
const M_CEIL_CONC := 13
const M_CEIL_PLASTER := 14
const M_FIXTURE := 15
const M_FIXTURE_DEAD := 16
const M_HOLE := 17
const M_PIT := 18
const M_GLASS := 19
const M_CABLE := 20
const M_RED_LAMP := 21
const M_CARPET_WET := 22
const M_WALL_PAINT := 23
const M_WALL_SCHOOL := 24
const M_LINO := 25
const M_WATER := 26
const M_COUNT := 27

const T := 0.1          # половина толщины стены
const DOOR_W := 0.55    # половина ширины узкого проёма
const DOOR_H := 2.1
const ARCH_H := 2.25
const PIT_DEPTH := 7.0
const SHAFT_H := 8.0
const LIGHT_R := 7.5
const LIGHT_A := 6.0
const LIGHT_K := 0.55   # общий множитель яркости
const WIND := -1.0      # знак обхода передних граней

var D: LayerData
var cx := 0
var cz := 0
var x0 := 0
var z0 := 0
var fy := 0.0
var surf := {}            # mat -> {v,n,uv,c,uv2}
var boxes := []           # [center, half]
var fixtures := []        # [pos, kind, I, group]
var lists := {}           # Vector2i -> Array[[fi, pathlen]]
var out_deco := []
var cell_light := PackedFloat32Array()


static func build(data: LayerData, ccx: int, ccz: int) -> Dictionary:
	var b := ChunkBuilder.new()
	b.D = data
	b.cx = ccx
	b.cz = ccz
	b.x0 = ccx * L.CHUNK
	b.z0 = ccz * L.CHUNK
	b.fy = data.floor_y
	b._run()
	return {"surf": b.surf, "boxes": b.boxes, "deco": b.out_deco, "cell_light": b.cell_light,
		"cx": ccx, "cz": ccz, "layer": data.layer}


func _run() -> void:
	_gather_lights()
	for j in L.CHUNK:
		for i in L.CHUNK:
			_cell(x0 + i, z0 + j)
	for j in L.CHUNK:
		for i in L.CHUNK:
			_edges(x0 + i, z0 + j)
	for j in L.CHUNK:
		for i in L.CHUNK:
			_post(x0 + i, z0 + j)
	_floor_collision()
	_cables()
	_cell_lights()
	for d in D.deco_for(cx, cz):
		var dd: Dictionary = d
		var p: Vector3 = dd.p
		var lc := light_at(p + Vector3(0, 1.0, 0), Vector3.UP, true)
		dd["light"] = lc
		out_deco.append(dd)


# ------------------------------------------------------------ свет

func _gather_lights() -> void:
	var pad := 4
	for z in range(z0 - pad, z0 + L.CHUNK + pad):
		for x in range(x0 - pad, x0 + L.CHUNK + pad):
			var i := L.idx(x, z)
			var k := D.light[i]
			if k == L.L_NONE or k == L.L_DEAD or k == L.L_HOLE:
				continue
			var h := D.height_m(x, z)
			if h <= 0.01:
				h = 2.7
			var c := L.cell_center(x, z)
			var y := fy + h - 0.05
			if D.zone[L.idx(x, z)] == L.Z_FLIP:
				y = fy + 0.06
			var I := 1.0
			var grp := -1
			# зал-великан: лампы под 9-метровым потолком светят как будто ниже, иначе пол тонет во тьме
			if h > 5.0 and D.zone[L.idx(x, z)] != L.Z_STRETCH:
				y = fy + 4.2
				I = 1.25
			match k:
				L.L_FLICK:
					grp = (x * 7 + z * 13) % 7
				L.L_RED:
					I = 0.45
					y = fy + h - 0.15
				L.L_ASYNC:
					I = 1.9
					y = fy + 1.9
				L.L_BULB:
					I = 0.95
					y = fy + h - 0.35
				L.L_GREEN:
					I = 0.7
					grp = 7
			var fi := fixtures.size()
			fixtures.append([Vector3(c.x, y, c.y), k, I, grp])
			_bfs_light(fi, x, z)


func _bfs_light(fi: int, sx: int, sz: int) -> void:
	var seen := {}
	var q := [[sx, sz, 0.0, 0]]
	seen[Vector2i(sx, sz)] = 0.0
	var head := 0
	while head < q.size():
		var e: Array = q[head]
		head += 1
		var x: int = e[0]
		var z: int = e[1]
		var pl: float = e[2]
		var depth: int = e[3]
		if float(seen.get(Vector2i(x, z), 1e9)) < pl:
			continue
		if depth >= 3:
			continue
		for d in 4:
			var ev := D.edge(x, z, d)
			if ev == L.E_WALL:
				continue
			var o: Vector2i = L.DIRS[d]
			var nx := x + o.x
			var nz := z + o.y
			if D.flo[L.idx(nx, nz)] == L.F_SOLID and ev != L.E_WINDOW:
				continue
			var cost := 1.0
			if ev == L.E_DOOR:
				cost = 1.8
			elif ev == L.E_ARCH:
				cost = 1.25
			elif ev == L.E_WINDOW:
				cost = 1.6
			var npl := pl + cost
			var nk := Vector2i(nx, nz)
			if seen.has(nk) and float(seen[nk]) <= npl:
				continue
			seen[nk] = npl
			q.append([nx, nz, npl, depth + 1])
	for k in seen.keys():
		var key: Vector2i = k
		if key.x >= x0 - 1 and key.x <= x0 + L.CHUNK and key.y >= z0 - 1 and key.y <= z0 + L.CHUNK:
			if not lists.has(key):
				lists[key] = []
			(lists[key] as Array).append([fi, float(seen[k]) - (absi(key.x - sx) + absi(key.y - sz))])


## Свет в точке p (нормаль n) по спискам ламп клетки, в которой лежит точка (со стороны нормали)
func light_at(p: Vector3, n: Vector3, omni := false, cell := Vector2i(-99999, 0), ceiling := false) -> Color:
	var c := cell
	if c.x == -99999:
		c = Vector2i(int(floor(p.x / L.C)), int(floor(p.z / L.C)))
	var lst: Array = lists.get(c, [])
	var steady := 0.0
	var flick := 0.0
	var red := 0.0
	var grp := 0
	var gbest := 0.0
	for e in lst:
		var f: Array = fixtures[int(e[0])]
		var fp: Vector3 = f[0]
		var dv := fp - p
		var d := dv.length()
		if d > LIGHT_R:
			continue
		if ceiling:
			d = maxf(d, 0.9)
		var fall := LIGHT_A / (LIGHT_A + d * d)
		if ceiling:
			fall = 0.75 / (1.0 + d * d * 0.9) + 0.12 * LIGHT_A / (LIGHT_A + d * d)
		var w := 1.0 - (d / LIGHT_R) * (d / LIGHT_R)
		fall *= w * w
		var lam := 1.0
		if omni:
			lam = 0.85
		elif ceiling:
			lam = 1.0
		else:
			lam = 0.28 + 0.72 * maxf(0.0, n.dot(dv / maxf(d, 0.001)))
		var extra: float = e[1]
		var occ := pow(0.55, maxf(0.0, extra))
		var v := float(f[2]) * fall * lam * occ * LIGHT_K
		var kind: int = f[1]
		var g: int = f[3]
		if kind == L.L_RED:
			red += v
		elif g >= 0:
			flick += v
			if v > gbest:
				gbest = v
				grp = g
		else:
			steady += v
	return Color(minf(steady * 0.5, 1.0), minf(flick * 0.5, 1.0), minf(red * 0.5, 1.0), grp / 8.0)


func _cell_lights() -> void:
	cell_light.resize(L.CHUNK * L.CHUNK * 4)
	for j in L.CHUNK:
		for i in L.CHUNK:
			var x := x0 + i
			var z := z0 + j
			var c := L.cell_center(x, z)
			var col := light_at(Vector3(c.x, fy + 1.2, c.y), Vector3.UP, true, Vector2i(x, z))
			var k := (j * L.CHUNK + i) * 4
			cell_light[k] = col.r * 2.0
			cell_light[k + 1] = col.g * 2.0
			cell_light[k + 2] = col.b * 2.0
			cell_light[k + 3] = col.a


# ------------------------------------------------------------ геометрия

func _s(mat: int) -> Dictionary:
	if not surf.has(mat):
		surf[mat] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(),
			"c": PackedColorArray(), "uv2": PackedVector2Array()}
	return surf[mat]


## Четырёхугольник p0..p3 (по кругу) с разбиением nu×nv, свет из клетки cell.
## uvf: Callable(p) -> Vector2, aof: Callable(p) -> float
func quad(mat: int, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3, nu: int, nv: int,
		cell: Vector2i, uvf: Callable, aof: Callable, ceiling := false, lit := true) -> void:
	var s := _s(mat)
	var vs: PackedVector3Array = s.v
	var ns: PackedVector3Array = s.n
	var uvs: PackedVector2Array = s.uv
	var cs: PackedColorArray = s.c
	var u2: PackedVector2Array = s.uv2
	var grid := []
	for b in nv + 1:
		var row := []
		var tb := float(b) / nv
		for a in nu + 1:
			var ta := float(a) / nu
			var p := p0.lerp(p1, ta).lerp(p3.lerp(p2, ta), tb)
			var col := light_at(p + n * 0.05, n, false, cell, ceiling) if lit else Color(0, 0, 0, 0)
			row.append([p, col, uvf.call(p), aof.call(p)])
		grid.append(row)
	var flip := (p1 - p0).cross(p3 - p0).dot(n) * WIND < 0.0
	for b in nv:
		for a in nu:
			var q0: Array = grid[b][a]
			var q1: Array = grid[b][a + 1]
			var q2: Array = grid[b + 1][a + 1]
			var q3: Array = grid[b + 1][a]
			var tri := [q0, q1, q2, q0, q2, q3]
			if flip:
				tri = [q0, q2, q1, q0, q3, q2]
			for t in tri:
				var tt: Array = t
				vs.append(tt[0])
				ns.append(n)
				cs.append(tt[1])
				uvs.append(tt[2])
				u2.append(Vector2(float(tt[3]), 0.0))
	s.v = vs
	s.n = ns
	s.c = cs
	s.uv = uvs
	s.uv2 = u2


func _uv_xz(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


func _wall_mat(zn: int) -> int:
	match zn:
		L.Z_OLD: return M_WALL_OLD
		L.Z_CONCRETE, L.Z_CELLAR: return M_WALL_CONC
		L.Z_TILE: return M_WALL_TILE
		L.Z_HOUSE: return M_WALL_HOUSE
		L.Z_STRETCH: return M_WALL_STRETCH
		L.Z_STORE: return M_WALL_PAINT
		L.Z_CLASS: return M_WALL_SCHOOL
	return M_WALL_Y


func _floor_mat(zn: int, x: int, z: int) -> int:
	match zn:
		L.Z_OLD: return M_CARPET_OLD
		L.Z_CONCRETE, L.Z_CELLAR: return M_FLOOR_CONC
		L.Z_TILE: return M_FLOOR_TILE
		L.Z_HOUSE: return M_FLOOR_WOOD
		L.Z_STORE, L.Z_CLASS: return M_LINO
		L.Z_DARK:
			return M_CARPET_WET if (x * 31 + z * 17) % 5 < 2 else M_CARPET
	return M_CARPET


func _ceil_mat(zn: int) -> int:
	match zn:
		L.Z_CONCRETE, L.Z_CELLAR: return M_CEIL_CONC
		L.Z_HOUSE: return M_CEIL_PLASTER
	return M_CEIL_TILE


func _has_base(zn: int) -> bool:
	return zn != L.Z_CONCRETE and zn != L.Z_TILE and zn != L.Z_CELLAR


func _cell(x: int, z: int) -> void:
	var i := L.idx(x, z)
	var f := D.flo[i]
	if f == L.F_SOLID:
		return
	var zn := D.zone[i]
	var h := D.height_m(x, z)
	var X0 := x * L.C
	var Z0 := z * L.C
	var X1 := X0 + L.C
	var Z1 := Z0 + L.C
	var cell := Vector2i(x, z)
	var walls := [L.edge_solid(D.edge(x, z, 0)) or D.edge(x, z, 0) == L.E_DOOR,
		L.edge_solid(D.edge(x, z, 1)) or D.edge(x, z, 1) == L.E_DOOR,
		L.edge_solid(D.edge(x, z, 2)) or D.edge(x, z, 2) == L.E_DOOR,
		L.edge_solid(D.edge(x, z, 3)) or D.edge(x, z, 3) == L.E_DOOR]
	var aof := func(p: Vector3) -> float:
		var a := 1.0
		var dxs := [X1 - p.x, Z1 - p.z, p.x - X0, p.z - Z0]
		for d in 4:
			if walls[d]:
				a *= 0.55 + 0.45 * smoothstep(0.0, 0.9, float(dxs[d]))
		return a
	var flip := zn == L.Z_FLIP
	var aofc := func(p: Vector3) -> float:
		return 0.35 + 0.65 * float(aof.call(p))
	if f == L.F_FLOOR:
		if flip:
			# перевёртыш: на полу — потолочные плиты и лампы
			quad(M_CEIL_TILE, Vector3(X0, fy, Z0), Vector3(X1, fy, Z0), Vector3(X1, fy, Z1), Vector3(X0, fy, Z1),
				Vector3.UP, 3, 3, cell, _uv_xz, aofc, true)
			_fixture(x, z, fy, zn, true)
		else:
			quad(_floor_mat(zn, x, z), Vector3(X0, fy, Z0), Vector3(X1, fy, Z0), Vector3(X1, fy, Z1), Vector3(X0, fy, Z1),
				Vector3.UP, 3, 3, cell, _uv_xz, aof)
		if D.water[i] > 0:
			var wy := fy + 0.055
			quad(M_WATER, Vector3(X0, wy, Z0), Vector3(X1, wy, Z0), Vector3(X1, wy, Z1), Vector3(X0, wy, Z1),
				Vector3.UP, 2, 2, cell, _uv_xz, func(_p: Vector3) -> float: return 1.0)
	elif f == L.F_PIT:
		_pit(x, z)
	# потолок
	if h > 0.01:
		var cy := fy + h
		if flip:
			quad(M_CARPET, Vector3(X0, cy, Z0), Vector3(X1, cy, Z0), Vector3(X1, cy, Z1), Vector3(X0, cy, Z1),
				Vector3.DOWN, 3, 3, cell, _uv_xz, aof)
		else:
			quad(_ceil_mat(zn), Vector3(X0, cy, Z0), Vector3(X1, cy, Z0), Vector3(X1, cy, Z1), Vector3(X0, cy, Z1),
				Vector3.DOWN, 3, 3, cell, _uv_xz, aofc, true)
			_fixture(x, z, cy, zn)
		if h < 2.2:
			# низкий потолок — твёрдый (пролезть можно только пригнувшись)
			boxes.append([Vector3(X0 + L.C * 0.5, cy + 0.2, Z0 + L.C * 0.5), Vector3(L.C * 0.5, 0.2, L.C * 0.5)])
	else:
		_shaft(x, z)
	# ступенька потолка между клетками разной высоты (открытые рёбра)
	for d in [0, 1]:
		var ev := D.edge(x, z, d)
		if L.edge_solid(ev):
			continue
		var o: Vector2i = L.DIRS[d]
		var j := L.idx(x + o.x, z + o.y)
		if D.flo[j] == L.F_SOLID:
			continue
		var h2 := D.height_m(x + o.x, z + o.y)
		if h2 <= 0.01 or h <= 0.01 or absf(h2 - h) < 0.05:
			continue
		var lo := minf(h, h2)
		var hi := maxf(h, h2)
		# ступенька видна из клетки с ВЫСОКИМ потолком — туда и смотрит
		var low_cell := Vector2i(x + o.x, z + o.y) if h < h2 else cell
		var nrm := Vector3(o.x, 0, o.y) if h < h2 else Vector3(-o.x, 0, -o.y)
		var zl := _wall_mat(D.zone[L.idx(low_cell.x, low_cell.y)])
		if d == 0:
			quad(zl, Vector3(X1, fy + lo, Z0), Vector3(X1, fy + lo, Z1), Vector3(X1, fy + hi, Z1), Vector3(X1, fy + hi, Z0),
				nrm, 3, 2, low_cell, func(p: Vector3) -> Vector2: return Vector2(p.z, p.y), func(_p: Vector3) -> float: return 0.9)
		else:
			quad(zl, Vector3(X0, fy + lo, Z1), Vector3(X1, fy + lo, Z1), Vector3(X1, fy + hi, Z1), Vector3(X0, fy + hi, Z1),
				nrm, 3, 2, low_cell, func(p: Vector3) -> Vector2: return Vector2(p.x, p.y), func(_p: Vector3) -> float: return 0.9)


func _fixture(x: int, z: int, cy: float, zn: int, up := false) -> void:
	var k := D.light[L.idx(x, z)]
	if k == L.L_NONE or k == L.L_ASYNC:
		return
	var c := L.cell_center(x, z)
	var y := cy - 0.012 if not up else cy + 0.012
	var fn := Vector3.UP if up else Vector3.DOWN
	var hw := 0.3
	var hd := 0.6
	if zn == L.Z_HOUSE or k == L.L_BULB or k == L.L_RED or k == L.L_GREEN:
		hw = 0.12
		hd = 0.12
	var mat := M_FIXTURE
	if k == L.L_DEAD:
		mat = M_FIXTURE_DEAD
	elif k == L.L_HOLE:
		mat = M_HOLE
		y = cy - 0.004 if not up else cy + 0.004
	elif k == L.L_RED:
		mat = M_RED_LAMP
	var group := 0.0
	if k == L.L_FLICK:
		group = float((x * 7 + z * 13) % 7) / 8.0 + 0.0001
	elif k == L.L_GREEN:
		group = 7.0 / 8.0
	var col := Color(1.0 if (k == L.L_ON or k == L.L_BULB) else 0.0, 1.0 if (k == L.L_FLICK or k == L.L_GREEN) else 0.0, 1.0 if k == L.L_RED else 0.0, group)
	if k == L.L_DEAD:
		# погасший светильник освещён соседними лампами, как потолок
		col = light_at(Vector3(c.x, y - 0.05 * fn.y, c.y), fn, false, Vector2i(x, z), true)
	var s := _s(mat)
	var p0 := Vector3(c.x - hw, y, c.y - hd)
	var p1 := Vector3(c.x + hw, y, c.y - hd)
	var p2 := Vector3(c.x + hw, y, c.y + hd)
	var p3 := Vector3(c.x - hw, y, c.y + hd)
	var pts := [p0, p1, p2, p0, p2, p3]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]
	var flip := (p1 - p0).cross(p3 - p0).dot(fn) * WIND < 0.0
	if flip:
		pts = [p0, p2, p1, p0, p3, p2]
		uvs = [Vector2(0, 0), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)]
	var vs: PackedVector3Array = s.v
	var ns: PackedVector3Array = s.n
	var cs: PackedColorArray = s.c
	var us: PackedVector2Array = s.uv
	var u2: PackedVector2Array = s.uv2
	for t in 6:
		vs.append(pts[t])
		ns.append(fn)
		cs.append(col)
		us.append(uvs[t])
		u2.append(Vector2(1, 0))
	s.v = vs
	s.n = ns
	s.c = cs
	s.uv = us
	s.uv2 = u2


func _pit(x: int, z: int) -> void:
	var X0 := x * L.C
	var Z0 := z * L.C
	var cell := Vector2i(x, z)
	var aof := func(p: Vector3) -> float:
		return clampf(1.0 + (p.y - fy) / 2.5, 0.0, 1.0) * 0.8
	for d in 4:
		var o: Vector2i = L.DIRS[d]
		if D.flo[L.idx(x + o.x, z + o.y)] == L.F_PIT:
			continue
		var inset := T if L.edge_solid(D.edge(x, z, d)) else 0.0
		var n := Vector3(-o.x, 0, -o.y)
		var a: Vector3
		var b: Vector3
		match d:
			0:
				a = Vector3(X0 + L.C - inset, 0, Z0)
				b = Vector3(X0 + L.C - inset, 0, Z0 + L.C)
			1:
				a = Vector3(X0 + L.C, 0, Z0 + L.C - inset)
				b = Vector3(X0, 0, Z0 + L.C - inset)
			2:
				a = Vector3(X0 + inset, 0, Z0 + L.C)
				b = Vector3(X0 + inset, 0, Z0)
			_:
				a = Vector3(X0, 0, Z0 + inset)
				b = Vector3(X0 + L.C, 0, Z0 + inset)
		var top := fy
		var bot := fy - PIT_DEPTH
		quad(M_PIT, Vector3(a.x, bot, a.z), Vector3(b.x, bot, b.z), Vector3(b.x, top, b.z), Vector3(a.x, top, a.z), n, 2, 3, cell,
			func(p: Vector3) -> Vector2: return Vector2(p.x + p.z, p.y), aof)


func _shaft(x: int, z: int) -> void:
	# вертикальная шахта над клеткой (под ямой верхнего слоя)
	var X0 := x * L.C
	var Z0 := z * L.C
	var cell := Vector2i(x, z)
	var base := fy + 2.7
	var aof := func(p: Vector3) -> float:
		return clampf(1.0 - (p.y - base) / 4.0, 0.0, 1.0) * 0.7
	for d in 4:
		var o: Vector2i = L.DIRS[d]
		var nh := D.height_m(x + o.x, z + o.y)
		if nh <= 0.01 and D.flo[L.idx(x + o.x, z + o.y)] != L.F_SOLID:
			continue
		var n := Vector3(-o.x, 0, -o.y)
		var a: Vector3
		var b: Vector3
		match d:
			0:
				a = Vector3(X0 + L.C, 0, Z0)
				b = Vector3(X0 + L.C, 0, Z0 + L.C)
			1:
				a = Vector3(X0 + L.C, 0, Z0 + L.C)
				b = Vector3(X0, 0, Z0 + L.C)
			2:
				a = Vector3(X0, 0, Z0 + L.C)
				b = Vector3(X0, 0, Z0)
			_:
				a = Vector3(X0, 0, Z0)
				b = Vector3(X0 + L.C, 0, Z0)
		quad(M_PIT, Vector3(a.x, base, a.z), Vector3(b.x, base, b.z), Vector3(b.x, base + SHAFT_H, b.z), Vector3(a.x, base + SHAFT_H, a.z),
			n, 2, 3, cell, func(p: Vector3) -> Vector2: return Vector2(p.x + p.z, p.y), aof)


## Рёбра на восток (d=0) и юг (d=1) клетки: стены, проёмы, окна
func _edges(x: int, z: int) -> void:
	for d in [0, 1]:
		var ev := D.edge(x, z, d)
		if ev == L.E_OPEN:
			continue
		var o: Vector2i = L.DIRS[d]
		var ia := L.idx(x, z)
		var ib := L.idx(x + o.x, z + o.y)
		var fa := D.flo[ia]
		var fb := D.flo[ib]
		if fa == L.F_SOLID and fb == L.F_SOLID:
			continue
		var ha := D.height_m(x, z)
		var hb := D.height_m(x + o.x, z + o.y)
		if ha <= 0.01:
			ha = 2.7
		if hb <= 0.01:
			hb = 2.7
		var H := maxf(ha if fa != L.F_SOLID else 0.0, hb if fb != L.F_SOLID else 0.0)
		var lo := fy - (PIT_DEPTH if (fa == L.F_PIT or fb == L.F_PIT) else 0.0)
		var ca := Vector2i(x, z)
		var cb := Vector2i(x + o.x, z + o.y)
		# плоскость стены и направление вдоль
		var e0: Vector3
		var e1: Vector3
		var na: Vector3      # нормаль стороны A (смотрит в клетку A)
		if d == 0:
			var px := (x + 1) * L.C
			e0 = Vector3(px, 0, z * L.C + T)
			e1 = Vector3(px, 0, (z + 1) * L.C - T)
			na = Vector3(-1, 0, 0)
		else:
			var pz := (z + 1) * L.C
			e0 = Vector3(x * L.C + T, 0, pz)
			e1 = Vector3((x + 1) * L.C - T, 0, pz)
			na = Vector3(0, 0, -1)
		var mid := (e0 + e1) * 0.5
		var along := (e1 - e0).normalized()
		var len_half := (e1 - e0).length() * 0.5
		var zone_a := D.zone[ia]
		var zone_b := D.zone[ib]
		var spans := []   # [t0, t1, y0, y1]  t — вдоль от центра
		match ev:
			L.E_WALL:
				spans.append([-len_half, len_half, lo, fy + H])
			L.E_DOOR:
				spans.append([-len_half, -DOOR_W, lo, fy + H])
				spans.append([DOOR_W, len_half, lo, fy + H])
				if H > DOOR_H + 0.05:
					spans.append([-DOOR_W, DOOR_W, fy + DOOR_H, fy + H])
			L.E_ARCH:
				if H > ARCH_H + 0.05:
					spans.append([-len_half, len_half, fy + ARCH_H, fy + H])
			L.E_WINDOW:
				spans.append([-len_half, len_half, lo, fy + 0.9])
				if H > 2.2:
					spans.append([-len_half, len_half, fy + 2.2, fy + H])
		for sp in spans:
			var t0: float = sp[0]
			var t1: float = sp[1]
			var y0: float = sp[2]
			var y1: float = sp[3]
			var a := mid + along * t0
			var b := mid + along * t1
			for side in 2:
				var n := na if side == 0 else -na
				var cell := ca if side == 0 else cb
				var fside := fa if side == 0 else fb
				if fside == L.F_SOLID:
					continue
				var zs := zone_a if side == 0 else zone_b
				var off := n * T
				var p0 := Vector3(a.x, y0, a.z) + off
				var p1 := Vector3(b.x, y0, b.z) + off
				var p2 := Vector3(b.x, y1, b.z) + off
				var p3 := Vector3(a.x, y1, a.z) + off
				var hh := y1 - y0
				var nv := 1 if hh < 0.8 else (3 if hh < 3.5 else 5)
				var flo_y := fy
				var ceil_y := fy + (ha if side == 0 else hb)
				var aof := func(p: Vector3) -> float:
					var ao := 0.62 + 0.38 * smoothstep(flo_y - 0.05, flo_y + 0.7, p.y)
					ao *= 0.8 + 0.2 * smoothstep(ceil_y + 0.05, ceil_y - 0.5, p.y)
					if p.y < flo_y - 0.01:
						ao *= clampf(1.0 + (p.y - flo_y) / 2.5, 0.0, 1.0)
					return ao
				var uvf: Callable
				if d == 0:
					uvf = func(p: Vector3) -> Vector2: return Vector2(p.z, p.y)
				else:
					uvf = func(p: Vector3) -> Vector2: return Vector2(p.x, p.y)
				quad(_wall_mat(zs), p0, p1, p2, p3, n, 3, nv, cell, uvf, aof)
				var bflip := zs == L.Z_FLIP
				if _has_base(zs) and ((not bflip and y0 <= fy + 0.01 and y1 > fy + 0.2) or (bflip and y1 >= ceil_y - 0.01)):
					var bo := n * (T + 0.012)
					var by := ceil_y - 0.1 if bflip else fy
					var q0 := Vector3(a.x, by, a.z) + bo
					var q1 := Vector3(b.x, by, b.z) + bo
					quad(M_BASE, q0, q1, q1 + Vector3(0, 0.1, 0), q0 + Vector3(0, 0.1, 0), n, 2, 1, cell, uvf, func(_p: Vector3) -> float: return 0.8)
					quad(M_BASE, q0 + Vector3(0, 0.1, 0), q1 + Vector3(0, 0.1, 0), q1 + Vector3(0, 0.1, 0) - n * 0.012, q0 + Vector3(0, 0.1, 0) - n * 0.012,
						Vector3.UP, 1, 1, cell, uvf, func(_p: Vector3) -> float: return 0.9)
			# торцы проёма (откосы) и низ перемычки
			if ev == L.E_DOOR or ev == L.E_ARCH or ev == L.E_WINDOW:
				var zs2 := zone_a if fa != L.F_SOLID else zone_b
				var cellj := ca if fa != L.F_SOLID else cb
				var wm := _wall_mat(zs2)
				var uvj := func(p: Vector3) -> Vector2: return Vector2(p.x + p.z, p.y)
				if y0 > fy + 0.5:
					# низ перемычки
					var s0 := Vector3(a.x, y0, a.z) + na * T
					var s1 := Vector3(b.x, y0, b.z) + na * T
					quad(wm, s0, s1, s1 - na * 2.0 * T, s0 - na * 2.0 * T, Vector3.DOWN, 2, 1, cellj, uvj, func(_p: Vector3) -> float: return 0.85)
				elif ev == L.E_WINDOW and y1 < fy + 1.5:
					var s0w := Vector3(a.x, y1, a.z) + na * T
					var s1w := Vector3(b.x, y1, b.z) + na * T
					quad(wm, s0w, s1w, s1w - na * 2.0 * T, s0w - na * 2.0 * T, Vector3.UP, 2, 1, cellj, uvj, func(_p: Vector3) -> float: return 0.9)
				if ev == L.E_DOOR and absf(t0) < len_half - 0.01 and y0 <= fy + 0.01:
					# откос у внутреннего края куска (t1 или t0 — тот, что у проёма)
					var tj := t1 if t1 < 0.0 else t0
					var jn := along if t1 < 0.0 else -along
					var j0 := mid + along * tj
					var top := fy + DOOR_H if H > DOOR_H else fy + H
					var a0 := Vector3(j0.x, fy, j0.z) + na * T
					var a1 := Vector3(j0.x, fy, j0.z) - na * T
					quad(wm, a0, a1, a1 + Vector3(0, top - fy, 0), a0 + Vector3(0, top - fy, 0), jn, 1, 2, cellj, uvj,
						func(p: Vector3) -> float: return 0.7 + 0.3 * smoothstep(fy, fy + 0.6, p.y))
			# коллизия куска
			var cpos := (a + b) * 0.5
			var halfv := Vector3(T, (y1 - y0) * 0.5, absf(b.z - a.z) * 0.5 + T) if d == 0 else Vector3(absf(b.x - a.x) * 0.5 + T, (y1 - y0) * 0.5, T)
			boxes.append([Vector3(cpos.x, (y0 + y1) * 0.5, cpos.z), halfv])
		if ev == L.E_WINDOW:
			# стекло
			var g0 := Vector3(e0.x, fy + 0.9, e0.z)
			var g1 := Vector3(e1.x, fy + 0.9, e1.z)
			var gq := func(p: Vector3) -> Vector2: return Vector2(p.x + p.z, p.y)
			quad(M_GLASS, g0, g1, g1 + Vector3(0, 1.3, 0), g0 + Vector3(0, 1.3, 0), na, 1, 1, ca, gq, func(_p: Vector3) -> float: return 1.0)
			boxes.append([Vector3(mid.x, fy + 1.55, mid.z), Vector3(T if d == 0 else len_half, 0.65, T if d == 1 else len_half)])


## Колонна/стык стен в СЗ-углу клетки (x, z)
func _post(x: int, z: int) -> void:
	var e_n := D.wall_e[L.idx(x - 1, z - 1)]   # вверх (−z) по линии x
	var e_s := D.wall_e[L.idx(x - 1, z)]       # вниз (+z)
	var e_w := D.wall_s[L.idx(x - 1, z - 1)]   # влево (−x) по линии z
	var e_e := D.wall_s[L.idx(x, z - 1)]       # вправо (+x)
	var pil := D.post[L.idx(x, z)] == 1
	var any := e_n != L.E_OPEN or e_s != L.E_OPEN or e_w != L.E_OPEN or e_e != L.E_OPEN
	if not any and not pil:
		return
	var cells := [Vector2i(x - 1, z - 1), Vector2i(x, z - 1), Vector2i(x - 1, z), Vector2i(x, z)]
	var H := 0.0
	var all_solid := true
	var lo := fy
	var zn := L.Z_YELLOW
	for c in cells:
		var cc: Vector2i = c
		var i := L.idx(cc.x, cc.y)
		if D.flo[i] != L.F_SOLID:
			all_solid = false
			var hh := D.height_m(cc.x, cc.y)
			H = maxf(H, hh if hh > 0.01 else 2.7)
			zn = D.zone[i]
		if D.flo[i] == L.F_PIT:
			lo = fy - PIT_DEPTH
	if all_solid:
		return
	var hw := T if any else 0.22
	var px := x * L.C
	var pz := z * L.C
	var y0 := lo
	var y1 := fy + H
	var faces := [
		[Vector3(1, 0, 0), e_e == L.E_WALL, Vector2i(x, z)],
		[Vector3(-1, 0, 0), e_w == L.E_WALL, Vector2i(x - 1, z - 1)],
		[Vector3(0, 0, 1), e_s == L.E_WALL, Vector2i(x, z)],
		[Vector3(0, 0, -1), e_n == L.E_WALL, Vector2i(x - 1, z - 1)],
	]
	var wm := _wall_mat(zn)
	for f in faces:
		var n: Vector3 = f[0]
		if f[1]:
			continue
		var cell: Vector2i = f[2]
		if D.flo[L.idx(cell.x, cell.y)] == L.F_SOLID:
			continue
		var t := Vector3(-n.z, 0, n.x)
		var c := Vector3(px, 0, pz) + n * hw
		var a := c - t * hw
		var b := c + t * hw
		var flo_y := fy
		quad(wm, Vector3(a.x, y0, a.z), Vector3(b.x, y0, b.z), Vector3(b.x, y1, b.z), Vector3(a.x, y1, a.z), n, 1, 3, cell,
			func(p: Vector3) -> Vector2: return Vector2(p.x + p.z, p.y),
			func(p: Vector3) -> float: return 0.6 + 0.4 * smoothstep(flo_y, flo_y + 0.7, p.y))
		if _has_base(zn) and pil:
			var bo := n * 0.012
			quad(M_BASE, Vector3(a.x, fy, a.z) + bo, Vector3(b.x, fy, b.z) + bo, Vector3(b.x, fy + 0.1, b.z) + bo, Vector3(a.x, fy + 0.1, a.z) + bo,
				n, 1, 1, cell, func(p: Vector3) -> Vector2: return Vector2(p.x + p.z, p.y), func(_p: Vector3) -> float: return 0.8)
	boxes.append([Vector3(px, (y0 + y1) * 0.5, pz), Vector3(hw, (y1 - y0) * 0.5, hw)])


func _floor_collision() -> void:
	for j in L.CHUNK:
		var run_start := -1
		for i in L.CHUNK + 1:
			var ok := false
			if i < L.CHUNK:
				ok = D.flo[L.idx(x0 + i, z0 + j)] == L.F_FLOOR
			if ok and run_start < 0:
				run_start = i
			elif not ok and run_start >= 0:
				var xa := (x0 + run_start) * L.C
				var xb := (x0 + i) * L.C
				var zc := (z0 + j + 0.5) * L.C
				boxes.append([Vector3((xa + xb) * 0.5, fy - 0.25, zc), Vector3((xb - xa) * 0.5, 0.25, L.C * 0.5)])
				run_start = -1


## Кабели Async по полу: через «центр» клетки к серединам рёбер
func _cables() -> void:
	for j in L.CHUNK:
		for i in L.CHUNK:
			var x := x0 + i
			var z := z0 + j
			var bits := D.cable[L.idx(x, z)]
			if bits == 0:
				continue
			var c := L.cell_center(x, z)
			var h := _hash2(x, z)
			var cc := Vector3(c.x + (h - 0.5) * 0.9, fy + 0.025, c.y + (_hash2(z, x) - 0.5) * 0.9)
			for d in 4:
				if bits & (1 << d) == 0:
					continue
				var o: Vector2i = L.DIRS[d]
				var ex := c.x + o.x * L.C * 0.5
				var ez := c.y + o.y * L.C * 0.5
				# точка на ребре со сдвигом вдоль ребра — общая для обеих клеток
				var ekx := x if o.x >= 0 else x - 1
				var ekz := z if o.y >= 0 else z - 1
				var sh := (_hash2(ekx * 3 + (1 if o.x != 0 else 0), ekz * 5) - 0.5) * 0.8
				var ep := Vector3(ex + (sh if o.x == 0 else 0.0), fy + 0.025, ez + (sh if o.y == 0 else 0.0))
				_tube(cc, ep, 0.022, Vector2i(x, z))


func _tube(a: Vector3, b: Vector3, r: float, cell: Vector2i) -> void:
	var dir := (b - a)
	var ln := dir.length()
	if ln < 0.01:
		return
	dir /= ln
	var side := dir.cross(Vector3.UP).normalized() * r
	var up := Vector3.UP * r
	var segs := maxi(2, int(ln / 0.4))
	var col := light_at(a.lerp(b, 0.5) + Vector3.UP * 0.1, Vector3.UP, false, cell)
	var s := _s(M_CABLE)
	var vs: PackedVector3Array = s.v
	var ns: PackedVector3Array = s.n
	var cs: PackedColorArray = s.c
	var us: PackedVector2Array = s.uv
	var u2: PackedVector2Array = s.uv2
	for k in segs:
		var t0 := float(k) / segs
		var t1 := float(k + 1) / segs
		var w0 := sin(t0 * PI) * 0.05 * (_hash2(cell.x + k, cell.y) - 0.5)
		var w1 := sin(t1 * PI) * 0.05 * (_hash2(cell.x + k + 1, cell.y) - 0.5)
		var p0 := a.lerp(b, t0) + side * w0 * 20.0
		var p1 := a.lerp(b, t1) + side * w1 * 20.0
		# два ребра «трубки»: верх и бок
		for face in [[up, side], [side, -up], [-side, up]]:
			var f0: Vector3 = face[0]
			var f1: Vector3 = face[1]
			var n := (f0 + f1).normalized()
			var q := [p0 + f0, p1 + f0, p1 + f1, p0 + f1]
			var flip := ((q[1] as Vector3) - (q[0] as Vector3)).cross((q[3] as Vector3) - (q[0] as Vector3)).dot(n) * WIND < 0.0
			var order := [0, 1, 2, 0, 2, 3] if not flip else [0, 2, 1, 0, 3, 2]
			for o in order:
				vs.append(q[o])
				ns.append(n)
				cs.append(col)
				us.append(Vector2(t0, 0))
				u2.append(Vector2(0.9, 0))
	s.v = vs
	s.n = ns
	s.c = cs
	s.uv = us
	s.uv2 = u2


static func _hash2(x: int, z: int) -> float:
	var h := (x * 374761393 + z * 668265263) & 0x7fffffff
	h = (h ^ (h >> 13)) * 1274126177
	h = h & 0x7fffffff
	return float(h % 10007) / 10007.0
