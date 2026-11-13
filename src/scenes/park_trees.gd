extends RefCounted
## Деревья парка — процедурные меши. Ствол и ветви — трубки с корой, крона — карточки с кластерами листьев
## (alpha scissor, «сферические» нормали кроны, затенение к центру), всё качается ветром в шейдере.
## Виды: платан/ясень (broad), калифорнийский дуб (oak), эвкалипт (euc), вашингтония (palm).
## На вид несколько вариантов меша, деревья — их экземпляры с разным поворотом, масштабом и оттенком.

const LEAF_SHADER := preload("res://src/shaders/park_leaves.gdshader")
const BARK_SHADER := preload("res://src/shaders/park_bark.gdshader")

## Параметры видов: ствол (высота, радиус), сучья (число, угол от вертикали, длина), ветвление, карточки
const SPECIES := {
	"broad": {"trunk_h": Vector2(2.4, 3.4), "trunk_r": Vector2(0.22, 0.3), "lean": 0.25, "limbs": Vector2i(5, 7),
		"limb_t": 0.6, "limb_ang": Vector2(24, 50), "limb_len": Vector2(3.6, 4.8), "kids": Vector2i(3, 4),
		"kid_ang": Vector2(26, 50), "kid_len": Vector2(0.6, 0.75), "up": [0.0, 0.12, 0.08, 0.02], "wiggle": 0.22,
		"depth": 3, "taper": 0.45, "leader": true, "cards": 14, "card": Vector2(1.0, 1.4), "spread": 1.0,
		"bark": "bark_broad", "leaf": "leaf_broad", "hang": false, "dry": 0.06},
	"oak": {"trunk_h": Vector2(1.5, 2.3), "trunk_r": Vector2(0.3, 0.42), "lean": 0.35, "limbs": Vector2i(5, 7),
		"limb_t": 0.7, "limb_ang": Vector2(50, 76), "limb_len": Vector2(4.2, 5.8), "kids": Vector2i(3, 4),
		"kid_ang": Vector2(30, 60), "kid_len": Vector2(0.55, 0.7), "up": [0.0, 0.05, 0.12, 0.08], "wiggle": 0.3,
		"depth": 3, "taper": 0.42, "leader": false, "cards": 14, "card": Vector2(0.95, 1.3), "spread": 1.0,
		"bark": "bark_oak", "leaf": "leaf_oak", "hang": false, "dry": 0.04},
	"euc": {"trunk_h": Vector2(7.0, 9.5), "trunk_r": Vector2(0.3, 0.4), "lean": 0.5, "limbs": Vector2i(5, 7),
		"limb_t": 0.45, "limb_ang": Vector2(18, 42), "limb_len": Vector2(4.5, 7.0), "kids": Vector2i(2, 3),
		"kid_ang": Vector2(25, 50), "kid_len": Vector2(0.55, 0.75), "up": [0.0, 0.1, -0.02, -0.1], "wiggle": 0.25,
		"depth": 3, "taper": 0.4, "leader": true, "cards": 9, "card": Vector2(1.2, 1.6), "spread": 0.75,
		"bark": "bark_euc", "leaf": "leaf_euc", "hang": true, "dry": 0.12},
}

var mats := {}
var variants := {}       # вид → Array мешей
var info := {}           # меш → {"r": радиус ствола, "crown": радиус кроны, "h": высота}
var wind_mats: Array = []
var rng := RandomNumberGenerator.new()


class Geo:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()

	## Вес изгиба (альфа цвета): 0 у земли, 1 у верхушки высоты h
	func weights(h: float) -> void:
		for i in v.size():
			var col := c[i]
			col.a = pow(clampf((v[i].y - 0.4) / maxf(h - 0.4, 1.0), 0.0, 1.0), 1.5)
			c[i] = col

	func commit(mesh: ArrayMesh, mat: Material) -> void:
		if v.is_empty():
			return
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


