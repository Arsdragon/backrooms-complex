extends RefCounted
## Предметы мира по описаниям декора из WorldGen. Всё собирается из примитивов.

const DECAL := preload("res://src/shaders/decal.gdshader")
const GLASS_SHADER := preload("res://src/shaders/prop_glass.gdshader")
const LD := preload("res://src/world/layer_data.gd")

static var _decals := {}
static var park_mode := false   # парк/концовки: модели с обычными PBR-материалами
static var _font_hand: Font = null
static var _font_sign: Font = null
static var _pr: GDScript = null


static func font_hand() -> Font:
	if _font_hand == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Segoe Print", "Ink Free", "Comic Sans MS", "sans-serif"])
		f.font_weight = 700
		_font_hand = f
	return _font_hand


static func font_sign() -> Font:
	if _font_sign == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Bahnschrift", "Arial Narrow", "Arial", "sans-serif"])
		f.font_weight = 700
		_font_sign = f
	return _font_sign


# ------------------------------------------------------------ материалы

static func m_wood() -> Material: return mc(Color(0.58, 0.42, 0.28), "wood", 1.0)
static func m_iron() -> Material: return mc(Color(0.13, 0.14, 0.13), "metal", 0.5, {"gloss": 30.0, "spec": 0.12})
static func m_green() -> Material: return mc(Color(0.14, 0.27, 0.17), "metal", 0.4)
static func m_conc() -> Material: return mc(Color(0.78, 0.76, 0.7), "concrete", 1.0)
## Крашеный металл/пластик: светлые цвета ужимаются до альбедо ~0.62 (белое не «светится»), лёгкий атласный блик
static func m_plastic(c := Color(0.86, 0.85, 0.8)) -> Material:
	return mc(cap(c), "metal", 0.35, {"gloss": 36.0, "spec": 0.1})
static func m_metal() -> Material: return mc(Color(0.5, 0.51, 0.5), "metal", 0.6, {"gloss": 45.0, "spec": 0.22})
static func m_black() -> Material: return mc(Color(0.045, 0.045, 0.045), "metal", 0.3, {"gloss": 30.0, "spec": 0.1})
static func m_cloth(c: Color) -> Material: return mc(c, "fabric", 0.7)


## Цвет с альбедо не выше mx (сохраняя оттенок)
static func cap(c: Color, mx := 0.62) -> Color:
	var m := maxf(c.r, maxf(c.g, c.b))
	if m <= mx:
		return c
	var k := mx / m
	return Color(c.r * k, c.g * k, c.b * k, c.a)
static func m_wall() -> Material: return Mats.prop("wall_w", {"tex": "wall_yellow", "world_uv": 1.0, "world_scale": Vector2(1.2, 1.2), "tex_mix": 1.0, "spec": 0.05, "gloss": 18.0})
static func m_carpet() -> Material: return Mats.prop("carpet_w", {"tex": "carpet", "world_uv": 1.0, "world_scale": Vector2(1.2, 1.2), "tex_mix": 1.0, "spec": 0.02, "gloss": 30.0})
static func m_bark() -> Material: return mc(Color(1, 1, 1), "bark", 1.0, {"uv_scale": Vector2(2.0, 3.0)})
static func m_leaves() -> Material: return Mats.prop("leaves_cut", {"tex": "leaves", "tex_mix": 1.0, "alpha_cut": 0.3, "uv_scale": Vector2(2, 2)})
## Светящееся. mains — от сети: гаснет при отключении питания (лампы, табло, экраны); без — на батарейках (огоньки REC)
static func m_emit(c: Color, power := 2.0, mains := false) -> Material:
	var cc := cap(c, 0.62)
	return mc(cc, "metal", 0.0, {"emit": power, "emit_color": Vector3(c.r, c.g, c.b), "powered": 1.0 if mains else 0.0})


static var _blob_tex: Texture2D = null


## Мягкое круглое пятно (альфа от центра к краю) — для теней-«контактов» под предметами
static func blob_tex() -> Texture2D:
	if _blob_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0.0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_blob_tex = t
	return _blob_tex


## Тень-«контакт» под предметом на полу: мягкое тёмное пятно по габаритам (размер — по x/z, k — плотность)
static func blob(p: Node3D, size: Vector2, pos := Vector3.ZERO, k := 0.5) -> MeshInstance3D:
	var kq := snappedf(clampf(k, 0.1, 0.9), 0.05)
	var key := "contact_%.2f" % kq
	var mat := decal_mat(key, {"tint": Color(0.0, 0.0, 0.0, kq)})
	mat.set_shader_parameter("tex", blob_tex())
	var q := quad(p, size, Vector3(pos.x, pos.y + 0.004, pos.z), mat, Vector3(-PI * 0.5, 0, 0))
	q.set_meta("blob", true)
	return q


static var _box_blob := {}


## Тень-«контакт» под большим прямоугольным предметом (машина, шкаф): плотная под всем основанием и мягко
## гаснет за краем на edge метров — круглое пятно под длинным предметом у его краёв почти прозрачно
static func blob_box(p: Node3D, size: Vector2, pos := Vector3.ZERO, k := 0.7, edge := 0.3) -> MeshInstance3D:
	var key := "%.1f_%.1f_%.2f" % [size.x, size.y, edge]
	if not _box_blob.has(key):
		var full := size + Vector2(edge, edge) * 2.0
		var w := 64
		var h := clampi(int(64.0 * full.y / full.x), 16, 256)
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for j in h:
			for i in w:
				var q := Vector2((float(i) + 0.5) / w * full.x - full.x * 0.5, (float(j) + 0.5) / h * full.y - full.y * 0.5)
				var dq := Vector2(absf(q.x), absf(q.y)) - size * 0.5 + Vector2(0.1, 0.1)
				var sd := Vector2(maxf(dq.x, 0.0), maxf(dq.y, 0.0)).length() + minf(maxf(dq.x, dq.y), 0.0) - 0.1
				# внутри — плотно (к середине чуть светлее: свет затекает под днище), снаружи — быстрый спад
				var a := 1.0 - smoothstep(-0.05, edge, sd)
				a *= 1.0 - 0.15 * (1.0 - smoothstep(-0.6, -0.1, sd))
				img.set_pixel(i, j, Color(1, 1, 1, a))
		_box_blob[key] = ImageTexture.create_from_image(img)
	var kq := snappedf(clampf(k, 0.1, 0.95), 0.05)
	var mat := decal_mat("contact_box_%s_%.2f" % [key, kq], {"tint": Color(0.0, 0.0, 0.0, kq)})
	mat.set_shader_parameter("tex", _box_blob[key])
	var q2 := quad(p, size + Vector2(edge, edge) * 2.0, Vector3(pos.x, pos.y + 0.004, pos.z), mat, Vector3(-PI * 0.5, 0, 0))
	q2.set_meta("blob", true)
	return q2


## Тень под всем, что стоит на полу внутри n: габариты сеток в осях n. Висящее (низ выше 15 см) — без тени
static func blob_under(n: Node3D, k := 0.5, grow := 1.15) -> void:
	var box := AABB()
	var first := true
	for mi in Models._meshes(n):
		var m := mi as MeshInstance3D
		if m.has_meta("blob") or m.mesh == null or m.material_override is ShaderMaterial and (m.material_override as ShaderMaterial).shader == DECAL:
			continue
		var bb := Models._rel_xform(m, n) * m.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	if first or box.position.y > 0.15 or box.size.y < 0.05:
		return
	var c := box.get_center()
	var sz := Vector2(box.size.x * grow + 0.12, box.size.z * grow + 0.12)
	blob(n, sz, Vector3(c.x, 0.0, c.z), k)


## Высота верха модели (м) при масштабе sy — ставить вещи на столы и тумбы
static func top_of(id: String, sy := 1.0) -> float:
	if not Models.has(id):
		return 0.76
	return Models.aabb(id).end.y * sy


static func decal_mat(key: String, params: Dictionary) -> ShaderMaterial:
	if _decals.has(key):
		return _decals[key]
	var m := ShaderMaterial.new()
	m.shader = DECAL
	m.set_shader_parameter("noise_tex", Mats.tex("noise"))
	m.set_shader_parameter("tex", Mats.tex(String(params.get("tex", "mold"))))
	for k in params.keys():
		if k != "tex":
			m.set_shader_parameter(k, params[k])
	_decals[key] = m
	return m


# ------------------------------------------------------------ примитивы

## Размер плитки текстуры (м) для сгенерированной геометрии — одна плотность текселей у любых ящиков и цилиндров
const TILE := {"metal": Vector2(0.9, 0.9), "wood": Vector2(0.7, 0.7), "fabric": Vector2(0.45, 0.45), "paper": Vector2(0.3, 0.3),
	"concrete": Vector2(1.6, 1.6), "noise": Vector2(1.0, 1.0), "fiber": Vector2(0.5, 0.5), "wall_yellow": Vector2(1.2, 1.2),
	"carpet": Vector2(1.2, 1.2), "baseboard": Vector2(1.2, 0.1), "ceiling_tile": Vector2(1.2, 1.2), "wall_under": Vector2(1.2, 1.2),
	"bark": Vector2(0.9, 0.9), "asphalt": Vector2(2.4, 2.4), "grass": Vector2(0.6, 0.6), "plaster": Vector2(1.2, 1.2),
	"prop_cubicle": Vector2(0.5, 0.5), "prop_sleepbag": Vector2(0.5, 0.5), "prop_gingham": Vector2(1.0, 1.0)}


## Материал сгенерированной геометрии (как Mats.col), но текстура — по объектным метрам (box_uv, плитка по виду
## текстуры из TILE): одна плотность текселей у ящиков и цилиндров любого размера; мягкий потолок альбедо 0.66.
## Свою разметку UV (world_uv, вырез по альфе, свечение по маске) не трогает.
static func mc(c: Color, texname := "fabric", texmix := 0.6, extra := {}) -> Material:
	if TILE.has(texname) and not extra.has("world_uv") and not extra.has("emit_mask") and not extra.has("alpha_cut"):
		var ex := extra.duplicate()
		ex["box_uv"] = 1.0
		ex["world_scale"] = TILE[texname]
		if not ex.has("albedo_cap"):
			ex["albedo_cap"] = 0.66
		return Mats.col(c, texname, texmix, ex)
	return Mats.col(c, texname, texmix, extra)


static func box(p: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi)
	return mi


static func cyl(p: Node3D, rt: float, rb: float, h: float, pos: Vector3, mat: Material, rot := Vector3.ZERO, seg := 12) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi)
	return mi


static func sph(p: Node3D, r: float, pos: Vector3, mat: Material, sc := Vector3.ONE, seg := 12) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = maxi(4, seg / 2)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.scale = sc
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi)
	return mi


## Палка между двумя точками
static func rod(p: Node3D, a: Vector3, b: Vector3, r: float, mat: Material, seg := 6) -> MeshInstance3D:
	var d := b - a
	var mi := cyl(p, r, r, d.length(), (a + b) * 0.5, mat, Vector3.ZERO, seg)
	var up := d.normalized()
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(up).normalized()
	var z := x.cross(up).normalized()
	mi.basis = Basis(x, up, z)
	return mi


static func quad(p: Node3D, size: Vector2, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi)
	return mi


## Узел-сетка без теней (для процедурных сеток ниже)
static func mesh_node(p: Node3D, m: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, sc := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = sc
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi)
	return mi


# ------------------------------------------------------------ процедурные сетки

## Треугольник лицом наружу: обход выбирается по средней нормали вершин (у Godot лицевая сторона — по часовой)
static func _tri(vs: PackedVector3Array, ns: PackedVector3Array, us: PackedVector2Array, a: Array, b: Array, c: Array) -> void:
	var p0: Vector3 = a[0]
	var p1: Vector3 = b[0]
	var p2: Vector3 = c[0]
	var fn := (p1 - p0).cross(p2 - p0)
	if fn.length_squared() < 1e-14:
		return
	var nn: Vector3 = a[1] + b[1] + c[1]
	var order := [a, b, c] if fn.dot(nn) < 0.0 else [a, c, b]
	for e in order:
		var ee: Array = e
		vs.append(ee[0])
		ns.append(ee[1])
		us.append(ee[2])


## Сетка из колец точек (у каждого кольца — свои нормали и UV; соседние кольца сшиваются по порядку точек)
static func ring_mesh(rings: Array, nrms: Array, uvs: Array) -> ArrayMesh:
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var us := PackedVector2Array()
	for i in rings.size() - 1:
		var r0: PackedVector3Array = rings[i]
		var r1: PackedVector3Array = rings[i + 1]
		var n0: PackedVector3Array = nrms[i]
		var n1: PackedVector3Array = nrms[i + 1]
		var u0: PackedVector2Array = uvs[i]
		var u1: PackedVector2Array = uvs[i + 1]
		for k in r0.size() - 1:
			var q0 := [r0[k], n0[k], u0[k]]
			var q1 := [r0[k + 1], n0[k + 1], u0[k + 1]]
			var q2 := [r1[k + 1], n1[k + 1], u1[k + 1]]
			var q3 := [r1[k], n1[k], u1[k]]
			_tri(vs, ns, us, q0, q1, q2)
			_tri(vs, ns, us, q0, q2, q3)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	arr[Mesh.ARRAY_TEX_UV] = us
	var m := ArrayMesh.new()
	if vs.size() > 0:
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Гладкая труба по оси pts: в каждой точке эллипс (rx — по первой оси рамки, rz — по второй) поперёк оси.
## Рамки — параллельным переносом от ref; нормали аналитические (эллипс + наклон от сужения): шва нет.
## Радиус 0 на конце — острый кончик (пальцы, шипы).
static func loft(pts: PackedVector3Array, rx: PackedFloat32Array, rz: PackedFloat32Array, sides := 12, ref := Vector3(1, 0, 0)) -> ArrayMesh:
	var n := pts.size()
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(1, n):
		s[i] = s[i - 1] + pts[i].distance_to(pts[i - 1])
	var t0 := (pts[1] - pts[0]).normalized()
	var bx := ref - t0 * ref.dot(t0)
	if bx.length() < 0.05:
		bx = Vector3(0, 0, 1) - t0 * t0.z
	bx = bx.normalized()
	var rings := []
	var nrms := []
	var uvs := []
	for i in n:
		var ia := maxi(i - 1, 0)
		var ib := mini(i + 1, n - 1)
		var t := (pts[ib] - pts[ia]).normalized()
		bx = (bx - t * bx.dot(t)).normalized()
		var bz := t.cross(bx)
		var ds := maxf(s[ib] - s[ia], 1e-4)
		var slope := ((rx[ib] + rz[ib]) - (rx[ia] + rz[ia])) * 0.5 / ds
		var ring := PackedVector3Array()
		var rn := PackedVector3Array()
		var ru := PackedVector2Array()
		for k in sides + 1:
			var an := TAU * float(k) / float(sides)
			var c := cos(an)
			var sn := sin(an)
			ring.append(pts[i] + bx * (c * rx[i]) + bz * (sn * rz[i]))
			var nn := (bx * (c * maxf(rz[i], 1e-4)) + bz * (sn * maxf(rx[i], 1e-4))).normalized()
			rn.append((nn - t * slope).normalized())
			ru.append(Vector2(float(k) / float(sides), s[i]))
		rings.append(ring)
		nrms.append(rn)
		uvs.append(ru)
	return ring_mesh(rings, nrms, uvs)


## Изогнутый конус-«рог»: от основания a к кончику, изгиб bend (смещение середины), радиус r у основания
static func horn(a: Vector3, tip: Vector3, r: float, bend: Vector3, sides := 8, segs := 7) -> ArrayMesh:
	var pts := PackedVector3Array()
	var rr := PackedFloat32Array()
	for i in segs + 1:
		var t := float(i) / segs
		var q := a.lerp(tip, t) + bend * (4.0 * t * (1.0 - t))
		pts.append(q)
		rr.append(r * pow(1.0 - t, 0.8) + 0.0006)
	return loft(pts, rr, rr, sides)


## Ком: сфера, искажённая шумом (lumps — сила бугров), масштаб sc; нормали — по соседним точкам (без шва)
static func blob_mesh(r: float, lumps: float, seed: int, sc := Vector3.ONE, seg := 22, freq := 1.3) -> ArrayMesh:
	var nz := FastNoiseLite.new()
	nz.seed = seed
	nz.frequency = freq
	nz.fractal_octaves = 3
	var rows := seg / 2
	var grid_p := []
	for i in rows + 1:
		var lat := PI * float(i) / rows
		var row := PackedVector3Array()
		for k in seg + 1:
			var lon := TAU * float(k % seg) / seg
			var dir := Vector3(sin(lat) * cos(lon), cos(lat), sin(lat) * sin(lon))
			var d := r * (1.0 + lumps * nz.get_noise_3d(dir.x, dir.y, dir.z))
			row.append(dir * d * sc)
		grid_p.append(row)
	var rings := []
	var nrms := []
	var uvs := []
	for i in rows + 1:
		var row: PackedVector3Array = grid_p[i]
		var rn := PackedVector3Array()
		var ru := PackedVector2Array()
		for k in seg + 1:
			var kk := k % seg
			var rowa: PackedVector3Array = grid_p[maxi(i - 1, 0)]
			var rowb: PackedVector3Array = grid_p[mini(i + 1, rows)]
			var e1 := row[(kk + 1) % seg] - row[(kk + seg - 1) % seg]
			var e2 := rowb[kk] - rowa[kk]
			var nn := e1.cross(e2)
			if nn.length_squared() < 1e-12 or i == 0 or i == rows:
				nn = row[kk].normalized() if row[kk].length() > 1e-5 else Vector3(0, 1 if i == 0 else -1, 0)
			elif nn.dot(row[kk]) < 0.0:
				nn = -nn
			rn.append(nn.normalized())
			ru.append(Vector2(float(k) / seg, float(i) / rows))
		rings.append(row)
		nrms.append(rn)
		uvs.append(ru)
	return ring_mesh(rings, nrms, uvs)


