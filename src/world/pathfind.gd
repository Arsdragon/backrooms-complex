class_name Pathfind
extends RefCounted
## A* по клеткам слоя (неограниченные координаты, мир — тор). Возвращает список клеток от старта к цели.

const LD := preload("res://src/world/layer_data.gd")


static func find(L: LayerData, from: Vector2i, to: Vector2i, max_nodes := 2500) -> Array:
	if from == to:
		return [to]
	var open := [from]
	var g := {from: 0}
	var came := {}
	var f := {from: _h(from, to)}
	var closed := {}
	var expanded := 0
	var best := from
	var best_h := _h(from, to)
	while not open.is_empty() and expanded < max_nodes:
		# минимальный f (открытый список небольшой — линейный поиск)
		var bi := 0
		var bf: int = f[open[0]]
		for i in range(1, open.size()):
			var fi: int = f[open[i]]
			if fi < bf:
				bf = fi
				bi = i
		var cur: Vector2i = open[bi]
		open.remove_at(bi)
		if cur == to:
			return _rebuild(came, cur)
		closed[cur] = true
		expanded += 1
		var hc := _h(cur, to)
		if hc < best_h:
			best_h = hc
			best = cur
		for d in 4:
			if not L.can_step(cur.x, cur.y, d):
				continue
			var o: Vector2i = LD.DIRS[d]
			var nb := cur + o
			if closed.has(nb):
				continue
			var cost := 10
			var ev := L.edge(cur.x, cur.y, d)
			if ev == LD.E_DOOR:
				cost = 13
			var ng: int = int(g[cur]) + cost
			if not g.has(nb) or ng < int(g[nb]):
				g[nb] = ng
				f[nb] = ng + _h(nb, to)
				came[nb] = cur
				if not open.has(nb):
					open.append(nb)
	# цель недостижима за лимит — идём к ближайшей найденной
	return _rebuild(came, best)


static func _h(a: Vector2i, b: Vector2i) -> int:
	return (absi(a.x - b.x) + absi(a.y - b.y)) * 10


static func _rebuild(came: Dictionary, cur: Vector2i) -> Array:
	var path := [cur]
	var c := cur
	var guard := 0
	while came.has(c) and guard < 5000:
		c = came[c]
		path.push_front(c)
		guard += 1
	return path


## Случайная проходимая клетка на расстоянии [rmin, rmax] по пути (BFS) от точки
static func cell_at_path_distance(L: LayerData, from: Vector2i, rmin: int, rmax: int, prefer_dark := true, avoid: Callable = Callable()) -> Vector2i:
	var dist := {from: 0}
	var q := [from]
	var head := 0
	var cands := []
	while head < q.size() and head < 6000:
		var c: Vector2i = q[head]
		head += 1
		var d0: int = dist[c]
		if d0 >= rmin and d0 <= rmax:
			if not avoid.is_valid() or not avoid.call(c):
				cands.append(c)
		if d0 >= rmax:
			continue
		for d in 4:
			if not L.can_step(c.x, c.y, d):
				continue
			var nb: Vector2i = c + LD.DIRS[d]
			if dist.has(nb):
				continue
			dist[nb] = d0 + 1
			q.append(nb)
	if cands.is_empty():
		return Vector2i(999999, 0)
	if prefer_dark:
		var dark := []
		for c in cands:
			var cc: Vector2i = c
			var lt := L.light[LD.idx(cc.x, cc.y)]
			var zn := L.zone[LD.idx(cc.x, cc.y)]
			if zn == LD.Z_DARK or lt == LD.L_DEAD or lt == LD.L_NONE:
				dark.append(cc)
		if dark.size() > 3:
			return dark[randi() % dark.size()]
	return cands[randi() % cands.size()]
