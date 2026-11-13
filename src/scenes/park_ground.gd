extends RefCounted
## Земля парка: маска (асфальт, площадь, голая земля, песок), пологий рельеф (ровно у дорожек и вещей, вал по краю),
## меш газона с шейдером, коллизия HeightMapShape3D и трава вокруг камеры (два слоя MultiMesh).
## Маска — расстояния до краёв в метрах, поэтому края дорожек в шейдере плавные и чёткие без наложения мешей.

const GROUND_SHADER := preload("res://src/shaders/park_ground.gdshader")
const GRASS_SHADER := preload("res://src/shaders/park_grass.gdshader")

const AREA := 96.0      # маска и рельеф покрывают квадрат ±AREA
const MRES := 384       # пикселей маски по стороне (0,5 м)
const HRES := 193       # узлов рельефа по стороне (шаг 1 м)
const HALF := 96        # (HRES - 1) / 2
# каналы маски (RGBA, по 4 float на пиксель — сразу в формате текстуры)
const ASPH := 0         # расстояние до края асфальта, м (внутри < 0)
const PLAZA := 1        # то же для бетонной площади
const BARE := 2         # голая земля 0..1
const SAND := 3         # расстояние до края песка

var mask := PackedFloat32Array()
var hs := PackedFloat32Array()         # высоты узлов рельефа
var flat_spots: Array = []             # [Vector2 центр, радиус]: тут земля ровная (площадка, плед, тележка)
var mask_tex: ImageTexture
var h_tex: ImageTexture
var macro: Texture2D
var wind_mats: Array = []
# прямоугольники без травинок (под пледом и т. п.): [центр Vector2 (x, z), полуразмеры Vector2, поворот по Y]
var grass_cuts: Array = []
var _noise := FastNoiseLite.new()

const MAX_CUTS := 4     # столько прямоугольников знает шейдер травы (park_grass.gdshader: cut_rect)


func _init() -> void:
	var img := Image.create_empty(MRES, MRES, false, Image.FORMAT_RGBAF)
	img.fill(Color(8.0, 8.0, 0.0, 8.0))
	mask = img.get_data().to_float32_array()
	_noise.seed = 1407
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.03
	_noise.fractal_octaves = 3
	macro = Mats.tex("park_noise")


# ------------------------------------------------------------ маска

func _px() -> float:
	return 2.0 * AREA / MRES


func _range(lo: float, hi: float) -> Vector2i:
	var px := _px()
	return Vector2i(clampi(int(floor((lo + AREA) / px)), 0, MRES - 1), clampi(int(ceil((hi + AREA) / px)), 0, MRES - 1))


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Асфальтовая лента вдоль ломаной (полуширина hw)
func paint_road(pts: PackedVector2Array, hw: float, closed: bool) -> void:
	var px := _px()
	var n := pts.size()
	var cnt := n if closed else n - 1
	var margin := hw + 6.0
	for s in cnt:
		var a := pts[s]
		var b := pts[(s + 1) % n]
		var ri := _range(minf(a.x, b.x) - margin, maxf(a.x, b.x) + margin)
		var rj := _range(minf(a.y, b.y) - margin, maxf(a.y, b.y) + margin)
		for j in range(rj.x, rj.y + 1):
			var z := -AREA + (j + 0.5) * px
			for i in range(ri.x, ri.y + 1):
				var d := _seg_dist(Vector2(-AREA + (i + 0.5) * px, z), a, b) - hw
				var k := (j * MRES + i) * 4 + ASPH
				if d < mask[k]:
					mask[k] = d


## Круглая бетонная площадь
func paint_plaza(c: Vector2, r: float) -> void:
	var px := _px()
	var ri := _range(c.x - r - 6.0, c.x + r + 6.0)
	var rj := _range(c.y - r - 6.0, c.y + r + 6.0)
	for j in range(rj.x, rj.y + 1):
		for i in range(ri.x, ri.y + 1):
			var d := Vector2(-AREA + (i + 0.5) * px, -AREA + (j + 0.5) * px).distance_to(c) - r
			var k := (j * MRES + i) * 4 + PLAZA
			mask[k] = minf(mask[k], d)


