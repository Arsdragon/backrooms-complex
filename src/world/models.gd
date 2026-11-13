class_name Models
extends RefCounted
## Готовые 3D-модели (Poly Haven, CC0) из res://models/<id>/<id>_1k.gltf.
## В Комплексе материалы заменяются на шейдер предметов (попиксельный свет по сетке ламп, complex_mat),
## в парке и концовках остаются обычными PBR-материалами.

const GLASS := preload("res://src/shaders/prop_glass.gdshader")

static var _scenes := {}
static var _conv := {}
static var _aabb := {}


static func path(id: String) -> String:
	return "res://models/%s/%s_1k.gltf" % [id, id]


static func has(id: String) -> bool:
	return ResourceLoader.exists(path(id))


static func _scene(id: String) -> PackedScene:
	if not _scenes.has(id):
		_scenes[id] = load(path(id)) if has(id) else null
	return _scenes[id]


## Экземпляр модели. complex=true — материалы Комплекса; extra — доп. параметры шейдера (pale, smear, mold…)
## Наборы Poly Haven, где в одном файле лежат несколько вариантов или все детали конструктора:
## оставляем только перечисленные меши одного предмета и ставим его по центру
const PARTS := {
	"modular_street_seating": ["crossbar", "legs_double", "legs_single", "suspended_support_01", "back_support_r", "back_support_l",
		"arm_rest_01", "arm_rest_02", "seat", "seat_back"],
	"metal_trash_can": ["metal_trash_can", "metal_trash_can_handle_left", "metal_trash_can_handle_right"],
	"exterior_aircon_unit": ["exterior_aircon_unit_rusted"],
	"fire_hydrant": ["fire_hydrant_aged", "fire_hydrant_cap_01_aged", "fire_hydrant_cap_02_aged", "fire_hydrant_cap_03_aged", "fire_hydrant_chain_aged"],
	"old_military_crate": ["old_military_crate_a", "old_military_crate_lid_a", "old_military_crate_loop_a", "old_military_crate_latch_a", "old_military_crate_cloth_a"],
	"vintage_suitcase": ["vintage_suitcase_01_bottom", "vintage_suitcase_01_clasp", "vintage_suitcase_01_handle", "vintage_suitcase_01_top"],
}


static func make(id: String, complex := true, extra := {}) -> Node3D:
	var ps := _scene(id)
	if ps == null:
		return null
	var n := ps.instantiate() as Node3D
	if PARTS.has(id):
		_keep_parts(n, PARTS[id])
	if complex:
		_convert(n, extra)
	else:
		_shadows(n)
	return n


static func _keep_parts(n: Node3D, keep: Array) -> void:
	var box := AABB()
	var first := true
	for mi in _meshes(n):
		var m := mi as MeshInstance3D
		if not keep.has(String(m.name)):
			m.get_parent().remove_child(m)
			m.free()
			continue
		var bb := _rel_xform(m, n) * m.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	if first:
		return
	var c := box.get_center()
	for ch in n.get_children():
		if ch is Node3D:
			(ch as Node3D).position -= Vector3(c.x, 0.0, c.z)