func _init() -> void:
	rng.seed = 19900714
	_mats()
	for k in ["broad", "broad", "broad", "oak", "oak", "euc", "euc", "palm", "palm", "palm", "shrub", "shrub", "shrub"]:
		if not variants.has(k):
			variants[k] = []
		var m: ArrayMesh
		match k:
			"palm": m = _palm()
			"shrub": m = _shrub()
			_: m = _tree(SPECIES[k])
		(variants[k] as Array).append(m)


# ------------------------------------------------------------ материалы

func _leaf_mat(tex: String, tint: Color, sway: float, flutter: float, transl: float, cut := 0.5) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = LEAF_SHADER
	m.set_shader_parameter("leaf_tex", Mats.tex(tex))
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("sway", sway)
	m.set_shader_parameter("flutter", flutter)
	m.set_shader_parameter("translucency", transl)
	m.set_shader_parameter("alpha_cut", cut)
	wind_mats.append(m)
	return m


func _bark_mat(tex: String, tint: Color, sway: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = BARK_SHADER
	m.set_shader_parameter("bark_tex", Mats.tex(tex))
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("sway", sway)
	wind_mats.append(m)
	return m


func _mats() -> void:
	mats["leaf_broad"] = _leaf_mat("park_leaf_broad", Color(1.0, 1.0, 0.95), 0.32, 0.035, 0.55)
	mats["leaf_oak"] = _leaf_mat("park_leaf_oak", Color(0.95, 1.0, 0.95), 0.22, 0.022, 0.4)
	mats["leaf_euc"] = _leaf_mat("park_leaf_euc", Color(1.0, 1.0, 1.0), 0.45, 0.06, 0.5)
	mats["palm_fan"] = _leaf_mat("park_palm_fan", Color(1.0, 1.0, 0.92), 0.4, 0.05, 0.6, 0.45)
	# разрезной веер вдали не заливается в сплошной диск: альфа на мипах не «густеет» и берётся не мельче 2-го мипа
	(mats["palm_fan"] as ShaderMaterial).set_shader_parameter("mip_fill", 0.0)
	(mats["palm_fan"] as ShaderMaterial).set_shader_parameter("alpha_max_lod", 2.0)
	mats["palm_skirt"] = _leaf_mat("park_palm_skirt", Color(0.85, 0.85, 0.85), 0.4, 0.0, 0.12, 0.5)
	(mats["palm_skirt"] as ShaderMaterial).set_shader_parameter("ao_min", 0.7)
	mats["leaf_shrub"] = _leaf_mat("park_leaf_oak", Color(1.05, 1.08, 0.98), 0.06, 0.018, 0.35)
	mats["bark_broad"] = _bark_mat("park_bark", Color(1.0, 1.0, 1.0), 0.32)
	mats["bark_oak"] = _bark_mat("park_bark", Color(0.85, 0.82, 0.8), 0.22)
	mats["bark_euc"] = _bark_mat("park_bark_euc", Color(1.0, 1.0, 1.0), 0.45)
	mats["palm_trunk"] = _bark_mat("park_palm_trunk", Color(1.0, 1.0, 1.0), 0.4)


# ------------------------------------------------------------ геометрия

## Трубка по точкам pts с радиусами rad: кольца с параллельным переносом рамки (без перекрутов).
## cap — закрыть конец скруглённой «пробкой» (у веток нет открытых срезов)
func _tube(g: Geo, pts: PackedVector3Array, rad: PackedFloat32Array, sides: int, ao: float, tile_u: float, tile_v: float, v0 := 0.0, cap := false) -> void:
	var n := pts.size()
	var base := g.v.size()
	var t0 := (pts[1] - pts[0]).normalized()
	var ref := Vector3.RIGHT if absf(t0.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var nx := t0.cross(ref).normalized()
	var acc := v0
	var urep := maxf(1.0, round(TAU * rad[0] / tile_u))
	for i in n:
		var t: Vector3
		if i == 0:
			t = (pts[1] - pts[0]).normalized()
		elif i == n - 1:
			t = (pts[i] - pts[i - 1]).normalized()
		else:
			t = (pts[i + 1] - pts[i - 1]).normalized()
		nx = (nx - t * nx.dot(t)).normalized()
		var bx := t.cross(nx)
		if i > 0:
			acc += pts[i].distance_to(pts[i - 1])
		for s in sides + 1:
			var a := float(s) / sides * TAU
			var d := nx * cos(a) + bx * sin(a)
			g.v.append(pts[i] + d * rad[i])
			g.n.append(d)
			g.uv.append(Vector2(float(s) / sides * urep, acc / tile_v))
			g.c.append(Color(ao, 0, 0, 0))
	var row := sides + 1
	for i in n - 1:
		for s in sides:
			var a := base + i * row + s
			g.idx.append_array([a, a + row, a + 1, a + 1, a + row, a + row + 1])
	if cap:
		# пробка: ещё одно сжатое кольцо и вершина-макушка по касательной
		var te := (pts[n - 1] - pts[n - 2]).normalized()
		var re := rad[n - 1]
		var last := base + (n - 1) * row
		var mid := g.v.size()
		for s in sides + 1:
			var q := g.v[last + s] - pts[n - 1]
			g.v.append(pts[n - 1] + q * 0.5 + te * re * 0.7)
			g.n.append((q.normalized() * 0.55 + te * 0.84).normalized())
			g.uv.append(g.uv[last + s] + Vector2(0.0, re * 0.6 / tile_v))
			g.c.append(Color(ao, 0, 0, 0))
		for s in sides:
			var a2 := last + s
			var b2 := mid + s
			g.idx.append_array([a2, b2, a2 + 1, a2 + 1, b2, b2 + 1])
		var tip := g.v.size()
		g.v.append(pts[n - 1] + te * re * 1.9)
		g.n.append(te)
		g.uv.append(g.uv[last] + Vector2(urep * 0.5, re * 0.9 / tile_v))
		g.c.append(Color(ao, 0, 0, 0))
		for s in sides:
			g.idx.append_array([mid + s, tip, mid + s + 1])


func _rnd_unit() -> Vector3:
	var z := rng.randf_range(-1.0, 1.0)
	var a := rng.randf() * TAU
	var r := sqrt(1.0 - z * z)
	return Vector3(r * cos(a), z, r * sin(a))


static func _deviate(dir: Vector3, ang: float, roll: float) -> Vector3:
	var ref := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var a := dir.cross(ref).normalized()
	var b := dir.cross(a).normalized()
	var perp := a * cos(roll) + b * sin(roll)
	return (dir * cos(ang) + perp * sin(ang)).normalized()


## Плавная кривая через опорные точки (Катмулл — Ром): sub точек на отрезок, касательная без изломов
static func _smooth(ctrl: PackedVector3Array, sub: int) -> PackedVector3Array:
	var n := ctrl.size()
	var out := PackedVector3Array([ctrl[0]])
	for i in n - 1:
		var p0 := ctrl[i - 1] if i > 0 else ctrl[0] * 2.0 - ctrl[1]
		var p1 := ctrl[i]
		var p2 := ctrl[i + 1]
		var p3 := ctrl[i + 2] if i + 2 < n else ctrl[n - 1] * 2.0 - ctrl[n - 2]
		for k in range(1, sub + 1):
			var t := float(k) / sub
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	return out


static func _along_f(vals: PackedFloat32Array, t: float) -> float:
	var k := t * (vals.size() - 1)
	var i := mini(int(k), vals.size() - 2)
	return lerpf(vals[i], vals[i + 1], k - i)


static func _along(pts: PackedVector3Array, t: float) -> Vector3:
	var k := t * (pts.size() - 1)
	var i := mini(int(k), pts.size() - 2)
	return pts[i].lerp(pts[i + 1], k - i)


## Ветвь: выходит из оси родителя (pr — его радиус в точке выхода) прямо, дальше плавно изгибается: поворот
## меняется понемногу (без «локтей»), кривая сглажена. У основания — наплыв, переходящий в родителя; конец
## закрыт острым кончиком. Последний уровень — тонкие веточки (4 грани, 1–3 см), на них сидит листва
func _branch(g: Geo, p0: Vector3, d: Vector3, length: float, r0: float, depth: int, sp: Dictionary, tips: Array, pr := 0.0) -> void:
	var segs := 4 if depth == 1 else 3
	var ups: Array = sp.up
	var taper: float = sp.taper
	var wig: float = sp.wiggle
	var lead := pr + r0 * 2.0
	var ctrl := PackedVector3Array([p0, p0 + d * lead])
	var p := ctrl[1]
	var dir := d
	var bend := _rnd_unit() * wig
	var rest := maxf(length - lead, length * 0.5)
	for i in segs:
		bend = bend * 0.55 + _rnd_unit() * wig * 0.7
		dir = (dir + bend * 0.75 + Vector3.UP * float(ups[depth])).normalized()
		p += dir * rest / segs
		ctrl.append(p)
	var pts := _smooth(ctrl, [1, 4, 3, 2][depth] as int)
	var acc := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		acc.append(acc[i - 1] + pts[i].distance_to(pts[i - 1]))
	var total := acc[acc.size() - 1]
	var rad := PackedFloat32Array()
	for i in pts.size():
		var sa := acc[i]
		# к концу ветвь истончается сильнее (последняя треть — вдвое): кончик острый, а не тупая «пробка»
		var r := r0 * lerpf(1.0, taper, sa / total) * lerpf(1.0, 0.45, smoothstep(0.55, 1.0, sa / total)) * (1.0 + 0.55 * exp(-maxf(sa - pr, 0.0) / (r0 * 1.3)))
		rad.append(maxf(r, 0.007))
	var last_depth := int(sp.depth)
	# все уровни, вплоть до тонких веточек под листвой: иначе сучья обрываются, а нарисованные на карточках
	# черешки висят в воздухе отдельно от дерева
	var sides := [12, 10, 7, 4][mini(depth, 3)] as int
	_tube(g, pts, rad, sides, [1.0, 0.85, 0.72, 0.6][mini(depth, 3)] as float, 0.9, 1.8, 0.0, true)
	if depth >= last_depth:
		tips.append([pts, dir, 1.0])
		return
	if depth == last_depth - 1:
		tips.append([pts, dir, 0.5])
	var kids: Vector2i = sp.kids
	var nc := rng.randi_range(kids.x, kids.y)
	var roll0 := rng.randf() * TAU
	var ka: Vector2 = sp.kid_ang
	var kl: Vector2 = sp.kid_len
	for k in nc:
		var t := lerpf(0.4, 0.95, (k + rng.randf() * 0.6) / nc)
		var cp := _along(pts, t)
		var ki := mini(int(t * (pts.size() - 1)), pts.size() - 2)
		var tang := (pts[ki + 1] - pts[ki]).normalized()
		var prr := _along_f(rad, t)
		var cr := r0 * lerpf(1.0, taper, t) * 0.78
		var cd := _deviate(tang, deg_to_rad(rng.randf_range(ka.x, ka.y)), roll0 + k * 2.39996 + rng.randf_range(-0.3, 0.3))
		_branch(g, cp, cd, length * rng.randf_range(kl.x, kl.y), cr, depth + 1, sp, tips, prr * 0.85)


## Карточка листвы: центр q, размер s, ячейка атласа cell; нормали — от центра кроны (эллипсоид c/rad)
func _card(g: Geo, q: Vector3, s: float, cell: int, hang: bool, c: Vector3, rad: Vector3, dry: float) -> void:
	var u: Vector3
	var vv: Vector3
	if hang:
		# свисающая веточка: плоскость почти вертикальна, верх текстуры (черенок) — вверху
		var a := rng.randf() * TAU
		var f := Vector3(cos(a), rng.randf_range(-0.25, 0.25), sin(a)).normalized()
		vv = (Vector3.DOWN + _rnd_unit() * 0.35).normalized()
		u = vv.cross(f).normalized()
		vv = f.cross(u).normalized()
		if vv.y > 0.0:
			vv = -vv
	else:
		var f := (_rnd_unit() + Vector3.UP * 0.35).normalized()
		var ref := Vector3.UP if absf(f.y) < 0.9 else Vector3.RIGHT
		u = f.cross(ref).normalized().rotated(f, rng.randf() * TAU)
		vv = f.cross(u).normalized()
	var u0 := float(cell % 2) * 0.5 + 0.004
	var v0 := float(cell / 2) * 0.5 + 0.004
	var w := 0.492
	var flip := rng.randf() < 0.5
	var rnd := rng.randf()
	var base := g.v.size()
	var corners := [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]
	for cc in corners:
		var cx: float = cc[0]
		var cy: float = cc[1]
		var p := q + u * cx * s * 0.5 + vv * cy * s * 0.5
		var rel := (p - c) / rad
		var sn := (rel / rad).normalized()
		var nrm := (sn * 0.85 + Vector3.UP * 0.25).normalized()
		var depth_k := clampf(rel.length(), 0.0, 1.2)
		var ao := smoothstep(0.15, 1.0, depth_k) * lerpf(0.7, 1.0, clampf((p.y - (c.y - rad.y)) / (2.0 * rad.y), 0.0, 1.0))
		g.v.append(p)
		g.n.append(nrm)
		var uu := (cx * 0.5 + 0.5) if not flip else (0.5 - cx * 0.5)
		g.uv.append(Vector2(u0 + uu * w, v0 + (cy * 0.5 + 0.5) * w))
		g.c.append(Color(ao, rnd, dry, 0.0))
	g.idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


func _tree(sp: Dictionary) -> ArrayMesh:
	var bark := Geo.new()
	var leaf := Geo.new()
	var tips: Array = []
	var th_r: Vector2 = sp.trunk_h
	var tr_r: Vector2 = sp.trunk_r
	var th := rng.randf_range(th_r.x, th_r.y)
	var tr := rng.randf_range(tr_r.x, tr_r.y)
	var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * float(sp.lean)
	# ствол: корневой наплыв у земли, дальше плавно сужается
	var pts := PackedVector3Array([Vector3(0, -0.4, 0), Vector3(0, 0.0, 0), Vector3(0, 0.35, 0)])
	var rad := PackedFloat32Array([tr * 1.55, tr * 1.4, tr * 1.12])
	var segs := 5
	for i in segs:
		var t := float(i + 1) / segs
		var p := Vector3(0, 0.35 + (th - 0.35) * t, 0) + lean * t * t + Vector3(rng.randf_range(-0.05, 0.05), 0, rng.randf_range(-0.05, 0.05))
		pts.append(p)
		rad.append(tr * lerpf(1.0, 0.78, t))
	pts = _smooth(pts, 2)
	var rad2 := PackedFloat32Array()
	for i in pts.size():
		rad2.append(_along_f(rad, float(i) / (pts.size() - 1)))
	rad = rad2
	_tube(bark, pts, rad, 12, 1.0, 0.9, 1.8, 0.0, true)
	var top := pts[pts.size() - 1]
	var tdir := (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()
	var trunk_pts := pts.slice(4)
	var trunk_rad := rad.slice(4)
	# сучья
	var lim: Vector2i = sp.limbs
	var nl := rng.randi_range(lim.x, lim.y)
	var la: Vector2 = sp.limb_ang
	var ll: Vector2 = sp.limb_len
	var lt: float = sp.limb_t
	var az0 := rng.randf() * TAU
	for k in nl:
		var az := az0 + k * TAU / nl + rng.randf_range(-0.35, 0.35)
		var el := deg_to_rad(rng.randf_range(la.x, la.y))
		var d := Vector3(sin(el) * cos(az), cos(el), sin(el) * sin(az))
		var t := lerpf(lt, 1.0, float(k) / maxf(nl - 1, 1)) if lt < 0.99 else 1.0
		var sp0 := _along(trunk_pts, t)
		var r0 := tr * lerpf(1.0, 0.78, t) * rng.randf_range(0.55, 0.7)
		_branch(bark, sp0, d, rng.randf_range(ll.x, ll.y), r0, 1, sp, tips, _along_f(trunk_rad, t) * 0.85)
	if bool(sp.leader):
		_branch(bark, top - tdir * tr * 0.6, (tdir + Vector3.UP).normalized(), rng.randf_range(ll.x, ll.y) * 1.05, tr * 0.62, 1, sp, tips, tr * 0.5)
	# листва: точки по концевым веточкам, затем эллипсоид кроны
	var qs: Array = []
	var cards: int = sp.cards
	var spread: float = sp.spread
	for tp in tips:
		var tpts: PackedVector3Array = tp[0]
		var tk: float = tp[2]
		for k in int(round(cards * tk)):
			var t := (rng.randf_range(0.2, 1.0) if k > 0 else 1.0) if tk > 0.5 else rng.randf_range(0.55, 1.0)
			qs.append(_along(tpts, t) + _rnd_unit() * rng.randf() * spread)
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for q in qs:
		var qv: Vector3 = q
		lo = lo.min(qv)
		hi = hi.max(qv)
	var c := (lo + hi) * 0.5
	var crad := ((hi - lo) * 0.5).max(Vector3(1.0, 1.0, 1.0))
	var cs: Vector2 = sp.card
	var hang: bool = sp.hang
	var dry0: float = sp.dry
	for q in qs:
		var dry := dry0 * rng.randf() * 2.0 if rng.randf() < 0.3 else 0.0
		_card(leaf, q, rng.randf_range(cs.x, cs.y), rng.randi_range(0, 3), hang, c, crad, dry)
	var h := hi.y + 0.5
	bark.weights(h)
	leaf.weights(h)
	var mesh := ArrayMesh.new()
	bark.commit(mesh, mats[sp.bark])
	leaf.commit(mesh, mats[sp.leaf])
	info[mesh] = {"r": tr * 1.3, "crown": maxf(crad.x, crad.z), "h": h}
	return mesh


## Куст олеандра (живые изгороди по валу): пучок стеблей от земли и плотная приплюснутая крона из карточек
func _shrub() -> ArrayMesh:
	var bark := Geo.new()
	var leaf := Geo.new()
	var h := rng.randf_range(1.7, 2.6)
	var r := rng.randf_range(1.1, 1.7)
	for k in rng.randi_range(6, 9):
		var a := rng.randf() * TAU
		var d := Vector3(cos(a), 0, sin(a))
		var top := d * r * rng.randf_range(0.3, 0.7) + Vector3(0, h * rng.randf_range(0.6, 0.9), 0)
		var p0 := d * rng.randf_range(0.0, 0.25) + Vector3(0, -0.2, 0)
		_tube(bark, PackedVector3Array([p0, p0.lerp(top, 0.5) + Vector3(0, 0.1, 0), top]), PackedFloat32Array([0.035, 0.025, 0.012]), 4, 0.6, 0.5, 1.2)
	var c := Vector3(0, h * 0.5, 0)
	var rad := Vector3(r, h * 0.55, r)
	for i in rng.randi_range(150, 190):
		var dir := _rnd_unit()
		var q := c + dir * rad * (0.5 + 0.5 * sqrt(rng.randf()))
		q.y = maxf(q.y, 0.3)
		_card(leaf, q, rng.randf_range(0.75, 1.05), rng.randi_range(0, 3), false, c, rad, 0.0)
	bark.weights(h * 2.0)
	leaf.weights(h * 2.0)
	var mesh := ArrayMesh.new()
	bark.commit(mesh, mats["bark_broad"])
	leaf.commit(mesh, mats["leaf_shrub"])
	info[mesh] = {"r": r * 0.55, "crown": r, "h": h}
	return mesh


## Вашингтония: тонкий высокий ствол с кольцами, «юбка» сухих листьев, голова из веерных листьев
func _palm() -> ArrayMesh:
	var trunk := Geo.new()
	var fan := Geo.new()
	var skirt := Geo.new()
	var h := rng.randf_range(11.0, 18.5)
	var bend := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.2, 1.1)
	var pts := PackedVector3Array([Vector3(0, -0.4, 0)])
	var rad := PackedFloat32Array([0.48])
	for i in 12:
		var t := float(i + 1) / 12.0
		pts.append(Vector3(0, -0.4 + (h + 0.4) * t, 0) + bend * t * t)
		var r := lerpf(0.27, 0.21, t)
		if t < 0.12:
			r = lerpf(0.44, 0.28, t / 0.12)
		rad.append(r)
	_tube(trunk, pts, rad, 12, 1.0, 1.4, 1.5, 0.0, true)
	var top := pts[pts.size() - 1]
	var head := top + Vector3(0, 0.35, 0)
	# юбка сухих листьев (у части пальм обрезана коротко)
	var sk_len := rng.randf_range(1.8, 3.6) if rng.randf() < 0.7 else rng.randf_range(0.5, 0.9)
	for layer in 2:
		var r_top := 0.3 + layer * 0.1
		var r_bot := r_top + 0.3 + sk_len * 0.1
		var y0 := top.y + 0.3 - layer * 0.15
		var y1 := top.y - sk_len * (1.0 - layer * 0.15)
		var sides := 14
		var base := skirt.v.size()
		var off := rng.randf()
		for s in sides + 1:
			var a := float(s) / sides * TAU
			var d := Vector3(cos(a), 0, sin(a))
			var cx := Vector3(top.x, 0, top.z)
			for e in [[y0, r_top, 0.0], [y1, r_bot, 1.0]]:
				var ey: float = e[0]
				var er: float = e[1]
				var ev: float = e[2]
				skirt.v.append(cx + d * er + Vector3(0, ey, 0))
				skirt.n.append((d + Vector3.UP * 0.15).normalized())
				skirt.uv.append(Vector2(float(s) / sides * 3.0 + off, ev))
				skirt.c.append(Color(lerpf(0.75, 0.45, ev), rng.randf(), 0.0, 0.0))
		for s in sides:
			var a2 := base + s * 2
			skirt.idx.append_array([a2, a2 + 2, a2 + 1, a2 + 1, a2 + 2, a2 + 3])
	# сухие листья свисают из-под юбки: снизу видна лохматая бахрома, а не ровный тёмный диск
	for k in rng.randi_range(9, 13):
		var az2 := rng.randf() * TAU
		var rd := Vector3(cos(az2), 0, sin(az2))
		var hy := top.y - sk_len * rng.randf_range(0.35, 0.9)
		var hub2 := Vector3(top.x, hy, top.z) + rd * rng.randf_range(0.45, 0.7)
		var fd2 := (rd * rng.randf_range(0.12, 0.35) + Vector3.DOWN).normalized()
		_fan(fan, hub2, fd2, rng.randf_range(1.5, 2.1), rng.randf_range(-0.6, 0.6), rng.randf_range(0.45, 0.7), rng.randf_range(0.85, 1.0), head)
	# веерные листья: молодые торчат вверх, старые свисают и буреют
	var nf := rng.randi_range(32, 40)
	for i in nf:
		var t := float(i) / (nf - 1)
		var az := i * 2.39996 + rng.randf_range(-0.2, 0.2)
		var el := deg_to_rad(lerpf(76.0, -58.0, t) + rng.randf_range(-9.0, 9.0))
		var d := Vector3(cos(el) * cos(az), sin(el), cos(el) * sin(az))
		var pl := rng.randf_range(1.35, 1.9)
		var p0 := head + Vector3(d.x, 0, d.z) * 0.15
		var hub := p0 + d * pl + Vector3(0, -pl * 0.08, 0)
		_tube(trunk, PackedVector3Array([p0, p0.lerp(hub, 0.5) + Vector3(0, 0.05, 0), hub]), PackedFloat32Array([0.05, 0.035, 0.025]), 3, 0.8, 0.5, 1.5)
		var fd := (d + Vector3.DOWN * (0.2 + t * 0.55)).normalized()
		var dry := 0.0
		if t > 0.82:
			dry = rng.randf_range(0.6, 1.0)
		elif rng.randf() < 0.15:
			dry = rng.randf_range(0.1, 0.35)
		# веер ~1,5 м (лист вашингтонии), сложен по жилке глубже: снизу и вдали — гребёнка, а не плоский диск
		_fan(fan, hub, fd, rng.randf_range(2.7, 3.2) * 0.74, rng.randf_range(-0.5, 0.5), rng.randf_range(0.25, 0.45) + 0.3, dry, head)
	trunk.weights(h + 1.5)
	fan.weights(h + 1.5)
	skirt.weights(h + 1.5)
	var mesh := ArrayMesh.new()
	trunk.commit(mesh, mats["palm_trunk"])
	fan.commit(mesh, mats["palm_fan"])
	skirt.commit(mesh, mats["palm_skirt"])
	info[mesh] = {"r": 0.42, "crown": 3.0, "h": h + 1.5}
	return mesh


## Веер: две половины, сложенные вдоль средней жилки (V), центр текстуры (0.5, 0.64) — в точке hub
func _fan(g: Geo, hub: Vector3, fd: Vector3, s: float, roll: float, fold: float, dry: float, head: Vector3) -> void:
	var right := fd.cross(Vector3.UP)
	if right.length() < 0.05:
		right = Vector3.RIGHT
	right = right.normalized().rotated(fd, roll)
	var nf := right.cross(fd).normalized()
	if nf.y < 0.0:
		nf = -nf
	var rnd := rng.randf()
	for half in 2:
		var sv := right.rotated(fd, fold if half == 0 else -fold)
		var ua := 0.0 if half == 0 else 0.5
		var ub := 0.5 if half == 0 else 1.0
		var base := g.v.size()
		for cc in [[ua, 0.0], [ub, 0.0], [ub, 1.0], [ua, 1.0]]:
			var cu: float = cc[0]
			var cv: float = cc[1]
			var p := hub + sv * (cu - 0.5) * s + fd * (0.64 - cv) * s
			var sn := (p - head).normalized()
			g.v.append(p)
			g.n.append((sn * 0.6 + nf * 0.4 + Vector3.UP * 0.2).normalized())
			g.uv.append(Vector2(cu, cv))
			g.c.append(Color(lerpf(0.55, 1.0, clampf(0.5 + (p.y - head.y) * 0.4, 0.0, 1.0)), rnd, dry, 0.0))
		g.idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


# ------------------------------------------------------------ деревья

## Поставить дерево вида kind; возвращает узел и данные (радиус кроны и т. п.)
func spawn(parent: Node3D, kind: String, pos: Vector3, rot: float, sc: float, hue: float, collide: bool, pick := -1) -> MeshInstance3D:
	var list: Array = variants[kind]
	var mesh: ArrayMesh = list[pick % list.size()] if pick >= 0 else list[rng.randi_range(0, list.size() - 1)]
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation.y = rot
	mi.scale = Vector3.ONE * sc
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	mi.set_instance_shader_parameter("hue_shift", hue)
	var inf: Dictionary = info[mesh]
	mi.set_meta("crown", float(inf.crown) * sc)
	mi.set_meta("h", float(inf.h) * sc)
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = float(inf.r) * sc * 0.85
		cy.height = 3.0
		cs.shape = cy
		cs.position.y = 1.5
		body.add_child(cs)
		mi.add_child(body)
	return mi