## Плита по контуру poly (x, z) толщиной th: верх, низ, бока (рваные края обломков). Контур — звезда вокруг центра
static func slab_mesh(poly: PackedVector2Array, th: float) -> ArrayMesh:
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var us := PackedVector2Array()
	var c := Vector2.ZERO
	for q in poly:
		c += q
	c /= poly.size()
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		for side: float in [1.0, -1.0]:
			var y := th * 0.5 * side
			var nn := Vector3(0, side, 0)
			_tri(vs, ns, us, [Vector3(c.x, y, c.y), nn, c], [Vector3(a.x, y, a.y), nn, a], [Vector3(b.x, y, b.y), nn, b])
		var en := Vector3(b.y - a.y, 0, -(b.x - a.x)).normalized()
		if en.dot(Vector3(a.x - c.x, 0, a.y - c.y)) < 0.0:
			en = -en
		var p0 := [Vector3(a.x, th * 0.5, a.y), en, Vector2(0, 0)]
		var p1 := [Vector3(b.x, th * 0.5, b.y), en, Vector2(1, 0)]
		var p2 := [Vector3(b.x, -th * 0.5, b.y), en, Vector2(1, 1)]
		var p3 := [Vector3(a.x, -th * 0.5, a.y), en, Vector2(0, 1)]
		_tri(vs, ns, us, p0, p1, p2)
		_tri(vs, ns, us, p0, p2, p3)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	arr[Mesh.ARRAY_TEX_UV] = us
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Тело вращения вокруг оси Y по профилю prof (точки (r, y), обход так, чтобы лицевая сторона была слева:
## снаружи — снизу вверх, внутри чаши — сверху вниз). Нормали — перпендикуляры к отрезкам профиля; на стыке
## отрезков с изломом меньше crease (градусы) нормали усредняются (гладко), круче — острое ребро.
## UV: u — метры по окружности (на радиусе точки), v — метры вдоль профиля
static func lathe(prof: PackedVector2Array, sides := 32, crease := 35.0) -> ArrayMesh:
	var n := prof.size()
	var sn := PackedVector2Array()
	for i in n - 1:
		var d := (prof[i + 1] - prof[i]).normalized()
		sn.append(Vector2(d.y, -d.x))
	var cr := deg_to_rad(crease)
	var rings := []
	var nrms := []
	var uvs := []
	var s := 0.0
	for i in n - 1:
		var ends := [i, i + 1]
		for e in 2:
			var pi_: int = ends[e]
			var nn := sn[i]
			# сосед по профилю с той стороны точки
			var other := i - 1 if e == 0 else i + 1
			if other >= 0 and other < n - 1 and absf(sn[other].angle_to(sn[i])) < cr:
				nn = (sn[other] + sn[i]).normalized()
			var p2 := prof[pi_]
			var sv := s + (prof[i + 1].distance_to(prof[i]) if e == 1 else 0.0)
			var ring := PackedVector3Array()
			var rn := PackedVector3Array()
			var ru := PackedVector2Array()
			for k in sides + 1:
				var a := TAU * float(k) / sides
				var c := cos(a)
				var sa := sin(a)
				ring.append(Vector3(p2.x * c, p2.y, p2.x * sa))
				rn.append(Vector3(nn.x * c, nn.y, nn.x * sa).normalized())
				ru.append(Vector2(a * maxf(p2.x, 0.05), sv))
			rings.append(ring)
			nrms.append(rn)
			uvs.append(ru)
		s += prof[i + 1].distance_to(prof[i])
	return ring_mesh(rings, nrms, uvs)


## Призма вдоль x от x0 до x1 по многоугольнику poly в плоскости (z, y) (любой обход, может быть невыпуклым):
## торцы — триангуляция, бока — по рёбрам с внешними нормалями. UV — метры (box_uv у mc их и не читает)
static func prism_x(poly: PackedVector2Array, x0: float, x1: float) -> ArrayMesh:
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var us := PackedVector2Array()
	var n := poly.size()
	var area := 0.0
	for i in n:
		area += poly[i].x * poly[(i + 1) % n].y - poly[(i + 1) % n].x * poly[i].y
	var ccw := area > 0.0
	var tri := Geometry2D.triangulate_polygon(poly)
	for side: float in [-1.0, 1.0]:
		var x := x0 if side < 0.0 else x1
		var nn := Vector3(side, 0, 0)
		for t in range(0, tri.size(), 3):
			var a := poly[tri[t]]
			var b := poly[tri[t + 1]]
			var c := poly[tri[t + 2]]
			_tri(vs, ns, us, [Vector3(x, a.y, a.x), nn, a], [Vector3(x, b.y, b.x), nn, b], [Vector3(x, c.y, c.x), nn, c])
	for i in n:
		var a2 := poly[i]
		var b2 := poly[(i + 1) % n]
		var d := (b2 - a2).normalized()
		# внешняя нормаль ребра в плоскости (z, y)
		var o := Vector2(d.y, -d.x) if ccw else Vector2(-d.y, d.x)
		var en := Vector3(0, o.y, o.x)
		var l := a2.distance_to(b2)
		_tri(vs, ns, us, [Vector3(x0, a2.y, a2.x), en, Vector2(0, 0)], [Vector3(x1, a2.y, a2.x), en, Vector2(x1 - x0, 0)], [Vector3(x1, b2.y, b2.x), en, Vector2(x1 - x0, l)])
		_tri(vs, ns, us, [Vector3(x0, a2.y, a2.x), en, Vector2(0, 0)], [Vector3(x1, b2.y, b2.x), en, Vector2(x1 - x0, l)], [Vector3(x0, b2.y, b2.x), en, Vector2(0, l)])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	arr[Mesh.ARRAY_TEX_UV] = us
	var m := ArrayMesh.new()
	if vs.size() > 0:
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static var _tile_mats := {}


## Материалы обломков плиты потолка: [лицо, изнанка, торец]. Лицо — настоящая текстура плиты (по UV — одна
## плитка 0,6 м без рамки сетки) с рельефом, изнанка — серо-бурый картон, торец — рыхлая минвата.
## dusty — пыльнее и темнее (обломки, пролежавшие под провалом)
static func tile_mats(dusty := false) -> Array:
	var key := "d" if dusty else "c"
	if not _tile_mats.has(key):
		var k := 0.8 if dusty else 0.93
		var face := Mats.prop("tile_face_" + key, {"tex": "ceiling_tile", "tex_mix": 1.0, "color": Vector3(k, k * 0.985, k * 0.94),
			"nmap": Mats.tex("ceiling_tile_n"), "bump": 1.0, "albedo_cap": 0.5 if dusty else 0.58, "gloss": 12.0, "spec": 0.03, "wash": 0.25 if dusty else 0.0})
		var back := mc(Color(0.64, 0.6, 0.52), "fiber", 0.45, {"nmap": Mats.tex("fiber_n"), "bump": 0.6, "albedo_cap": 0.5})
		var edge := mc(Color(0.66, 0.62, 0.54), "fiber", 1.0, {"nmap": Mats.tex("fiber_n"), "bump": 1.4, "albedo_cap": 0.48})
		_tile_mats[key] = [face, back, edge]
	return _tile_mats[key]


## Кусок плиты потолка по контуру poly (x, z в метрах плиты: плита — квадрат ±0,3) толщиной th:
## три поверхности — лицо (верх, UV в текстуре плиты), изнанка (низ), рваный торец
static func tile_slab(poly: PackedVector2Array, th: float) -> ArrayMesh:
	var n := poly.size()
	var area := 0.0
	for i in n:
		area += poly[i].x * poly[(i + 1) % n].y - poly[(i + 1) % n].x * poly[i].y
	var tri := Geometry2D.triangulate_polygon(poly)
	var m := ArrayMesh.new()
	for surf in 3:
		var vs := PackedVector3Array()
		var ns := PackedVector3Array()
		var us := PackedVector2Array()
		if surf < 2:
			var y := th * 0.5 if surf == 0 else -th * 0.5
			var nn := Vector3(0, 1 if surf == 0 else -1, 0)
			for t in range(0, tri.size(), 3):
				var q := []
				for e in 3:
					var a := poly[tri[t + e]]
					# лицо: одна плитка текстуры (u, v 0,02…0,5 — между линиями сетки)
					var uv := Vector2(0.02 + (a.x + 0.3) / 0.6 * 0.48, 0.02 + (a.y + 0.3) / 0.6 * 0.48)
					q.append([Vector3(a.x, y, a.y), nn, uv])
				_tri(vs, ns, us, q[0], q[1], q[2])
		else:
			var s := 0.0
			for i in n:
				var a2 := poly[i]
				var b2 := poly[(i + 1) % n]
				var d := (b2 - a2).normalized()
				var o := Vector2(d.y, -d.x) if area > 0.0 else Vector2(-d.y, d.x)
				var en := Vector3(o.x, 0, o.y)
				var l := a2.distance_to(b2)
				var p0 := [Vector3(a2.x, th * 0.5, a2.y), en, Vector2(s, 0)]
				var p1 := [Vector3(b2.x, th * 0.5, b2.y), en, Vector2(s + l, 0)]
				var p2 := [Vector3(b2.x, -th * 0.5, b2.y), en, Vector2(s + l, th)]
				var p3 := [Vector3(a2.x, -th * 0.5, a2.y), en, Vector2(s, th)]
				_tri(vs, ns, us, p0, p1, p2)
				_tri(vs, ns, us, p0, p2, p3)
				s += l
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = vs
		arr[Mesh.ARRAY_NORMAL] = ns
		arr[Mesh.ARRAY_TEX_UV] = us
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Узел-кусок плиты с тремя материалами (лицо/изнанка/торец)
static func tile_node(p: Node3D, poly: PackedVector2Array, th: float, mats: Array, pos: Vector3, rot: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = tile_slab(poly, th)
	for i in 3:
		mi.set_surface_override_material(i, mats[i])
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi)
	return mi


## Плита 0,6×0,6, расколотая по рваной трещине на два куска: [кусок по одну сторону, по другую].
## Углы иногда отбиты
static func tile_halves(rng: RandomNumberGenerator) -> Array:
	var z0 := rng.randf_range(-0.18, 0.18)
	var z1 := rng.randf_range(-0.18, 0.18)
	var crack := PackedVector2Array()
	for i in 7:
		var t := float(i) / 6.0
		var jz := 0.0 if i == 0 or i == 6 else rng.randf_range(-0.04, 0.04)
		crack.append(Vector2(lerpf(-0.3, 0.3, t), lerpf(z0, z1, t) + jz))
	var a := PackedVector2Array(crack)
	a.append(Vector2(0.3, -0.3))
	a.append(Vector2(-0.3, -0.3))
	var b := PackedVector2Array()
	for i2 in range(crack.size() - 1, -1, -1):
		b.append(crack[i2])
	b.append(Vector2(-0.3, 0.3))
	b.append(Vector2(0.3, 0.3))
	# отбитый угол
	if rng.randf() < 0.5:
		var c := b[b.size() - 1]
		b[b.size() - 1] = c + Vector2(-rng.randf_range(0.04, 0.1), 0)
		b.append(c + Vector2(0, -rng.randf_range(0.04, 0.1)))
	return [a, b]


## Рваный контур обломка: n точек вокруг центра, радиус r с разбросом jag, вытянут по x на ax
static func shard_poly(rng: RandomNumberGenerator, r: float, jag := 0.35, n := 7, ax := 1.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	var a0 := rng.randf() * TAU
	for i in n:
		var a := a0 + TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / n
		var rr := r * rng.randf_range(1.0 - jag, 1.0 + jag * 0.4)
		out.append(Vector2(cos(a) * rr * ax, sin(a) * rr))
	return out


## Готовая модель (Poly Haven). sc — масштаб (число или Vector3). Возвращает null, если модели нет.
static func model(p: Node3D, id: String, pos := Vector3.ZERO, rot := 0.0, sc: Variant = 1.0, collide := true) -> Node3D:
	var m := Models.make(id, not park_mode)
	if m == null:
		return null
	var s3: Vector3 = sc if typeof(sc) == TYPE_VECTOR3 else Vector3.ONE * float(sc)
	p.add_child(m)
	m.position = pos
	m.rotation.y = rot
	m.scale = s3
	if collide:
		var bb := Models.aabb(id)
		var c := (bb.position + bb.size * 0.5) * s3
		collider(p, bb.size * s3, pos + Basis(Vector3.UP, rot) * c, 1, Vector3(0, rot, 0))
	return m


static func collider(p: Node3D, size: Vector3, pos: Vector3, layer := 1, rot := Vector3.ZERO) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = layer
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	b.position = pos
	b.rotation = rot
	p.add_child(b)
	return b


static func interactable(p: Node3D, size: Vector3, pos: Vector3, hint: String, cb: Callable) -> StaticBody3D:
	var b := collider(p, size, pos, 2)
	b.set_meta("interact", cb)
	b.set_meta("hint", hint)
	return b


static func trigger(p: Node3D, size: Vector3, pos: Vector3, cb: Callable) -> Area3D:
	var a := Area3D.new()
	a.collision_layer = 0
	a.collision_mask = 1
	a.monitoring = true
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	a.add_child(cs)
	a.position = pos
	p.add_child(a)
	a.body_entered.connect(func(body: Node3D) -> void:
		if body is Player:
			cb.call())
	return a


static func set_light(n: Node, c: Color) -> void:
	if n is GeometryInstance3D and not (n is Label3D):
		(n as GeometryInstance3D).set_instance_shader_parameter("light_level", Vector4(c.r * 2.0, c.g * 2.0, c.b * 2.0, c.a))
	elif n is Label3D:
		var lb := n as Label3D
		var lum := clampf((c.r + c.g + c.b * 0.5) * 2.0 + 0.04, 0.03, 1.2)
		var base: Color = lb.get_meta("ink", lb.modulate)
		lb.modulate = Color(base.r * lum, base.g * lum, base.b * lum, base.a)
	for ch in n.get_children():
		set_light(ch, c)


static var _lifted := {}


## Светлее альбедо модели в k раз (материалы prop-шейдера; копии материалов общие для одинаковых k).
## Металл (ARM.b) ослаблен: без отражений окружения металлические детали в шейдере уходят в чёрное
static func lift(n: Node, k: float) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var sm := mi.get_surface_override_material(i) as ShaderMaterial
				if sm == null or sm.shader == GLASS_SHADER:
					continue
				var key := "%d_%.2f" % [sm.get_instance_id(), k]
				if not _lifted.has(key):
					var m2 := sm.duplicate() as ShaderMaterial
					var c: Variant = m2.get_shader_parameter("color")
					if c is Color:
						var cc := c as Color
						m2.set_shader_parameter("color", Color(cc.r * k, cc.g * k, cc.b * k, cc.a))
					elif c is Vector3:
						m2.set_shader_parameter("color", (c as Vector3) * k)
					var mk: Variant = m2.get_shader_parameter("metal_k")
					if mk != null:
						m2.set_shader_parameter("metal_k", minf(float(mk), 0.3))
					_lifted[key] = m2
				mi.set_surface_override_material(i, _lifted[key])
	for ch in n.get_children():
		lift(ch, k)


## Все материалы предмета → обои/ковёр («Комплекс перепутал материал»)
static func swap_mats(n: Node, m: Material) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_override = m
	for ch in n.get_children():
		swap_mats(ch, m)


# ------------------------------------------------------------ точка входа

static func spawn_all(cx: Node3D, parent: Node3D, decos: Array, layer: int) -> void:
	for d in decos:
		var dd: Dictionary = d
		var n := spawn(cx, dd, layer)
		if n == null:
			continue
		parent.add_child(n)
		n.set_meta("k", dd.get("k", ""))
		n.position = dd.p
		if not n.has_meta("keep_rot"):
			n.rotation.y = float(dd.get("r", 0.0))
		if n.has_meta("tilt"):
			n.rotation.x = float(n.get_meta("tilt"))
		var lc: Color = dd.get("light", Color(0.4, 0, 0, 0))
		set_light(n, lc)
		if n.has_method("on_spawned"):
			n.on_spawned(cx)


static func spawn(cx: Node3D, d: Dictionary, layer: int) -> Node3D:
	var k := String(d.get("k", ""))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(d.get("seed", hash(d.p)))
	if not d.has("ceil"):
		d["ceil"] = float(cx.ceil_at(d.p)) if cx != null and cx.has_method("ceil_at") else 2.7
	match k:
		"obj": return obj(String(d.get("what", "chair")), String(d.get("wrong", "none")), rng, d)
		"copy": return copy_person(cx, d, rng, layer)
		"copy_self": return copy_self(cx, d)
		"graf": return graffiti(d)
		"tag": return cable_tag(d)
		"sign": return sign_board(d)
		"note": return note(cx, d)
		"stain": return stain(d, rng)
		"mold": return mold_patch(d, rng)
		"papers": return papers(rng)
		"grass": return grass_patch(d, rng)
		"async": return async_item(cx, String(d.get("what", "case")), d, rng)
		"threshold": return threshold(cx, d)
		"null": return null_zone(cx, d)
		"nest": return nest(rng)
		"house": return house_item(String(d.get("what", "sofa")), rng)
		"sound": return sound_emitter(d)
		"voice_wall": return voice_wall(cx)
		"red_city": return red_city(d, rng)
		"side_room": return side_room(d, rng)
	if _pr == null:
		_pr = load("res://src/world/props_rooms.gd")
	return _pr.spawn(cx, d, rng, layer)


## Боковая комната: ковёр на западной стене, мебель «стоит» на ней, на восточной стене — светильник
static func side_room(d: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var w := float(d.get("w", 9.6))
	var h := float(d.get("h", 9.6))
	var cm := Mats.prop("carpet_side", {"tex": "carpet", "tex_mix": 1.0, "uv_scale": Vector2(w / 1.2, 2.6 / 1.2)})
	var wx := -w * 0.5 + 0.12
	quad(n, Vector2(h - 0.25, 2.66), Vector3(wx, 1.33, 0), cm, Vector3(0, PI * 0.5, 0))
	# пол покрыт обоями — будто комнату повернули
	quad(n, Vector2(w - 0.3, h - 0.3), Vector3(0, 0.012, 0), Mats.prop("wall_floor", {"tex": "wall_yellow", "tex_mix": 1.0, "uv_scale": Vector2(w / 1.2, h / 1.2)}), Vector3(-PI * 0.5, 0, 0))
	# мебель на стене (повернута на 90°)
	var things := [["desk", Vector3(0, 1.2, -1.0)], ["ochair", Vector3(0, 0.7, 0.6)], ["cabinet", Vector3(0, 2.0, 1.6)], ["chair", Vector3(0, 1.6, -2.4)]]
	for t in things:
		var a: Array = t
		var hold := Node3D.new()
		n.add_child(hold)
		hold.position = Vector3(wx, 0, 0) + a[1]
		hold.rotation = Vector3(0, rng.randf_range(-0.3, 0.3), -PI * 0.5)
		match String(a[0]):
			"desk": _desk(hold)
			"ochair": _ochair(hold)
			"cabinet": _cabinet(hold)
			_: _chair(hold)
	# светильник на восточной стене
	var lamp := quad(n, Vector2(0.6, 1.2), Vector3(w * 0.5 - 0.13, 1.4, 0), Mats.prop("fixture_side", {"tex": "fixture", "tex_mix": 1.0, "emit": 2.2, "emit_color": Vector3(1, 0.97, 0.88), "powered": 1.0}), Vector3(0, -PI * 0.5, 0))
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


# ------------------------------------------------------------ парк и мебель

static func obj(what: String, wrong: String, rng: RandomNumberGenerator, d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var inner := Node3D.new()
	n.add_child(inner)
	match what:
		"bench": _bench(inner)
		"lamp": _lamp(inner)
		"bin": _bin(inner)
		"tree": _tree(inner, rng)
		"fountain": _fountain(inner)
		"slide": _slide(inner)
		"swing": _swing(inner, wrong == "ceiling")
		"cart": _cart(inner, String(d.get("parasol", "open")))
		"car":
			if model(inner, "covered_car") == null:
				_car(inner)
			# машина стоит: плотная тень под всем днищем, мягко выходит за край (круглое пятно у краёв прозрачно)
			if not park_mode:
				blob_box(n, Vector2(1.8, 4.4), Vector3.ZERO, 0.8, 0.35)
		"stroller": _stroller(inner)
		"balloon": _balloon_ceiling(inner)
		"blanket": _blanket(inner)
		"phone": _phone(inner)
		"chair": _chair(inner)
		"desk": _desk(inner)
		"cabinet": _cabinet(inner)
		"cooler": _cooler(inner)
		"ochair": _ochair(inner)
		"boxes": _boxes(inner, rng)
		"tv": _tv(inner)
		"shelf": _shelf(inner, rng)
		"sign_park": _sign_park(inner)
		"hill_chair": _hill_chair(inner)
		"debris": _debris(inner, rng)
		"wetsign": model(inner, "WetFloorSign_01", Vector3.ZERO, 0.0, 1.15, false)
		"wheelchair": model(inner, "wheelchair_01")
		"hydrant": model(inner, "fire_hydrant")
		"trashbag": model(inner, "trashbag", Vector3.ZERO, 0.0, 1.0, false)
		"tyre": model(inner, "old_tyre", Vector3(0, 0.3, 0), 0.0, 1.0, false)
		"utilitybox": model(inner, "utility_box_01")
		"crate": model(inner, "plastic_crate_01", Vector3.ZERO, 0.0, 1.0, false)
		"covered_car": model(inner, "covered_car")
		_: _chair(inner)
	match wrong:
		"stretch":
			var ax := rng.randi_range(0, 2)
			inner.scale = [Vector3(rng.randf_range(2.2, 3.5), 1, 1), Vector3(1, rng.randf_range(1.8, 2.6), 1), Vector3(1, 1, rng.randf_range(2.5, 4.0))][ax]
		"ceiling":
			if what != "swing" and what != "balloon":
				inner.rotation.x = PI
				inner.position.y = float(d.get("ceil", 2.7)) + (0.15 if what == "lamp" else 0.0)
				if what == "lamp":
					inner.position.y = 4.2
		"stack":
			for k2 in 2:
				var dup := inner.duplicate()
				n.add_child(dup)
				dup.position = Vector3(rng.randf_range(-0.15, 0.15), 0.55 * (k2 + 1), rng.randf_range(-0.15, 0.15))
				dup.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))
		"sink":
			inner.position.y -= rng.randf_range(0.3, 0.6)
			inner.rotation = Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
		"wallpaper":
			swap_mats(inner, m_wall())
		"row":
			for k3 in 3:
				var dup2 := inner.duplicate()
				n.add_child(dup2)
				dup2.position = Vector3(0, 0, -(k3 + 1) * 0.35)
		"tilt":
			inner.rotation = Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(0.4, 0.9) * (1 if rng.randf() < 0.5 else -1))
		"wall":
			pass
	# тень-«контакт» под тем, что стоит на полу (под потолком и в воздухе — нет)
	if not park_mode and what not in ["balloon", "hill_chair", "debris", "blanket", "car"]:
		blob_under(n, 0.4 if what in ["chair", "ochair", "swing", "lamp", "stroller"] else 0.55)
	return n


static func _bench(p: Node3D) -> void:
	var bm := model(p, "modular_street_seating", Vector3.ZERO, 0.0, Vector3(0.8, 1.0, 1.0))
	if bm != null:
		# в Комплексе тёмный крашеный металл и морёное дерево модели под лампами уходят в чёрное
		if not park_mode:
			lift(bm, 1.9)
		return
	var w := m_wood()
	var ir := m_iron()
	for k in 3:
		box(p, Vector3(1.8, 0.035, 0.1), Vector3(0, 0.45, -0.12 + k * 0.12), w)
	for k in 2:
		box(p, Vector3(1.8, 0.1, 0.035), Vector3(0, 0.62 + k * 0.14, -0.22), w, Vector3(-0.15, 0, 0))
	for s in [-0.75, 0.75]:
		box(p, Vector3(0.05, 0.45, 0.06), Vector3(s, 0.22, 0.12), ir)
		box(p, Vector3(0.05, 0.85, 0.06), Vector3(s, 0.42, -0.2), ir, Vector3(-0.15, 0, 0))
		box(p, Vector3(0.05, 0.05, 0.45), Vector3(s, 0.43, -0.02), ir)
	collider(p, Vector3(1.8, 0.5, 0.5), Vector3(0, 0.25, 0))


static func _lamp(p: Node3D) -> void:
	var g := m_green()
	cyl(p, 0.06, 0.09, 3.3, Vector3(0, 1.65, 0), g)
	cyl(p, 0.13, 0.13, 0.12, Vector3(0, 0.06, 0), g)
	box(p, Vector3(0.26, 0.04, 0.26), Vector3(0, 3.32, 0), g)
	box(p, Vector3(0.2, 0.32, 0.2), Vector3(0, 3.5, 0), m_emit(Color(1.0, 0.85, 0.55), 1.6))
	cyl(p, 0.02, 0.17, 0.14, Vector3(0, 3.72, 0), g, Vector3.ZERO, 4)
	collider(p, Vector3(0.2, 3.3, 0.2), Vector3(0, 1.65, 0))


static func _bin(p: Node3D) -> void:
	var bn := model(p, "metal_trash_can", Vector3.ZERO, 0.0, 1.0)
	if bn != null:
		if not park_mode:
			lift(bn, 1.8)
		return
	var g := m_green()
	cyl(p, 0.27, 0.24, 0.85, Vector3(0, 0.43, 0), g, Vector3.ZERO, 14)
	cyl(p, 0.28, 0.28, 0.04, Vector3(0, 0.86, 0), m_iron(), Vector3.ZERO, 14)
	box(p, Vector3(0.3, 0.12, 0.2), Vector3(0, 0.86, 0), mc(Color(0.8, 0.8, 0.75), "paper", 0.8), Vector3(0.3, 0.4, 0.1))
	collider(p, Vector3(0.5, 0.85, 0.5), Vector3(0, 0.42, 0))


static func _tree(p: Node3D, rng: RandomNumberGenerator) -> void:
	var b := m_bark()
	var lean := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
	cyl(p, 0.24, 0.34, 3.2, Vector3(lean.x * 0.5, 1.6, lean.z * 0.5), b, Vector3(lean.z * 0.15, 0, -lean.x * 0.15), 10)
	cyl(p, 0.36, 0.52, 0.3, Vector3(0, 0.15, 0), b, Vector3.ZERO, 10)
	var top := Vector3(lean.x, 3.1, lean.z)
	for k in 5:
		var a2 := k * TAU / 5 + rng.randf_range(-0.4, 0.4)
		var s0 := Vector3(lean.x * 0.7, 2.3 + k * 0.15, lean.z * 0.7)
		var e := Vector3(cos(a2) * rng.randf_range(1.0, 1.7), rng.randf_range(3.6, 4.4), sin(a2) * rng.randf_range(1.0, 1.7))
		rod(p, s0, e, 0.09 - k * 0.008, b)
	rod(p, top, Vector3(lean.x, 4.6, lean.z), 0.12, b)
	var lv := m_leaves()
	for k in 13:
		var a3 := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 2.1
		var y := 4.3 + rng.randf_range(-0.7, 0.9) - r * 0.25
		sph(p, rng.randf_range(0.95, 1.45), Vector3(cos(a3) * r + lean.x, y, sin(a3) * r + lean.z), lv, Vector3(1.0, 0.78, 1.0), 10)
	collider(p, Vector3(0.6, 3.0, 0.6), Vector3(0, 1.5, 0))


static var _fountain_mesh := {}


## Фонтан 60-х: литая бетонная чаша-кольцо (наружная стенка, скруглённый бортик с капельником, внутренняя
## стенка, дно), в центре — пьедестал с тягами и верхняя чаша-«таццa» с отбортовкой. Всё — тела вращения,
## без стыков. Сетки чаш — прямые потомки p (парк кладёт на них свой бетон), вода — с meta "water"
static func _fountain(p: Node3D) -> void:
	var c := m_conc()
	if _fountain_mesh.is_empty():
		_fountain_mesh["basin"] = lathe(PackedVector2Array([Vector2(1.8, 0.0), Vector2(1.8, 0.35), Vector2(1.835, 0.375),
			Vector2(1.845, 0.4), Vector2(1.845, 0.435), Vector2(1.83, 0.46), Vector2(1.8, 0.474), Vector2(1.76, 0.48),
			Vector2(1.62, 0.48), Vector2(1.585, 0.47), Vector2(1.565, 0.445), Vector2(1.56, 0.42), Vector2(1.56, 0.06),
			Vector2(1.5, 0.04), Vector2(0.0, 0.04)]), 64, 32.0)
		_fountain_mesh["stem"] = lathe(PackedVector2Array([Vector2(0.44, 0.0), Vector2(0.44, 0.14), Vector2(0.42, 0.16),
			Vector2(0.36, 0.18), Vector2(0.33, 0.2), Vector2(0.33, 0.25), Vector2(0.27, 0.28), Vector2(0.21, 0.33),
			Vector2(0.19, 0.38), Vector2(0.175, 0.7), Vector2(0.18, 0.74), Vector2(0.215, 0.77), Vector2(0.225, 0.8),
			Vector2(0.215, 0.83), Vector2(0.18, 0.86), Vector2(0.15, 0.9), Vector2(0.13, 0.98), Vector2(0.125, 1.04)]), 32, 32.0)
		_fountain_mesh["bowl"] = lathe(PackedVector2Array([Vector2(0.125, 1.04), Vector2(0.2, 1.075), Vector2(0.32, 1.11),
			Vector2(0.44, 1.15), Vector2(0.55, 1.19), Vector2(0.615, 1.22), Vector2(0.645, 1.245), Vector2(0.655, 1.27),
			Vector2(0.648, 1.29), Vector2(0.63, 1.3), Vector2(0.6, 1.3), Vector2(0.582, 1.285), Vector2(0.55, 1.262),
			Vector2(0.45, 1.235), Vector2(0.3, 1.21), Vector2(0.12, 1.195), Vector2(0.0, 1.193)]), 48, 32.0)
		_fountain_mesh["spout"] = lathe(PackedVector2Array([Vector2(0.06, 1.19), Vector2(0.06, 1.26), Vector2(0.045, 1.29),
			Vector2(0.03, 1.31), Vector2(0.022, 1.33), Vector2(0.0, 1.335)]), 16, 40.0)
	for k in ["basin", "stem", "bowl", "spout"]:
		mesh_node(p, _fountain_mesh[k], c)
	cyl(p, 1.575, 1.575, 0.36, Vector3(0, 0.18, 0), m_carpet(), Vector3.ZERO, 48).set_meta("water", true)
	cyl(p, 0.56, 0.56, 0.05, Vector3(0, 1.265, 0), m_carpet(), Vector3.ZERO, 32).set_meta("water", true)
	collider(p, Vector3(3.6, 0.5, 3.6), Vector3(0, 0.25, 0))
	collider(p, Vector3(0.5, 1.3, 0.5), Vector3(0, 0.65, 0))
	if park_mode:
		_fountain_water(p)


const FALL_SHADER := preload("res://src/shaders/fx_water_fall.gdshader")
const RIPPLE_SHADER := preload("res://src/shaders/fx_ripple.gdshader")


## Живая вода фонтана (только в парке): струйка-«колокол» над верхней чашей, завеса, стекающая с её края
## в нижнюю, и круги там, где вода падает. Материалы — на сетках (не material_override): парк переводит
## в PBR только override, эти шейдеры уже освещаемые
static func _fountain_water(p: Node3D) -> void:
	var fx := FountainFX.new()
	p.add_child(fx)
	var nz := Mats.tex("noise")
	var mk := func(sp: float, op: float, sc: Vector2) -> ShaderMaterial:
		var m := ShaderMaterial.new()
		m.shader = FALL_SHADER
		m.set_shader_parameter("noise_tex", nz)
		m.set_shader_parameter("speed", sp)
		m.set_shader_parameter("opacity", op)
		m.set_shader_parameter("scale", sc)
		return m
	# струя вверх из центра верхней чаши
	var jet := CylinderMesh.new()
	jet.top_radius = 0.012
	jet.bottom_radius = 0.028
	jet.height = 0.5
	jet.radial_segments = 10
	jet.rings = 4
	jet.cap_top = false
	jet.cap_bottom = false
	jet.material = mk.call(-2.2, 0.5, Vector2(3.0, 1.4))
	fx.add_mesh(jet, Vector3(0, 1.58, 0))
	# «колокол»: вода с верха струи расходится и падает в чашу
	var bell := CylinderMesh.new()
	bell.top_radius = 0.015
	bell.bottom_radius = 0.3
	bell.height = 0.4
	bell.radial_segments = 24
	bell.rings = 6
	bell.cap_top = false
	bell.cap_bottom = false
	bell.material = mk.call(1.6, 0.12, Vector2(12.0, 1.2))
	fx.add_mesh(bell, Vector3(0, 1.45, 0))
	# перелив с отбортовки верхней чаши в нижнюю: у края — тонкая плёнка, ниже рвётся на струи
	var cur := CylinderMesh.new()
	cur.top_radius = 0.66
	cur.bottom_radius = 0.8
	cur.height = 0.95
	cur.radial_segments = 48
	cur.rings = 8
	cur.cap_top = false
	cur.cap_bottom = false
	var cm2: ShaderMaterial = mk.call(1.3, 0.55, Vector2(26.0, 1.3))
	cm2.set_shader_parameter("sheet", 1.0)
	cur.material = cm2
	fx.add_mesh(cur, Vector3(0, 0.775, 0))
	# круги на воде: нижняя чаша (кольцо падения завесы) и верхняя (под колоколом)
	for spec in [[3.1, 0.326, 0.8 / 1.55], [1.1, 1.252, 0.42 / 0.55]]:
		var a: Array = spec
		var q := QuadMesh.new()
		q.size = Vector2(float(a[0]), float(a[0]))
		q.orientation = PlaneMesh.FACE_Y
		var rm := ShaderMaterial.new()
		rm.shader = RIPPLE_SHADER
		rm.set_shader_parameter("noise_tex", nz)
		rm.set_shader_parameter("ring_r", float(a[2]))
		q.material = rm
		fx.add_mesh(q, Vector3(0, float(a[1]), 0))


## Детская горка: лестница сзади (−z) до площадки на 1,8 м, скат вперёд (+z) вниз, внизу — короткий
## пологий выкат. Скат — дочерний узел с наклоном: высокий конец у площадки, низкий — у земли
static func _slide(p: Node3D) -> void:
	var red := mc(Color(0.75, 0.15, 0.12), "metal", 0.2, {"gloss": 60.0, "spec": 0.2})
	var mt := m_metal()
	var deck_y := 1.8
	var lz := -1.15
	for s2 in [-0.3, 0.3]:
		box(p, Vector3(0.05, deck_y + 0.75, 0.05), Vector3(s2, (deck_y + 0.75) * 0.5, lz), mt)
		box(p, Vector3(0.05, deck_y, 0.05), Vector3(s2, deck_y * 0.5, lz + 0.42), mt)
		# поручни над площадкой
		box(p, Vector3(0.04, 0.04, 0.46), Vector3(s2, deck_y + 0.72, lz + 0.21), mt)
		box(p, Vector3(0.04, 0.7, 0.04), Vector3(s2, deck_y + 0.36, lz + 0.42), mt)
	for k in 6:
		box(p, Vector3(0.6, 0.035, 0.06), Vector3(0, 0.3 + k * 0.3, lz), mt)
	box(p, Vector3(0.66, 0.04, 0.46), Vector3(0, deck_y, lz + 0.21), mt)
	# скат: от края площадки (z = lz + 0.44, y = 1.8) вниз до (z = 1.45, y = 0.38)
	var z0 := lz + 0.44
	var z1 := 1.45
	var y1 := 0.38
	var ln := Vector2(z1 - z0, deck_y - y1).length()
	var ang := atan2(deck_y - y1, z1 - z0)
	var bed := Node3D.new()
	p.add_child(bed)
	bed.position = Vector3(0, (deck_y + y1) * 0.5, (z0 + z1) * 0.5)
	bed.rotation.x = ang
	box(bed, Vector3(0.62, 0.035, ln), Vector3(0, 0, 0), red)
	for s3 in [-0.33, 0.33]:
		box(bed, Vector3(0.04, 0.2, ln), Vector3(s3, 0.08, 0), red)
	# выкат и опоры
	box(p, Vector3(0.62, 0.035, 0.5), Vector3(0, y1 - 0.01, z1 + 0.22), red)
	for s4 in [-0.33, 0.33]:
		box(p, Vector3(0.04, 0.2, 0.5), Vector3(s4, y1 + 0.07, z1 + 0.22), red)
		box(p, Vector3(0.05, y1, 0.05), Vector3(s4, y1 * 0.5, z1 + 0.4), mt)
		box(p, Vector3(0.05, 1.0, 0.05), Vector3(s4, 0.5, (z0 + z1) * 0.5 - 0.3), mt)
	collider(p, Vector3(0.8, 1.6, 2.4), Vector3(0, 0.8, 0.2))


static func _swing(p: Node3D, ceiling: bool) -> void:
	var mt := m_metal()
	var top := 2.69 if ceiling else 2.2
	if not ceiling:
		for s in [-1.2, 1.2]:
			rod(p, Vector3(s, 0, -0.7), Vector3(s, top, 0), 0.04, mt)
			rod(p, Vector3(s, 0, 0.7), Vector3(s, top, 0), 0.04, mt)
		rod(p, Vector3(-1.25, top, 0), Vector3(1.25, top, 0), 0.05, mt)
	for s2 in [-0.55, 0.55]:
		var seat_y := 0.5 if not ceiling else 1.2
		for e in [-0.2, 0.2]:
			rod(p, Vector3(s2 + e, top, 0), Vector3(s2 + e, seat_y, 0), 0.008, mt, 4)
		box(p, Vector3(0.45, 0.04, 0.18), Vector3(s2, seat_y, 0), mc(Color(0.12, 0.12, 0.12), "metal", 0.2))


static var _cart_mesh := {}


## Тележка мороженщика: короб-холодильник из белой эмали со скруглёнными рёбрами (лофт), синий пояс,
## по бортам — выцветшая облупленная наклейка «ICE CREAM», хромированная столешница и две крышки с ручками,
## на дальнем конце — пара спицованных колёс на оси, у ручки — две ножки с резиновыми пятками.
## parasol: "open" — раскрытый зонт (парк), "closed" — сложенный и перехваченный ремешком (под низким потолком)
static func _cart(p: Node3D, parasol := "open") -> void:
	var wht := mc(cap(Color(0.9, 0.89, 0.84)), "metal", 0.3, {"gloss": 60.0, "spec": 0.15, "wash": 0.18})
	var stripe := mc(Color(0.17, 0.33, 0.6), "metal", 0.2, {"gloss": 50.0, "spec": 0.12})
	var chrome := mc(Color(0.62, 0.62, 0.6), "metal", 0.3, {"gloss": 90.0, "spec": 0.45})
	var rubber := m_black()
	if _cart_mesh.is_empty():
		# лофт вдоль z (потом повёрнут вдоль x): [z, полуширина низа, верха, низ, верх, скругление]
		_cart_mesh["body"] = section_loft([[0.75, 0.355, 0.36, 0.39, 1.1, 0.03], [0.742, 0.372, 0.378, 0.37, 1.12, 0.05],
			[-0.742, 0.372, 0.378, 0.37, 1.12, 0.05], [-0.75, 0.355, 0.36, 0.39, 1.1, 0.03]])
		_cart_mesh["band"] = section_loft([[0.756, 0.375, 0.381, 0.9, 1.01, 0.012], [-0.756, 0.375, 0.381, 0.9, 1.01, 0.012]])
		_cart_mesh["kick"] = section_loft([[0.756, 0.375, 0.378, 0.37, 0.43, 0.012], [-0.756, 0.375, 0.378, 0.37, 0.43, 0.012]])
		_cart_mesh["top"] = section_loft([[0.775, 0.39, 0.39, 1.12, 1.15, 0.012], [-0.775, 0.39, 0.39, 1.12, 1.15, 0.012]])
		_cart_mesh["lid"] = section_loft([[0.33, 0.3, 0.29, 1.15, 1.18, 0.012], [-0.33, 0.3, 0.29, 1.15, 1.18, 0.012]])
		var tire := TorusMesh.new()
		tire.inner_radius = 0.19
		tire.outer_radius = 0.235
		tire.rings = 28
		tire.ring_segments = 8
		_cart_mesh["tire"] = tire
	for k in ["body", "band", "kick", "top"]:
		var mt: Material = {"body": wht, "band": stripe, "kick": chrome, "top": chrome}[k]
		mesh_node(p, _cart_mesh[k], mt, Vector3.ZERO, Vector3(0, PI * 0.5, 0))
	# крышки: петли к середине, ручки — с краю
	for sx in [-0.37, 0.37]:
		mesh_node(p, _cart_mesh["lid"], chrome, Vector3(sx, 0, 0), Vector3(0, PI * 0.5, 0))
		rod(p, Vector3(sx - 0.07, 1.2, 0.24), Vector3(sx + 0.07, 1.2, 0.24), 0.008, rubber, 6)
		for hx in [-0.08, 0.08]:
			box(p, Vector3(0.01, 0.022, 0.012), Vector3(sx + hx, 1.19, 0.24), rubber)
			box(p, Vector3(0.05, 0.008, 0.03), Vector3(sx + hx * 2.0, 1.183, -0.25), chrome)
	# наклейки по бортам
	if Mats.has_tex("prop_cart_side"):
		var dm := Mats.prop("cart_side", {"tex": "prop_cart_side", "tex_mix": 1.0, "alpha_cut": 0.5, "albedo_cap": 0.6, "gloss": 50.0, "spec": 0.1})
		quad(p, Vector2(1.28, 0.4), Vector3(0, 0.66, 0.3815), dm)
		quad(p, Vector2(1.28, 0.4), Vector3(0, 0.66, -0.3815), dm, Vector3(0, PI, 0))
		# на торцах — та же наклейка поменьше
		quad(p, Vector2(0.6, 0.19), Vector3(0.7515, 0.68, 0), dm, Vector3(0, PI * 0.5, 0))
		quad(p, Vector2(0.6, 0.19), Vector3(-0.7515, 0.68, 0), dm, Vector3(0, -PI * 0.5, 0))
	# ось и два колеса на дальнем конце: шина, обод, спицы, ступица
	var wx := 0.5
	var wr := 0.235
	rod(p, Vector3(wx, wr, -0.47), Vector3(wx, wr, 0.47), 0.012, chrome, 6)
	for sz in [-0.45, 0.45]:
		var wh := Node3D.new()
		p.add_child(wh)
		wh.position = Vector3(wx, wr, sz)
		wh.rotation = Vector3(PI * 0.5, 0, 0)
		mesh_node(wh, _cart_mesh["tire"], rubber)
		cyl(wh, 0.19, 0.19, 0.025, Vector3.ZERO, chrome, Vector3.ZERO, 24)
		cyl(wh, 0.17, 0.17, 0.03, Vector3.ZERO, rubber, Vector3.ZERO, 24)
		for k in 10:
			var a := TAU * k / 10.0
			rod(wh, Vector3.ZERO, Vector3(cos(a) * 0.175, 0, sin(a) * 0.175), 0.004, chrome, 4)
		cyl(wh, 0.035, 0.035, 0.07, Vector3.ZERO, chrome, Vector3.ZERO, 12)
	# ножки с резиновыми пятками у ручки
	for sz2 in [-0.3, 0.3]:
		rod(p, Vector3(-0.6, 0.38, sz2), Vector3(-0.62, 0.02, sz2 * 1.08), 0.014, chrome, 6)
		cyl(p, 0.025, 0.03, 0.03, Vector3(-0.62, 0.015, sz2 * 1.08), rubber, Vector3.ZERO, 10)
	# ручка-толкатель: две трубки и перекладина с резиновой рукоятью
	for sz3 in [-0.3, 0.3]:
		rod(p, Vector3(-0.75, 0.98, sz3), Vector3(-1.02, 1.06, sz3), 0.013, chrome, 8)
		cyl(p, 0.02, 0.02, 0.03, Vector3(-0.755, 0.98, sz3), chrome, Vector3(0, 0, PI * 0.5), 8)
	rod(p, Vector3(-1.02, 1.06, -0.33), Vector3(-1.02, 1.06, 0.33), 0.012, chrome, 8)
	rod(p, Vector3(-1.02, 1.06, -0.24), Vector3(-1.02, 1.06, 0.24), 0.02, rubber, 8)
	# стойка зонта в гнезде на борту
	cyl(p, 0.03, 0.03, 0.12, Vector3(0.6, 1.17, -0.33), chrome, Vector3.ZERO, 10)
	if parasol == "closed":
		rod(p, Vector3(0.6, 1.12, -0.33), Vector3(0.6, 2.32, -0.33), 0.016, chrome, 8)
		_parasol_closed(p, Vector3(0.6, 2.3, -0.33), 0.9)
	else:
		rod(p, Vector3(0.6, 1.12, -0.33), Vector3(0.6, 2.9, -0.33), 0.016, chrome, 8)
		_parasol(p, Vector3(0.6, 2.95, -0.33), 1.15)
	collider(p, Vector3(1.5, 1.2, 0.8), Vector3(0, 0.6, 0))


## Сложенный зонт: восемь складок купола (красные/белые) собраны вокруг стойки веретеном, посередине —
## ремешок с кнопкой, сверху — навершие. top — верх купола, length — длина свёрнутой ткани вниз
static func _parasol_closed(p: Node3D, top: Vector3, length: float) -> void:
	var cols := [Color(0.72, 0.14, 0.12), Color(0.86, 0.84, 0.78)]
	var segs := 32
	var rows := 12
	var grid := []
	for i in rows + 1:
		var t := float(i) / rows
		var r := 0.014 + 0.062 * sin(clampf(t * 1.6, 0.0, 1.0) * PI * 0.5) * (1.0 - 0.6 * smoothstep(0.5, 1.0, t))
		# ремешок перетягивает складки
		r *= 1.0 - 0.3 * exp(-pow((t - 0.62) / 0.05, 2.0))
		var ring := []
		for k in segs + 1:
			var a := TAU * float(k) / segs
			var lobe := 1.0 + 0.25 * cos(a * 8.0) + 0.05 * sin(a * 3.0 + t * 5.0)
			ring.append(top + Vector3(cos(a + t * 0.35) * r * lobe, -length * t, sin(a + t * 0.35) * r * lobe))
		grid.append(ring)
	for c in 2:
		var vs := PackedVector3Array()
		var ns := PackedVector3Array()
		var us := PackedVector2Array()
		for i in rows:
			var r0: Array = grid[i]
			var r1: Array = grid[i + 1]
			for k in segs:
				var am := TAU * (float(k) + 0.5) / segs
				var lobe_i := int(round(am / (TAU / 8.0))) % 8
				if lobe_i % 2 != c:
					continue
				var q0: Vector3 = r0[k]
				var q1: Vector3 = r0[k + 1]
				var q2: Vector3 = r1[k + 1]
				var q3: Vector3 = r1[k]
				var n0 := Vector3(q0.x - top.x, 0.12, q0.z - top.z).normalized()
				var n1 := Vector3(q1.x - top.x, 0.12, q1.z - top.z).normalized()
				var n2 := Vector3(q2.x - top.x, 0.12, q2.z - top.z).normalized()
				var n3 := Vector3(q3.x - top.x, 0.12, q3.z - top.z).normalized()
				_tri(vs, ns, us, [q0, n0, Vector2.ZERO], [q1, n1, Vector2.ZERO], [q2, n2, Vector2.ZERO])
				_tri(vs, ns, us, [q0, n0, Vector2.ZERO], [q2, n2, Vector2.ZERO], [q3, n3, Vector2.ZERO])
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = vs
		arr[Mesh.ARRAY_NORMAL] = ns
		arr[Mesh.ARRAY_TEX_UV] = us
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh_node(p, m, mc(cols[c], "fabric", 0.3))
	var strap := TorusMesh.new()
	strap.inner_radius = 0.03
	strap.outer_radius = 0.042
	strap.rings = 16
	strap.ring_segments = 4
	mesh_node(p, strap, m_black(), top + Vector3(0, -length * 0.62, 0), Vector3.ZERO, Vector3(1.0, 1.6, 1.0))
	sph(p, 0.03, top + Vector3(0, 0.03, 0), m_metal(), Vector3(1, 1.4, 1), 8)
	# концы спиц торчат из-под ткани внизу
	for k2 in 8:
		var a2 := TAU * float(k2) / 8.0
		rod(p, top + Vector3(cos(a2) * 0.02, -length * 0.98, sin(a2) * 0.02), top + Vector3(cos(a2) * 0.028, -length * 1.04, sin(a2) * 0.028), 0.003, m_metal(), 3)


## Зонт: пологий купол из 16 клиньев, клинья чередуются (две сетки — два материала), каждый провисает между
## спицами; по краю — фестоны, снизу — спицы, сверху — навершие. Видна и изнанка
static func _parasol(p: Node3D, top: Vector3, r: float) -> void:
	var cols := [Color(0.82, 0.16, 0.13), Color(0.9, 0.88, 0.82)]
	var nseg := 16
	var up := Vector3(0, 1, 0)
	for c in 2:
		var vs := PackedVector3Array()
		var ns := PackedVector3Array()
		var us := PackedVector2Array()
		for k in nseg:
			if k % 2 != c:
				continue
			var a0 := TAU * float(k) / nseg
			var a1 := TAU * float(k + 1) / nseg
			var am := (a0 + a1) * 0.5
			var rings := 4
			for i in rings:
				var pa := []
				for tt in [float(i) / rings, float(i + 1) / rings]:
					var t: float = tt
					var drop := 0.36 * t + 0.08 * t * t
					var sag := 0.035 * sin(t * PI * 0.5)
					pa.append([Vector3(cos(a0) * r * t, -drop, sin(a0) * r * t), Vector3(cos(am) * r * t * 0.985, -drop - sag, sin(am) * r * t * 0.985),
						Vector3(cos(a1) * r * t, -drop, sin(a1) * r * t)])
				var ra: Array = pa[0]
				var rb: Array = pa[1]
				for j in 2:
					var q0: Vector3 = ra[j]
					var q1: Vector3 = ra[j + 1]
					var q2: Vector3 = rb[j + 1]
					var q3: Vector3 = rb[j]
					for sgn in [1.0, -1.0]:
						var nn: Vector3 = up * sgn
						_tri(vs, ns, us, [q0, nn, Vector2.ZERO], [q1, nn, Vector2.ZERO], [q2, nn, Vector2.ZERO])
						_tri(vs, ns, us, [q0, nn, Vector2.ZERO], [q2, nn, Vector2.ZERO], [q3, nn, Vector2.ZERO])
			# фестон: короткая юбка по краю клина с полукруглым низом
			var steps := 4
			for st in steps:
				var b0 := lerpf(a0, a1, float(st) / steps)
				var b1 := lerpf(a0, a1, float(st + 1) / steps)
				var hh0 := 0.07 + 0.03 * sin(float(st) / steps * PI)
				var hh1 := 0.07 + 0.03 * sin(float(st + 1) / steps * PI)
				var o0 := Vector3(cos(b0) * r, -0.44, sin(b0) * r)
				var o1 := Vector3(cos(b1) * r, -0.44, sin(b1) * r)
				var l0 := o0 - Vector3(0, hh0, 0)
				var l1 := o1 - Vector3(0, hh1, 0)
				for sgn2 in [1.0, -1.0]:
					var n0 := Vector3(cos(b0), 0, sin(b0)) * float(sgn2)
					var n1 := Vector3(cos(b1), 0, sin(b1)) * float(sgn2)
					_tri(vs, ns, us, [o0, n0, Vector2.ZERO], [o1, n1, Vector2.ZERO], [l1, n1, Vector2.ZERO])
					_tri(vs, ns, us, [o0, n0, Vector2.ZERO], [l1, n1, Vector2.ZERO], [l0, n0, Vector2.ZERO])
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = vs
		arr[Mesh.ARRAY_NORMAL] = ns
		arr[Mesh.ARRAY_TEX_UV] = us
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh_node(p, m, mc(cols[c], "fabric", 0.25), top)
	var mt := m_metal()
	for k2 in 8:
		var a := TAU * float(k2) / 8.0
		rod(p, top + Vector3(0, -0.02, 0), top + Vector3(cos(a) * r * 0.96, -0.46, sin(a) * r * 0.96), 0.005, mt, 4)
		rod(p, top + Vector3(0, -0.55, 0), top + Vector3(cos(a) * r * 0.5, -0.23, sin(a) * r * 0.5), 0.004, mt, 4)
	sph(p, 0.035, top + Vector3(0, 0.03, 0), mt, Vector3(1, 1.4, 1), 8)


## Скруглённая трапеция в плоскости XY: [z, полуширина низа, полуширина верха, низ, верх, радиус скругления];
## точки по кругу (4 угла по 4 точки) и внешние нормали к контуру
static func _rtrap(sec: Array) -> Array:
	var hb: float = sec[1]
	var ht: float = sec[2]
	var y0: float = sec[3]
	var y1: float = maxf(float(sec[4]), y0 + 0.0005)
	var r: float = minf(float(sec[5]), (y1 - y0) * 0.45)
	r = maxf(r, 0.0002)
	# углы трапеции: правый низ, правый верх, левый верх, левый низ (обход против часовой в XY)
	var cs := [Vector2(hb, y0), Vector2(ht, y1), Vector2(-ht, y1), Vector2(-hb, y0)]
	var pts := PackedVector2Array()
	var nrm := PackedVector2Array()
	for i in 4:
		var c: Vector2 = cs[i]
		var a: Vector2 = cs[(i + 3) % 4]
		var b: Vector2 = cs[(i + 1) % 4]
		var da := (a - c).normalized()
		var db := (b - c).normalized()
		var half := acos(clampf(da.dot(db), -1.0, 1.0)) * 0.5
		var off := r / maxf(tan(half), 0.05)
		var pa := c + da * off
		var pb := c + db * off
		var na := Vector2(da.y, -da.x) if Vector2(da.y, -da.x).dot(c) > 0.0 else Vector2(-da.y, da.x)
		var nb := Vector2(-db.y, db.x) if Vector2(-db.y, db.x).dot(c) > 0.0 else Vector2(db.y, -db.x)
		for k in 4:
			var t := float(k) / 3.0
			var nn := na.slerp(nb, t).normalized()
			var cc := pa - na * r
			pts.append(cc + nn * r if k > 0 and k < 3 else (pa if k == 0 else pb))
			nrm.append(nn)
	return [pts, nrm]


## Кузов из сечений вдоль Z (каждое — скруглённая трапеция). Нормали — по соседям (сглажено и вдоль, и поперёк),
## торцы закрыты плоскими крышками (если сечение не вырождено)
static func section_loft(secs: Array, caps := true) -> ArrayMesh:
	var rows := []
	var nr2 := []
	for sc in secs:
		var o: Array = _rtrap(sc)
		rows.append(o[0])
		nr2.append(o[1])
	var npt: int = (rows[0] as PackedVector2Array).size()
	var P := []
	for i in secs.size():
		var z: float = secs[i][0]
		var row := PackedVector3Array()
		var ol: PackedVector2Array = rows[i]
		for k in npt:
			row.append(Vector3(ol[k].x, ol[k].y, z))
		P.append(row)
	var rings := []
	var nrms := []
	var uvs := []
	var ns := secs.size()
	for i in ns:
		var row: PackedVector3Array = P[i]
		var ra: PackedVector3Array = P[maxi(i - 1, 0)]
		var rb: PackedVector3Array = P[mini(i + 1, ns - 1)]
		var o2: PackedVector2Array = nr2[i]
		var ring := PackedVector3Array()
		var rn := PackedVector3Array()
		var ru := PackedVector2Array()
		for k in npt + 1:
			var kk := k % npt
			var du := row[(kk + 1) % npt] - row[(kk + npt - 1) % npt]
			var dv := rb[kk] - ra[kk]
			var nn := du.cross(dv)
			var want := Vector3(o2[kk].x, o2[kk].y, 0.0)
			if nn.length_squared() < 1e-10:
				nn = want
			elif nn.dot(want) < 0.0:
				nn = -nn
			ring.append(row[kk])
			rn.append(nn.normalized())
			ru.append(Vector2(float(k) / npt, row[kk].z))
		rings.append(ring)
		nrms.append(rn)
		uvs.append(ru)
	var m := ring_mesh(rings, nrms, uvs)
	if caps:
		var vs := PackedVector3Array()
		var nv := PackedVector3Array()
		var us := PackedVector2Array()
		for e in [0, ns - 1]:
			var row: PackedVector3Array = P[e]
			var c := Vector3.ZERO
			for q in row:
				c += q
			c /= row.size()
			var nz := Vector3(0, 0, 1) if row[0].z > float(secs[1 if e == 0 else ns - 2][0]) else Vector3(0, 0, -1)
			for k in npt:
				_tri(vs, nv, us, [c, nz, Vector2.ZERO], [row[k], nz, Vector2.ZERO], [row[(k + 1) % npt], nz, Vector2.ZERO])
		if vs.size() > 0:
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = vs
			arr[Mesh.ARRAY_NORMAL] = nv
			arr[Mesh.ARRAY_TEX_UV] = us
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static var _car_mesh := {}


## Седан конца 80-х (вроде Chevrolet Caprice / Volvo 240): кузов-лофт со скруглёнными рёбрами, капот ниже
## пояса, наклонное лобовое и заднее стекло, крыша и стойки цвета кузова, хромированные бамперы и молдинги,
## прямоугольные сдвоенные фары, широкие задние фонари, колёса с колпаками.
## Парк перекрашивает материал кузова (зелёный канал > 0,4 при красном < 0,5) и гасит фары — состав
## материалов и то, что все детали — прямые потомки p, это учитывает
static func _car(p: Node3D) -> void:
	var paint := mc(Color(0.45, 0.5, 0.42), "metal", 0.3, {"gloss": 70.0, "spec": 0.25})
	var glass := mc(Color(0.05, 0.06, 0.07), "metal", 0.1, {"gloss": 140.0, "spec": 0.5})
	var chrome := mc(Color(0.62, 0.62, 0.6), "metal", 0.2, {"gloss": 120.0, "spec": 0.55})
	var rubber := m_black()
	if _car_mesh.is_empty():
		# сечения кузова: опорные (z, полуширина низа, верха, верх, скругление) + низ по аркам колёс
		var keys := [[2.37, 0.8, 0.8, 0.7, 0.05], [2.31, 0.86, 0.85, 0.78, 0.07], [1.6, 0.88, 0.87, 0.83, 0.08],
			[0.85, 0.89, 0.87, 0.9, 0.08], [-1.2, 0.89, 0.87, 0.93, 0.08], [-2.27, 0.87, 0.86, 0.9, 0.07], [-2.36, 0.82, 0.81, 0.84, 0.05]]
		var zs := [2.37, 2.31, 1.6, 0.85, -1.2, -2.27, -2.36]
		for zw in [1.4, -1.45]:
			for dz in [-0.4, -0.34, -0.26, -0.14, 0.0, 0.14, 0.26, 0.34, 0.4]:
				zs.append(float(zw) + float(dz))
		zs.sort()
		zs.reverse()
		var secs := []
		for z in zs:
			var zf: float = z
			var a: Array = keys[0]
			var b: Array = keys[0]
			for i in keys.size() - 1:
				var k0: Array = keys[i]
				var k1: Array = keys[i + 1]
				if zf <= float(k0[0]) and zf >= float(k1[0]):
					a = k0
					b = k1
			var t := 0.0 if absf(float(a[0]) - float(b[0])) < 1e-4 else (zf - float(a[0])) / (float(b[0]) - float(a[0]))
			var y0 := 0.3 if absf(zf) < 2.3 else 0.34
			for zw2 in [1.4, -1.45]:
				var dzz := absf(zf - float(zw2))
				if dzz < 0.38:
					y0 = maxf(y0, 0.31 + sqrt(0.38 * 0.38 - dzz * dzz) * 0.95)
			secs.append([zf, lerpf(a[1], b[1], t), lerpf(a[2], b[2], t), y0, lerpf(a[3], b[3], t), lerpf(a[4], b[4], t)])
		_car_mesh["body"] = section_loft(secs)
		_car_mesh["glass"] = section_loft([
			[0.86, 0.83, 0.83, 0.86, 0.865, 0.0], [0.82, 0.83, 0.8, 0.86, 0.95, 0.03], [0.16, 0.83, 0.71, 0.86, 1.38, 0.06],
			[-0.84, 0.83, 0.71, 0.86, 1.38, 0.06], [-1.24, 0.83, 0.79, 0.86, 0.97, 0.03], [-1.27, 0.83, 0.83, 0.86, 0.87, 0.0]], false)
		_car_mesh["roof"] = section_loft([
			[0.2, 0.72, 0.7, 1.36, 1.385, 0.01], [0.14, 0.725, 0.705, 1.37, 1.41, 0.02], [-0.82, 0.725, 0.705, 1.37, 1.41, 0.02],
			[-0.88, 0.72, 0.7, 1.36, 1.385, 0.01]])
	mesh_node(p, _car_mesh["body"], paint)
	mesh_node(p, _car_mesh["glass"], glass)
	mesh_node(p, _car_mesh["roof"], paint)
	# стойки: A — вдоль лобового, B — тонкая, C — широкая (как у седанов того времени)
	for sx in [-1.0, 1.0]:
		rod(p, Vector3(sx * 0.835, 0.9, 0.84), Vector3(sx * 0.718, 1.385, 0.17), 0.035, paint, 6)
		box(p, Vector3(0.05, 0.44, 0.09), Vector3(sx * 0.775, 1.16, -0.32), paint, Vector3(0, 0, sx * 0.25))
		var cp := Node3D.new()
		p.add_child(cp)
		cp.position = Vector3(sx * 0.79, 1.17, -1.0)
		cp.rotation = Vector3(-0.62, 0, sx * 0.24)
		box(cp, Vector3(0.06, 0.52, 0.3), Vector3.ZERO, paint)
		# молдинг по поясу и по низу дверей, ручки, зеркало
		box(p, Vector3(0.012, 0.025, 3.2), Vector3(sx * 0.89, 0.86, -0.2), chrome)
		box(p, Vector3(0.016, 0.06, 3.6), Vector3(sx * 0.892, 0.5, -0.1), rubber)
		for zz in [0.42, -0.62]:
			box(p, Vector3(0.012, 0.025, 0.14), Vector3(sx * 0.893, 0.78, zz), chrome)
		for zd in [0.58, -0.36, -1.18]:
			box(p, Vector3(0.006, 0.5, 0.006), Vector3(sx * 0.892, 0.6, zd), rubber)
		box(p, Vector3(0.1, 0.08, 0.14), Vector3(sx * 0.95, 0.96, 0.62), rubber)
	# бамперы, решётка, фары, фонари, номера
	for zs in [1.0, -1.0]:
		box(p, Vector3(1.86, 0.14, 0.13), Vector3(0, 0.42, zs * 2.4), chrome)
		box(p, Vector3(1.8, 0.04, 0.12), Vector3(0, 0.35, zs * 2.39), rubber)
		box(p, Vector3(0.32, 0.16, 0.012), Vector3(0, 0.6 if zs < 0.0 else 0.3, zs * 2.39), mc(Color(0.82, 0.78, 0.55), "metal", 0.2))
	box(p, Vector3(0.82, 0.2, 0.02), Vector3(0, 0.6, 2.372), mc(Color(0.07, 0.07, 0.07), "metal", 0.3))
	box(p, Vector3(0.86, 0.24, 0.01), Vector3(0, 0.6, 2.368), chrome)
	for sx2 in [-1.0, 1.0]:
		for k in 2:
			box(p, Vector3(0.18, 0.12, 0.03), Vector3(sx2 * (0.52 + k * 0.2), 0.6, 2.365), m_emit(Color(1.0, 0.95, 0.75), 1.2))
		box(p, Vector3(0.42, 0.13, 0.03), Vector3(sx2 * 0.6, 0.72, -2.37), m_emit(Color(0.8, 0.1, 0.08), 0.6))
		box(p, Vector3(0.12, 0.13, 0.031), Vector3(sx2 * 0.33, 0.72, -2.37), mc(Color(0.85, 0.8, 0.7), "metal", 0.1))
	# колёса: шина, колпак, ступица
	for sx3 in [-0.78, 0.78]:
		for sz in [-1.45, 1.4]:
			cyl(p, 0.31, 0.31, 0.2, Vector3(sx3, 0.31, sz), rubber, Vector3(0, 0, PI * 0.5), 18)
			cyl(p, 0.2, 0.2, 0.012, Vector3(sx3 + signf(sx3) * 0.1, 0.31, sz), chrome, Vector3(0, 0, PI * 0.5), 16)
			cyl(p, 0.06, 0.06, 0.02, Vector3(sx3 + signf(sx3) * 0.105, 0.31, sz), mc(Color(0.3, 0.3, 0.3), "metal", 0.3), Vector3(0, 0, PI * 0.5), 10)
	collider(p, Vector3(1.8, 1.4, 4.7), Vector3(0, 0.7, 0))


static var _stroller_mesh := {}


## Детская коляска конца 80-х: тёмно-синяя люлька-ванночка (лофт со скруглёнными краями, белый кант), над
## изголовьем — складной капюшон с дугами, сверху у ног — фартук; хромированное шасси: большие задние колёса
## у ручки, маленькие передние; ручка с поролоновой обмоткой — наклонно к идущему, под люлькой — сетка-корзина.
## Ручка — у +z узла (в парке и у копии коляску ставят перед человеком и поворачивают на PI: ручка к нему)
static func _stroller(p: Node3D) -> void:
	p.set_meta("stroller", true)
	var fr := mc(Color(0.6, 0.6, 0.58), "metal", 0.3, {"gloss": 90.0, "spec": 0.4})
	var cl := mc(Color(0.12, 0.15, 0.3), "fabric", 0.9, {"nmap": Mats.tex("fabric_n"), "bump": 1.0, "gloss": 14.0, "spec": 0.03})
	var trim := mc(Color(0.78, 0.76, 0.7), "fabric", 0.6)
	var rubber := m_black()
	if _stroller_mesh.is_empty():
		_stroller_mesh["tub"] = section_loft([[0.3, 0.17, 0.2, 0.42, 0.7, 0.06], [0.26, 0.2, 0.235, 0.38, 0.72, 0.08],
			[-0.3, 0.2, 0.235, 0.38, 0.72, 0.08], [-0.38, 0.17, 0.205, 0.42, 0.7, 0.06], [-0.4, 0.13, 0.17, 0.46, 0.68, 0.04]])
		_stroller_mesh["apron"] = section_loft([[0.0, 0.215, 0.205, 0.7, 0.745, 0.02], [-0.37, 0.195, 0.185, 0.69, 0.73, 0.02]])
		var tb := TorusMesh.new()
		tb.inner_radius = 0.105
		tb.outer_radius = 0.14
		tb.rings = 24
		tb.ring_segments = 8
		_stroller_mesh["tire_b"] = tb
		var ts := TorusMesh.new()
		ts.inner_radius = 0.07
		ts.outer_radius = 0.1
		ts.rings = 20
		ts.ring_segments = 8
		_stroller_mesh["tire_s"] = ts
		var hood := SphereMesh.new()
		hood.radius = 0.235
		hood.height = 0.235
		hood.is_hemisphere = true
		hood.radial_segments = 20
		hood.rings = 8
		_stroller_mesh["hood"] = hood
	mesh_node(p, _stroller_mesh["tub"], cl)
	mesh_node(p, _stroller_mesh["apron"], cl)
	# кант по верхнему краю люльки
	box(p, Vector3(0.48, 0.014, 0.012), Vector3(0, 0.72, -0.385), trim)
	for sx in [-1.0, 1.0]:
		box(p, Vector3(0.012, 0.014, 0.66), Vector3(sx * 0.237, 0.722, -0.05), trim)
	# капюшон над изголовьем: полукупол открыт к ногам, две дуги-спицы
	var hn := mesh_node(p, _stroller_mesh["hood"], cl, Vector3(0, 0.72, 0.08), Vector3(PI * 0.5, 0, 0), Vector3(1.0, 1.25, 1.0))
	hn.set_meta("hood", true)
	for rb in [[0.085, 0.238], [0.26, 0.182]]:
		var ra: Array = rb
		var arc := TorusMesh.new()
		arc.inner_radius = float(ra[1]) - 0.005
		arc.outer_radius = float(ra[1]) + 0.004
		arc.rings = 24
		arc.ring_segments = 4
		mesh_node(p, arc, trim, Vector3(0, 0.72, float(ra[0])), Vector3(PI * 0.5, 0, 0))
	# шасси: продольные трубки, оси, колёса (задние большие — у ручки)
	for sx2 in [-0.23, 0.23]:
		rod(p, Vector3(sx2, 0.38, -0.3), Vector3(sx2, 0.38, 0.28), 0.011, fr, 6)
		rod(p, Vector3(sx2, 0.38, 0.22), Vector3(sx2 * 1.05, 0.14, 0.3), 0.011, fr, 6)
		rod(p, Vector3(sx2, 0.38, -0.25), Vector3(sx2 * 1.0, 0.1, -0.34), 0.011, fr, 6)
	rod(p, Vector3(-0.26, 0.14, 0.3), Vector3(0.26, 0.14, 0.3), 0.008, fr, 6)
	rod(p, Vector3(-0.24, 0.1, -0.34), Vector3(0.24, 0.1, -0.34), 0.008, fr, 6)
	for w in [[0.27, 0.14, 0.3, "tire_b"], [0.25, 0.1, -0.34, "tire_s"]]:
		var a: Array = w
		for sx3 in [-1.0, 1.0]:
			var wh := Node3D.new()
			p.add_child(wh)
			wh.position = Vector3(sx3 * float(a[0]), float(a[1]), float(a[2]))
			wh.rotation = Vector3(0, 0, PI * 0.5)
			mesh_node(wh, _stroller_mesh[a[3]], rubber)
			var rr: float = float(a[1]) * 0.72
			cyl(wh, rr, rr, 0.02, Vector3.ZERO, fr, Vector3.ZERO, 16)
			cyl(wh, rr * 0.35, rr * 0.35, 0.03, Vector3.ZERO, trim, Vector3.ZERO, 12)
	# корзина-сетка под люлькой
	box(p, Vector3(0.36, 0.1, 0.42), Vector3(0, 0.25, -0.02), mc(Color(0.06, 0.06, 0.06), "fabric", 0.4))
	# ручка: две трубки от изголовья наклонно вверх-назад, перекладина в поролоне
	for sx4 in [-0.21, 0.21]:
		rod(p, Vector3(sx4, 0.42, 0.24), Vector3(sx4, 1.0, 0.44), 0.011, fr, 6)
	rod(p, Vector3(-0.23, 1.0, 0.44), Vector3(0.23, 1.0, 0.44), 0.011, fr, 6)
	rod(p, Vector3(-0.17, 1.0, 0.44), Vector3(0.17, 1.0, 0.44), 0.02, rubber, 8)


## Воздушный шарик на нитке: узел p — рука (кончик нитки), шарик парит над ней на string метров.
## Ориентация берётся в мире (BalloonFloat), а не от кисти: нитка всегда идёт вверх, шарик чуть покачивается
static func _balloon(p: Node3D, string := 1.15) -> void:
	var b := BalloonFloat.new()
	p.add_child(b)
	var latex := mc(Color(0.82, 0.07, 0.07), "metal", 0.05, {"wet": 0.6, "gloss": 90.0, "spec": 0.35})
	b.top = Node3D.new()
	b.add_child(b.top)
	b.top.position = Vector3(0, string, 0)
	sph(b.top, 0.16, Vector3(0, 0.17, 0), latex, Vector3(1, 1.18, 1), 16)
	cyl(b.top, 0.012, 0.022, 0.03, Vector3(0, 0.0, 0), latex, Vector3.ZERO, 8)
	b.line = rod(b, Vector3.ZERO, Vector3(0, string, 0), 0.0025, m_plastic(Color(0.9, 0.9, 0.88)), 3)


## Гелиевый шарик, упёршийся в потолок: узел — на потолке, шарик под ним, ленточка висит вниз завитками
static func _balloon_ceiling(p: Node3D) -> void:
	var latex := mc(Color(0.82, 0.07, 0.07), "metal", 0.05, {"wet": 0.6, "gloss": 90.0, "spec": 0.35})
	sph(p, 0.16, Vector3(0, -0.19, 0), latex, Vector3(1, 1.18, 1), 16)
	cyl(p, 0.012, 0.022, 0.03, Vector3(0, -0.385, 0), latex, Vector3.ZERO, 8)
	var pts := PackedVector3Array()
	var rr := PackedFloat32Array()
	for i in 13:
		var t := float(i) / 12.0
		pts.append(Vector3(sin(t * 14.0) * 0.025 * t, -0.4 - t * 1.0, cos(t * 14.0) * 0.025 * t))
		rr.append(0.0025)
	mesh_node(p, loft(pts, rr, rr, 4), m_plastic(Color(0.9, 0.85, 0.3)))


static var _blanket_mesh: ArrayMesh = null


## Плед для пикника 2×2 м: одна мягкая ткань (сетка 24×24), лежит на примятой траве — середина на 3–4 см
## над землёй, мелкие волны и морщины, один угол завёрнут, края свисают до земли. Клетка — prop_gingham
## (UV в метрах: плитка 1 м — 8 клеток). Рядом — плетёная корзина с ручкой
static func _blanket(p: Node3D) -> void:
	if _blanket_mesh == null:
		var nn := 24
		var half := 1.0
		var hs := []
		var ps := []
		for j in nn + 1:
			var row := []
			for i in nn + 1:
				var x := -half + 2.0 * half * i / nn
				var z := -half + 2.0 * half * j / nn
				var e := minf(half - absf(x), half - absf(z))
				var lift := 0.035 * smoothstep(0.0, 0.12, e)
				var wav := 0.008 * sin(x * 7.0 + z * 2.0) * sin(z * 5.5 - x * 1.5) + 0.005 * sin(x * 17.0 + z * 13.0)
				var y := lift + wav * smoothstep(0.0, 0.2, e)
				var px := x
				var pz := z
				# завёрнутый угол (+x, +z): ткань перегнута по линии x + z = 1,55 и легла на себя; на сгибе — валик
				var cd := (x + z) - 1.55
				if cd > 0.0:
					px = x - cd
					pz = z - cd
					var e2 := minf(half - absf(px), half - absf(pz))
					y = 0.035 * smoothstep(0.0, 0.12, e2) + 0.01 + 0.014 * (1.0 - smoothstep(0.0, 0.1, cd))
				row.append(Vector3(px, y, pz))
			ps.append(row)
		var vs := PackedVector3Array()
		var ns := PackedVector3Array()
		var us := PackedVector2Array()
		for j in nn:
			for i in nn:
				var q := [ps[j][i], ps[j][i + 1], ps[j + 1][i + 1], ps[j + 1][i]]
				var uvq := [Vector2(float(i) / nn * 2.0, float(j) / nn * 2.0), Vector2(float(i + 1) / nn * 2.0, float(j) / nn * 2.0),
					Vector2(float(i + 1) / nn * 2.0, float(j + 1) / nn * 2.0), Vector2(float(i) / nn * 2.0, float(j + 1) / nn * 2.0)]
				var fnm := ((q[1] as Vector3) - (q[0] as Vector3)).cross((q[3] as Vector3) - (q[0] as Vector3)).normalized()
				if fnm.y < 0.0:
					fnm = -fnm
				_tri(vs, ns, us, [q[0], fnm, uvq[0]], [q[1], fnm, uvq[1]], [q[2], fnm, uvq[2]])
				_tri(vs, ns, us, [q[0], fnm, uvq[0]], [q[2], fnm, uvq[2]], [q[3], fnm, uvq[3]])
		# сглаженные нормали: общие вершины склеиваются (позиция + UV), нормали — по соседним граням
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = vs
		arr[Mesh.ARRAY_TEX_UV] = us
		var st := SurfaceTool.new()
		st.create_from_arrays(arr)
		st.index()
		st.generate_normals()
		_blanket_mesh = st.commit()
	var cloth: Material = Mats.col(Color(0.9, 0.88, 0.85), "prop_gingham", 1.0, {"nmap": Mats.tex("fabric_n"), "bump": 0.8, "gloss": 8.0, "spec": 0.02, "ds": true}) 		if Mats.has_tex("prop_gingham") else m_cloth(Color(0.75, 0.12, 0.1))
	mesh_node(p, _blanket_mesh, cloth)
	# плетёная корзина: короб со скруглёнными рёбрами, крышка-половинки, дуга ручки
	var wick := mc(Color(0.62, 0.46, 0.27), "fiber", 1.0, {"nmap": Mats.tex("fiber_n"), "bump": 1.5, "gloss": 14.0, "spec": 0.03})
	var bk := Node3D.new()
	p.add_child(bk)
	bk.position = Vector3(0.45, 0.035, 0.35)
	bk.rotation.y = 0.5
	mesh_node(bk, section_loft([[0.2, 0.15, 0.17, 0.0, 0.24, 0.03], [-0.2, 0.15, 0.17, 0.0, 0.24, 0.03]]), wick)
	mesh_node(bk, section_loft([[0.205, 0.175, 0.17, 0.235, 0.265, 0.012], [-0.205, 0.175, 0.17, 0.235, 0.265, 0.012]]), wick)
	var hp := PackedVector3Array()
	var hr := PackedFloat32Array()
	for i2 in 11:
		var a := PI * float(i2) / 10.0
		hp.append(Vector3(cos(a) * 0.15, 0.26 + sin(a) * 0.17, 0.0))
		hr.append(0.009)
	mesh_node(bk, loft(hp, hr, hr, 6), wick)


static func _phone(p: Node3D) -> void:
	box(p, Vector3(0.22, 0.08, 0.2), Vector3(0, 0.04, 0), m_plastic(Color(0.85, 0.8, 0.7)))
	box(p, Vector3(0.24, 0.05, 0.06), Vector3(0, 0.1, 0), m_plastic(Color(0.85, 0.8, 0.7)))


static func _chair(p: Node3D) -> void:
	if model(p, "plastic_monobloc_chair_01", Vector3.ZERO, 0.0, 1.0, false) != null:
		return
	var pl := m_plastic(Color(0.86, 0.85, 0.8))
	box(p, Vector3(0.45, 0.04, 0.42), Vector3(0, 0.45, 0), pl)
	box(p, Vector3(0.45, 0.4, 0.04), Vector3(0, 0.67, -0.2), pl, Vector3(-0.12, 0, 0))
	for sx in [-0.2, 0.2]:
		for sz in [-0.18, 0.18]:
			box(p, Vector3(0.03, 0.45, 0.03), Vector3(sx, 0.22, sz), pl)


## Высота столешницы _desk (модель или запасной стол из ящиков)
static func desk_top() -> float:
	return top_of("metal_office_desk") if Models.has("metal_office_desk") else 0.76


static func _desk(p: Node3D) -> void:
	if model(p, "metal_office_desk", Vector3.ZERO, 0.0, Vector3(0.75, 1.0, 0.8)) != null:
		return
	var w := mc(Color(0.62, 0.55, 0.45), "wood", 0.6)
	box(p, Vector3(1.4, 0.04, 0.7), Vector3(0, 0.74, 0), w)
	box(p, Vector3(0.04, 0.72, 0.68), Vector3(-0.68, 0.36, 0), w)
	box(p, Vector3(0.45, 0.72, 0.68), Vector3(0.47, 0.36, 0), w)
	box(p, Vector3(1.3, 0.4, 0.02), Vector3(0, 0.5, -0.33), w)
	collider(p, Vector3(1.4, 0.76, 0.7), Vector3(0, 0.38, 0))


static func _cabinet(p: Node3D) -> void:
	var g := mc(Color(0.52, 0.53, 0.5), "metal", 0.5)
	box(p, Vector3(0.48, 1.32, 0.62), Vector3(0, 0.66, 0), g)
	for k in 4:
		box(p, Vector3(0.42, 0.02, 0.01), Vector3(0, 0.3 + k * 0.32, 0.315), m_black())
		box(p, Vector3(0.12, 0.03, 0.03), Vector3(0, 0.42 + k * 0.32, 0.32), m_metal())
	collider(p, Vector3(0.48, 1.32, 0.62), Vector3(0, 0.66, 0))


static func _cooler(p: Node3D) -> void:
	box(p, Vector3(0.32, 1.0, 0.32), Vector3(0, 0.5, 0), m_plastic(Color(0.85, 0.84, 0.8)))
	# бутыль: голубоватый пластик с водой — блестит, но не светится
	cyl(p, 0.15, 0.15, 0.45, Vector3(0, 1.22, 0), mc(Color(0.32, 0.45, 0.55), "metal", 0.1, {"gloss": 90.0, "spec": 0.3}), Vector3.ZERO, 12)


static func _ochair(p: Node3D) -> void:
	if model(p, "SchoolChair_01", Vector3.ZERO, 0.0, 1.0, false) != null:
		return
	var c := m_cloth(Color(0.2, 0.22, 0.28))
	box(p, Vector3(0.5, 0.08, 0.48), Vector3(0, 0.48, 0), c)
	box(p, Vector3(0.46, 0.55, 0.07), Vector3(0, 0.82, -0.22), c)
	cyl(p, 0.03, 0.03, 0.4, Vector3(0, 0.25, 0), m_black())


static func _boxes(p: Node3D, rng: RandomNumberGenerator) -> void:
	if Models.has("cardboard_box_01"):
		var n := rng.randi_range(2, 4)
		for k in n:
			var sc := rng.randf_range(0.8, 1.25)
			var y := 0.0 if k < 2 else 0.34 * sc
			model(p, "cardboard_box_01", Vector3(rng.randf_range(-0.35, 0.35), y, rng.randf_range(-0.35, 0.35)), rng.randf_range(-0.5, 0.5), sc, k < 2)
		return
	var cb := mc(Color(0.62, 0.48, 0.3), "paper", 0.6)
	for k in rng.randi_range(2, 5):
		var s := Vector3(rng.randf_range(0.35, 0.6), rng.randf_range(0.25, 0.45), rng.randf_range(0.35, 0.55))
		box(p, s, Vector3(rng.randf_range(-0.3, 0.3), s.y * 0.5 + (0.4 if k > 2 else 0.0), rng.randf_range(-0.3, 0.3)), cb, Vector3(0, rng.randf_range(-0.4, 0.4), 0))


static func _tv(p: Node3D) -> void:
	box(p, Vector3(0.7, 0.5, 0.5), Vector3(0, 0.25, 0), mc(Color(0.35, 0.25, 0.18), "wood", 0.7))
	# включённый кинескоп как в комнатах телевизоров (props_rooms._crt): «снег», строки, выпуклое стекло;
	# своя яркость поменьше — в тёмном доме автоусиление камеры не выжигает экран в белое
	if _pr == null:
		_pr = load("res://src/world/props_rooms.gd")
	var t: Node3D = _pr._crt(p, null, "static", Vector3(0, 0.5, 0))
	if _tv_dim == null:
		var src: ShaderMaterial = _pr.tv_mat(null, "static")
		_tv_dim = src.duplicate() as ShaderMaterial
		_tv_dim.set_shader_parameter("bright", 0.45)
	for ch in t.get_children():
		var mi := ch as MeshInstance3D
		if mi != null and mi.material_override is ShaderMaterial and (mi.material_override as ShaderMaterial).shader == _pr.TV_SHADER:
			mi.material_override = _tv_dim


static var _tv_dim: ShaderMaterial = null


static func _shelf(p: Node3D, rng: RandomNumberGenerator) -> void:
	if model(p, "steel_frame_shelves_01", Vector3.ZERO, 0.0, 0.1) != null:
		for k in 3:
			if rng.randf() < 0.6 and Models.has("cardboard_box_01"):
				model(p, "cardboard_box_01", Vector3(rng.randf_range(-0.25, 0.25), 0.05 + k * 0.52, 0), rng.randf_range(-0.3, 0.3), 0.8, false)
		return
	var g := mc(Color(0.5, 0.5, 0.48), "metal", 0.5)
	for sx in [-0.45, 0.45]:
		for sz in [-0.18, 0.18]:
			box(p, Vector3(0.03, 1.8, 0.03), Vector3(sx, 0.9, sz), g)
	for k in 4:
		box(p, Vector3(0.95, 0.025, 0.4), Vector3(0, 0.3 + k * 0.45, 0), g)


static func _sign_park(p: Node3D) -> void:
	var bw := 1.2
	var bh := 0.6
	for sx in [-bw * 0.42, bw * 0.42]:
		box(p, Vector3(0.08, 1.55, 0.08), Vector3(sx, 0.78, -0.05), mc(Color(0.35, 0.25, 0.15), "wood", 0.8))
	box(p, Vector3(bw, bh, 0.05), Vector3(0, 1.5, 0), mc(Color(0.15, 0.32, 0.2), "wood", 0.4))
	# надпись подгоняем под табличку: шрифт системный, ширина строки зависит от языка
	var txt := Loc.t("sign.park")
	var f := font_sign()
	var tsz := f.get_multiline_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 64)
	var px := minf((bw - 0.16) / maxf(tsz.x, 1.0), (bh - 0.14) / maxf(tsz.y, 1.0))
	var lb := label(txt, f, px, Color(0.9, 0.88, 0.8))
	lb.position = Vector3(0, 1.5, 0.03)
	p.add_child(lb)


