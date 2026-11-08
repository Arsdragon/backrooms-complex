class_name Models
extends RefCounted
## Готовые 3D-модели (Poly Haven, CC0) из res://models/<id>/<id>_1k.gltf.
## В Комплексе материалы заменяются на шейдер предметов (свет ламп из instance uniform),
## в парке и концовках остаются обычными PBR-материалами.

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
static func make(id: String, complex := true, extra := {}) -> Node3D:
	var ps := _scene(id)
	if ps == null:
		return null
	var n := ps.instantiate() as Node3D
	if complex:
		_convert(n, extra)
	else:
		_shadows(n)
	return n


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


static func complex_mat(src: Material, extra := {}) -> Material:
	var key := str(src.get_instance_id() if src != null else 0) + str(extra)
	if _conv.has(key):
		return _conv[key]
	var m := ShaderMaterial.new()
	m.shader = Mats.PROP
	m.set_shader_parameter("noise_tex", Mats.tex("noise"))
	var sm := src as BaseMaterial3D
	if sm != null:
		var c := sm.albedo_color
		m.set_shader_parameter("color", Vector3(c.r, c.g, c.b))
		if sm.albedo_texture != null:
			m.set_shader_parameter("tex", sm.albedo_texture)
			m.set_shader_parameter("tex_mix", 1.0)
		else:
			m.set_shader_parameter("tex", Mats.tex("noise"))
			m.set_shader_parameter("tex_mix", 0.0)
		if sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR or sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
			m.set_shader_parameter("alpha_cut", 0.4)
		# блеск для металла/стекла
		if sm.metallic > 0.5 or sm.roughness < 0.25:
			m.set_shader_parameter("wet", 0.35)
		if sm.emission_enabled:
			var e := sm.emission
			m.set_shader_parameter("emit", sm.emission_energy_multiplier)
			m.set_shader_parameter("emit_color", Vector3(e.r, e.g, e.b))
	else:
		m.set_shader_parameter("tex", Mats.tex("noise"))
		m.set_shader_parameter("tex_mix", 0.0)
		m.set_shader_parameter("color", Vector3(0.6, 0.6, 0.6))
	for k in extra.keys():
		m.set_shader_parameter(k, extra[k])
	_conv[key] = m
	return m


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
