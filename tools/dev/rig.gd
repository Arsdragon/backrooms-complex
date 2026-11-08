extends SceneTree
func _find(n: Node, cls: String) -> Array:
	var out := []
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		out.append_array(_find(c, cls))
	return out
func _init() -> void:
	for id in ["Sports_Male_04", "Chef_Female_01", "Male_Child_01"]:
		var ps: PackedScene = load("res://humans/%s/Export/%s.fbx" % [id, id])
		var n: Node = ps.instantiate()
		var sks := _find(n, "Skeleton3D")
		print("== ", id, " skeletons=", sks.size(), " meshes=", _find(n, "MeshInstance3D").size())
		var sk: Skeleton3D = sks[0]
		print("skel path ", n.get_path_to(sk), " xform ", (sk as Node3D).transform)
		var cur: Node = sk
		while cur != n:
			print("  parent ", cur.name, " ", (cur as Node3D).transform.basis.get_scale() if cur is Node3D else "")
			cur = cur.get_parent()
		for b in sk.get_bone_count():
			var nm := sk.get_bone_name(b)
			if id == "Sports_Male_04" or nm in ["Bip01 Head", "Bip01 L Hand", "Bip01 R Hand", "Bip01 L Foot", "Bip01 Pelvis"]:
				var g := sk.get_bone_global_rest(b)
				print("  %2d %-24s parent=%d pos=(%.2f %.2f %.2f)" % [b, nm, sk.get_bone_parent(b), g.origin.x, g.origin.y, g.origin.z])
		for mi in _find(n, "MeshInstance3D"):
			var m := mi as MeshInstance3D
			var s := ""
			for i in m.mesh.get_surface_count():
				var mat := m.get_active_material(i) as BaseMaterial3D
				if mat:
					s += " [%s tex=%s tr=%d]" % [mat.resource_name, mat.albedo_texture.resource_path.get_file() if mat.albedo_texture else "-", mat.transparency]
			print("  mesh ", m.name, " aabb ", m.get_aabb(), s)
	quit()