static func _shadows(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for c in n.get_children():
		_shadows(c)


static func _convert(n: Node, extra: Dictionary) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var src := mi.get_active_material(i)
				mi.set_surface_override_material(i, complex_mat(src, extra))
	for c in n.get_children():
		_convert(c, extra)


## Материал Комплекса из PBR-материала модели (glTF Poly Haven или FBX Rocketbox):
## альбедо, карта нормалей (*_nor_gl — OpenGL, зелёный переворачивается), ARM (AO/шероховатость/металл → блеск),
## свечение по карте (от сети — гаснет при отключении), двусторонность, прозрачность:
## стекло → prop_glass.gdshader, решётки *_opacity → вырез по яркости маски.
## extra — доп. параметры шейдера (pale, smear, mold…); "nmap" — Texture2D карты нормалей (люди Rocketbox).
static func complex_mat(src: Material, extra := {}) -> Material:
	var key := str(src.get_instance_id() if src != null else 0) + str(extra)
	if _conv.has(key):
		return _conv[key]
	var sm := src as BaseMaterial3D
	if sm != null and is_glass(sm):
		var gm := glass_mat(sm)
		_conv[key] = gm
		return gm
	var m := ShaderMaterial.new()
	m.shader = Mats.PROP
	m.set_shader_parameter("noise_tex", Mats.tex("noise"))
	m.set_shader_parameter("albedo_cap", 0.66)
	if sm != null:
		if sm.cull_mode == BaseMaterial3D.CULL_DISABLED:
			m.shader = Mats.PROP_DS
		# Color, а не Vector3: цвет материала в sRGB — шейдер (source_color) переведёт в линейный,
		# и параметр переживёт duplicate() (Human.tune)
		m.set_shader_parameter("color", sm.albedo_color)
		var at := sm.albedo_texture
		var tpath := at.resource_path.to_lower() if at != null else ""
		if at != null and tpath.contains("_opacity"):
			# у решёток Poly Haven вместо цвета — маска прозрачности: цвет — тёмный крашеный металл, вырез по маске
			m.set_shader_parameter("tex", at)
			m.set_shader_parameter("tex_mix", 0.0)
			m.set_shader_parameter("alpha_from_r", 1.0)
			m.set_shader_parameter("alpha_cut", 0.5)
			m.set_shader_parameter("color", Color(0.55, 0.54, 0.52))
			m.shader = Mats.PROP_DS
		elif at != null:
			m.set_shader_parameter("tex", at)
			m.set_shader_parameter("tex_mix", 1.0)
			if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and at.has_alpha():
				m.set_shader_parameter("alpha_cut", 0.4)
		else:
			m.set_shader_parameter("tex", Mats.tex("noise"))
			m.set_shader_parameter("tex_mix", 0.0)
		if sm.normal_enabled and sm.normal_texture != null:
			m.set_shader_parameter("nmap", sm.normal_texture)
			m.set_shader_parameter("bump", clampf(sm.normal_scale, 0.0, 2.0))
			m.set_shader_parameter("nmap_gl", 1.0)
		# ARM (R — AO, G — шероховатость, B — металл): блеск и блики считает шейдер; металл × metallicFactor
		var rt := sm.roughness_texture
		var rpath := rt.resource_path.to_lower() if rt != null else ""
		if rt != null and rpath.contains("_arm"):
			m.set_shader_parameter("arm_tex", rt)
			m.set_shader_parameter("has_arm", 1.0)
			m.set_shader_parameter("metal_k", clampf(sm.metallic, 0.0, 1.0))
		else:
			# без ARM: по коэффициентам материала (отдельная карта шероховатости — ткань, матовое)
			var rough := clampf(sm.roughness if rt == null else 0.85, 0.05, 1.0)
			var met := clampf(sm.metallic, 0.0, 1.0) if rt == null else 0.0
			m.set_shader_parameter("gloss", lerpf(160.0, 3.0, sqrt(rough)))
			m.set_shader_parameter("spec", lerpf(0.04, 0.35, met) * (1.0 - rough * 0.7))
		if sm.emission_enabled:
			var e := sm.emission
			var et := sm.emission_texture
			if et != null:
				m.set_shader_parameter("emit_tex", et)
				m.set_shader_parameter("has_emit_tex", 1.0)
				# glTF без emissiveFactor — карта как есть
				if e.r + e.g + e.b < 0.01:
					e = Color(1.0, 0.95, 0.85)
			if e.r + e.g + e.b > 0.01:
				m.set_shader_parameter("emit", clampf(sm.emission_energy_multiplier, 0.3, 1.6))
				m.set_shader_parameter("emit_color", e)
				# лампы и лампочки — от сети
				m.set_shader_parameter("powered", 1.0)
	else:
		m.set_shader_parameter("tex", Mats.tex("noise"))
		m.set_shader_parameter("tex_mix", 0.0)
		m.set_shader_parameter("color", Color(0.77, 0.77, 0.77))
	for k in extra.keys():
		if k == "ds":
			if bool(extra[k]):
				m.shader = Mats.PROP_DS
			continue
		if k == "nmap":
			m.set_shader_parameter("nmap", extra[k])
			m.set_shader_parameter("bump", float(extra.get("bump", 1.0)))
			continue
		m.set_shader_parameter(k, extra[k])
	_conv[key] = m
	return m


## Стекло модели: прозрачный материал (BLEND) с «glass» в имени (или прозрачная крышка кассетника)
static func is_glass(sm: BaseMaterial3D) -> bool:
	if sm.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
		return false
	var nm := sm.resource_name.to_lower()
	return nm.contains("glass") or nm.ends_with("_flap")


static func glass_mat(sm: BaseMaterial3D) -> ShaderMaterial:
	var g := ShaderMaterial.new()
	g.shader = GLASS
	g.set_shader_parameter("noise_tex", Mats.tex("noise"))
	var nm := sm.resource_name.to_lower()
	# у рамок с картиной и часов — почти чистое стекло, у фар и приборов — пыльнее
	var clean := nm.contains("picture_frame") or nm.contains("clock")
	g.set_shader_parameter("dirt", 0.3 if clean else 0.6)
	g.set_shader_parameter("opacity", 0.04 if clean else 0.08)
	if nm.contains("clock"):
		# выпуклое стекло циферблата: блик лампы — маленькое резкое пятно, стекло почти прозрачно,
		# циферблат и стрелки видны и «в лоб»
		g.set_shader_parameter("shine", 1600.0)
		g.set_shader_parameter("spec_gl", 0.35)
		g.set_shader_parameter("dirt", 0.15)
		g.set_shader_parameter("opacity", 0.02)
	return g


## Габариты модели (по сеткам), для подгонки размеров
static func aabb(id: String) -> AABB:
	if _aabb.has(id):
		return _aabb[id]
	var n := make(id, false)
	var box := AABB()
	var first := true
	if n != null:
		for mi in _meshes(n):
			var m := mi as MeshInstance3D
			var bb := m.get_aabb()
			var xf := _rel_xform(m, n)
			bb = xf * bb
			if first:
				box = bb
				first = false
			else:
				box = box.merge(bb)
		n.free()
	_aabb[id] = box
	return box


static func _meshes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


static func _rel_xform(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