static func _hill_chair(p: Node3D) -> void:
	sph(p, 1.0, Vector3(0, -0.35, 0), m_carpet(), Vector3(1.9, 1.0, 1.6), 16)
	var ch := Node3D.new()
	p.add_child(ch)
	ch.position = Vector3(0.1, 0.62, 0)
	ch.rotation = Vector3(0.1, 0.5, -0.08)
	_chair(ch)
	collider(p, Vector3(2.8, 0.6, 2.4), Vector3(0, 0.3, 0))


static var _crumbs: Array = []


## Обломки под провалом: рваные куски минераловатной плиты потолка (лицом вверх — пыльная крашеная сторона
## с узором и рельефом, изнанкой — серо-бурый картон), клочья ковра сверху, крошка, гнутый профиль подвеса,
## вокруг — светлая пыль. Альбедо не выше ~0,55: на тёмном ковре обломки не «светятся»
static func _debris(p: Node3D, rng: RandomNumberGenerator) -> void:
	var tm := tile_mats(true)
	var crumb := mc(Color(0.5, 0.48, 0.43), "fiber", 0.6, {"albedo_cap": 0.42})
	var carpet := mc(Color(0.62, 0.52, 0.4), "carpet", 1.0, {"nmap": Mats.tex("carpet_n"), "bump": 1.0})
	if _crumbs.is_empty():
		for k in 4:
			_crumbs.append(blob_mesh(1.0, 0.45, 77 + k, Vector3(1.2, 0.6, 1.0), 8, 2.0))
	var dust := decal_mat("debris_dust", {"radial": 1.0, "tint": Color(0.5, 0.48, 0.43, 0.22)})
	var dq := quad(p, Vector2(2.6, 2.6), Vector3(0, 0.006, 0), dust, Vector3(-PI * 0.5, 0, 0))
	dq.set_instance_shader_parameter("seed", rng.randf() * 10.0)
	# куски плиты 16 мм: лицо с текстурой потолка, рыхлый торец, изнанка; часть лежит изнанкой вверх, часть
	# опирается на соседние (наклон — по-разному освещены), уложены друг на друга
	var y := 0.009
	var cnt := rng.randi_range(5, 8)
	for k in cnt:
		var poly := shard_poly(rng, rng.randf_range(0.09, 0.2), 0.45, rng.randi_range(5, 8), rng.randf_range(0.8, 1.4))
		var lean := rng.randf() < 0.35
		var pos := Vector3(rng.randf_range(-0.75, 0.75), y, rng.randf_range(-0.75, 0.75))
		var rot := Vector3(rng.randf_range(-0.08, 0.08), rng.randf() * TAU, rng.randf_range(-0.08, 0.08))
		if lean:
			pos.y = 0.05
			rot.x = rng.randf_range(0.2, 0.42)
		if rng.randf() < 0.3:
			rot.z += PI
		tile_node(p, poly, 0.017, tm, pos, rot)
		y += 0.005
	# клочья ковра с подложкой
	for k2 in rng.randi_range(1, 2):
		var cp := shard_poly(rng, rng.randf_range(0.18, 0.32), 0.3, 7, rng.randf_range(1.0, 1.8))
		mesh_node(p, slab_mesh(cp, 0.012), carpet, Vector3(rng.randf_range(-0.7, 0.7), 0.008 + k2 * 0.003, rng.randf_range(-0.7, 0.7)),
			Vector3(rng.randf_range(-0.04, 0.04), rng.randf() * TAU, rng.randf_range(-0.04, 0.04)))
	# крошка
	for k3 in rng.randi_range(10, 18):
		var r := rng.randf_range(0.012, 0.035)
		var a := rng.randf() * TAU
		var dd := rng.randf_range(0.1, 1.1)
		mesh_node(p, _crumbs[k3 % _crumbs.size()], crumb, Vector3(cos(a) * dd, r * 0.4, sin(a) * dd), Vector3(0, rng.randf() * TAU, 0), Vector3.ONE * r)
	# гнутый Т-профиль подвесного потолка
	var bar := Node3D.new()
	p.add_child(bar)
	bar.position = Vector3(rng.randf_range(-0.4, 0.4), 0.015, rng.randf_range(-0.4, 0.4))
	bar.rotation.y = rng.randf() * TAU
	var enamel := mc(Color(0.62, 0.61, 0.58), "metal", 0.3, {"albedo_cap": 0.45, "gloss": 50.0, "spec": 0.15})
	box(bar, Vector3(0.024, 0.006, 0.7), Vector3(0, 0.003, 0.35), enamel)
	box(bar, Vector3(0.004, 0.03, 0.7), Vector3(0, 0.018, 0.35), enamel)
	var b2 := Node3D.new()
	bar.add_child(b2)
	b2.rotation = Vector3(0.35, 0.5, 0)
	box(b2, Vector3(0.024, 0.006, 0.5), Vector3(0, 0.003, -0.25), enamel)
	box(b2, Vector3(0.004, 0.03, 0.5), Vector3(0, 0.018, -0.25), enamel)


