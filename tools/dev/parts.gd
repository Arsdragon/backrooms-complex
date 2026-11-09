extends SceneTree
## Детали (MeshInstance3D) каждой модели: имя, центр и размер — найти «наборы», где в одном файле несколько вариантов
func _init() -> void:
	for d in DirAccess.get_directories_at("res://models"):
		var id := String(d)
		var n := Models.make(id, false)
		if n == null:
			continue
		var ms: Array = Models._meshes(n)
		if ms.size() > 1:
			var parts := []
			for mi in ms:
				var m := mi as MeshInstance3D
				var bb: AABB = Models._rel_xform(m, n) * m.get_aabb()
				parts.append("%s@(%.1f,%.1f,%.1f)" % [m.name, bb.get_center().x, bb.get_center().y, bb.get_center().z])
			print("%s [%d]: %s" % [id, ms.size(), ", ".join(parts)])
		n.free()
	quit()