## Песок: прямоугольник со скруглёнными углами (half — полуразмеры, rot — поворот)
func paint_sand(c: Vector2, half: Vector2, rot: float, rr: float) -> void:
	var px := _px()
	var ext := half.length() + 6.0
	var ri := _range(c.x - ext, c.x + ext)
	var rj := _range(c.y - ext, c.y + ext)
	var cs := cos(-rot)
	var sn := sin(-rot)
	for j in range(rj.x, rj.y + 1):
		for i in range(ri.x, ri.y + 1):
			var p := Vector2(-AREA + (i + 0.5) * px, -AREA + (j + 0.5) * px) - c
			p = Vector2(p.x * cs - p.y * sn, p.x * sn + p.y * cs)
			var q := Vector2(absf(p.x), absf(p.y)) - half + Vector2(rr, rr)
			var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - rr
			var k := (j * MRES + i) * 4 + SAND
			mask[k] = minf(mask[k], d)


## Голая земля: пятно радиуса r (amount в центре, мягкий край). stretch — вытянутость по оси dir
func paint_bare(c: Vector2, r: float, amount: float, dir := Vector2.ZERO, stretch := 1.0) -> void:
	var px := _px()
	var ext := r * maxf(stretch, 1.0) + 1.0
	var ri := _range(c.x - ext, c.x + ext)
	var rj := _range(c.y - ext, c.y + ext)
	for j in range(rj.x, rj.y + 1):
		for i in range(ri.x, ri.y + 1):
			var p := Vector2(-AREA + (i + 0.5) * px, -AREA + (j + 0.5) * px) - c
			if stretch != 1.0 and dir != Vector2.ZERO:
				var along := p.dot(dir)
				p = p - dir * along + dir * (along / stretch)
			var v := amount * (1.0 - smoothstep(r * 0.15, r, p.length()))
			var k := (j * MRES + i) * 4 + BARE
			if v > mask[k]:
				mask[k] = v


## Травинок нет в прямоугольнике: центр c (мир x, z), полуразмеры half (по локальным x, z), поворот rot — как
## rotation.y узла, который там лежит (плед: cut_grass(Vector2(p.x, p.z), Vector2(1.0, 1.0), bl.rotation.y)).
## Земля под ним не меняется. Можно звать и до, и после build_grass (материалы травы обновятся); до MAX_CUTS штук
func cut_grass(c: Vector2, half: Vector2, rot: float) -> void:
	if grass_cuts.size() >= MAX_CUTS:
		push_warning("park_ground: больше %d вырезов травы" % MAX_CUTS)
		return
	grass_cuts.append([c, half, rot])
	for m in wind_mats:
		_apply_cuts(m as ShaderMaterial)


func _apply_cuts(m: ShaderMaterial) -> void:
	var rects := PackedVector4Array()
	var rots := Vector4.ZERO
	for i in MAX_CUTS:
		if i < grass_cuts.size():
			var c: Vector2 = grass_cuts[i][0]
			var h: Vector2 = grass_cuts[i][1]
			rects.append(Vector4(c.x, c.y, h.x, h.y))
			rots[i] = float(grass_cuts[i][2])
		else:
			rects.append(Vector4(0.0, 0.0, -1.0, -1.0))
	m.set_shader_parameter("cut_rect", rects)
	m.set_shader_parameter("cut_rot", rots)


