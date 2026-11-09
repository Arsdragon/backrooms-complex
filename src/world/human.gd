class_name Human
extends Node3D
## Человек. Основной вариант — модель Microsoft Rocketbox (MIT) со скелетом Biped; запасной — из примитивов.
## В парке — живой (обычные материалы), в Комплексе — «копия»: бледная, смазанная, с кривым переносом.
## Позы задаются «суставами-посредниками» j[...] (как у примитивного человека, оси совпадают с осями модели);
## в режиме модели каждый кадр они переводятся в повороты костей (_drive).

var j := {}                 # суставы: имя -> Node3D
var parts: Array = []       # MeshInstance3D
var who := "civ_a"
var copy := false
var pose_name := "stand"
var phase := 0.0
var anim_speed := 1.0
var react := false
var breathe := 0.0
var look_target: Node3D = null
var _head_rest := Quaternion()
var _t := 0.0
var scale_h := 1.0
var _twitch := 0.0
# режим модели
var sk: Skeleton3D = null
var _chain: Array = []          # индексы костей цепочки (родители раньше детей)
var _rest := {}                 # кость -> локальный Transform3D покоя (ортонормированный)
var _arest := {}                # кость -> глобальный Basis покоя
var _b2j := {}                  # кость -> имя сустава-посредника
var _off := {}                  # имя сустава -> поправка (руки из A-позы вниз)
var _hands := {}                # "l"/"r" -> узел для предметов в руке
var _root_bone := -1
var _drive_t := 0.0

## кто в игре -> аватар Rocketbox (humans/<id>/Export/<id>.fbx)
const CAST := {"jogger": "Sports_Male_04", "mother": "Female_Adult_02", "kid": "Male_Child_01", "oldman": "Male_Adult_03",
	"couple": "Male_Adult_06", "suit": "Business_Male_02", "vendor": "Chef_Female_01", "teen": "Male_Adult_09",
	"worker": "Business_Male_06", "explorer": "Fire_Male_01", "player": "Male_Adult_05", "civ_a": "Female_Adult_04",
	"civ_b": "Female_Adult_10", "civ_c": "Female_Adult_12", "civ_d": "Male_Adult_01",
	"civ_e": "Business_Female_01", "civ_f": "Female_Adult_01", "civ_g": "Female_Adult_06", "civ_h": "Male_Adult_13",
	"civ_i": "Male_Adult_16", "civ_j": "Medical_Male_01", "civ_k": "Police_Male_01", "civ_l": "Female_Child_01",
	"civ_m": "Male_Child_02", "civ_n": "Gardener_Male_01", "civ_o": "Security_Male_01", "civ_p": "Male_Adult_14"}
# наш сустав -> кость Biped. Наши «l» стоят на −X, это правая сторона персонажа (R)
const BONES := {"pelvis": "Bip01 Pelvis", "spine": "Bip01 Spine", "chest": "Bip01 Spine2", "neck": "Bip01 Neck", "head": "Bip01 Head",
	"sh_l": "Bip01 R UpperArm", "el_l": "Bip01 R Forearm", "wr_l": "Bip01 R Hand",
	"sh_r": "Bip01 L UpperArm", "el_r": "Bip01 L Forearm", "wr_r": "Bip01 L Hand",
	"hip_l": "Bip01 R Thigh", "kn_l": "Bip01 R Calf", "an_l": "Bip01 R Foot",
	"hip_r": "Bip01 L Thigh", "kn_r": "Bip01 L Calf", "an_r": "Bip01 L Foot"}
const CHAIN := ["Bip01", "Bip01 Pelvis", "Bip01 Spine", "Bip01 Spine1", "Bip01 Spine2", "Bip01 Neck", "Bip01 Head",
	"Bip01 L Clavicle", "Bip01 L UpperArm", "Bip01 L Forearm", "Bip01 L Hand",
	"Bip01 R Clavicle", "Bip01 R UpperArm", "Bip01 R Forearm", "Bip01 R Hand",
	"Bip01 L Thigh", "Bip01 L Calf", "Bip01 L Foot", "Bip01 R Thigh", "Bip01 R Calf", "Bip01 R Foot"]
# родитель в нашей иерархии суставов
const JPARENT := {"pelvis": "", "spine": "pelvis", "chest": "spine", "neck": "chest", "head": "neck",
	"sh_l": "chest", "el_l": "sh_l", "wr_l": "el_l", "sh_r": "chest", "el_r": "sh_r", "wr_r": "el_r",
	"hip_l": "pelvis", "kn_l": "hip_l", "an_l": "kn_l", "hip_r": "pelvis", "kn_r": "hip_r", "an_r": "kn_r"}

