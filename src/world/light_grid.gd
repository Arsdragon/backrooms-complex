class_name LightGrid
extends RefCounted
## Текстуры сетки слоя для попиксельного света (src/shaders/grid_light.gdshaderinc):
##  g_cells  (RGBA8)  r — ребро на восток (0..4) | ребро на юг << 3 | сплошная клетка << 6 | яма << 7;
##                    g — потолок, дм от floor_y (0 — шахта); b — пол, дм + 128; a — пандус/лестница (LayerData.ramp, 0..8)
##  g_lamps  (RGBAH)  r — высота лампы над floor_y (м), g — сила (0 — нет лампы), b — вид, a — группа мигания
##                    вид: 0 — длинный светильник, 1 — он же мигающий, 2 — красный, 3 — зелёный,
##                    4 — точечный (лампочка), 5 — точечный мигающий, 6 — прожектор вниз (рабочий свет Async)
##  g_bounce (RGBAH)  отражённый свет клетки из cell_light готовых чанков: ровный, мигающий, красный, группа/8
## Высота и сила ламп — те же правила, что в ChunkBuilder._gather_lights.

const LD := preload("res://src/world/layer_data.gd")

var cells_img: Image
var lamps_img: Image
var bounce_img: Image
var cells_tex: ImageTexture
var lamps_tex: ImageTexture
var bounce_tex: ImageTexture
var floor_y := 0.0
var _bounce_dirty := false


static func cells_image(D: LayerData) -> Image:
	var n := LD.N
	var bytes := PackedByteArray()
	bytes.resize(n * n * 4)
	var we := D.wall_e
	var ws := D.wall_s
	var fl := D.flo
	var ch := D.ceil_h
	var fh := D.fh
	var rp := D.ramp
	for i in n * n:
		var f := fl[i]
		var r := (we[i] & 7) | ((ws[i] & 7) << 3)
		if f == LD.F_SOLID:
			r |= 64
		elif f == LD.F_PIT:
			r |= 128
		var k := i * 4
		bytes[k] = r
		bytes[k + 1] = ch[i]
		bytes[k + 2] = clampi(fh[i] + 128, 0, 255)
		bytes[k + 3] = rp[i]
	return Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, bytes)


static func lamps_image(D: LayerData) -> Image:
	var n := LD.N
	var img := Image.create(n, n, false, Image.FORMAT_RGBAH)
	img.fill(Color(0, 0, 0, 0))
	for z in n:
		for x in n:
			var i := z * n + x
			var k := D.light[i]
			if k == LD.L_NONE or k == LD.L_DEAD or k == LD.L_HOLE:
				continue
			var zn := D.zone[i]
			var h := D.height_m(x, z)
			if h <= 0.01:
				h = 2.7
			var y := h - 0.05
			if zn == LD.Z_FLIP:
				y = 0.06
			var I := 1.0
			var kind := 0
			var grp := 0
			var fl := D.fh[i] * 0.1
			# высокий зал или провал: светильник висит на тросах на 4.2 м над полом (как в ChunkBuilder)
			if (k == LD.L_ON or k == LD.L_FLICK) and D.lamp_hangs(x, z):
				y = fl + 4.2
				I = 2.3
			match k:
				LD.L_FLICK:
					kind = 1
					grp = LD.flick_group(x, z)
				LD.L_RED:
					I = 0.45
					y = h - 0.15
					kind = 2
				LD.L_ASYNC:
					I = 3.2
					y = 1.9
					kind = 6
				LD.L_BULB:
					I = 0.95
					y = h - 0.35
					kind = 4
				LD.L_GREEN:
					I = 0.7
					kind = 3
					grp = 7
			if zn == LD.Z_HOUSE and kind <= 1:
				kind += 4
			img.set_pixel(x, z, Color(y, I, float(kind), float(grp)))
	return img


func setup(D: LayerData) -> void:
	floor_y = D.floor_y
	cells_img = cells_image(D)
	lamps_img = lamps_image(D)
	bounce_img = Image.create(LD.N, LD.N, false, Image.FORMAT_RGBAH)
	bounce_img.fill(Color(0, 0, 0, 0))
	cells_tex = ImageTexture.create_from_image(cells_img)
	lamps_tex = ImageTexture.create_from_image(lamps_img)
	bounce_tex = ImageTexture.create_from_image(bounce_img)


## Отражённый свет клеток готового чанка (cell_light из ChunkBuilder: r, g, b уже ×2, a — группа/8)
func put_chunk(cx: int, cz: int, cl: PackedFloat32Array) -> void:
	if cl.size() < LD.CHUNK * LD.CHUNK * 4:
		return
	for j in LD.CHUNK:
		for i in LD.CHUNK:
			var k := (j * LD.CHUNK + i) * 4
			var x := posmod(cx * LD.CHUNK + i, LD.N)
			var z := posmod(cz * LD.CHUNK + j, LD.N)
			bounce_img.set_pixel(x, z, Color(cl[k], cl[k + 1], cl[k + 2], cl[k + 3]))
	_bounce_dirty = true


func flush() -> void:
	if _bounce_dirty:
		bounce_tex.update(bounce_img)
		_bounce_dirty = false


## Включить сетку в шейдерах. bounce_k — доля отражённого света, spec_k — общий множитель бликов
func bind(bounce_k: float, spec_k: float) -> void:
	RenderingServer.global_shader_parameter_set("g_cells", cells_tex)
	RenderingServer.global_shader_parameter_set("g_lamps", lamps_tex)
	RenderingServer.global_shader_parameter_set("g_bounce", bounce_tex)
	RenderingServer.global_shader_parameter_set("g_grid", Vector4(floor_y, 1.0, bounce_k, spec_k))


static func unbind() -> void:
	RenderingServer.global_shader_parameter_set("g_grid", Vector4(0.0, 0.0, 0.0, 0.0))