# ------------------------------------------------------------ люди-копии

static func copy_person(cx: Node3D, d: Dictionary, rng: RandomNumberGenerator, layer: int) -> Node3D:
	var who := String(d.get("who", "civ_a"))
	var wrong := String(d.get("wrong", "none"))
	var holder := Node3D.new()
	var h := Human.make("civ_a" if who == "couple" else who, int(d.get("seed", 1)), true)
	holder.add_child(h)
	var ps := String(d.get("pose", "stand"))
	if who == "oldman":
		ps = "read"
	elif who == "couple":
		ps = "sit_ground"
	if ps == "run":
		h.pose("run", float(d.get("phase", 0.0)) * TAU)
		h.pose_name = "run_frozen"
	else:
		h.pose(ps)
	h.apply_wrong(wrong, rng)
	if wrong == "ceiling":
		# головой в потолок — на настоящей высоте потолка этой клетки
		h.position.y += float(d.get("ceil", 2.7)) - 2.7
	h.uncanny(rng)
	if bool(d.get("mold", false)):
		h.tune({"mold": 0.55})
	match who:
		"kid":
			if rng.randf() < 0.6:
				# под потолком Комплекса нитка короче
				var bal := Node3D.new()
				_balloon(bal, 0.7)
				h.hold(bal, "r", Vector3(0, 0.2, 0))
				h.pose("hold_up")
		"oldman":
			box(h.hand("l"), Vector3(0.45, 0.32, 0.01), Vector3(0.15, -0.12, 0.08), mc(Color(0.82, 0.8, 0.74), "paper", 1.0, {"pale": 0.3}), Vector3(0, 0, 0.1))
		"suit":
			box(h.hand("r"), Vector3(0.42, 0.3, 0.09), Vector3(0, -0.2, 0), mc(Color(0.2, 0.12, 0.06), "metal", 0.3, {"pale": 0.3}))
		"couple":
			var h2 := Human.make("civ_b", int(d.get("seed", 1)) + 7, true)
			h2.pose("sit_ground")
			holder.add_child(h2)
			if wrong == "fused":
				h2.position = Vector3(0.12, 0, 0.05)
				h2.rotation.y = PI * 0.85
				h2.scale = Vector3(1.0, 1.06, 1.0)
			else:
				h2.position = Vector3(0.6, 0, 0)
	if wrong == "melt_bench":
		var b := Node3D.new()
		_bench(b)
		swap_mats(b, mc(Color(0.58, 0.42, 0.28), "wood", 1.0, {"pale": 0.25, "smear": 1.0}))
		holder.add_child(b)
		b.position = Vector3(0, -0.05, -0.05)
		h.position.z = 0.05
	if wrong == "stroller_fused":
		var s := Node3D.new()
		_stroller(s)
		holder.add_child(s)
		s.position = Vector3(0, 0, 0.45)
		s.rotation.y = PI
		h.pose("push")
		h.position.y -= 0.35
		h.position.z = -0.1
	if wrong == "seated_air":
		h.position.y += 0.0
	h.breathe = 1.0 if rng.randf() < 0.4 else 0.0
	h.react = bool(d.get("react", false))
	if h.react and cx.get("player") != null:
		h.look_target = cx.player
	# тихий звук рядом с некоторыми копиями
	if rng.randf() < 0.3:
		var se := SoundEmitter.new()
		se.snd = ["copy_whisper", "copy_breath", "copy_moan"][rng.randi_range(0, 2)]
		se.every = rng.randf_range(9.0, 20.0)
		se.vol = -14.0
		se.position = Vector3(0, 1.4, 0)
		holder.add_child(se)
	holder.set_meta("copy", true)
	return holder