const SKIN := [Color(0.84, 0.69, 0.58), Color(0.72, 0.54, 0.42), Color(0.55, 0.38, 0.28), Color(0.9, 0.76, 0.66)]


static func outfit(w: String, rng: RandomNumberGenerator) -> Dictionary:
	var skin: Color = SKIN[rng.randi_range(0, SKIN.size() - 1)]
	var o := {"skin": skin, "shirt": Color(0.5, 0.5, 0.5), "pants": Color(0.2, 0.22, 0.3), "shoes": Color(0.15, 0.13, 0.12),
		"hair": Color(0.18, 0.12, 0.08), "sleeves": "long", "skirt": false, "hat": "", "scale": 1.0, "build": 1.0}
	match w:
		"jogger":
			o.shirt = Color(0.12, 0.55, 0.6)
			o.pants = Color(0.12, 0.14, 0.4)
			o.shoes = Color(0.92, 0.92, 0.9)
			o.hat = "headband"
		"mother":
			o.shirt = Color(0.86, 0.55, 0.62)
			o.pants = o.skin
			o.skirt = true
			o.hair = Color(0.35, 0.22, 0.1)
			o.hat = "long_hair"
			o.build = 0.9
		"kid":
			o.shirt = Color(0.95, 0.8, 0.2)
			o.pants = Color(0.2, 0.35, 0.7)
			o.sleeves = "short"
			o.scale = 0.66
			o.shoes = Color(0.8, 0.15, 0.12)
		"oldman":
			o.shirt = Color(0.45, 0.42, 0.38)
			o.pants = Color(0.36, 0.28, 0.2)
			o.hair = Color(0.75, 0.75, 0.72)
			o.hat = "cap"
		"couple":
			o.shirt = Color(0.95, 0.95, 0.92)
			o.pants = Color(0.3, 0.4, 0.62)
			o.sleeves = "short"
		"suit":
			o.shirt = Color(0.16, 0.17, 0.2)
			o.pants = Color(0.16, 0.17, 0.2)
			o.shoes = Color(0.06, 0.05, 0.05)
			o.hat = "tie"
		"vendor":
			o.shirt = Color(0.95, 0.95, 0.93)
			o.pants = Color(0.92, 0.92, 0.9)
			o.hat = "paper_cap"
		"teen":
			o.shirt = Color(0.3, 0.42, 0.62)
			o.pants = Color(0.08, 0.08, 0.1)
			o.hair = Color(0.08, 0.06, 0.05)
		"worker":
			o.shirt = Color(0.88, 0.88, 0.85)
			o.pants = Color(0.3, 0.3, 0.32)
			o.hat = "tie"
		"explorer":
			o.shirt = Color(0.62, 0.6, 0.5)
			o.pants = Color(0.62, 0.6, 0.5)
			o.shoes = Color(0.1, 0.1, 0.1)
			o.hat = "mask"
		"player":
			o.shirt = Color(0.42, 0.18, 0.16)
			o.pants = Color(0.25, 0.32, 0.48)
			o.hair = Color(0.22, 0.15, 0.1)
		_:
			var shirts := [Color(0.7, 0.2, 0.25), Color(0.2, 0.5, 0.3), Color(0.85, 0.75, 0.55), Color(0.4, 0.3, 0.6), Color(0.9, 0.5, 0.2)]
			o.shirt = shirts[rng.randi_range(0, shirts.size() - 1)]
			o.pants = [Color(0.25, 0.32, 0.5), Color(0.3, 0.27, 0.22), Color(0.12, 0.12, 0.14)][rng.randi_range(0, 2)]
			o.sleeves = "short" if rng.randf() < 0.5 else "long"
			if rng.randf() < 0.35:
				o.hat = "long_hair"
	return o


## Сборка. mode: "park" — обычный свет (StandardMaterial3D); "copy" — копия в Комплексе
static func make(w: String, seed: int, is_copy: bool) -> Human:
	var h := Human.new()
	h.who = w
	h.copy = is_copy
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var id: String = CAST.get(w, "")
	var path := "res://humans/%s/Export/%s.fbx" % [id, id]
	if id != "" and not Cfg.has_arg("prim_humans") and ResourceLoader.exists(path):
		h._build_model(path, rng)
	else:
		h._build(outfit(w, rng), rng)
	return h


func is_model() -> bool:
	return sk != null


