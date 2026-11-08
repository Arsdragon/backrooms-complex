class_name Mats
extends RefCounted
## Материалы: архитектура Комплекса (по номерам из ChunkBuilder) и предметы (prop.gdshader).

const ARCH := preload("res://src/shaders/arch.gdshader")
const PROP := preload("res://src/shaders/prop.gdshader")
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


static func _a(t1: String, t2: String, scale: Vector2, dirt: float, extra := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ARCH
	m.set_shader_parameter("tex", tex(t1))
	m.set_shader_parameter("tex2", tex(t2))
	m.set_shader_parameter("noise_tex", tex("noise"))
	m.set_shader_parameter("scale", scale)
	m.set_shader_parameter("dirt", dirt)
	for k in extra.keys():
		m.set_shader_parameter(k, extra[k])
	return m


static func arch(id: int) -> Material:
	if _arch.has(id):
		return _arch[id]
	var m: Material
	match id:
		CB.M_WALL_Y: m = _a("wall_yellow", "wall_yellow_dirty", Vector2(0.8, 0.8), 0.3)
		CB.M_WALL_OLD: m = _a("wall_old", "wall_old_dirty", Vector2(0.9, 0.9), 0.5)
		CB.M_WALL_CONC: m = _a("concrete", "concrete_dirty", Vector2(2.4, 2.4), 0.6)
		CB.M_WALL_TILE: m = _a("tile", "tile_dirty", Vector2(1.2, 1.2), 0.5)
		CB.M_WALL_HOUSE: m = _a("wall_house", "wall_house_dirty", Vector2(0.9, 0.9), 0.4)
		CB.M_WALL_STRETCH: m = _a("wall_yellow", "wall_yellow_dirty", Vector2(3.6, 0.8), 0.55)
		CB.M_BASE: m = _a("baseboard", "baseboard", Vector2(1.0, 0.4), 0.0)
		CB.M_CARPET: m = _a("carpet", "carpet_wet", Vector2(1.5, 1.5), 0.35, {"dirt_scale": 0.09})
		CB.M_CARPET_WET: m = _a("carpet", "carpet_wet", Vector2(1.5, 1.5), 0.85, {"dirt_scale": 0.12})
		CB.M_CARPET_OLD: m = _a("carpet_old", "carpet_wet", Vector2(1.2, 1.2), 0.3)
		CB.M_FLOOR_CONC: m = _a("concrete_floor", "concrete_dirty", Vector2(2.4, 2.4), 0.5)
		CB.M_FLOOR_TILE: m = _a("tile", "tile_dirty", Vector2(1.2, 1.2), 0.6)
		CB.M_FLOOR_WOOD: m = _a("wood_floor", "wood_floor", Vector2(2.4, 2.4), 0.0)
		CB.M_CEIL_TILE: m = _a("ceiling_tile", "ceiling_tile_dirty", Vector2(1.2, 1.2), 0.3)
		CB.M_CEIL_CONC: m = _a("concrete", "concrete_dirty", Vector2(2.4, 2.4), 0.5)
		CB.M_CEIL_PLASTER: m = _a("plaster", "plaster", Vector2(1.5, 1.5), 0.0)
		CB.M_FIXTURE: m = _a("fixture", "fixture", Vector2(1.0, 1.0), 0.0, {"emissive": 2.6})
		CB.M_FIXTURE_DEAD: m = _a("fixture", "fixture", Vector2(1.0, 1.0), 0.0, {"emissive": 0.0, "tint": Vector3(0.55, 0.55, 0.52)})
		CB.M_HOLE: m = _a("concrete", "concrete", Vector2(1.0, 1.0), 0.0, {"tint": Vector3(0.02, 0.02, 0.02)})
		CB.M_PIT: m = _a("concrete", "concrete_dirty", Vector2(2.4, 2.4), 0.7, {"pit": 1.0, "tint": Vector3(0.6, 0.58, 0.5)})
		CB.M_GLASS:
			var g := ShaderMaterial.new()
			g.shader = GLASS
			g.set_shader_parameter("noise_tex", tex("noise"))
			m = g
		CB.M_CABLE: m = _a("metal", "metal", Vector2(1.0, 1.0), 0.0, {"tint": Vector3(0.75, 0.32, 0.08)})
		CB.M_WALL_PAINT: m = _a("wall_paint", "wall_paint_dirty", Vector2(1.5, 1.5), 0.45)
		CB.M_WALL_SCHOOL: m = _a("wall_school", "wall_school_dirty", Vector2(2.4, 2.4), 0.35)
		CB.M_LINO: m = _a("linoleum", "linoleum_dirty", Vector2(1.2, 1.2), 0.45)
		CB.M_WATER:
			var wm := ShaderMaterial.new()
			wm.shader = WATER_CX
			wm.set_shader_parameter("noise_tex", tex("noise"))
			m = wm
		CB.M_RED_LAMP: m = _a("fixture", "fixture", Vector2(1.0, 1.0), 0.0, {"emissive": 2.2})
		_: m = _a("wall_yellow", "wall_yellow", Vector2(1, 1), 0.0)
	_arch[id] = m
	return m


## Материал предмета. key — для кэша; params — параметры шейдера
static func prop(key: String, params: Dictionary) -> ShaderMaterial:
	if _props.has(key):
		return _props[key]
	var m := ShaderMaterial.new()
	m.shader = PROP
	m.set_shader_parameter("noise_tex", tex("noise"))
	m.set_shader_parameter("tex", tex(String(params.get("tex", "fabric"))))
	for k in params.keys():
		if k == "tex":
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