static var _camc_mesh := {}


## Бытовая видеокамера 1990 года (компактная, как у героя): тёмно-серый пластиковый корпус со скруглёнными
## рёбрами, объектив с блендой и тёмным стеклом, сверху — микрофон с решёткой, сзади слева — видоискатель
## с резиновым наглазником, справа — ремень для руки, сбоку — крышка кассетного отсека и серебристая полоска.
## Объектив смотрит в +z, низ корпуса — y = 0, центр — x = 0. Возвращает узел огонька REC (или null)
static func camcorder(p: Node3D, rec := true) -> MeshInstance3D:
	var body := mc(Color(0.1, 0.1, 0.105), "metal", 0.25, {"gloss": 40.0, "spec": 0.08})
	var dark := mc(Color(0.05, 0.05, 0.052), "metal", 0.2, {"gloss": 30.0, "spec": 0.06})
	var rubber := mc(Color(0.03, 0.03, 0.03), "fabric", 0.4, {"gloss": 10.0, "spec": 0.02})
	var silver := mc(Color(0.55, 0.55, 0.53), "metal", 0.4, {"gloss": 70.0, "spec": 0.3})
	var glass := mc(Color(0.03, 0.035, 0.05), "metal", 0.0, {"gloss": 160.0, "spec": 0.6, "wet": 0.5})
	if _camc_mesh.is_empty():
		_camc_mesh["body"] = section_loft([[0.1, 0.048, 0.044, 0.0, 0.112, 0.018], [0.09, 0.054, 0.05, 0.0, 0.118, 0.022],
			[-0.1, 0.054, 0.05, 0.0, 0.118, 0.022], [-0.11, 0.048, 0.044, 0.004, 0.112, 0.018]])
		_camc_mesh["lens"] = lathe(PackedVector2Array([Vector2(0.0, -0.002), Vector2(0.032, -0.002), Vector2(0.034, 0.01),
			Vector2(0.034, 0.05), Vector2(0.038, 0.055), Vector2(0.042, 0.075), Vector2(0.04, 0.078), Vector2(0.03, 0.074)]), 24, 30.0)
		_camc_mesh["vf"] = lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.016, 0.0), Vector2(0.017, 0.07), Vector2(0.024, 0.08),
			Vector2(0.026, 0.1), Vector2(0.02, 0.102), Vector2(0.0, 0.1)]), 16, 30.0)
	mesh_node(p, _camc_mesh["body"], body)
	# объектив: бленда с рифлёным кольцом, тёмное стекло
	mesh_node(p, _camc_mesh["lens"], dark, Vector3(0.006, 0.06, 0.1), Vector3(PI * 0.5, 0, 0))
	cyl(p, 0.0355, 0.0355, 0.012, Vector3(0.006, 0.06, 0.14), rubber, Vector3(PI * 0.5, 0, 0), 20)
	cyl(p, 0.028, 0.028, 0.004, Vector3(0.006, 0.06, 0.172), glass, Vector3(PI * 0.5, 0, 0), 20)
	# микрофон сверху спереди: решётка
	cyl(p, 0.012, 0.012, 0.05, Vector3(0.012, 0.128, 0.07), dark, Vector3(PI * 0.5, 0, 0), 10)
	cyl(p, 0.0125, 0.0125, 0.02, Vector3(0.012, 0.128, 0.098), silver, Vector3(PI * 0.5, 0, 0), 10)
	# видоискатель: трубка назад слева (сторона −x — правая у держащего), наглазник
	mesh_node(p, _camc_mesh["vf"], dark, Vector3(-0.045, 0.104, -0.05), Vector3(-PI * 0.5, 0, 0))
	box(p, Vector3(0.03, 0.02, 0.05), Vector3(-0.04, 0.115, -0.03), body)
	# ремень для руки на правом боку (−x: камеру держат правой рукой)
	var strap := TorusMesh.new()
	strap.inner_radius = 0.07
	strap.outer_radius = 0.082
	strap.rings = 18
	strap.ring_segments = 4
	mesh_node(p, strap, rubber, Vector3(-0.058, 0.06, -0.01), Vector3(0, 0, PI * 0.5), Vector3(0.55, 0.25, 1.3))
	# крышка кассетного отсека (шов) и серебристая полоска с кнопками на левом боку
	box(p, Vector3(0.002, 0.07, 0.14), Vector3(0.0545, 0.06, -0.01), dark)
	box(p, Vector3(0.002, 0.012, 0.16), Vector3(0.0548, 0.1, -0.01), silver)
	for k in 3:
		box(p, Vector3(0.004, 0.008, 0.012), Vector3(0.056, 0.03, -0.06 + k * 0.022), silver)
	# батарея сзади
	box(p, Vector3(0.09, 0.07, 0.025), Vector3(0.0, 0.05, -0.115), dark)
	if not rec:
		return null
	var lamp := sph(p, 0.005, Vector3(0.04, 0.1, 0.1), m_emit(Color(1.0, 0.05, 0.05), 3.0))
	return lamp


static func copy_self(cx: Node3D, d: Dictionary) -> Node3D:
	var holder := Node3D.new()
	var b := Node3D.new()
	_bench(b)
	holder.add_child(b)
	var h := Human.make("player", 77, true)
	holder.add_child(h)
	h.pose("film")
	h.position = Vector3(0, -0.45, 0.02)
	(h.j["pelvis"] as Node3D).position.y = 0.95
	h.pose("sit")
	h._r("sh_l", -1.2, 0.4, -0.2)
	h._r("sh_r", -1.2, -0.4, 0.2)
	h._r("el_l", -1.1)
	h._r("el_r", -1.1)
	h.position = Vector3(0, 0.0, 0.05)
	# видеокамера у глаза, объективом вперёд — на того, кто вошёл; горит REC. Крепится к голове (не к кости
	# кисти, у которой оси повёрнуты как угодно): копия следит за героем — камера ведёт его вместе с головой.
	# Наглазник видоискателя — у правого глаза, корпус закрывает правую половину лица
	var cam := Node3D.new()
	var hf := h.head_frame()
	if hf != null:
		hf.add_child(cam)
		cam.position = Vector3(0.014, -0.016, 0.23)
	else:
		holder.add_child(cam)
		cam.position = Vector3(-0.03, 1.1, 0.22)
	camcorder(cam)
	h.react = true
	h.look_target = cx.player if cx.get("player") != null else null
	var se := SoundEmitter.new()
	se.snd = "tape_whir"
	se.every = 0.0
	se.vol = -16.0
	se.position = Vector3(0, 1.0, 0)
	holder.add_child(se)
	var tr := ProxTrigger.new()
	tr.radius = 4.0
	tr.once = true
	tr.cb = func() -> void:
		if Game.main != null:
			Game.main.burst(0.8)
		Snd.play("sting_low", -6.0)
		Game.say("sub.self")
	holder.add_child(tr)
	return holder


# ------------------------------------------------------------ надписи, метки, таблички

static var _text_tex := {}


## Надпись. В Комплексе — плоская табличка-текстура: буквы шрифта переносятся из кэша глифов в картинку
## (один раз на текст), квадрат с материалом предмета и вырезом по альфе — освещён лампами по сетке,
## мигает и гаснет вместе со светом, тонет в тумане (не «выскакивает» на 30 м). glow > 0 — светится сама
## (табло; mains — от сети: гаснет при отключении). В парке и концовках — Label3D, как раньше.
## width > 0 — перенос по словам на этой ширине (в пикселях шрифта 64).
static func label(text: String, font: Font, px: float, ink: Color, outline := 0, width := 0.0, glow := 0.0, mains := true) -> GeometryInstance3D:
	if park_mode:
		var lb := Label3D.new()
		lb.text = text
		lb.font = font
		lb.font_size = 64
		lb.pixel_size = px
		lb.modulate = ink
		lb.set_meta("ink", ink)
		lb.outline_size = outline
		lb.double_sided = false
		lb.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		lb.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		lb.visibility_range_end = 30.0
		lb.autowrap_mode = TextServer.AUTOWRAP_OFF
		if width > 0.0:
			lb.width = width
			lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return lb
	var tex := text_texture(text, font, width)
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(tex.get_width(), tex.get_height()) * px
	mi.mesh = q
	var c := cap(ink, 0.7)
	var ex := {"tex_mix": 0.0, "color": Vector3(c.r, c.g, c.b), "alpha_cut": 0.5, "gloss": 20.0, "spec": 0.04}
	if glow > 0.0:
		ex["color"] = Vector3(ink.r, ink.g, ink.b) * 0.3
		ex["emit"] = glow
		ex["emit_color"] = Vector3(ink.r, ink.g, ink.b)
		ex["powered"] = 1.0 if mains else 0.0
	var m := Mats.prop("label_%d_%s_%.2f_%d" % [tex.get_instance_id(), ink.to_html(), glow, int(mains)], ex)
	m.set_shader_parameter("tex", tex)
	mi.material_override = m
	mi.set_meta("ink", ink)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Картинка надписи (буквы — альфа-покрытие), шрифт 64 px, строки по центру; отступ 4 px.
## Глифы берутся из кэша шрифта (TextServer), поэтому годится любой системный шрифт, в том числе рукописный.
static func text_texture(text: String, font: Font, width := 0.0) -> ImageTexture:
	var key := "%s|%d|%.0f" % [text, font.get_instance_id(), width]
	if _text_tex.has(key):
		return _text_tex[key]
	var ts := TextServerManager.get_primary_interface()
	var para := TextParagraph.new()
	para.width = width if width > 0.0 else -1.0
	para.alignment = HORIZONTAL_ALIGNMENT_CENTER
	para.add_string(text, font, 64)
	var pad := 4
	var sz := para.get_size()
	var w := maxi(int(ceil(sz.x)) + pad * 2, 8)
	var h := maxi(int(ceil(sz.y)) + pad * 2, 8)
	# проход 1: раскладка и отрисовка глифов в кэш шрифта
	var put := []
	var y := float(pad)
	for li in para.get_line_count():
		var lrid := para.get_line_rid(li)
		var lsz := para.get_line_size(li)
		var base := y + para.get_line_ascent(li)
		var x := pad + (sz.x - lsz.x) * 0.5
		for g in ts.shaped_text_get_glyphs(lrid):
			var gd: Dictionary = g
			var frid: RID = gd.get("font_rid", RID())
			var gi := int(gd.get("index", 0))
			var adv := float(gd.get("advance", 0.0))
			var off: Vector2 = gd.get("offset", Vector2.ZERO)
			var gsz := Vector2i(int(gd.get("font_size", 64)), 0)
			for _r in maxi(int(gd.get("repeat", 1)), 1):
				if frid.is_valid() and gi > 0:
					ts.font_render_glyph(frid, gsz, gi)
					put.append([frid, gsz, gi, Vector2(x + off.x, base + off.y)])
				x += adv
		y += lsz.y
	# проход 2: перенос из страниц кэша (они уже дописаны) в картинку
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var pages := {}
	for e in put:
		var frid: RID = e[0]
		var gsz: Vector2i = e[1]
		var gi: int = e[2]
		var ti := ts.font_get_glyph_texture_idx(frid, gsz, gi)
		if ti < 0:
			continue
		var pk := "%d|%d|%d" % [frid.get_id(), gsz.x, ti]
		if not pages.has(pk):
			var src := ts.font_get_texture_image(frid, gsz, ti)
			if src == null:
				continue
			var s2 := src.duplicate() as Image
			if s2.is_compressed():
				s2.decompress()
			s2.convert(Image.FORMAT_RGBA8)
			pages[pk] = s2
		var uv := ts.font_get_glyph_uv_rect(frid, gsz, gi)
		var go := ts.font_get_glyph_offset(frid, gsz, gi)
		if uv.size.x <= 0.0 or uv.size.y <= 0.0:
			continue
		var at: Vector2 = e[3]
		img.blend_rect(pages[pk], Rect2i(uv), Vector2i(roundi(at.x + go.x), roundi(at.y + go.y)))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_text_tex[key] = tex
	return tex