## Сборка из модели Rocketbox: невидимые суставы-посредники + скелет
func _build_model(path: String, rng: RandomNumberGenerator) -> void:
	var root := _joint("root", self, Vector3.ZERO)
	var ps: PackedScene = load(path)
	var inst := ps.instantiate() as Node3D
	root.add_child(inst)
	sk = _find_skel(inst)
	var tex_dir := path.get_base_dir().get_base_dir() + "/Textures/"
	for mi in _meshes(inst):
		var m := mi as MeshInstance3D
		parts.append(m)
		if m.mesh != null:
			for i in m.mesh.get_surface_count():
				var bm := m.get_active_material(i) as BaseMaterial3D
				if bm != null and bm.albedo_texture == null:
					var want := "head" if bm.resource_name.to_lower().contains("head") else "body"
					var tx := _find_tex(tex_dir, want)
					if tx != null:
						var nm2 := bm.duplicate() as BaseMaterial3D
						nm2.albedo_texture = tx
						nm2.albedo_color = Color(1, 1, 1)
						m.set_surface_override_material(i, nm2)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if copy else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if copy and m.mesh != null:
			for i in m.mesh.get_surface_count():
				m.set_surface_override_material(i, Models.complex_mat(m.get_active_material(i), {"pale": 0.5, "smear": 1.0}))
	# суставы-посредники (вне видимой иерархии), как у примитивного человека
	var px := Node3D.new()
	px.name = "_px"
	add_child(px)
	var pos := {"pelvis": Vector3(0, 0.95, 0), "spine": Vector3(0, 0.06, 0), "chest": Vector3(0, 0.26, 0), "neck": Vector3(0, 0.2, 0),
		"head": Vector3(0, 0.11, 0), "sh_l": Vector3(-0.2, 0.14, 0), "sh_r": Vector3(0.2, 0.14, 0), "el_l": Vector3(0, -0.29, 0),
		"el_r": Vector3(0, -0.29, 0), "wr_l": Vector3(0, -0.26, 0), "wr_r": Vector3(0, -0.26, 0), "hip_l": Vector3(-0.095, -0.04, 0),
		"hip_r": Vector3(0.095, -0.04, 0), "kn_l": Vector3(0, -0.44, 0), "kn_r": Vector3(0, -0.44, 0), "an_l": Vector3(0, -0.44, 0), "an_r": Vector3(0, -0.44, 0)}
	for k in BONES.keys():
		var n := Node3D.new()
		n.name = "px_" + k
		n.position = pos[k]
		px.add_child(n)
		j[k] = n
	if sk == null:
		return
	var pre := sk.get_bone_name(0).split(" ")[0] if sk.get_bone_count() > 0 else "Bip01"
	var bidx := {}
	for nm0 in CHAIN:
		var nm: String = String(nm0)
		var b := sk.find_bone(nm.replace("Bip01", pre))
		if b < 0:
			continue
		bidx[nm] = b
		_chain.append(b)
		_rest[b] = sk.get_bone_rest(b).orthonormalized()
		_arest[b] = sk.get_bone_global_rest(b).basis.orthonormalized()
	for k in BONES.keys():
		if bidx.has(BONES[k]):
			_b2j[bidx[BONES[k]]] = k
	_root_bone = bidx.get("Bip01", -1)
	# руки из A-позы — вниз
	for side in ["l", "r"]:
		var ub: int = bidx.get(BONES["sh_" + side], -1)
		var fb: int = bidx.get(BONES["el_" + side], -1)
		if ub < 0 or fb < 0:
			continue
		var v := (sk.get_bone_global_rest(fb).origin - sk.get_bone_global_rest(ub).origin).normalized()
		var q := Quaternion(v, Vector3.DOWN)
		for jn in ["sh_", "el_", "wr_"]:
			_off[jn + side] = Basis(q)
	# руки: узлы для предметов (оси как у модели)
	for side in ["l", "r"]:
		var hb: int = bidx.get(BONES["wr_" + side], -1)
		if hb < 0:
			continue
		var ba := BoneAttachment3D.new()
		ba.bone_idx = hb
		sk.add_child(ba)
		var fr := Node3D.new()
		fr.name = "hold_" + side
		var o: Basis = _off.get("wr_" + side, Basis())
		fr.basis = (o * _arest[hb]).inverse()
		ba.add_child(fr)
		_hands[side] = fr
	# «смазанное» лицо поверх головы у части копий
	if copy and rng.randf() < 0.55 and bidx.has("Bip01 Head"):
		var hb2: int = bidx["Bip01 Head"]
		var ba2 := BoneAttachment3D.new()
		ba2.bone_idx = hb2
		sk.add_child(ba2)
		var fr2 := Node3D.new()
		fr2.basis = (_arest[hb2] as Basis).inverse()
		ba2.add_child(fr2)
		var fq := QuadMesh.new()
		fq.size = Vector2(0.16, 0.21)
		var face := MeshInstance3D.new()
		face.mesh = fq
		face.material_override = Mats.prop("face_face_smear_m", {"tex": "face_smear", "tex_mix": 1.0, "alpha_cut": 0.4, "pale": 0.35, "smear": 0.8})
		face.position = Vector3(0, 0.075, 0.125)
		face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fr2.add_child(face)
		parts.append(face)
	pose("stand")
	_drive()


