class_name Mats
extends RefCounted
## Материалы: архитектура Комплекса (по номерам из ChunkBuilder) и предметы (prop.gdshader).
## Карта нормалей <имя>_n.png подхватывается сама, если есть; маски износа — по миру (arch.gdshader).

const ARCH := preload("res://src/shaders/arch.gdshader")
const PROP := preload("res://src/shaders/prop.gdshader")
const PROP_DS := preload("res://src/shaders/prop_ds.gdshader")
const GLASS := preload("res://src/shaders/glass.gdshader")
const WATER_CX := preload("res://src/shaders/water_cx.gdshader")
const CB := preload("res://src/world/chunk_builder.gd")

static var _arch := {}
static var _tex := {}
static var _props := {}


static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load("res://tex/%s.png" % name)
	return _tex[name]


static func has_tex(name: String) -> bool:
	return ResourceLoader.exists("res://tex/%s.png" % name)


## Материал архитектуры. extra — параметры шейдера; bump — сила карты нормалей <t1>_n (если карта есть)
static func _a(t1: String, t2: String, scale: Vector2, dirt: float, extra := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ARCH
	m.set_shader_parameter("tex", tex(t1))
	m.set_shader_parameter("tex2", tex(t2))
	m.set_shader_parameter("noise_tex", tex("noise"))
	m.set_shader_parameter("scale", scale)
	m.set_shader_parameter("dirt", dirt)
	var bump := float(extra.get("bump", 0.0))
	if bump > 0.0 and has_tex(t1 + "_n"):
		m.set_shader_parameter("nmap", tex(t1 + "_n"))
	else:
		bump = 0.0
	m.set_shader_parameter("bump", bump)
	var gname := String(extra.get("grime_tex", ""))
	if gname != "" and has_tex(gname):
		m.set_shader_parameter("grime_tex", tex(gname))
	else:
		extra["grime"] = 0.0
	for k in extra.keys():
		if k == "bump" or k == "grime_tex":
			continue
		m.set_shader_parameter(k, extra[k])
	return m


## Копия словаря a с дописанными/заменёнными ключами из b
static func _mix(a: Dictionary, b: Dictionary) -> Dictionary:
	var r := a.duplicate()
	r.merge(b, true)
	return r


static func arch(id: int) -> Material:
	if _arch.has(id):
		return _arch[id]
	var m: Material
	# обои: повтор 1.2 м (две полосы рулона по 0.6 м), износ по миру: пятна и потёки от потолка, сырость от пола
	var wall := {"bump": 1.0, "grime_mode": 1, "grime": 0.85, "grime_tex": "wall_grime", "grime_span": Vector2(4.8, 3.2)}
	var carpet := {"bump": 1.0, "spec": 0.004, "gloss": 30.0, "wet_spec": 0.07, "spec_tint": 0.85, "detile": 1.0, "grime_mode": 3, "grime_tex": "carpet_damp", "grime_span": Vector2(9.6, 9.6)}
	match id:
		CB.M_WALL_Y: m = _a("wall_yellow", "wall_yellow_dirty", Vector2(1.2, 1.2), 0.3, _mix(wall, {"spec": 0.05, "gloss": 18.0}))
		CB.M_WALL_OLD: m = _a("wall_old", "wall_old_dirty", Vector2(1.2, 1.2), 0.5, _mix(wall, {"spec": 0.03, "gloss": 12.0}))
		CB.M_WALL_CONC: m = _a("concrete", "concrete_dirty", Vector2(2.4, 2.4), 0.6, {"spec": 0.03, "gloss": 10.0, "bump": 1.0})
		CB.M_WALL_TILE: m = _a("tile", "tile_dirty", Vector2(1.2, 1.2), 0.5, {"spec": 0.35, "gloss": 120.0, "bump": 1.0, "grout": 1.0})
		CB.M_WALL_HOUSE: m = _a("wall_house", "wall_house_dirty", Vector2(1.2, 1.2), 0.4, _mix(wall, {"spec": 0.04, "gloss": 14.0, "grime": 0.5}))
		CB.M_WALL_STRETCH: m = _a("wall_yellow", "wall_yellow_dirty", Vector2(3.6, 1.2), 0.55, _mix(wall, {"spec": 0.05, "gloss": 18.0}))
		CB.M_BASE: m = _a("baseboard", "baseboard", Vector2(1.2, 0.1), 0.0, {"spec": 0.15, "gloss": 48.0, "bump": 1.0})
		CB.M_CARPET: m = _a("carpet", "carpet_wet", Vector2(1.2, 1.2), 0.15, _mix(carpet, {"dirt_scale": 0.07, "grime": 0.4, "tint": Vector3(1.24, 1.22, 1.2)}))
		CB.M_CARPET_WET: m = _a("carpet", "carpet_wet", Vector2(1.2, 1.2), 0.6, _mix(carpet, {"dirt_scale": 0.1, "grime": 0.75, "spec": 0.012, "wet_spec": 0.09, "gloss": 40.0, "tint": Vector3(1.16, 1.14, 1.12)}))
		CB.M_CARPET_OLD: m = _a("carpet_old", "carpet_wet", Vector2(1.2, 1.2), 0.3, {"spec": 0.02, "gloss": 6.0, "wet_spec": 0.08, "bump": 1.0})
		CB.M_FLOOR_CONC: m = _a("concrete_floor", "concrete_floor_dirty", Vector2(2.4, 2.4), 0.5, {"spec": 0.08, "gloss": 30.0, "wet_spec": 0.15, "bump": 0.8})
		CB.M_FLOOR_TILE: m = _a("tile", "tile_dirty", Vector2(1.2, 1.2), 0.6, {"spec": 0.35, "gloss": 120.0, "bump": 1.0, "grout": 1.0})
		CB.M_FLOOR_WOOD: m = _a("wood_floor", "wood_floor", Vector2(1.2, 1.2), 0.0, {"spec": 0.2, "gloss": 64.0, "bump": 0.8})
		CB.M_CEIL_TILE: m = _a("ceiling_tile", "ceiling_tile_dirty", Vector2(1.2, 1.2), 0.3,
			{"bump": 1.0, "grime_mode": 2, "grime": 0.9, "grime_tex": "ceil_stains", "grime_span": Vector2(9.6, 9.6), "tile_var": 1.0})
		CB.M_CEIL_CONC: m = _a("concrete", "concrete_dirty", Vector2(2.4, 2.4), 0.5, {"bump": 1.0})
		CB.M_CEIL_PLASTER: m = _a("plaster", "plaster", Vector2(1.2, 1.2), 0.0, {"bump": 0.7})
		CB.M_FIXTURE: m = _a("fixture", "fixture", Vector2(1.0, 1.0), 0.0, {"emissive": 5.0})
		CB.M_FIXTURE_DEAD: m = _a("fixture", "fixture", Vector2(1.0, 1.0), 0.0, {"emissive": 0.0, "tint": Vector3(0.9, 0.9, 0.87), "spec": 0.12, "gloss": 40.0, "lens_flat": 0.75})
		CB.M_HOLE: m = _a("concrete", "concrete", Vector2(1.0, 1.0), 0.0, {"hole_depth": 0.5})
		CB.M_PIT: m = _a("concrete", "concrete_dirty", Vector2(2.4, 2.4), 0.7, {"pit": 1.0, "tint": Vector3(0.6, 0.58, 0.5), "bump": 1.0})
		CB.M_GLASS:
			var g := ShaderMaterial.new()
			g.shader = GLASS
			g.set_shader_parameter("noise_tex", tex("noise"))
			m = g
		CB.M_CABLE: m = _a("metal", "metal", Vector2(1.0, 1.0), 0.0, {"tint": Vector3(0.75, 0.32, 0.08), "spec": 0.25, "gloss": 40.0})
		CB.M_WALL_PAINT: m = _a("wall_paint", "wall_paint_dirty", Vector2(1.2, 1.2), 0.45, _mix(wall, {"spec": 0.06, "gloss": 20.0, "grime": 0.5}))
		CB.M_WALL_SCHOOL: m = _a("wall_school", "wall_school_dirty", Vector2(1.2, 3.2), 0.35, {"spec": 0.14, "gloss": 40.0, "bump": 1.0, "anchor_floor": 1.0})
		CB.M_LINO: m = _a("linoleum", "linoleum_dirty", Vector2(1.2, 1.2), 0.45, {"spec": 0.15, "gloss": 48.0, "bump": 0.8})
		CB.M_WATER:
			var wm := ShaderMaterial.new()
			wm.shader = WATER_CX
			wm.set_shader_parameter("noise_tex", tex("noise"))
			m = wm
		# красная аварийная лампа: не выше ~1.6, иначе камера срезает её в белый квадрат
		CB.M_RED_LAMP: m = _a("fixture", "fixture", Vector2(1.0, 1.0), 0.0, {"emissive": 1.6})
		_: m = _a("wall_yellow", "wall_yellow", Vector2(1, 1), 0.0)
	_arch[id] = m
	return m


## Материал предмета. key — для кэша; params — параметры шейдера; "ds": true — двусторонний вариант
static func prop(key: String, params: Dictionary) -> ShaderMaterial:
	if _props.has(key):
		return _props[key]
	var m := ShaderMaterial.new()
	m.shader = PROP_DS if bool(params.get("ds", false)) else PROP
	m.set_shader_parameter("noise_tex", tex("noise"))
	m.set_shader_parameter("tex", tex(String(params.get("tex", "fabric"))))
	for k in params.keys():
		if k == "tex" or k == "ds":
			continue
		m.set_shader_parameter(k, params[k])
	_props[key] = m
	return m


## Быстрые варианты: цвет с текстурой
static func col(c: Color, texname := "fabric", texmix := 0.6, extra := {}) -> ShaderMaterial:
	var key := "c_%s_%s_%.2f_%s" % [c.to_html(), texname, texmix, str(extra)]
	var p := {"tex": texname, "color": Vector3(c.r, c.g, c.b), "tex_mix": texmix}
	p.merge(extra)
	return prop(key, p)