static func graffiti(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var key := String(d.get("key", "graf.g05"))
	# надпись «от руки»: заранее нарисованная текстура (tools/tex/make_graffiti.py) плоской наклейкой на стене
	var stem := "arrow" if key == "graf.arrow" else key.split(".", true, 1)[1]
	var tname := "graf_%s_%s" % [stem, "en" if Loc.is_en(key) else "ru"]
	if ResourceLoader.exists("res://tex/%s.png" % tname):
		var tx := Mats.tex(tname)
		var k := 0.0021 if key != "graf.arrow" else 0.0024
		var mat := decal_mat(tname, {"tex": tname, "tex_color": 1.0, "tint": Color(1, 1, 1, 0.94)})
		var q := quad(n, Vector2(tx.get_width(), tx.get_height()) * k, Vector3(float(d.get("along", 0.0)), 0, 0.012), mat)
		q.rotation.z = (float(absi(hash(d.p)) % 100) / 100.0 - 0.5) * 0.08 + (PI if bool(d.get("flip", false)) else 0.0)
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return n
	var txt := ""
	if key == "graf.arrow":
		txt = "<---" if bool(d.get("flip", false)) else "--->"
	else:
		txt = Loc.t(key)
	var inks := [Color(0.16, 0.1, 0.06), Color(0.08, 0.07, 0.07), Color(0.32, 0.06, 0.04), Color(0.1, 0.12, 0.2)]
	var ink: Color = inks[absi(hash(key)) % inks.size()]
	var lb := label(txt, font_hand(), 0.0042 if key != "graf.arrow" else 0.007, ink, 0, 400.0)
	lb.position = Vector3(float(d.get("along", 0.0)), 0, 0.012)
	lb.rotation.z = (float(absi(hash(d.p)) % 100) / 100.0 - 0.5) * 0.12
	n.add_child(lb)
	return n


static func cable_tag(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var dist := int(d.get("dist", 0))
	var txt := ""
	if bool(d.get("floor", false)):
		var t := Node3D.new()
		n.add_child(t)
		box(t, Vector3(0.12, 0.004, 0.5), Vector3(0, 0.003, 0), mc(Color(0.9, 0.75, 0.15), "metal", 0.1))
		box(t, Vector3(0.28, 0.004, 0.12), Vector3(0, 0.003, -0.25), mc(Color(0.9, 0.75, 0.15), "metal", 0.1), Vector3(0, PI * 0.25, 0))
		var lb0 := label("%d M" % dist, font_sign(), 0.003, Color(0.1, 0.1, 0.1))
		lb0.rotation = Vector3(-PI * 0.5, 0, 0)
		lb0.position = Vector3(0.18, 0.006, 0.1)
		n.add_child(lb0)
		return n
	# на стене: жёлтая лента со стрелкой к станции
	var side := int(d.get("side", 0))
	var to := int(d.get("dir", 0))
	box(n, Vector3(0.42, 0.11, 0.006), Vector3(0, 0, 0.004), mc(Color(0.9, 0.75, 0.15), "metal", 0.1))
	# стрелка: направление к станции относительно стены
	var o_side: Vector2i = LD.DIRS[side]
	var o_to: Vector2i = LD.DIRS[to]
	var right := Vector2i(-o_side.y, o_side.x)
	var arrow := "<--"
	if o_to == -o_side:
		arrow = "v"
	elif o_to == o_side:
		arrow = "^"
	elif o_to == right:
		arrow = "-->"
	else:
		arrow = "<--"
	txt = "KV31 %s %dM" % [arrow, dist]
	var lb := label(txt, font_sign(), 0.0022, Color(0.08, 0.07, 0.06))
	lb.position = Vector3(0, 0, 0.009)
	n.add_child(lb)
	return n


static func sign_board(d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var s := float(d.get("size", 1.0))
	box(n, Vector3(1.3 * s, 0.5 * s, 0.02), Vector3(0, 0, 0.012), mc(Color(0.62, 0.62, 0.59), "metal", 0.35, {"gloss": 40.0, "spec": 0.1}))
	var lb := label(Loc.t(String(d.get("key", "sign.station"))), font_sign(), 0.0034 * s, Color(0.07, 0.08, 0.1), 0, 340.0)
	lb.position = Vector3(0, 0, 0.0225)
	n.add_child(lb)
	return n


static func note(cx: Node3D, d: Dictionary) -> Node3D:
	var n := Node3D.new()
	var key := String(d.get("key", "note.n01"))
	if bool(d.get("clip", false)) or key.begins_with("note.a_") or key == "note.u01" or key == "note.u04":
		if model(n, "clipboard", Vector3.ZERO, 0.0, 1.0, false) != null:
			box(n, Vector3(0.2, 0.004, 0.27), Vector3(0, 0.03, 0.01), mc(Color(0.95, 0.93, 0.86), "paper", 1.0))
			interactable(n, Vector3(0.5, 0.25, 0.5), Vector3(0, 0.1, 0), "ui.read", func() -> void:
				Game.show_note(key))
			return n
	box(n, Vector3(0.21, 0.004, 0.29), Vector3(0, 0.003, 0), mc(Color(0.95, 0.93, 0.86), "paper", 1.0))
	box(n, Vector3(0.21, 0.004, 0.29), Vector3(0.03, 0.006, 0.02), mc(Color(0.92, 0.9, 0.82), "paper", 1.0), Vector3(0, 0.2, 0))
	interactable(n, Vector3(0.5, 0.25, 0.5), Vector3(0, 0.1, 0), "ui.read", func() -> void:
		Game.show_note(key))
	return n


static func stain(d: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var s := float(d.get("s", 1.4))
	var mat: Material
	if bool(d.get("burn", false)):
		mat = decal_mat("burn", {"radial": 1.0, "tint": Color(0.02, 0.02, 0.015, 0.75)})
	elif bool(d.get("tire", false)):
		mat = decal_mat("tire", {"stripes": 1.0, "tint": Color(0.03, 0.03, 0.03, 0.65)})
		s = 2.5
	elif bool(d.get("wet", false)):
		mat = decal_mat("wet", {"radial": 1.0, "tint": Color(0.05, 0.045, 0.02, 0.5), "sheen": 1.0})
	else:
		mat = decal_mat("dirt", {"radial": 1.0, "tint": Color(0.18, 0.14, 0.06, 0.35)})
	var ln := float(d.get("len", s * 2.4)) if bool(d.get("tire", false)) else s
	if bool(d.get("tire", false)) and d.has("s"):
		s = float(d.s)
	var q := quad(n, Vector2(s, ln), Vector3(0, 0.006, 0), mat, Vector3(-PI * 0.5, 0, 0))
	q.set_instance_shader_parameter("seed", rng.randf() * 10.0)
	return n


## Плесень и потёки на обоях: четыре разных силуэта (колония, налёт, потёк воды с «приливом», пятна),
## размер и поворот случайны; потёк стоит прямо (вода течёт вниз), остальные — с наклоном
static func mold_patch(d: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var s := float(d.get("s", 1.0))
	var v := clampi(int(d.get("v", rng.randi_range(0, 3))), 0, 3)
	var tname := "prop_mold_%s" % "abcd"[v]
	if not Mats.has_tex(tname):
		tname = "mold"
	var alpha: float = [0.8, 0.7, 0.75, 0.8][v]
	var mat := decal_mat("mold_" + tname, {"tex": tname, "tint": Color(1, 1, 1, alpha), "tex_color": 1.0})
	var asp := rng.randf_range(0.8, 1.2)
	var rot := rng.randf_range(-0.5, 0.5) + (PI if rng.randf() < 0.5 else 0.0)
	if v == 2:
		asp = rng.randf_range(1.15, 1.5)
		rot = rng.randf_range(-0.05, 0.05)
		s *= 0.9
	elif v == 0:
		s *= 0.75
	var q := quad(n, Vector2(s, s * asp), Vector3(float(d.get("along", 0.0)), 0, 0.012), mat, Vector3(0, 0, rot))
	q.set_instance_shader_parameter("seed", rng.randf())
	return n


static var _sheets: Array = []


## Лист A4, сложенный втрое и расправленный: три панели с изломом по сгибам, один угол чуть загнут.
## UV — по листу (картинка prop_paper_* целиком)
static func _sheet_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var w := 0.21
	var h := 0.297
	var nx := 5
	var nz := 10
	var f1 := rng.randf_range(0.003, 0.009)
	var f2 := rng.randf_range(0.0, 0.006)
	var curl := rng.randf_range(0.004, 0.02)
	var hgt := func(u: float, v: float) -> float:
		var tent := f1 * maxf(0.0, 1.0 - absf(v - 1.0 / 3.0) * 3.0) + f2 * maxf(0.0, 1.0 - absf(v - 2.0 / 3.0) * 3.0)
		var c := curl * pow(maxf(0.0, (u + v) - 1.4) / 0.6, 2.0)
		return tent + c
	var rings := []
	var nrms := []
	var uvs := []
	for j in nz + 1:
		var row := PackedVector3Array()
		var rn := PackedVector3Array()
		var ru := PackedVector2Array()
		for i in nx + 1:
			var u := float(i) / nx
			var v := float(j) / nz
			var y: float = hgt.call(u, v)
			row.append(Vector3((u - 0.5) * w, y, (v - 0.5) * h))
			var e := 0.02
			var dx: float = (float(hgt.call(minf(u + e, 1.0), v)) - float(hgt.call(maxf(u - e, 0.0), v))) / (2.0 * e * w)
			var dz: float = (float(hgt.call(u, minf(v + e, 1.0))) - float(hgt.call(u, maxf(v - e, 0.0)))) / (2.0 * e * h)
			rn.append(Vector3(-dx, 1.0, -dz).normalized())
			ru.append(Vector2(u, v))
		rings.append(row)
		nrms.append(rn)
		uvs.append(ru)
	return ring_mesh(rings, nrms, uvs)


## Бумаги на полу: листы с печатью (машинопись, бланк, распечатка, исписанный), помятые, а не плоские плашки
static func papers(rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	if _sheets.is_empty():
		var r0 := RandomNumberGenerator.new()
		r0.seed = 1990
		for k in 4:
			_sheets.append(_sheet_mesh(r0))
	for k in rng.randi_range(1, 4):
		var v := rng.randi_range(0, 3)
		var mat := Mats.prop("paper_sheet_%d" % v, {"tex": "prop_paper_%s" % "abcd"[v], "tex_mix": 1.0, "color": Vector3(0.84, 0.83, 0.79),
			"albedo_cap": 0.6, "gloss": 18.0, "spec": 0.03, "ds": true})
		mesh_node(n, _sheets[rng.randi_range(0, _sheets.size() - 1)], mat, Vector3(rng.randf_range(-0.4, 0.4), 0.003 + k * 0.0015, rng.randf_range(-0.4, 0.4)),
			Vector3(0, rng.randf() * TAU, 0))
	return n


static func grass_patch(d: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var s := float(d.get("s", 3.0))
	var mat := decal_mat("grass", {"radial": 1.0, "tint": Color(0.3, 0.42, 0.16, 0.8)})
	var q := quad(n, Vector2(s, s), Vector3(0, 0.007, 0), mat, Vector3(-PI * 0.5, 0, 0))
	q.set_instance_shader_parameter("seed", rng.randf() * 5.0)
	var gm := mc(Color(0.32, 0.45, 0.18), "leaves", 0.3)
	for k in 26:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * s * 0.38
		var hgt := rng.randf_range(0.06, 0.16)
		box(n, Vector3(0.012, hgt, 0.004), Vector3(cos(a) * r, hgt * 0.5, sin(a) * r), gm, Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, 0))
	return n


# ------------------------------------------------------------ Async

static func async_item(cx: Node3D, what: String, d: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var olive := mc(Color(0.24, 0.27, 0.22), "metal", 0.4)
	var blk := m_black()
	match what:
		"lamp_stand", "lamp_stand_off":
			var on := what == "lamp_stand"
			for k in 3:
				var a := k * TAU / 3
				rod(n, Vector3(0, 1.1, 0), Vector3(cos(a) * 0.45, 0, sin(a) * 0.45), 0.015, blk, 4)
			rod(n, Vector3(0, 1.1, 0), Vector3(0, 1.66, 0), 0.02, blk, 6)
			cyl(n, 0.03, 0.03, 0.08, Vector3(0, 1.1, 0), blk, Vector3.ZERO, 8)
			# скоба-вилка (не наклоняется), в ней на оси — прожектор (свет сетки L_ASYNC — в центре клетки
			# на 1,9 м, там же головка); светится только стекло самой модели — линза спереди, сзади её не видно
			var pivot := 1.86
			for sx in [-0.2, 0.2]:
				box(n, Vector3(0.025, 0.24, 0.045), Vector3(sx, pivot - 0.09, 0.0), blk)
				cyl(n, 0.03, 0.03, 0.03, Vector3(sx * 0.93, pivot, 0.0), blk, Vector3(0, 0, PI * 0.5), 10)
			box(n, Vector3(0.425, 0.03, 0.05), Vector3(0, pivot - 0.2, 0.0), blk)
			var head := Node3D.new()
			n.add_child(head)
			head.position = Vector3(0, pivot, 0)
			head.rotation.x = -0.5
			var sl := model(head, "portable_searchlight", Vector3(0, -0.02, 0.0), PI, 2.0, false)
			if sl != null:
				if on:
					var lens := m_emit(Color(1.0, 0.96, 0.86), 2.4, true)
					for mi in Models._meshes(sl):
						var m := mi as MeshInstance3D
						for i in m.mesh.get_surface_count():
							var src := m.mesh.surface_get_material(i)
							if src != null and src.resource_name.to_lower().contains("glass"):
								m.set_surface_override_material(i, lens)
			else:
				cyl(head, 0.14, 0.16, 0.3, Vector3.ZERO, blk, Vector3(PI * 0.5, 0, 0), 14)
				cyl(head, 0.13, 0.13, 0.01, Vector3(0, 0, -0.152), m_emit(Color(1.0, 0.96, 0.86), 2.4, true) if on else mc(Color(0.5, 0.5, 0.48), "metal", 0.2),
					Vector3(PI * 0.5, 0, 0), 14)
			if bool(d.get("fallen", false)):
				n.rotation.z = 1.35
				n.position.y = 0.2
				n.set_meta("keep_rot", false)
			rod(n, Vector3(0, 0.02, 0), Vector3(0.9, 0.02, 0.6), 0.012, blk, 4)
		"case", "case_open":
			if model(n, "metal_toolbox" if what == "case" else "industrial_pastic_container", Vector3.ZERO, 0.0, 1.3) != null:
				return n
			box(n, Vector3(0.7, 0.32, 0.45), Vector3(0, 0.16, 0), olive)
			if what == "case_open":
				box(n, Vector3(0.7, 0.06, 0.45), Vector3(0, 0.45, -0.25), olive, Vector3(-1.2, 0, 0))
				box(n, Vector3(0.6, 0.04, 0.35), Vector3(0, 0.3, 0), mc(Color(0.12, 0.12, 0.12), "fabric", 0.8))
			else:
				box(n, Vector3(0.2, 0.04, 0.05), Vector3(0, 0.34, 0), blk)
		"crate":
			if model(n, "wooden_military_crate" if rng.randf() < 0.6 else "old_military_crate") != null:
				return n
			box(n, Vector3(0.8, 0.6, 0.8), Vector3(0, 0.3, 0), mc(Color(0.5, 0.42, 0.3), "wood", 0.8))
			var lb := label("ASYNC  KV31", font_sign(), 0.0025, Color(0.1, 0.1, 0.1))
			lb.position = Vector3(0, 0.35, 0.41)
			n.add_child(lb)
		"table":
			box(n, Vector3(1.8, 0.04, 0.75), Vector3(0, 0.76, 0), mc(Color(0.75, 0.75, 0.72), "metal", 0.3))
			for sx in [-0.8, 0.8]:
				rod(n, Vector3(sx, 0, -0.3), Vector3(sx, 0.75, 0.3), 0.015, blk, 4)
				rod(n, Vector3(sx, 0, 0.3), Vector3(sx, 0.75, -0.3), 0.015, blk, 4)
			for k in 2:
				var mon := Node3D.new()
				n.add_child(mon)
				mon.position = Vector3(-0.45 + k * 0.8, 0.78, -0.1)
				mon.rotation.y = (k - 0.5) * 0.4
				box(mon, Vector3(0.42, 0.36, 0.4), Vector3(0, 0.2, 0), mc(Color(0.75, 0.73, 0.66), "metal", 0.3))
				box(mon, Vector3(0.34, 0.26, 0.01), Vector3(0, 0.21, 0.2), mc(Color(0.2, 0.6, 0.3), "noise", 1.0, {"emit": 0.7, "emit_color": Vector3(0.2, 0.9, 0.4)}))
			box(n, Vector3(0.45, 0.03, 0.15), Vector3(0.1, 0.79, 0.22), mc(Color(0.75, 0.73, 0.66), "metal", 0.3))
			collider(n, Vector3(1.8, 0.8, 0.75), Vector3(0, 0.4, 0))
		"spool":
			cyl(n, 0.4, 0.4, 0.05, Vector3(0, 0.4, -0.2), mc(Color(0.55, 0.42, 0.25), "wood", 0.8), Vector3(PI * 0.5, 0, 0), 14)
			cyl(n, 0.4, 0.4, 0.05, Vector3(0, 0.4, 0.2), mc(Color(0.55, 0.42, 0.25), "wood", 0.8), Vector3(PI * 0.5, 0, 0), 14)
			cyl(n, 0.3, 0.3, 0.36, Vector3(0, 0.4, 0), mc(Color(0.75, 0.32, 0.08), "metal", 0.3), Vector3(PI * 0.5, 0, 0), 14)
		"generator":
			if model(n, "portable_generator", Vector3.ZERO, 0.0, 1.1) == null:
				box(n, Vector3(0.9, 0.6, 0.6), Vector3(0, 0.35, 0), mc(Color(0.7, 0.55, 0.12), "metal", 0.4))
			var se := SoundEmitter.new()
			se.snd = "generator"
			se.every = 0.0
			se.vol = -10.0
			se.position = Vector3(0, 0.5, 0)
			n.add_child(se)
		"board":
			# белая маркерная доска: эмаль с бликом, слегка затёртая
			box(n, Vector3(1.4, 0.95, 0.03), Vector3(0, 1.35, 0), mc(Color(0.64, 0.64, 0.62), "metal", 0.25, {"gloss": 70.0, "spec": 0.18}))
			for sx in [-0.65, 0.65]:
				rod(n, Vector3(sx, 0, 0), Vector3(sx, 1.8, 0), 0.02, blk, 4)
			var lb2 := label(Loc.t("sign.board"), font_hand(), 0.0011, Color(0.1, 0.12, 0.35), 0, 1150.0)
			lb2.position = Vector3(0, 1.4, 0.0165)
			n.add_child(lb2)
		"rover":
			_rover(n)
		"barrier":
			model(n, "concrete_road_barrier")
		"gasmask":
			model(n, "old_gas_mask", Vector3(0, 0.08, 0), 0.0, 1.0, false)
			n.set_meta("tilt", 1.4)
		"cones":
			cyl(n, 0.02, 0.15, 0.5, Vector3(0, 0.25, 0), mc(Color(0.95, 0.4, 0.08), "metal", 0.1), Vector3.ZERO, 10)
			box(n, Vector3(0.32, 0.03, 0.32), Vector3(0, 0.015, 0), mc(Color(0.95, 0.4, 0.08), "metal", 0.1))
		"tripod":
			for k2 in 3:
				var a2 := k2 * TAU / 3
				rod(n, Vector3(0, 1.3, 0), Vector3(cos(a2) * 0.4, 0, sin(a2) * 0.4), 0.012, blk, 4)
			box(n, Vector3(0.14, 0.15, 0.32), Vector3(0, 1.4, 0), mc(Color(0.15, 0.15, 0.15), "metal", 0.3))
			cyl(n, 0.05, 0.05, 0.1, Vector3(0, 1.41, 0.2), blk, Vector3(PI * 0.5, 0, 0), 10)
			sph(n, 0.012, Vector3(0.05, 1.49, 0.14), m_emit(Color(1, 0.05, 0.05), 3.0))
		"radio":
			if model(n, "vintage_radio_transceiver", Vector3.ZERO, 0.0, 0.8, false) == null:
				box(n, Vector3(0.32, 0.22, 0.16), Vector3(0, 0.11, 0), olive)
				rod(n, Vector3(0.12, 0.22, 0), Vector3(0.18, 0.75, -0.05), 0.006, blk, 4)
			box(n, Vector3(0.06, 0.03, 0.01), Vector3(-0.1, 0.25, 0.16), m_emit(Color(0.9, 0.6, 0.2), 1.2))
			var rad := RadioPlayer.new()
			rad.position = Vector3(0, 0.2, 0)
			n.add_child(rad)
			interactable(n, Vector3(0.6, 0.5, 0.6), Vector3(0, 0.2, 0), "ui.radio", rad.toggle)
		"motioncam":
			if model(n, "security_camera_01", Vector3(0, -0.1, 0.15), 0.0, 1.0, false) == null:
				box(n, Vector3(0.14, 0.12, 0.25), Vector3(0, 0, 0.18), mc(Color(0.8, 0.8, 0.76), "metal", 0.3))
				rod(n, Vector3(0, 0, 0), Vector3(0, 0, 0.1), 0.015, blk, 4)
			var led := sph(n, 0.012, Vector3(0.04, 0.03, 0.31), m_emit(Color(1, 0.05, 0.05), 3.0))
			led.set_meta("blink", true)
		"winch":
			# стальная рама над ямой, барабан, трос вниз
			var steel := mc(Color(0.4, 0.42, 0.42), "metal", 0.6)
			var hw := LD.C * 0.5 + 0.1
			for sx in [-hw, hw]:
				for sz in [-hw, hw]:
					box(n, Vector3(0.1, 2.4, 0.1), Vector3(sx, 1.2, sz), steel)
			box(n, Vector3(hw * 2 + 0.1, 0.12, 0.12), Vector3(0, 2.4, -hw), steel)
			box(n, Vector3(hw * 2 + 0.1, 0.12, 0.12), Vector3(0, 2.4, hw), steel)
			box(n, Vector3(0.12, 0.12, hw * 2 + 0.1), Vector3(0, 2.42, 0), steel)
			cyl(n, 0.16, 0.16, 0.5, Vector3(hw - 0.4, 2.25, 0), mc(Color(0.7, 0.55, 0.12), "metal", 0.4), Vector3(0, 0, PI * 0.5), 12)
			rod(n, Vector3(0, 2.4, 0), Vector3(0, -6.5, 0), 0.012, blk, 4)
			for k3 in 4:
				box(n, Vector3(LD.C, 0.04, 0.4), Vector3(0, 0.02, -hw - 0.25 + (k3 % 2) * (hw * 2 + 0.5)), mc(Color(0.45, 0.42, 0.35), "wood", 0.6))
			var lbw := label("WINCH 2 / 14D\nDO NOT DESCEND\nWITHOUT TETHER", font_sign(), 0.0022, Color(0.85, 0.1, 0.08))
			lbw.position = Vector3(0, 1.6, -hw - 0.06)
			n.add_child(lbw)
		"ladder":
			var rope := mc(Color(0.55, 0.45, 0.3), "fabric", 0.6)
			for sx2 in [-0.22, 0.22]:
				rod(n, Vector3(sx2, 0.0, 0.0), Vector3(sx2, 9.5, 0.0), 0.015, rope, 4)
			for k4 in 28:
				box(n, Vector3(0.48, 0.03, 0.05), Vector3(0, 0.25 + k4 * 0.33, 0), mc(Color(0.5, 0.38, 0.25), "wood", 0.7))
			var to := String(d.get("to", "winch_0"))
			interactable(n, Vector3(0.7, 2.0, 0.5), Vector3(0, 1.0, 0), "ui.climb", func() -> void:
				if cx.has_method("climb_ladder"):
					cx.climb_ladder(to))
	return n


## Гусеничный разведчик Async (вроде роботов-сапёров 80-х): оливковый корпус на двух гусеницах, мачта с
## камерой на поворотной головке и фарами, катушка кабеля-привязи сзади, антенна, трафарет и полосы
static func _rover(p: Node3D) -> void:
	var paint := mc(Color(0.33, 0.35, 0.27), "metal", 0.55, {"gloss": 34.0, "spec": 0.12})
	var dark := mc(Color(0.06, 0.06, 0.058), "metal", 0.4, {"gloss": 26.0, "spec": 0.08})
	var tread := mc(Color(0.055, 0.055, 0.05), "fiber", 0.7)
	var alu := mc(Color(0.52, 0.53, 0.52), "metal", 0.6, {"gloss": 60.0, "spec": 0.28})
	var glass := mc(Color(0.03, 0.035, 0.04), "metal", 0.0, {"gloss": 160.0, "spec": 0.6})
	# гусеницы: лента «стадионом» вокруг ведущего и направляющего колёс, внутри — опорные катки
	var rr := 0.085
	var zf := 0.26
	for sx in [-0.245, 0.245]:
		var pts := PackedVector3Array()
		var steps := 12
		for k in steps + 1:
			var a := PI * 0.5 + PI * float(k) / steps
			pts.append(Vector3(sx, rr + sin(a) * rr, -zf + cos(a) * rr))
		for k in steps + 1:
			var a := -PI * 0.5 + PI * float(k) / steps
			pts.append(Vector3(sx, rr + sin(a) * rr, zf + cos(a) * rr))
		pts.append(pts[0])
		var rx := PackedFloat32Array()
		var rz := PackedFloat32Array()
		for k in pts.size():
			rx.append(0.05)
			rz.append(0.013)
		mesh_node(p, loft(pts, rx, rz, 10, Vector3(1, 0, 0)), tread)
		for zz in [-zf, zf]:
			cyl(p, 0.072, 0.072, 0.075, Vector3(sx, rr, zz), dark, Vector3(0, 0, PI * 0.5), 14)
			cyl(p, 0.035, 0.035, 0.08, Vector3(sx, rr, zz), alu, Vector3(0, 0, PI * 0.5), 10)
		for k2 in 3:
			cyl(p, 0.045, 0.045, 0.06, Vector3(sx, 0.05, -0.13 + k2 * 0.13), dark, Vector3(0, 0, PI * 0.5), 12)
		# крыло над гусеницей
		box(p, Vector3(0.12, 0.012, 0.66), Vector3(sx, 0.19, 0), paint)
	# корпус: низ между гусеницами, скошенный нос, задний ящик с электроникой
	box(p, Vector3(0.38, 0.13, 0.58), Vector3(0, 0.14, 0), paint)
	box(p, Vector3(0.38, 0.012, 0.2), Vector3(0, 0.205, 0.32), paint, Vector3(0.55, 0, 0))
	var hz := Mats.prop("rover_hazard", {"tex": "hazard", "tex_mix": 1.0, "box_uv": 1.0, "world_scale": Vector2(0.4, 0.1), "albedo_cap": 0.62, "gloss": 30.0, "spec": 0.08})
	box(p, Vector3(0.3, 0.004, 0.08), Vector3(0, 0.212, 0.335), hz, Vector3(0.55, 0, 0))
	box(p, Vector3(0.34, 0.12, 0.24), Vector3(0, 0.27, -0.14), paint)
	for k3 in 5:
		box(p, Vector3(0.006, 0.07, 0.012), Vector3(0.171, 0.27, -0.22 + k3 * 0.035), dark)
	# ручки для переноски
	for sz in [-0.24, 0.0]:
		rod(p, Vector3(-0.12, 0.33, sz), Vector3(-0.12, 0.38, sz + 0.03), 0.008, alu, 6)
		rod(p, Vector3(0.12, 0.33, sz), Vector3(0.12, 0.38, sz + 0.03), 0.008, alu, 6)
		rod(p, Vector3(-0.12, 0.38, sz + 0.03), Vector3(0.12, 0.38, sz + 0.03), 0.008, alu, 6)
	# катушка кабеля-привязи сзади
	cyl(p, 0.09, 0.09, 0.02, Vector3(-0.1, 0.26, -0.31), dark, Vector3(0, 0, PI * 0.5), 14)
	cyl(p, 0.09, 0.09, 0.02, Vector3(0.1, 0.26, -0.31), dark, Vector3(0, 0, PI * 0.5), 14)
	cyl(p, 0.07, 0.07, 0.18, Vector3(0, 0.26, -0.31), mc(Color(0.75, 0.32, 0.08), "metal", 0.3), Vector3(0, 0, PI * 0.5), 14)
	rod(p, Vector3(0, 0.19, -0.38), Vector3(0.05, 0.012, -0.75), 0.008, mc(Color(0.75, 0.32, 0.08), "metal", 0.3), 5)
	# мачта и головка с камерой и двумя фарами
	cyl(p, 0.05, 0.06, 0.04, Vector3(0, 0.23, 0.12), dark, Vector3.ZERO, 12)
	rod(p, Vector3(0, 0.23, 0.12), Vector3(0, 0.56, 0.12), 0.016, alu, 8)
	var hd := Node3D.new()
	p.add_child(hd)
	hd.position = Vector3(0, 0.6, 0.12)
	hd.rotation = Vector3(0.15, 0.3, 0)
	box(hd, Vector3(0.11, 0.08, 0.15), Vector3.ZERO, paint)
	cyl(hd, 0.03, 0.034, 0.06, Vector3(0, 0, 0.1), dark, Vector3(PI * 0.5, 0, 0), 12)
	cyl(hd, 0.024, 0.024, 0.004, Vector3(0, 0, 0.131), glass, Vector3(PI * 0.5, 0, 0), 12)
	for sx2 in [-0.085, 0.085]:
		cyl(hd, 0.025, 0.022, 0.05, Vector3(sx2, 0.0, 0.03), dark, Vector3(PI * 0.5, 0, 0), 10)
		cyl(hd, 0.019, 0.019, 0.003, Vector3(sx2, 0.0, 0.056), mc(Color(0.6, 0.6, 0.55), "metal", 0.0, {"gloss": 120.0, "spec": 0.5}), Vector3(PI * 0.5, 0, 0), 10)
	var led := sph(hd, 0.007, Vector3(0.04, 0.045, 0.05), m_emit(Color(1, 0.1, 0.05), 2.0))
	led.set_meta("blink", true)
	# антенна-хлыст
	rod(p, Vector3(-0.14, 0.33, -0.2), Vector3(-0.17, 0.95, -0.24), 0.003, dark, 4)
	sph(p, 0.008, Vector3(-0.17, 0.95, -0.24), dark, Vector3.ONE, 6)
	# трафарет на борту
	var lb := label("ASYNC  R-2", font_sign(), 0.0012, Color(0.85, 0.82, 0.7))
	lb.position = Vector3(0.1905, 0.27, -0.14)
	lb.rotation.y = PI * 0.5
	p.add_child(lb)
	collider(p, Vector3(0.6, 0.4, 0.75), Vector3(0, 0.2, 0))


const PORTAL_SHADER := preload("res://src/shaders/fx_portal.gdshader")
const NULL_SHADER := preload("res://src/shaders/fx_null.gdshader")


## Порог Async: стальной портал в проёме северной стены (проём — вся клетка, 2,4 м; за стеной клетка-пустота).
## Узел стоит на лице стены, локальная −Z — в стену. Рама выступает в комнату на 0,16 м, внутри — короткий
## стальной тамбур глубиной 1,4 м; в глубине — светящаяся зеленовато-белая пелена в несколько слоёв (fx_portal),
## свет от неё ложится на стенки тамбура (свечение по градиенту глубины). Табличка — на перемычке под потолком.
static func threshold(cx: Node3D, d := {}) -> Node3D:
	var n := Node3D.new()
	var steel := mc(Color(0.27, 0.29, 0.28), "metal", 0.45, {"gloss": 40.0, "spec": 0.16})
	var bolt := mc(Color(0.55, 0.45, 0.16), "metal", 0.4, {"gloss": 50.0, "spec": 0.2})
	var ceil_h := clampf(float(d.get("ceil", 2.7)), 2.5, 3.2)
	var ow := 2.0          # ширина проёма в свету
	var oh := 2.2          # высота проёма в свету
	var dep := 1.4         # глубина тамбура
	var fw := 0.32         # ширина стойки рамы
	var fz := 0.16         # вынос рамы в комнату
	# рама: стойки закрывают торцы стены по бокам проёма, перемычка — до потолка
	for s in [-1.0, 1.0]:
		var x0: float = s * (ow * 0.5 + fw * 0.5)
		box(n, Vector3(fw, oh + 0.05, 0.32), Vector3(x0, (oh + 0.05) * 0.5, fz - 0.16), steel)
		# наличник по стене и рёбра жёсткости
		box(n, Vector3(0.06, oh, 0.02), Vector3(x0 + s * (fw * 0.5 - 0.03), oh * 0.5, fz + 0.01), steel)
		for k in 6:
			var y := 0.25 + k * 0.36
			for bx in [-0.08, 0.08]:
				cyl(n, 0.018, 0.022, 0.025, Vector3(x0 + bx, y, fz + 0.012), bolt, Vector3(PI * 0.5, 0, 0), 8)
		# цоколь стойки
		box(n, Vector3(fw + 0.06, 0.12, 0.34), Vector3(x0, 0.06, fz - 0.15), mc(Color(0.18, 0.18, 0.17), "metal", 0.5))
	var head_h := ceil_h - oh
	box(n, Vector3(ow + fw * 2.0 + 0.4, head_h, 0.32), Vector3(0, oh + head_h * 0.5, fz - 0.16), steel)
	for k in 8:
		cyl(n, 0.018, 0.022, 0.025, Vector3(-1.2 + k * (2.4 / 7.0), oh + head_h - 0.1, fz + 0.012), bolt, Vector3(PI * 0.5, 0, 0), 8)
	# табличка на перемычке: белая эмаль, красные буквы — под потолком, видна из зала
	var plate_w := 1.5
	box(n, Vector3(plate_w, 0.26, 0.012), Vector3(0, oh + head_h * 0.5 - 0.02, fz + 0.006), mc(Color(0.82, 0.8, 0.74), "metal", 0.3, {"gloss": 50.0, "spec": 0.12}))
	var lb := label(Loc.t("sign.threshold"), font_sign(), 0.0031, Color(0.8, 0.08, 0.06))
	var lm := lb as MeshInstance3D
	if lm != null and lm.mesh is QuadMesh:
		var qs := (lm.mesh as QuadMesh).size
		var k2 := minf((plate_w - 0.12) / maxf(qs.x, 0.01), 0.2 / maxf(qs.y, 0.01))
		if k2 < 1.0:
			lm.scale = Vector3(k2, k2, 1.0)
	lb.position = Vector3(0, oh + head_h * 0.5 - 0.02, fz + 0.0125)
	n.add_child(lb)
	# тамбур: стальные стенки, пол-рифлёнка, потолок; светятся отражённым светом пелены (ярче к глубине)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([Color(0.05, 0.08, 0.06), Color(0.3, 0.45, 0.35), Color(0.85, 1.0, 0.9)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 64
	gt.height = 4
	var lining := Mats.prop("threshold_lining", {"tex": "metal", "tex_mix": 0.7, "color": Vector3(0.24, 0.27, 0.25), "emit": 0.3,
		"emit_color": Vector3(0.55, 0.95, 0.7), "gloss": 30.0, "spec": 0.1})
	lining.set_shader_parameter("emit_tex", gt)
	lining.set_shader_parameter("has_emit_tex", 1.0)
	var floor_m := Mats.prop("threshold_floor", {"tex": "metal", "tex_mix": 0.8, "color": Vector3(0.2, 0.22, 0.2), "emit": 0.24,
		"emit_color": Vector3(0.55, 0.95, 0.7), "gloss": 40.0, "spec": 0.14})
	floor_m.set_shader_parameter("emit_tex", gt)
	floor_m.set_shader_parameter("has_emit_tex", 1.0)
	# квады: U вдоль глубины (0 — у комнаты, 1 — у пелены); оси заданы базисом (X — в глубину, Z — нормаль)
	var ln := dep - 0.15
	var zc := -0.15 - ln * 0.5
	for s2 in [-1.0, 1.0]:
		var wq := quad(n, Vector2(ln, oh), Vector3(s2 * ow * 0.5, oh * 0.5, zc), lining)
		wq.basis = Basis(Vector3(0, 0, -1), Vector3(0, -s2, 0), Vector3(-s2, 0, 0))
	var cq := quad(n, Vector2(ln, ow), Vector3(0, oh, zc), lining)
	cq.basis = Basis(Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, -1, 0))
	var fq := quad(n, Vector2(dep + fz, ow), Vector3(0, 0.004, (fz - dep) * 0.5), floor_m)
	fq.basis = Basis(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0))
	# пелена: глухой светящийся задник (ярче к середине) и прозрачные слои в глубине (параллакс — видна глубина)
	var rg := Gradient.new()
	rg.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	rg.colors = PackedColorArray([Color(1.0, 1.0, 1.0), Color(0.62, 0.72, 0.66), Color(0.3, 0.38, 0.33)])
	var rt := GradientTexture2D.new()
	rt.gradient = rg
	rt.fill = GradientTexture2D.FILL_RADIAL
	rt.fill_from = Vector2(0.5, 0.55)
	rt.fill_to = Vector2(1.05, 0.55)
	rt.width = 64
	rt.height = 64
	var back := Mats.prop("threshold_back", {"tex": "noise", "tex_mix": 0.0, "color": Vector3(0.0, 0.0, 0.0), "emit": 0.24,
		"emit_color": Vector3(0.66, 0.95, 0.76)})
	back.set_shader_parameter("emit_tex", rt)
	back.set_shader_parameter("has_emit_tex", 1.0)
	quad(n, Vector2(ow + 0.02, oh + 0.02), Vector3(0, oh * 0.5, -dep), back)
	for k3 in 4:
		var pm := ShaderMaterial.new()
		pm.shader = PORTAL_SHADER
		pm.set_shader_parameter("noise_tex", Mats.tex("noise"))
		pm.set_shader_parameter("layer", float(k3))
		pm.set_shader_parameter("strength", [0.12, 0.1, 0.085, 0.06][k3])
		quad(n, Vector2(ow, oh), Vector3(0, oh * 0.5, -dep + 0.1 + k3 * 0.3), pm)
	# полосы краской по полу перед порогом: плитка текстуры 4:1 по объектным метрам (полоса ~8 см)
	box(n, Vector3(ow + fw * 2.0 + 0.4, 0.004, 1.2), Vector3(0, 0.004, fz + 0.6), Mats.prop("hazard_floor", {"tex": "hazard", "tex_mix": 1.0, "box_uv": 1.0,
		"world_scale": Vector2(1.4, 0.35), "albedo_cap": 0.66, "gloss": 30.0, "spec": 0.08}))
	# пол и стенки тамбура держат героя (за проёмом — клетка-пустота)
	collider(n, Vector3(ow, 0.2, dep + 0.2), Vector3(0, -0.1, -dep * 0.5))
	for s3 in [-1.0, 1.0]:
		collider(n, Vector3(0.2, oh, dep), Vector3(s3 * (ow * 0.5 + 0.1), oh * 0.5, -dep * 0.5))
	collider(n, Vector3(ow, oh, 0.2), Vector3(0, oh * 0.5, -dep - 0.1))
	var se := SoundEmitter.new()
	se.snd = "threshold_hum"
	se.every = 0.0
	se.vol = -4.0
	se.max_dist = 35.0
	se.position = Vector3(0, 1.2, -0.5)
	n.add_child(se)
	trigger(n, Vector3(ow - 0.3, 2.0, 0.7), Vector3(0, 1.0, -0.45), func() -> void:
		if cx.has_method("enter_threshold"):
			cx.enter_threshold())
	return n


static func null_zone(cx: Node3D, d: Dictionary) -> Node3D:
	var n := Node3D.new()
	# «прореха» в воздухе: оболочка-цилиндр, внутри — преломление фона и мягкое свечение (fx_null.gdshader)
	var sm := ShaderMaterial.new()
	sm.shader = NULL_SHADER
	sm.set_shader_parameter("noise_tex", Mats.tex("noise"))
	var hull := CylinderMesh.new()
	hull.top_radius = 0.8
	hull.bottom_radius = 0.8
	hull.height = 2.5
	hull.radial_segments = 20
	hull.rings = 1
	mesh_node(n, hull, sm, Vector3(0, 1.2, 0)).set_meta("null_core", true)
	# в оболочке своё начало координат: столб — от y0 до y0 + height относительно её центра
	sm.set_shader_parameter("y0", 0.1 - 1.2)
	sm.set_shader_parameter("height", 2.0)
	var mote := mc(Color(0.5, 0.75, 0.6), "metal", 0.0, {"emit": 0.9, "emit_color": Vector3(0.55, 1.0, 0.7)})
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(d.p)
	for k in 14:
		var m := sph(n, 0.007, Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0.1, 2.2), rng.randf_range(-0.6, 0.6)), mote, Vector3.ONE, 4)
		m.set_meta("float", rng.randf() * TAU)
	var anim := NullAnim.new()
	n.add_child(anim)
	var id := String(d.get("id", "null_0"))
	trigger(n, Vector3(0.9, 2.0, 0.9), Vector3(0, 1.0, 0), func() -> void:
		if cx.has_method("enter_null"):
			cx.enter_null(id))
	return n


static func nest(rng: RandomNumberGenerator) -> Node3D:
	# Гнездо Сущности: слипшиеся бугристые комья тёмной массы (мокрые и подсохшие), торчащие изогнутые «рёбра»
	# и волокна, тянущиеся к полу; вокруг — бурая корка и сырость; в массе — остатки снаряжения
	var n := Node3D.new()
	var wet := mc(Color(0.03, 0.028, 0.026), "fiber", 0.55, {"wet": 0.8, "smear": 0.6, "nmap": Mats.tex("fiber_n"), "bump": 1.0})
	var dry := mc(Color(0.075, 0.06, 0.045), "fiber", 0.7, {"wet": 0.15, "nmap": Mats.tex("fiber_n"), "bump": 1.2, "mold": 0.4})
	var flesh := mc(Color(0.075, 0.04, 0.035), "fiber", 0.6, {"wet": 1.0, "smear": 0.8})
	for k in 7:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 1.1) if k > 0 else 0.0
		var sz := rng.randf_range(0.4, 0.75) if k > 0 else 0.85
		var sc := Vector3(rng.randf_range(1.0, 1.5), rng.randf_range(0.45, 0.75), rng.randf_range(1.0, 1.5))
		var bm := blob_mesh(sz, 0.32, rng.randi(), sc, 22, 1.6)
		mesh_node(n, bm, wet if k % 3 != 2 else dry, Vector3(cos(a) * r, sz * sc.y * 0.25 - 0.06, sin(a) * r), Vector3(0, rng.randf() * TAU, 0))
	# мелкие наплывы и сгустки по краю
	for k2 in 10:
		var a2 := rng.randf() * TAU
		var r2 := rng.randf_range(1.0, 1.8)
		var s2 := rng.randf_range(0.08, 0.22)
		mesh_node(n, blob_mesh(s2, 0.4, rng.randi(), Vector3(1.3, 0.6, 1.0), 14, 2.5), flesh if k2 % 4 == 0 else wet,
			Vector3(cos(a2) * r2, 0.0, sin(a2) * r2), Vector3(0, rng.randf() * TAU, 0))
	# изогнутые «рёбра»-шипы: сужаются к кончику, гнутся наружу
	for k3 in 9:
		var a3 := rng.randf() * TAU
		var r3 := rng.randf_range(0.25, 1.0)
		var base := Vector3(cos(a3) * r3, 0.2, sin(a3) * r3)
		var out := Vector3(cos(a3), 0, sin(a3))
		var tip := base + out * rng.randf_range(0.4, 0.9) + Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(0.6, 1.6), rng.randf_range(-0.2, 0.2))
		mesh_node(n, horn(base, tip, rng.randf_range(0.06, 0.11), out * rng.randf_range(0.15, 0.4) + Vector3(0, 0.15, 0), 9, 9), dry if k3 % 3 == 0 else wet)
	# волокна: провисают от шипов к полу
	for k4 in 9:
		var a4 := rng.randf() * TAU
		var p0 := Vector3(cos(a4) * rng.randf_range(0.3, 0.9), rng.randf_range(0.9, 1.7), sin(a4) * rng.randf_range(0.3, 0.9))
		var p1 := Vector3(cos(a4 + rng.randf_range(-0.6, 0.6)) * rng.randf_range(1.4, 2.2), 0.01, sin(a4 + rng.randf_range(-0.6, 0.6)) * rng.randf_range(1.4, 2.2))
		var pts := PackedVector3Array()
		var rr := PackedFloat32Array()
		for i in 9:
			var t := float(i) / 8.0
			var q := p0.lerp(p1, t)
			q.y = lerpf(p0.y, p1.y, t) - sin(t * PI) * rng.randf_range(0.1, 0.35) * 0.6
			pts.append(q)
			rr.append(lerpf(0.012, 0.006, t) * (1.0 + 0.4 * sin(t * 9.0 + k4)))
		mesh_node(n, loft(pts, rr, rr, 6), wet)
	# бурая корка и сырость вокруг
	var crust := decal_mat("nest_crust", {"tex": "prop_mold_d", "tex_color": 1.0, "tint": Color(0.55, 0.42, 0.32, 0.85)})
	var q := quad(n, Vector2(4.2, 4.2), Vector3(0, 0.007, 0), crust, Vector3(-PI * 0.5, 0, 0))
	q.set_instance_shader_parameter("seed", rng.randf())
	var st := stain({"wet": true, "s": 3.2}, rng)
	n.add_child(st)
	# остатки снаряжения: кейс в плесени, наполовину в массе
	var tb := model(n, "metal_toolbox", Vector3(1.25, -0.05, 0.55), 0.7, 1.2, false)
	if tb != null:
		tb.rotation = Vector3(0.25, 0.7, 0.15)
	else:
		box(n, Vector3(0.6, 0.3, 0.4), Vector3(1.4, 0.15, 0.6), mc(Color(0.24, 0.27, 0.22), "metal", 0.4, {"mold": 0.7}), Vector3(0.2, 0.7, 0.1))
	var se := SoundEmitter.new()
	se.snd = "nest_creak"
	se.every = 14.0
	se.vol = -10.0
	se.position = Vector3(0, 0.5, 0)
	n.add_child(se)
	return n


static func house_item(what: String, rng: RandomNumberGenerator) -> Node3D:
	var n := _house(what, rng)
	if not park_mode and what in ["sofa", "armchair", "tv", "table", "stove", "floorlamp"]:
		blob_under(n, 0.55)
	return n


static func _house(what: String, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var fab := m_cloth(Color(0.45, 0.32, 0.3))
	var wd := mc(Color(0.45, 0.3, 0.2), "wood", 0.8)
	match what:
		"sofa":
			if model(n, "Sofa_01", Vector3.ZERO, 0.0, 1.15) != null:
				return n
			box(n, Vector3(2.0, 0.42, 0.85), Vector3(0, 0.21, 0), fab)
			box(n, Vector3(2.0, 0.5, 0.2), Vector3(0, 0.62, -0.33), fab)
			box(n, Vector3(0.2, 0.3, 0.85), Vector3(-0.9, 0.55, 0), fab)
			box(n, Vector3(0.2, 0.3, 0.85), Vector3(0.9, 0.55, 0), fab)
			collider(n, Vector3(2.0, 0.8, 0.85), Vector3(0, 0.4, 0))
		"armchair":
			if model(n, "ArmChair_01") != null:
				return n
			box(n, Vector3(0.9, 0.42, 0.85), Vector3(0, 0.21, 0), fab)
			box(n, Vector3(0.9, 0.55, 0.2), Vector3(0, 0.64, -0.33), fab)
		"tv":
			_tv(n)
			var se := SoundEmitter.new()
			se.snd = "tv_static"
			se.every = 0.0
			se.vol = -14.0
			se.position = Vector3(0, 0.8, 0)
			n.add_child(se)
		"rug":
			box(n, Vector3(2.2, 0.01, 1.6), Vector3(0, 0.005, 0), m_cloth(Color(0.5, 0.2, 0.18)))
		"floorlamp":
			rod(n, Vector3(0, 0, 0), Vector3(0, 1.5, 0), 0.012, mc(Color(0.42, 0.33, 0.18), "metal", 0.4, {"gloss": 70.0, "spec": 0.3}), 8)
			cyl(n, 0.14, 0.15, 0.03, Vector3(0, 0.015, 0), m_black(), Vector3.ZERO, 16)
			# абажур: ткань, просвеченная лампочкой изнутри (без донышек, видна с обеих сторон),
			# ярче по плетению, по краям — проволочные обручи; снизу видна лампочка
			var shade := CylinderMesh.new()
			shade.top_radius = 0.13
			shade.bottom_radius = 0.22
			shade.height = 0.3
			shade.radial_segments = 24
			shade.rings = 2
			shade.cap_top = false
			shade.cap_bottom = false
			var fab2 := mc(Color(0.6, 0.5, 0.36), "fabric", 0.8, {"emit": 1.3, "emit_color": Vector3(1.0, 0.66, 0.34), "emit_mask": 1.0,
				"powered": 1.0, "ds": true, "albedo_cap": 0.5})
			mesh_node(n, shade, fab2, Vector3(0, 1.55, 0))
			var wire := mc(Color(0.4, 0.32, 0.2), "metal", 0.3)
			for yy in [1.4, 1.7]:
				var rr0: float = 0.22 if yy < 1.5 else 0.13
				var tor := TorusMesh.new()
				tor.inner_radius = rr0 - 0.004
				tor.outer_radius = rr0 + 0.002
				tor.rings = 24
				tor.ring_segments = 4
				mesh_node(n, tor, wire, Vector3(0, yy, 0))
			sph(n, 0.035, Vector3(0, 1.5, 0), m_emit(Color(1.0, 0.86, 0.62), 1.4, true), Vector3(1, 1.25, 1), 10)
		"clock":
			model(n, "wall_clock", Vector3.ZERO, 0.0, 1.0, false)
		"stove":
			model(n, "electric_stove", Vector3.ZERO, 0.0, 1.05)
		"microwave":
			model(n, "vintage_microwave", Vector3.ZERO, 0.0, 0.55, false)
		"frame":
			# рамка, выцветшая фотобумага, на ней — смазанное лицо (вырез по альфе поверх бумаги)
			box(n, Vector3(0.5, 0.4, 0.03), Vector3(0, 0, 0.015), wd)
			quad(n, Vector2(0.42, 0.32), Vector3(0, 0, 0.0305), mc(Color(0.5, 0.45, 0.38), "paper", 1.0, {"gloss": 60.0, "spec": 0.12}))
			quad(n, Vector2(0.26, 0.3), Vector3(0, 0, 0.031), Mats.prop("photo_smear", {"tex": "face_smear", "tex_mix": 1.0, "color": Vector3(0.62, 0.57, 0.52), "alpha_cut": 0.35}))
		"counter":
			box(n, Vector3(2.2, 0.9, 0.6), Vector3(0, 0.45, 0), mc(Color(0.82, 0.8, 0.72), "wood", 0.3))
			box(n, Vector3(2.25, 0.04, 0.64), Vector3(0, 0.92, 0), mc(Color(0.5, 0.5, 0.48), "concrete", 0.5, {"gloss": 50.0, "spec": 0.12}))
			collider(n, Vector3(2.2, 0.95, 0.6), Vector3(0, 0.47, 0))
			blob(n, Vector2(2.5, 0.85), Vector3.ZERO, 0.6)
		"fridge":
			box(n, Vector3(0.75, 1.75, 0.7), Vector3(0, 0.88, 0), m_plastic(Color(0.9, 0.88, 0.82)))
			box(n, Vector3(0.74, 0.008, 0.01), Vector3(0, 1.22, 0.351), m_black())
			box(n, Vector3(0.03, 0.4, 0.03), Vector3(-0.3, 1.45, 0.37), m_metal())
			box(n, Vector3(0.03, 0.3, 0.03), Vector3(-0.3, 0.95, 0.37), m_metal())
			blob(n, Vector2(1.0, 0.95), Vector3.ZERO, 0.6)
			collider(n, Vector3(0.75, 1.75, 0.7), Vector3(0, 0.88, 0))
			var se2 := SoundEmitter.new()
			se2.snd = "fridge_hum"
			se2.every = 0.0
			se2.vol = -16.0
			se2.position = Vector3(0, 1.0, 0)
			n.add_child(se2)
		"table":
			if model(n, "WoodenTable_01", Vector3.ZERO, 0.0, Vector3(0.75, 1.35, 1.1)) != null:
				for k in 3:
					model(n, "dining_chair_02", Vector3(-0.45 + k * 0.45, 0, 0.62 if k != 1 else -0.62), PI if k != 1 else 0.0, 1.0, false)
				return n
			box(n, Vector3(1.2, 0.04, 0.8), Vector3(0, 0.75, 0), wd)
			for sx in [-0.55, 0.55]:
				for sz in [-0.35, 0.35]:
					box(n, Vector3(0.05, 0.75, 0.05), Vector3(sx, 0.37, sz), wd)
			for k in 3:
				var ch := Node3D.new()
				n.add_child(ch)
				ch.position = Vector3(-0.5 + k * 0.5, 0, 0.65 if k != 1 else -0.65)
				ch.rotation.y = PI if k != 1 else 0.0
				_chair(ch)
				swap_mats(ch, wd)
			collider(n, Vector3(1.2, 0.8, 0.8), Vector3(0, 0.4, 0))
		"stairs":
			for k2 in 12:
				box(n, Vector3(1.0, 0.2, 0.3), Vector3(0, 0.1 + k2 * 0.2, -1.2 + k2 * 0.25), mc(Color(0.5, 0.36, 0.24), "wood", 0.8))
			box(n, Vector3(0.05, 1.0, 3.2), Vector3(-0.5, 1.6, 0.2), wd, Vector3(-0.68, 0, 0))
			collider(n, Vector3(1.0, 1.2, 3.0), Vector3(0, 0.6, 0.2), 1, Vector3(-0.68, 0, 0))
		"phone":
			box(n, Vector3(0.18, 0.26, 0.08), Vector3(0, 0, 0.04), m_plastic(Color(0.85, 0.8, 0.7)))
			box(n, Vector3(0.05, 0.22, 0.06), Vector3(0.05, 0, 0.1), m_plastic(Color(0.85, 0.8, 0.7)))
	return n


static func sound_emitter(d: Dictionary) -> Node3D:
	var se := SoundEmitter.new()
	se.snd = String(d.get("snd", "copy_whisper"))
	se.every = float(d.get("every", 0.0))
	se.vol = float(d.get("vol", -6.0))
	se.max_dist = float(d.get("max_dist", 22.0))
	return se


static func voice_wall(cx: Node3D) -> Node3D:
	var v := VoiceWall.new()
	return v


const CITY_SHADER := preload("res://src/shaders/fx_city.gdshader")
const CITY_POOL := preload("res://src/shaders/fx_city_pool.gdshader")
static var _city_mats := {}


static func _city_mat(mode: int) -> ShaderMaterial:
	if not _city_mats.has(mode):
		var m := ShaderMaterial.new()
		m.shader = CITY_SHADER
		m.set_shader_parameter("mode", float(mode))
		_city_mats[mode] = m
	return _city_mats[mode]


## Вертикальная стена от a до b (по горизонтали) высотой от y0 до y1, лицом к точке look: UV — метры
## (u вдоль стены от a, v — высота над землёй ground)
static func _city_wall(a: Vector3, b: Vector3, y0: float, y1: float, ground: float, look: Vector3) -> ArrayMesh:
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var us := PackedVector2Array()
	var d := b - a
	var nn := Vector3(d.z, 0, -d.x).normalized()
	if nn.dot(look - (a + b) * 0.5) < 0.0:
		nn = -nn
	var l := d.length()
	var q0 := [Vector3(a.x, y0, a.z), nn, Vector2(0, y0 - ground)]
	var q1 := [Vector3(b.x, y0, b.z), nn, Vector2(l, y0 - ground)]
	var q2 := [Vector3(b.x, y1, b.z), nn, Vector2(l, y1 - ground)]
	var q3 := [Vector3(a.x, y1, a.z), nn, Vector2(0, y1 - ground)]
	_tri(vs, ns, us, q0, q1, q2)
	_tri(vs, ns, us, q0, q2, q3)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	arr[Mesh.ARRAY_TEX_UV] = us
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Дом: четыре стены (UV — метры: u по периметру, v от земли — окна сходятся на углах) и плоская крыша.
## Поверхность 0 — фасады, 1 — крыша
static func _city_block(w: float, h: float, dd: float) -> ArrayMesh:
	var m := ArrayMesh.new()
	var corners := [Vector3(-w * 0.5, 0, dd * 0.5), Vector3(w * 0.5, 0, dd * 0.5), Vector3(w * 0.5, 0, -dd * 0.5), Vector3(-w * 0.5, 0, -dd * 0.5)]
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var us := PackedVector2Array()
	var u := 0.0
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		var l := a.distance_to(b)
		var nn := Vector3((a.x + b.x) * 0.5, 0, (a.z + b.z) * 0.5).normalized()
		_tri(vs, ns, us, [a, nn, Vector2(u, 0)], [b, nn, Vector2(u + l, 0)], [b + Vector3(0, h, 0), nn, Vector2(u + l, h)])
		_tri(vs, ns, us, [a, nn, Vector2(u, 0)], [b + Vector3(0, h, 0), nn, Vector2(u + l, h)], [a + Vector3(0, h, 0), nn, Vector2(u, h)])
		u += l
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	arr[Mesh.ARRAY_TEX_UV] = us
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var rv := PackedVector3Array()
	var rn := PackedVector3Array()
	var ru := PackedVector2Array()
	var up := Vector3.UP
	var c := []
	for q in corners:
		c.append((q as Vector3) + Vector3(0, h, 0))
	_tri(rv, rn, ru, [c[0], up, Vector2.ZERO], [c[1], up, Vector2.ZERO], [c[2], up, Vector2.ZERO])
	_tri(rv, rn, ru, [c[0], up, Vector2.ZERO], [c[2], up, Vector2.ZERO], [c[3], up, Vector2.ZERO])
	var arr2 := []
	arr2.resize(Mesh.ARRAY_MAX)
	arr2[Mesh.ARRAY_VERTEX] = rv
	arr2[Mesh.ARRAY_NORMAL] = rn
	arr2[Mesh.ARRAY_TEX_UV] = ru
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr2)
	return m


## «Красный город» за окнами перехода (нижний слой): ночной квартал в пустоте на 14 м ниже пола.
## Проспект уходит от окон вдаль, его пересекает улица; вдоль них — дома сплошной застройкой (окна по этажам:
## часть горит красным/оранжевым, шторы, жалюзи; тёмные стёкла отражают зарево), за ними — второй ряд выше;
## у окон перехода дома ниже, чтобы не закрывать вид. Натриевые фонари с пятнами света, машины у тротуаров,
## по проспекту изредка проезжают фары. По краям пустоты — задник: зарево над горизонтом и силуэты дальних
## кварталов (закрывает стены Комплекса, видные из пустоты). Всё — fx_city.gdshader, свет — только свой.
## Пустота относительно узла: x ∈ [−34,8; 32,4], z ∈ [−42; 39,6] (окна перехода — на z = 39,6)
static func red_city(d: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var base_y := -14.0
	var x0 := -34.4
	var x1 := 32.0
	var zf := -41.6
	var zn := 39.2
	var look := Vector3(-1.2, 0, 30.0)
	var fac := _city_mat(0)
	var dark := _city_mat(1)
	var sky := _city_mat(2)
	# задник: дальняя стена и бока, от земли до +40 м
	for wl in [[Vector3(x0, 0, zf), Vector3(x1, 0, zf)], [Vector3(x0, 0, zn), Vector3(x0, 0, zf)], [Vector3(x1, 0, zf), Vector3(x1, 0, zn)]]:
		var a: Array = wl
		mesh_node(n, _city_wall(a[0], a[1], base_y, 40.0, base_y, look), sky)
	# земля
	box(n, Vector3(x1 - x0 + 2.0, 0.2, zn - zf + 2.0), Vector3((x0 + x1) * 0.5, base_y - 0.1, (zf + zn) * 0.5), dark)
	# проспект вдоль z и поперечная улица
	var ax := rng.randf_range(-3.0, 2.0)
	var cz := rng.randf_range(-16.0, -6.0)
	var road := mc(Color(0.05, 0.045, 0.045), "asphalt", 1.0, {"emit": 0.05, "emit_color": Vector3(0.55, 0.12, 0.04), "fog_mul": 0.0})
	box(n, Vector3(8.0, 0.04, zn - zf), Vector3(ax, base_y + 0.02, (zf + zn) * 0.5), road)
	box(n, Vector3(x1 - x0, 0.04, 7.0), Vector3((x0 + x1) * 0.5, base_y + 0.021, cz), road)
	var curb := mc(Color(0.04, 0.035, 0.035), "concrete", 0.6, {"emit": 0.03, "emit_color": Vector3(0.5, 0.15, 0.05), "fog_mul": 0.0})
	for sx in [-1.0, 1.0]:
		box(n, Vector3(2.0, 0.15, zn - zf), Vector3(ax + sx * 5.0, base_y + 0.075, (zf + zn) * 0.5), curb)
	# разметка: пунктир по оси проспекта
	var paint := mc(Color(0.05, 0.04, 0.02), "metal", 0.0, {"emit": 0.12, "emit_color": Vector3(0.7, 0.45, 0.1), "fog_mul": 0.0})
	var zz := zn - 2.0
	while zz > zf + 2.0:
		if absf(zz - cz) > 4.5:
			box(n, Vector3(0.15, 0.01, 2.0), Vector3(ax, base_y + 0.045, zz), paint)
		zz -= 5.0
	# кварталы: вдоль проспекта сплошной стеной, второй ряд — выше; у окон перехода — ниже
	var bid := 0
	for side in [-1.0, 1.0]:
		var sd: float = side
		var inner := ax + sd * 6.2
		var outer := x0 + 0.6 if sd < 0.0 else x1 - 0.6
		var z := zn - 1.0
		while z > zf + 4.0:
			var lot := rng.randf_range(9.0, 17.0)
			var zc := z - lot * 0.5
			z -= lot + rng.randf_range(0.3, 1.5)
			if absf(zc - cz) < lot * 0.5 + 4.2:
				continue
			# ряды от проспекта наружу
			var xa := inner
			var row := 0
			while absf(outer - xa) > 7.0 and row < 3:
				var dep := minf(rng.randf_range(9.0, 15.0), absf(outer - xa))
				var xc := xa + sd * dep * 0.5
				xa += sd * (dep + rng.randf_range(0.5, 2.5))
				if rng.randf() < 0.12:
					row += 1
					continue
				# высота: даль и задние ряды выше; у окон — ниже уровня взгляда
				var far := clampf((zn - zc) / 70.0, 0.0, 1.0)
				var hmax := lerpf(9.0, 30.0, far) + row * 5.0
				var fh := rng.randf_range(2.9, 3.4)
				var floors := maxi(2, int(rng.randf_range(0.35, 1.0) * hmax / fh))
				var hh := floors * fh + 0.6
				var bay := rng.randf_range(2.6, 3.6)
				var wz := maxf(2.0, round((lot - 0.6) / bay)) * bay
				var wx := maxf(2.0, round((dep - 0.4) / bay)) * bay
				var mi := mesh_node(n, _city_block(wx, hh, wz), fac, Vector3(xc, base_y, zc))
				mi.set_surface_override_material(1, dark)
				mi.set_instance_shader_parameter("bld", Vector4(float(bid) * 1.37 + rng.randf() * 10.0, fh, bay, rng.randf_range(0.18, 0.55)))
				mi.set_instance_shader_parameter("style", float(rng.randi_range(0, 2)))
				bid += 1
				# парапет и крышная мелочь (силуэты на фоне зарева)
				box(n, Vector3(wx + 0.3, 0.5, wz + 0.3), Vector3(xc, base_y + hh + 0.15, zc), dark)
				if rng.randf() < 0.6:
					box(n, Vector3(rng.randf_range(1.5, 3.0), rng.randf_range(1.0, 2.2), rng.randf_range(1.5, 3.0)),
						Vector3(xc + rng.randf_range(-wx, wx) * 0.3, base_y + hh + 0.9, zc + rng.randf_range(-wz, wz) * 0.3), dark)
				if rng.randf() < 0.3:
					var tx := xc + rng.randf_range(-wx, wx) * 0.25
					var tz := zc + rng.randf_range(-wz, wz) * 0.25
					cyl(n, 1.1, 1.1, 2.2, Vector3(tx, base_y + hh + 2.6, tz), dark, Vector3.ZERO, 10)
					for lg in 4:
						var la := lg * PI * 0.5 + 0.7
						rod(n, Vector3(tx + cos(la) * 0.9, base_y + hh, tz + sin(la) * 0.9), Vector3(tx + cos(la) * 0.9, base_y + hh + 1.5, tz + sin(la) * 0.9), 0.06, dark, 4)
				row += 1
	# фонари: натрий, по обе стороны проспекта; пятна света на асфальте
	var pole := mc(Color(0.02, 0.02, 0.02), "metal", 0.2, {"fog_mul": 0.0})
	var lampm := m_emit(Color(1.0, 0.55, 0.2), 2.4, false)
	var pool := ShaderMaterial.new()
	pool.shader = CITY_POOL
	var zl := zn - 4.0
	var alt := 0
	while zl > zf + 3.0:
		for sx2 in [-1.0, 1.0]:
			var px: float = ax + sx2 * 4.6
			var pz := zl + (6.0 if (alt + int(sx2 > 0.0)) % 2 == 0 else 0.0)
			if absf(pz - cz) < 4.0:
				continue
			rod(n, Vector3(px, base_y, pz), Vector3(px, base_y + 7.0, pz), 0.09, pole, 6)
			rod(n, Vector3(px, base_y + 7.0, pz), Vector3(px - sx2 * 1.6, base_y + 7.2, pz), 0.05, pole, 4)
			box(n, Vector3(0.5, 0.14, 0.24), Vector3(px - sx2 * 1.7, base_y + 7.1, pz), lampm)
			var pq := quad(n, Vector2(9.0, 9.0), Vector3(px - sx2 * 1.7, base_y + 0.06, pz), pool, Vector3(-PI * 0.5, 0, 0))
			pq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		alt += 1
		zl -= 12.0
	# машины у тротуаров: тёмные кузова, у некоторых горят задние огни
	var carb := mc(Color(0.03, 0.025, 0.025), "metal", 0.2, {"gloss": 60.0, "spec": 0.2, "fog_mul": 0.0})
	var tail := m_emit(Color(1.0, 0.05, 0.03), 2.0, false)
	for k3 in 9:
		var sx3 := -1.0 if k3 % 2 == 0 else 1.0
		var pz2 := rng.randf_range(zf + 6.0, zn - 8.0)
		if absf(pz2 - cz) < 5.0:
			continue
		var car := Node3D.new()
		n.add_child(car)
		car.position = Vector3(ax + sx3 * 3.2, base_y + 0.04, pz2)
		box(car, Vector3(1.8, 0.75, 4.5), Vector3(0, 0.55, 0), carb)
		box(car, Vector3(1.6, 0.55, 2.4), Vector3(0, 1.15, 0.2), carb)
		if rng.randf() < 0.5:
			for tx2 in [-0.7, 0.7]:
				box(car, Vector3(0.3, 0.12, 0.05), Vector3(tx2, 0.7, -2.27), tail)
	# движение по проспекту: фары и габариты
	var tr := CityTraffic.new()
	n.add_child(tr)
	tr.position = Vector3(ax, base_y + 0.04, 0.0)
	tr.z0 = zf + 2.0
	tr.z1 = zn - 1.0
	var head := m_emit(Color(1.0, 0.9, 0.7), 3.2, false)
	for k4 in 4:
		var c := Node3D.new()
		tr.add_child(c)
		var toward := k4 % 2 == 0
		c.position = Vector3(-1.6 if toward else 1.6, 0, rng.randf_range(tr.z0, tr.z1))
		c.rotation.y = 0.0 if toward else PI
		box(c, Vector3(1.75, 0.7, 4.4), Vector3(0, 0.55, 0), carb)
		box(c, Vector3(1.55, 0.5, 2.3), Vector3(0, 1.12, -0.2), carb)
		for hx in [-0.62, 0.62]:
			sph(c, 0.11, Vector3(hx, 0.62, 2.21), head, Vector3(1, 0.7, 0.4), 8)
			box(c, Vector3(0.28, 0.1, 0.04), Vector3(hx, 0.7, -2.21), tail)
		tr.cars.append([c, rng.randf_range(6.0, 11.0) * (1.0 if toward else -1.0)])
	# деревья вдоль тротуаров — чёрные силуэты
	for k2 in 18:
		var sx4 := -1.0 if k2 % 2 == 0 else 1.0
		var tz2 := rng.randf_range(zf + 4.0, zn - 6.0)
		if absf(tz2 - cz) < 5.0:
			continue
		var tx3 := ax + sx4 * rng.randf_range(5.6, 6.0)
		cyl(n, 0.12, 0.18, 3.0, Vector3(tx3, base_y + 1.5, tz2), dark)
		sph(n, 1.7, Vector3(tx3, base_y + 4.0, tz2), dark, Vector3(1, 1.15, 1), 8)
	# дорожный знак на углу
	box(n, Vector3(0.1, 2.6, 0.1), Vector3(ax + 4.4, base_y + 1.3, cz + 4.0), m_iron())
	box(n, Vector3(0.9, 0.9, 0.05), Vector3(ax + 4.4, base_y + 2.8, cz + 4.0), mc(Color(0.8, 0.65, 0.1), "metal", 0.2, {"emit": 0.15, "emit_color": Vector3(0.6, 0.1, 0.05)}), Vector3(0, 0, PI * 0.25))
	return n


# ------------------------------------------------------------ вспомогательные узлы

class CityTraffic extends Node3D:
	## Машины «Красного города»: пары фар (к окнам) и красных габаритов (от окон) едут по проспекту
	## по своим полосам, у края пустоты возвращаются в начало (машины строит red_city)
	var cars: Array = []
	var z0 := 0.0
	var z1 := 0.0

	func _process(dt: float) -> void:
		for e in cars:
			var c: Node3D = e[0]
			var v: float = e[1]
			c.position.z += v * dt
			if c.position.z > z1:
				c.position.z = z0
			elif c.position.z < z0:
				c.position.z = z1


class BalloonFloat extends Node3D:
	## Шарик над рукой: ориентация мировая (нитка всегда вверх, кисть может быть повёрнута как угодно),
	## масштаб мировой; лёгкое покачивание на ветру
	var top: Node3D = null
	var line: MeshInstance3D = null
	var _t := randf() * 10.0

	func _process(dt: float) -> void:
		_t += dt
		var sway := Vector3(sin(_t * 0.9) * 0.07 + sin(_t * 2.3) * 0.02, 0.0, cos(_t * 0.7) * 0.06)
		global_basis = Basis.from_euler(sway)


class FountainFX extends Node3D:
	## Вода фонтана: сетки без теней (парк включает тени всем сеткам после сборки — выключаем в первом кадре)
	var _meshes: Array = []
	var _fixed := false

	func add_mesh(m: Mesh, pos: Vector3) -> void:
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.position = pos
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_meshes.append(mi)

	func _process(_dt: float) -> void:
		if _fixed:
			return
		_fixed = true
		for mi in _meshes:
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


class SoundEmitter extends Node3D:
	var snd := "copy_whisper"
	var every := 0.0       # 0 — зациклено
	var vol := -8.0
	var max_dist := 22.0
	var _p: AudioStreamPlayer3D
	var _t := 0.0

	func _ready() -> void:
		_t = randf_range(1.0, maxf(every, 2.0))
		if every <= 0.0:
			var st := Snd.get_stream(snd)
			if st == null:
				return
			_p = AudioStreamPlayer3D.new()
			_p.stream = st
			_p.volume_db = vol
			_p.max_distance = max_dist
			_p.unit_size = 2.5
			_p.bus = "World"
			_p.attenuation_filter_cutoff_hz = 5000.0
			add_child(_p)
			_p.play(randf() * 2.0)
			_p.finished.connect(func() -> void: _p.play())

	func _process(dt: float) -> void:
		if every <= 0.0:
			return
		_t -= dt
		if _t <= 0.0:
			_t = every * randf_range(0.7, 1.4)
			var cam := get_viewport().get_camera_3d()
			if cam != null and cam.global_position.distance_to(global_position) < max_dist:
				Snd.play_at(snd, global_position, get_parent(), vol, randf_range(0.9, 1.1), max_dist)


class ProxTrigger extends Node3D:
	var radius := 3.0
	var once := true
	var cb: Callable
	var _done := false

	func _process(_dt: float) -> void:
		if _done:
			return
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var d := cam.global_position.distance_to(global_position + Vector3(0, 1.0, 0))
		if d < radius:
			_done = once
			if cb.is_valid():
				cb.call()


class NullAnim extends Node3D:
	var _t := 0.0

	func _process(dt: float) -> void:
		_t += dt
		for ch in get_parent().get_children():
			if ch.has_meta("spin"):
				(ch as Node3D).rotation.y = _t * 0.7
				(ch as Node3D).scale = Vector3(0.6 + sin(_t * 3.3) * 0.08, 2.2 + sin(_t * 1.7) * 0.2, 0.6 + cos(_t * 2.9) * 0.08)
			elif ch.has_meta("float"):
				var ph: float = ch.get_meta("float")
				var c := ch as Node3D
				c.position.y = fposmod(c.position.y + dt * (0.2 + 0.1 * sin(ph)), 2.3)
				c.position.x += sin(_t * 2.0 + ph) * dt * 0.1


class RadioPlayer extends Node3D:
	var on := false
	var _p: AudioStreamPlayer3D
	var _static: AudioStreamPlayer3D
	var _line := 0
	var _wait := 0.0
	const LINES := ["radio.r01", "radio.r02", "radio.r03", "radio.r04", "radio.r05"]

	func toggle() -> void:
		on = not on
		Snd.play_at("radio_click", global_position, self, -4.0)
		if on:
			_static = AudioStreamPlayer3D.new()
			_static.stream = Snd.get_stream("radio_static")
			_static.volume_db = -10.0
			_static.bus = "World"
			_static.max_distance = 20.0
			add_child(_static)
			_static.play()
			_static.finished.connect(func() -> void:
				if on and is_instance_valid(_static):
					_static.play())
			_line = 0
			_wait = 1.2
		else:
			if is_instance_valid(_static):
				_static.queue_free()
			if is_instance_valid(_p):
				_p.queue_free()
			Game.subs_clear()

	func _process(dt: float) -> void:
		if not on:
			return
		if is_instance_valid(_p) and _p.playing:
			return
		_wait -= dt
		if _wait > 0.0:
			return
		var key: String = LINES[_line % LINES.size()]
		_line += 1
		_wait = 2.5 if _line % LINES.size() != 0 else 12.0
		var path := Loc.voice_path(key)
		Game.say(key, Loc.t("ui.who_radio"))
		if ResourceLoader.exists(path):
			_p = AudioStreamPlayer3D.new()
			_p.stream = load(path)
			_p.volume_db = -2.0
			_p.bus = "Voice"
			_p.max_distance = 25.0
			add_child(_p)
			_p.play()


class VoiceWall extends Node3D:
	## Человек за стеной встроенного дома: зовёт, стучит; потом — шум и тишина
	var stage := 0
	var _t := 0.0
	var _cd := 0.0

	func _process(dt: float) -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var d := cam.global_position.distance_to(global_position)
		if stage >= 6:
			return
		_cd -= dt
		if d > 14.0:
			return
		_t += dt
		if _cd > 0.0:
			return
		match stage:
			0:
				Snd.play_at("knock", global_position, self, -2.0)
				_cd = 3.0
				stage = 1
			1:
				_voice("sub.wall1")
				_cd = 6.0
				stage = 2
			2:
				Snd.play_at("knock", global_position, self, 0.0)
				_cd = 4.0
				stage = 3 if d < 6.0 else 2
			3:
				_voice("sub.wall2")
				_cd = 7.0
				stage = 4
			4:
				_voice("sub.wall3")
				_cd = 6.0
				stage = 5
			5:
				Snd.play_at("noise_rush", global_position, self, 4.0)
				if Game.main != null:
					Game.main.burst(1.0)
				_cd = 99.0
				stage = 6

	func _voice(key: String) -> void:
		Game.say(key, Loc.t("ui.who_wall"))
		var path := Loc.voice_path(key)
		if ResourceLoader.exists(path):
			var p := AudioStreamPlayer3D.new()
			p.stream = load(path)
			p.volume_db = -6.0
			p.bus = "World"
			p.max_distance = 20.0
			p.attenuation_filter_cutoff_hz = 1200.0
			p.attenuation_filter_db = -30.0
			add_child(p)
			p.play()
			p.finished.connect(p.queue_free)