static func _find_tex(dir: String, part: String) -> Texture2D:
	var files: PackedStringArray = ResourceLoader.list_directory(dir) if ResourceLoader.has_method("list_directory") else DirAccess.get_files_at(dir)
	for f in files:
		var fn := String(f).trim_suffix(".import")
		if fn.contains(part) and fn.contains("color") and fn.get_extension() in ["tga", "png", "jpg"]:
			return load(dir + fn)
	return null


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _find_skel(c)
		if s != null:
			return s
	return null


func _meshes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


## Суставы-посредники -> кости скелета
func _drive() -> void:
	if sk == null:
		return
	var Q := {}
	for k in ["pelvis", "spine", "chest", "neck", "head", "sh_l", "el_l", "wr_l", "sh_r", "el_r", "wr_r", "hip_l", "kn_l", "an_l", "hip_r", "kn_r", "an_r"]:
		var p: String = JPARENT[k]
		var r := Basis((j[k] as Node3D).quaternion)
		Q[k] = r if p == "" else (Q[p] as Basis) * r
	var G := {}
	for b in _chain:
		var bi: int = b
		var par := sk.get_bone_parent(bi)
		var gp: Transform3D = G.get(par, Transform3D.IDENTITY)
		var rest: Transform3D = _rest[bi]
		if _b2j.has(bi):
			var jn: String = _b2j[bi]
			var o: Basis = _off.get(jn, Basis())
			var d: Basis = (Q[jn] as Basis) * o * (_arest[bi] as Basis)
			sk.set_bone_pose_rotation(bi, (gp.basis.inverse() * d).get_rotation_quaternion())
			G[bi] = Transform3D(d, gp * rest.origin)
			var sc := (j[jn] as Node3D).scale
			if not sc.is_equal_approx(Vector3.ONE):
				var ab: Basis = _arest[bi]
				var ax := (ab.inverse() * Vector3.UP).abs()
				var axz := (ab.inverse() * Vector3.RIGHT).abs()
				var s3 := Vector3.ONE
				# растяжение вдоль модели Y -> вдоль ближайшей оси кости; X/Z — по двум другим
				var iy := 0 if ax.x >= ax.y and ax.x >= ax.z else (1 if ax.y >= ax.z else 2)
				var ix := 0 if axz.x >= axz.y and axz.x >= axz.z else (1 if axz.y >= axz.z else 2)
				if ix == iy:
					ix = (iy + 1) % 3
				var iz := 3 - ix - iy
				s3[iy] = sc.y
				s3[ix] = sc.x
				s3[iz] = sc.z
				sk.set_bone_pose_scale(bi, s3)
			else:
				sk.set_bone_pose_scale(bi, Vector3.ONE)
		else:
			sk.set_bone_pose_rotation(bi, rest.basis.get_rotation_quaternion())
			G[bi] = gp * rest
	if _root_bone >= 0:
		var pp := (j["pelvis"] as Node3D).position
		var delta := (pp - Vector3(0, 0.95, 0)) * 0.95
		sk.set_bone_pose_position(_root_bone, (_rest[_root_bone] as Transform3D).origin + delta)


## Взгляд головы на цель (режим модели: посредник вне иерархии — считаем в локальных осях человека)
func _look_model(dt: float) -> void:
	var head: Node3D = j["head"]
	var t := to_local(look_target.global_position + Vector3(0, 1.5, 0)) - Vector3(0, 1.6, 0)
	var d := t.length()
	if d < 8.0 and d > 0.3:
		var yaw := clampf(atan2(t.x, t.z), -1.2, 1.2)
		var pitch := clampf(atan2(-t.y, Vector2(t.x, t.z).length()), -0.6, 0.6)
		var q := Quaternion.from_euler(Vector3(pitch, yaw, 0))
		head.quaternion = head.quaternion.slerp(q, clampf(dt * 0.35, 0.0, 1.0))
	else:
		head.quaternion = head.quaternion.slerp(_head_rest, clampf(dt * 0.2, 0.0, 1.0))


## Поменять параметр шейдера у всех материалов копии (плесень, бледность…)
func tune(params: Dictionary) -> void:
	for part in parts:
		var mi := part as MeshInstance3D
		if mi.material_override is ShaderMaterial:
			var m := (mi.material_override as ShaderMaterial).duplicate() as ShaderMaterial
			for k in params.keys():
				m.set_shader_parameter(k, params[k])
			mi.material_override = m
		elif mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var sm := mi.get_surface_override_material(i) as ShaderMaterial
				if sm == null:
					continue
				var m2 := sm.duplicate() as ShaderMaterial
				for k in params.keys():
					m2.set_shader_parameter(k, params[k])
				mi.set_surface_override_material(i, m2)


