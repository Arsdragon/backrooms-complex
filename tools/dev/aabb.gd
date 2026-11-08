extends SceneTree
func _init() -> void:
	for d in DirAccess.get_directories_at("res://models"):
		var id := String(d)
		var bb: AABB = Models.aabb(id)
		print("%-30s pos=(%.2f %.2f %.2f) size=(%.2f %.2f %.2f)" % [id, bb.position.x, bb.position.y, bb.position.z, bb.size.x, bb.size.y, bb.size.z])
	quit()