## Значение канала маски в точке (билинейно)
func sample(ch: int, p: Vector2) -> float:
	var px := _px()
	var fx := clampf((p.x + AREA) / px - 0.5, 0.0, MRES - 1.001)
	var fz := clampf((p.y + AREA) / px - 0.5, 0.0, MRES - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var k := (j * MRES + i) * 4 + ch
	var row := MRES * 4
	var a := lerpf(mask[k], mask[k + 4], tx)
	var b := lerpf(mask[k + row], mask[k + row + 4], tx)
	return lerpf(a, b, tz)


## Можно ли тут посадить дерево/куст (не на дорожке, площади, песке)
func clear_at(p: Vector2, margin: float) -> bool:
	return sample(ASPH, p) > margin and sample(PLAZA, p) > margin and sample(SAND, p) > margin


func finish_mask() -> void:
	var img := Image.create_from_data(MRES, MRES, false, Image.FORMAT_RGBAF, mask.to_byte_array())
	mask_tex = ImageTexture.create_from_image(img)


# ------------------------------------------------------------ рельеф

## Пологий вал по краю парка (к невидимым стенам), за ним — спуск к улице (тротуар с e = 66,5 м, улица ровная, y = 0)
static func berm(x: float, z: float) -> float:
	var e := maxf(absf(x), absf(z))
	return smoothstep(47.0, 57.0, e) * 0.9 * (1.0 - smoothstep(61.0, 66.0, e))


func _h_raw(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var u := _noise.get_noise_2d(x, z) * 0.62 + sin(x * 0.051 + 1.3) * sin(z * 0.043 + 0.4) * 0.22
	var dp := minf(sample(ASPH, p), sample(PLAZA, p))
	var flat := smoothstep(1.4, 7.0, dp) * smoothstep(0.0, 5.0, sample(SAND, p))
	for f in flat_spots:
		var c: Vector2 = f[0]
		var r: float = f[1]
		flat *= smoothstep(r, r + 4.0, p.distance_to(c))
	var e := maxf(absf(x), absf(z))
	var b := berm(x, z) * (1.0 + 0.35 * _noise.get_noise_2d(x * 0.6 + 300.0, z * 0.6))
	return u * flat * (1.0 - smoothstep(40.0, 56.0, e) * 0.5) * (1.0 - smoothstep(58.0, 64.0, e)) + b


func build_height() -> void:
	hs.resize(HRES * HRES)
	for j in HRES:
		for i in HRES:
			hs[j * HRES + i] = _h_raw(float(i - HALF), float(j - HALF))
	var img := Image.create_from_data(HRES, HRES, false, Image.FORMAT_RF, hs.to_byte_array())
	h_tex = ImageTexture.create_from_image(img)


## Высота земли в точке (так же, как коллизия)
func height(x: float, z: float) -> float:
	var fx := x + HALF
	var fz := z + HALF
	if fx < 0.0 or fz < 0.0 or fx > HRES - 1.001 or fz > HRES - 1.001:
		return berm(x, z)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var k := j * HRES + i
	# как треугольники HeightMapShape3D/меша: диагональ квадрата
	if tx + tz <= 1.0:
		return hs[k] + (hs[k + 1] - hs[k]) * tx + (hs[k + HRES] - hs[k]) * tz
	return hs[k + HRES + 1] + (hs[k + HRES] - hs[k + HRES + 1]) * (1.0 - tx) + (hs[k + 1] - hs[k + HRES + 1]) * (1.0 - tz)


func at(p: Vector3) -> Vector3:
	return Vector3(p.x, height(p.x, p.z), p.z)


# ------------------------------------------------------------ меш, коллизия

func build(parent: Node3D) -> MeshInstance3D:
	var xs := PackedFloat32Array([-900.0, -520.0, -330.0, -220.0, -160.0, -125.0])
	for i in HRES:
		xs.append(float(i - HALF))
	for v in [125.0, 160.0, 220.0, 330.0, 520.0, 900.0]:
		xs.append(v)
	var n := xs.size()
	var off := 6
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	verts.resize(n * n)
	norms.resize(n * n)
	for j in n:
		for i in n:
			var x := xs[i]
			var z := xs[j]
			var hi := i - off
			var hj := j - off
			var y := 0.0
			var nrm := Vector3.UP
			if hi >= 0 and hj >= 0 and hi < HRES and hj < HRES:
				var k := hj * HRES + hi
				y = hs[k]
				var l := hs[k - 1] if hi > 0 else y
				var r := hs[k + 1] if hi < HRES - 1 else y
				var d := hs[k - HRES] if hj > 0 else y
				var u := hs[k + HRES] if hj < HRES - 1 else y
				nrm = Vector3(l - r, 2.0, d - u).normalized()
			else:
				y = berm(x, z)
				nrm = Vector3(berm(x - 2.0, z) - berm(x + 2.0, z), 4.0, berm(x, z - 2.0) - berm(x, z + 2.0)).normalized()
			verts[j * n + i] = Vector3(x, y, z)
			norms[j * n + i] = nrm
	var idx := PackedInt32Array()
	idx.resize((n - 1) * (n - 1) * 6)
	var q := 0
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			# диагональ как у HeightMapShape3D: (i+1,j)–(i,j+1)
			idx[q] = a
			idx[q + 1] = a + 1
			idx[q + 2] = a + n
			idx[q + 3] = a + 1
			idx[q + 4] = a + n + 1
			idx[q + 5] = a + n
			q += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var m := ShaderMaterial.new()
	m.shader = GROUND_SHADER
	_common(m)
	m.set_shader_parameter("grass_tex", Mats.tex("park_grass"))
	m.set_shader_parameter("grass_dry_tex", Mats.tex("park_grass_dry"))
	m.set_shader_parameter("dirt_tex", Mats.tex("park_dirt"))
	m.set_shader_parameter("asphalt_tex", Mats.tex("park_asphalt"))
	m.set_shader_parameter("concrete_tex", Mats.tex("park_concrete"))
	m.set_shader_parameter("sand_tex", Mats.tex("park_sand"))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	# коллизия по тем же высотам
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := HeightMapShape3D.new()
	sh.map_width = HRES
	sh.map_depth = HRES
	sh.map_data = hs
	cs.shape = sh
	body.add_child(cs)
	body.set_meta("ground", true)
	parent.add_child(body)
	return mi


func _common(m: ShaderMaterial) -> void:
	m.set_shader_parameter("park_mask", mask_tex)
	m.set_shader_parameter("macro_tex", macro)
	m.set_shader_parameter("mask_rect", Vector4(-AREA, -AREA, 2.0 * AREA, 2.0 * AREA))


# ------------------------------------------------------------ трава

## Пучок травинок: n травинок в круге радиуса rad; у каждой 5 вершин (основание, середина, кончик)
static func _clump(rng: RandomNumberGenerator, n: int, rad: float, h0: float, h1: float, w0: float, w1: float) -> ArrayMesh:
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	for b in n:
		var a := rng.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * sqrt(rng.randf()) * rad
		var h := rng.randf_range(h0, h1)
		var w := rng.randf_range(w0, w1)
		var face := rng.randf() * TAU
		var side := Vector3(cos(face), 0, sin(face))
		var lean_dir := Vector3(-side.z, 0, side.x) * (1.0 if rng.randf() < 0.5 else -1.0)
		var lean := lean_dir * h * rng.randf_range(0.1, 0.55)
		var fn := side.cross(Vector3.UP + lean_dir * 0.3).normalized()
		var br := rng.randf_range(0.78, 1.22)
		var c := Color(br, br, br * rng.randf_range(0.85, 1.05), rng.randf())
		if rng.randf() < 0.08:
			c = Color(br * 1.25, br * 1.12, br * 0.75, 0.9)
		var s := v.size()
		var mid := base + lean * 0.35 + Vector3(0, h * 0.55, 0)
		var tip := base + lean + Vector3(0, h, 0)
		for e in [[base - side * w * 0.5, 0.0], [base + side * w * 0.5, 0.0], [mid - side * w * 0.36, 0.55], [mid + side * w * 0.36, 0.55], [tip, 1.0]]:
			v.append(e[0])
			nr.append(fn)
			uv.append(Vector2(float(b) / n, e[1]))
			col.append(c)
		for t in [0, 1, 2, 1, 3, 2, 2, 3, 4]:
			idx.append(s + t)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nr
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


func _layer(parent: Node3D, rng: RandomNumberGenerator, mesh: ArrayMesh, tile: float, density: float, fade: Vector2, bend: float, bare_kill: float) -> void:
	var m := ShaderMaterial.new()
	m.shader = GRASS_SHADER
	_common(m)
	m.set_shader_parameter("height_tex", h_tex)
	m.set_shader_parameter("height_rect", Vector4(-AREA - 0.5, -AREA - 0.5, float(HRES), float(HRES)))
	m.set_shader_parameter("tile", tile)
	m.set_shader_parameter("fade", fade)
	m.set_shader_parameter("bend_amp", bend)
	m.set_shader_parameter("bare_kill", bare_kill)
	_apply_cuts(m)
	mesh.surface_set_material(0, m)
	wind_mats.append(m)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	# стратифицированная случайная сетка: равномерно, без комков и проплешин
	var cells := int(ceil(sqrt(tile * tile * density)))
	mm.instance_count = cells * cells
	var cw := tile / cells
	var k := 0
	for j in cells:
		for i in cells:
			var p := Vector3((i + rng.randf()) * cw, 0, (j + rng.randf()) * cw)
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.25))
			mm.set_instance_transform(k, Transform3D(b, p))
			k += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# экземпляры переезжают за камерой в шейдере — границы на весь парк
	mmi.custom_aabb = AABB(Vector3(-AREA, -4.0, -AREA), Vector3(2.0 * AREA, 10.0, 2.0 * AREA))
	parent.add_child(mmi)


func build_grass(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7707
	# ближний газон: густые короткие травинки
	_layer(parent, rng, _clump(rng, 7, 0.07, 0.05, 0.13, 0.011, 0.02), 14.0, 34.0, Vector2(4.2, 6.6), 0.035, 1.0)
	# средний план: пучки повыше (недокошенная трава, сорняки), редеют к 20 м
	_layer(parent, rng, _clump(rng, 6, 0.09, 0.1, 0.24, 0.014, 0.026), 44.0, 1.6, Vector2(10.0, 20.0), 0.06, 0.55)