## Узел на голове (оси: +y вверх, +z вперёд) — для капюшона, маски
func head_frame() -> Node3D:
	if _hands.has("head"):
		return _hands["head"]
	var hb := -1
	for b in _b2j.keys():
		if _b2j[b] == "head":
			hb = b
	if sk == null or hb < 0:
		return j.get("head")
	var ba := BoneAttachment3D.new()
	ba.bone_idx = hb
	sk.add_child(ba)
	var fr := Node3D.new()
	fr.basis = (_arest[hb] as Basis).inverse()
	ba.add_child(fr)
	_hands["head"] = fr
	return fr


## Узел руки для предметов
func hand(side: String) -> Node3D:
	if _hands.has(side):
		return _hands[side]
	return j["wr_" + side]


func _mat(c: Color, kind := "fabric") -> Material:
	var tname := "fabric" if kind == "fabric" else "noise"
	if copy:
		var pale := 0.45
		return Mats.col(c, tname, 0.5 if kind == "fabric" else 0.12, {"pale": pale, "smear": 1.0})
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if kind == "fabric":
		m.albedo_texture = Mats.tex("fabric")
	m.roughness = 0.9
	return m


func _face_mat(rng: RandomNumberGenerator) -> Material:
	var tname := "face"
	if copy:
		tname = "face_smear" if rng.randf() < 0.7 else "face_blank"
	if copy:
		return Mats.prop("face_" + tname, {"tex": tname, "tex_mix": 1.0, "alpha_cut": 0.4, "pale": 0.3, "smear": 0.6})
	var m := StandardMaterial3D.new()
	m.albedo_texture = Mats.tex(tname)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.4
	m.roughness = 0.9
	return m


