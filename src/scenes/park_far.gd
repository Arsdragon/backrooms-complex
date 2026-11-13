extends RefCounted
## Дальние планы парка: кольца-полосы с силуэтами деревьев и крыш за парком, выгоревшие холмы долины Санта-Клара
## и несколько башен центра Сан-Хосе в дымке. Всё в пределах дальней плоскости камеры (700 м), туман делает остальное.

const FAR_SHADER := preload("res://src/shaders/park_far.gdshader")
const BUILDING_SHADER := preload("res://src/shaders/park_building.gdshader")


static func build(parent: Node3D, rng: RandomNumberGenerator) -> void:
	# дома за улицей (квадрат вдоль улицы), дальний слой деревьев, холмы
	_square(parent, "park_street", 91.0, 28.0, 0.0, 112.0, Color(0.9, 0.9, 0.88))
	_curbs(parent)
	_ring(parent, "park_treeline", 182.0, 27.0, -1.5, 10.0, 0.37, Color(0.95, 0.98, 0.95), 0.05)
	_ring(parent, "park_hills", 610.0, 105.0, -8.0, 5.0, 0.21, Color(1.0, 1.0, 1.0), 0.12)
	_downtown(parent, rng)


## Кольцо-полоса радиуса r, высоты h (низ на y0), текстура повторяется reps раз по кругу
static func _ring(parent: Node3D, tex: String, r: float, h: float, y0: float, reps: float, u_off: float, tint: Color, lift: float) -> void:
	var seg := 160
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	for s in seg + 1:
		var a := float(s) / seg * TAU
		var d := Vector3(cos(a), 0, sin(a))
		for e in 2:
			v.append(d * r + Vector3(0, y0 + h * e, 0))
			n.append((-d + Vector3.UP * 0.3).normalized())
			uv.append(Vector2(float(s) / seg * reps + u_off, 1.0 - e))
	for s in seg:
		var b := s * 2
		idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var m := ShaderMaterial.new()
	m.shader = FAR_SHADER
	m.set_shader_parameter("tex", Mats.tex(tex))
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("lift", lift)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## Полоса-квадрат: стороны на расстоянии e от центра, высота h, текстура длиной tile_m метров
static func _square(parent: Node3D, tex: String, e: float, h: float, y0: float, tile_m: float, tint: Color) -> void:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var corners := [Vector3(-e, 0, -e), Vector3(e, 0, -e), Vector3(e, 0, e), Vector3(-e, 0, e)]
	var u := 0.0
	for k in 4:
		var a: Vector3 = corners[k]
		var b: Vector3 = corners[(k + 1) % 4]
		var inward := (-(a + b) * 0.5).normalized()
		var seg := 24
		var base := v.size()
		for s in seg + 1:
			var p := a.lerp(b, float(s) / seg)
			for j in 2:
				v.append(p + Vector3(0, y0 + h * j, 0))
				n.append((inward + Vector3.UP * 0.3).normalized())
				uv.append(Vector2(u + a.distance_to(p) / tile_m, 1.0 - j))
		for s in seg:
			var q := base + s * 2
			idx.append_array([q, q + 1, q + 2, q + 1, q + 3, q + 2])
		u += a.distance_to(b) / tile_m + 0.31
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var m := ShaderMaterial.new()
	m.shader = FAR_SHADER
	m.set_shader_parameter("tex", Mats.tex(tex))
	m.set_shader_parameter("tint", tint)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## Центр города на севере: башни с фасадами (окна поэтажно), у части — уступ и надстройка с машинным
## отделением на крыше; в дымке почти силуэты
static func _downtown(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var m := ShaderMaterial.new()
	m.shader = BUILDING_SHADER
	m.set_shader_parameter("facade", Mats.tex("park_facade"))
	var base_a := -PI * 0.5 - 0.35
	for k in 9:
		var a := base_a + rng.randf_range(-0.22, 0.22)
		var r := rng.randf_range(380.0, 520.0)
		var h := rng.randf_range(30.0, 72.0) if k > 1 else rng.randf_range(85.0, 110.0)
		var sz := Vector3(rng.randf_range(16.0, 32.0), h, rng.randf_range(16.0, 30.0))
		var root := Node3D.new()
		root.position = Vector3(cos(a) * r, -2.0, sin(a) * r)
		root.rotation.y = rng.randf_range(-0.3, 0.3)
		parent.add_child(root)
		var cell := float(rng.randi_range(0, 3))
		var shade := rng.randf_range(0.85, 1.1)
		_tower_box(root, m, sz, sz.y * 0.5, cell, shade)
		var top := sz.y
		if rng.randf() < 0.45:
			# уступ: верхние этажи уже
			var sz2 := Vector3(sz.x * rng.randf_range(0.6, 0.8), sz.y * rng.randf_range(0.15, 0.3), sz.z * rng.randf_range(0.6, 0.8))
			_tower_box(root, m, sz2, top + sz2.y * 0.5, cell, shade)
			top += sz2.y
		# машинное отделение лифтов и парапет
		var mr := Vector3(rng.randf_range(4.0, 7.0), rng.randf_range(3.0, 5.0), rng.randf_range(4.0, 7.0))
		_tower_box(root, m, mr, top + mr.y * 0.5, 4.0, shade * 0.8)


static func _tower_box(root: Node3D, m: Material, size: Vector3, y: float, cell: float, shade: float) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = m
	mi.position.y = y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.set_instance_shader_parameter("cell", cell)
	mi.set_instance_shader_parameter("shade", shade)


## Бордюры вдоль улицы за парком (у тротуаров с обеих сторон): невысокий бетонный порожек, ловит солнце и тень
static func _curbs(parent: Node3D) -> void:
	var cm := StandardMaterial3D.new()
	cm.albedo_texture = Mats.tex("park_concrete")
	cm.albedo_color = Color(0.74, 0.72, 0.68)
	cm.uv1_triplanar = true
	cm.uv1_world_triplanar = true
	cm.uv1_scale = Vector3(0.8, 0.8, 0.8)
	cm.roughness = 0.9
	for e in [68.4, 79.35]:
		for k in 4:
			var bm := BoxMesh.new()
			bm.size = Vector3(2.0 * e + 0.2, 0.15, 0.2)
			var mi := MeshInstance3D.new()
			mi.mesh = bm
			mi.material_override = cm
			mi.position = [Vector3(0, 0.06, -e), Vector3(e, 0.06, 0), Vector3(0, 0.06, e), Vector3(-e, 0.06, 0)][k]
			mi.rotation.y = 0.0 if k % 2 == 0 else PI * 0.5
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mi)