func _joint(name: String, parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.position = pos
	parent.add_child(n)
	j[name] = n
	return n


func _cap(parent: Node3D, r: float, length: float, mat: Material, down := true, offset := Vector3.ZERO) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = maxf(length + r * 2.0, r * 2.0 + 0.001)
	m.radial_segments = 10
	m.rings = 4
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = (Vector3(0, -length * 0.5, 0) if down else Vector3(0, length * 0.5, 0)) + offset
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if not copy else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	parts.append(mi)
	return mi


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if not copy else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	parts.append(mi)
	return mi


func _sphere(parent: Node3D, r: float, pos: Vector3, mat: Material, sc := Vector3.ONE) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 12
	m.rings = 8
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.scale = sc
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if not copy else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	parts.append(mi)
	return mi


func _build(o: Dictionary, rng: RandomNumberGenerator) -> void:
	var sc: float = o.scale
	scale_h = sc
	var b: float = o.build
	var skin := _mat(o.skin, "skin")
	var shirt := _mat(o.shirt)
	var pants := _mat(o.pants)
	var shoes := _mat(o.shoes, "skin")
	var hair := _mat(o.hair, "skin")
	var root := _joint("root", self, Vector3.ZERO)
	root.scale = Vector3.ONE * sc
	var pelvis := _joint("pelvis", root, Vector3(0, 0.95, 0))
	_box(pelvis, Vector3(0.32 * b, 0.16, 0.2), Vector3(0, 0, 0), pants)
	var spine := _joint("spine", pelvis, Vector3(0, 0.06, 0))
	var chest := _joint("chest", spine, Vector3(0, 0.26, 0))
	_cap(spine, 0.16 * b, 0.32, shirt, false, Vector3(0, 0.02, 0)).scale = Vector3(1.12, 1.0, 0.78)
	_cap(chest, 0.17 * b, 0.08, shirt, false, Vector3(0, -0.02, 0)).scale = Vector3(1.25, 1.0, 0.78)
	var neck := _joint("neck", chest, Vector3(0, 0.2, 0))
	_cap(neck, 0.05, 0.08, skin, false)
	var head := _joint("head", neck, Vector3(0, 0.11, 0))
	_sphere(head, 0.11, Vector3(0, 0.08, 0), skin, Vector3(0.92, 1.12, 1.0))
	# лицо — плоская «маска» спереди (+Z)
	var fq := QuadMesh.new()
	fq.size = Vector2(0.2, 0.24)
	var face := MeshInstance3D.new()
	face.mesh = fq
	face.material_override = _face_mat(rng)
	face.position = Vector3(0, 0.08, 0.103)
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.add_child(face)
	parts.append(face)
	j["face"] = face
	_sphere(head, 0.112, Vector3(0, 0.13, -0.012), hair, Vector3(0.95, 0.72, 1.02))
	match String(o.hat):
		"long_hair":
			_cap(head, 0.1, 0.18, hair, true, Vector3(0, 0.1, -0.05)).scale = Vector3(1.05, 1.0, 0.6)
		"cap":
			_sphere(head, 0.12, Vector3(0, 0.16, 0.0), _mat(Color(0.3, 0.28, 0.25)), Vector3(1.0, 0.45, 1.1))
			_box(head, Vector3(0.18, 0.015, 0.08), Vector3(0, 0.15, 0.12), _mat(Color(0.3, 0.28, 0.25)))
		"headband":
			_sphere(head, 0.113, Vector3(0, 0.12, 0), _mat(Color(0.95, 0.95, 0.95)), Vector3(0.95, 0.22, 1.02))
		"paper_cap":
			_box(head, Vector3(0.2, 0.07, 0.12), Vector3(0, 0.2, 0), _mat(Color(0.95, 0.95, 0.95)))
		"tie":
			_box(chest, Vector3(0.05, 0.3, 0.02), Vector3(0, -0.12, 0.14), _mat(Color(0.5, 0.08, 0.1)))
		"mask":
			_sphere(head, 0.07, Vector3(0, 0.03, 0.09), _mat(Color(0.12, 0.12, 0.12), "skin"), Vector3(1.0, 0.8, 0.7))
			_sphere(head, 0.125, Vector3(0, 0.1, 0), _mat(Color(0.6, 0.58, 0.5)), Vector3(1.05, 1.05, 1.05))
			_box(chest, Vector3(0.3, 0.4, 0.15), Vector3(0, -0.1, -0.2), _mat(Color(0.3, 0.32, 0.3)))
	# руки
	for s in [-1.0, 1.0]:
		var nm := "l" if s < 0 else "r"
		var sh := _joint("sh_" + nm, chest, Vector3(0.2 * s * b, 0.14, 0))
		_cap(sh, 0.052, 0.28, shirt)
		var el := _joint("el_" + nm, sh, Vector3(0, -0.29, 0))
		_cap(el, 0.045, 0.25, skin if o.sleeves == "short" else shirt)
		var wr := _joint("wr_" + nm, el, Vector3(0, -0.26, 0))
		_box(wr, Vector3(0.07, 0.1, 0.035), Vector3(0, -0.05, 0), skin)
	# ноги
	for s in [-1.0, 1.0]:
		var nm2 := "l" if s < 0 else "r"
		var hp := _joint("hip_" + nm2, pelvis, Vector3(0.095 * s * b, -0.04, 0))
		_cap(hp, 0.075, 0.38, pants if not o.skirt else skin)
		var kn := _joint("kn_" + nm2, hp, Vector3(0, -0.44, 0))
		_cap(kn, 0.058, 0.38, pants if not o.skirt else skin)
		var an := _joint("an_" + nm2, kn, Vector3(0, -0.44, 0))
		_box(an, Vector3(0.1, 0.07, 0.24), Vector3(0, -0.02, 0.05), shoes)
	if o.skirt:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.17
		cyl.bottom_radius = 0.3
		cyl.height = 0.5
		cyl.radial_segments = 12
		var sk := MeshInstance3D.new()
		sk.mesh = cyl
		sk.material_override = shirt
		sk.position = Vector3(0, -0.22, 0)
		pelvis.add_child(sk)
		parts.append(sk)
	_head_rest = head.quaternion


## Положить в руку предмет (узел), рука l/r
func hold(item: Node3D, side := "r", offset := Vector3(0, -0.1, 0.05)) -> void:
	var w: Node3D = hand(side)
	w.add_child(item)
	item.position = offset


func set_light(c: Color) -> void:
	_apply_light(self, c)


static func _apply_light(n: Node, c: Color) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).set_instance_shader_parameter("light_level", Vector4(c.r * 2.0, c.g * 2.0, c.b * 2.0, c.a))
	for ch in n.get_children():
		_apply_light(ch, c)


# ------------------------------------------------------------ позы

func _r(name: String, x: float, y := 0.0, z := 0.0) -> void:
	if j.has(name):
		(j[name] as Node3D).rotation = Vector3(x, y, z)


func pose(p: String, t := 0.0) -> void:
	pose_name = p
	for k in ["sh_l", "sh_r", "el_l", "el_r", "hip_l", "hip_r", "kn_l", "kn_r", "spine", "neck", "head", "chest", "an_l", "an_r"]:
		_r(k, 0.0)
	(j["pelvis"] as Node3D).position = Vector3(0, 0.95, 0)
	_r("sh_l", 0, 0, -0.08)
	_r("sh_r", 0, 0, 0.08)
	match p:
		"stand":
			_r("el_l", -0.12)
			_r("el_r", -0.12)
		"walk", "run":
			var amp := 0.5 if p == "walk" else 0.95
			var s := sin(t)
			_r("hip_l", s * amp)
			_r("hip_r", -s * amp)
			_r("kn_l", maxf(0.0, -cos(t)) * amp * 1.4)
			_r("kn_r", maxf(0.0, cos(t)) * amp * 1.4)
			_r("sh_l", -s * amp * 0.8, 0, -0.1)
			_r("sh_r", s * amp * 0.8, 0, 0.1)
			_r("el_l", -0.3 - (0.9 if p == "run" else 0.2))
			_r("el_r", -0.3 - (0.9 if p == "run" else 0.2))
			_r("spine", 0.08 if p == "walk" else 0.22)
			(j["pelvis"] as Node3D).position.y = 0.95 + absf(cos(t)) * (0.02 if p == "walk" else 0.06) - (0.0 if p == "walk" else 0.05)
		"sit":
			(j["pelvis"] as Node3D).position.y = 0.5
			_r("hip_l", -1.5, 0, 0.06)
			_r("hip_r", -1.5, 0, -0.06)
			_r("kn_l", 1.5)
			_r("kn_r", 1.5)
			_r("sh_l", -0.35, 0, -0.1)
			_r("sh_r", -0.35, 0, 0.1)
			_r("el_l", -0.7)
			_r("el_r", -0.7)
		"sit_ground":
			(j["pelvis"] as Node3D).position.y = 0.12
			_r("hip_l", -1.4, 0, 0.25)
			_r("hip_r", -1.4, 0, -0.25)
			_r("kn_l", 0.6)
			_r("kn_r", 0.6)
			_r("sh_l", 0.5, 0, -0.3)
			_r("sh_r", 0.5, 0, 0.3)
			_r("spine", -0.15)
		"read":
			pose("sit")
			pose_name = "read"
			_r("sh_l", -1.0, 0.3, -0.1)
			_r("sh_r", -1.0, -0.3, 0.1)
			_r("el_l", -0.9)
			_r("el_r", -0.9)
			_r("neck", 0.35)
		"push":
			_r("sh_l", -0.9)
			_r("sh_r", -0.9)
			_r("el_l", -0.4)
			_r("el_r", -0.4)
			_r("spine", 0.12)
		"hold_up":
			_r("sh_r", -2.6, 0, 0.2)
			_r("el_r", -0.1)
		"film":
			_r("sh_l", -1.2, 0.4, -0.2)
			_r("sh_r", -1.2, -0.4, 0.2)
			_r("el_l", -1.1)
			_r("el_r", -1.1)
		"slump":
			pose("sit")
			pose_name = "slump"
			_r("spine", 0.35)
			_r("neck", 0.6)
			_r("sh_l", 0.1, 0, -0.05)
			_r("sh_r", 0.1, 0, 0.05)
			_r("el_l", -0.2)
			_r("el_r", -0.2)
	_head_rest = (j["head"] as Node3D).quaternion


## Общая «неправильность» любой копии: асимметрия, вывернутый сустав, ноги вросли в пол
func uncanny(rng: RandomNumberGenerator) -> void:
	var head: Node3D = j["head"]
	head.rotation.z += rng.randf_range(-0.45, 0.45)
	head.rotation.x += rng.randf_range(-0.2, 0.35)
	var sl: Node3D = j["sh_l"]
	var sr: Node3D = j["sh_r"]
	sl.position.y += rng.randf_range(-0.05, 0.06)
	sr.position.y += rng.randf_range(-0.05, 0.06)
	if rng.randf() < 0.5:
		var arm: Node3D = j["sh_l" if rng.randf() < 0.5 else "sh_r"]
		arm.scale = Vector3(1, rng.randf_range(1.15, 1.45), 1)
	if rng.randf() < 0.4:
		var el: Node3D = j["el_l" if rng.randf() < 0.5 else "el_r"]
		el.rotation.x = rng.randf_range(0.5, 1.1)
	if rng.randf() < 0.3:
		var kn: Node3D = j["kn_l" if rng.randf() < 0.5 else "kn_r"]
		kn.rotation.x = rng.randf_range(-0.5, -0.25)
	(j["root"] as Node3D).position.y -= rng.randf_range(0.02, 0.07)
	_head_rest = head.quaternion


## Кривой перенос
func apply_wrong(w: String, rng: RandomNumberGenerator) -> void:
	var root: Node3D = j["root"]
	match w:
		"stretch":
			var k := rng.randi_range(0, 2)
			if k == 0:
				(j["neck"] as Node3D).scale = Vector3(1, 3.5, 1)
				(j["head"] as Node3D).scale = Vector3(1, 1.0 / 3.5, 1)
			elif k == 1:
				for n in ["hip_l", "hip_r"]:
					(j[n] as Node3D).scale = Vector3(1, 2.1, 1)
				for n2 in ["kn_l", "kn_r"]:
					(j[n2] as Node3D).scale = Vector3(1, 1.0, 1)
			else:
				root.scale = Vector3(0.7, 1.7, 0.7) * scale_h
		"hstretch":
			root.scale = Vector3(3.2, 0.95, 0.35) * scale_h
		"twist":
			(j["head"] as Node3D).rotation.y = PI * rng.randf_range(0.8, 1.0)
			(j["chest"] as Node3D).rotation.y = rng.randf_range(0.8, 1.6)
		"back":
			(j["chest"] as Node3D).rotation.y = PI
			(j["head"] as Node3D).rotation.y = 0.0
		"arms":
			if is_model():
				(j["el_l"] as Node3D).rotation.x = rng.randf_range(0.8, 1.4)
				(j["sh_r"] as Node3D).rotation = Vector3(rng.randf_range(-2.4, -1.6), 0, rng.randf_range(0.2, 0.6))
				(j["neck"] as Node3D).rotation.z = rng.randf_range(-0.6, 0.6)
			for k2 in (0 if is_model() else rng.randi_range(1, 2)):
				var extra := Node3D.new()
				(j["chest"] as Node3D).add_child(extra)
				extra.position = Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.05, 0.15), rng.randf_range(-0.08, 0.08))
				extra.rotation = Vector3(rng.randf_range(-2.5, 0.5), rng.randf_range(-1, 1), rng.randf_range(-1.2, 1.2))
				_cap(extra, 0.05, 0.55, (parts[0] as MeshInstance3D).material_override)
				_box(extra, Vector3(0.07, 0.1, 0.035), Vector3(0, -0.6, 0), (parts[2] as MeshInstance3D).material_override)
		"ceiling":
			rotation.x = PI
			position.y += 2.68
		"sunk":
			position.y -= 0.85 * scale_h
		"fused_floor":
			rotation.z = PI * 0.5
			position.y -= 0.12
		"flat":
			root.scale = Vector3(1.05, 1.0, 0.07) * scale_h
		"seated_air":
			pose("sit")
		"melt_bench":
			pose("slump")
			position.y -= 0.18
			root.scale = Vector3(1.0, 0.85, 1.0) * scale_h
		"fused":
			pass
		"corner":
			pass
		"none", "wall":
			pass
	_head_rest = (j["head"] as Node3D).quaternion


func _process(dt: float) -> void:
	_tick(dt)
	if sk != null:
		# копии далеко от камеры — обновлять скелет реже
		_drive_t -= dt
		if _drive_t <= 0.0:
			var cam := get_viewport().get_camera_3d()
			var far := cam != null and cam.global_position.distance_to(global_position) > 25.0
			_drive_t = 0.25 if far else 0.0
			_drive()


func _tick(dt: float) -> void:
	_t += dt
	if pose_name == "walk" or pose_name == "run":
		phase += dt * anim_speed * (5.2 if pose_name == "walk" else 9.0)
		pose(pose_name, phase)
		return
	if breathe > 0.0:
		var s := 1.0 + sin(_t * 1.6) * 0.02 * breathe
		(j["chest"] as Node3D).scale = Vector3(s, 1.0, s)
	if react and look_target != null and is_instance_valid(look_target) and sk != null:
		_look_model(dt)
	elif react and look_target != null and is_instance_valid(look_target):
		var head: Node3D = j["head"]
		var to := look_target.global_position + Vector3(0, 1.5, 0) - head.global_position
		var d := to.length()
		if d < 8.0 and d > 0.3:
			var tgt := head.global_transform.looking_at(look_target.global_position + Vector3(0, 1.5, 0), Vector3.UP, true)
			var parent_b := (head.get_parent() as Node3D).global_transform.basis
			var local := parent_b.orthonormalized().inverse() * tgt.basis.orthonormalized()
			head.quaternion = head.quaternion.slerp(local.get_rotation_quaternion(), clampf(dt * 0.35, 0.0, 1.0))
		else:
			head.quaternion = head.quaternion.slerp(_head_rest, clampf(dt * 0.2, 0.0, 1.0))
	if copy:
		_twitch -= dt
		if _twitch <= 0.0:
			_twitch = randf_range(4.0, 18.0)
			if randf() < 0.5 and j.has("neck"):
				var n: Node3D = j["neck"]
				n.rotation.z = randf_range(-0.25, 0.25)
