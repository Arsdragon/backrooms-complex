extends SceneTree
func _init() -> void:
	for w in ["kid", "jogger"]:
		var h := Human.make(w, 1, false)
		root.add_child(h)
		print("== ", w, " model=", h.is_model(), " offs=", h._off.keys())
		var sk := h.sk
		for nm in ["Bip01 R UpperArm", "Bip01 R Forearm", "Bip01 L UpperArm", "Bip01 L Forearm"]:
			var b := sk.find_bone(nm)
			print("  ", nm, " idx=", b, " grest=", sk.get_bone_global_rest(b).origin if b >= 0 else Vector3.ZERO)
		var b2 := sk.find_bone("Bip01 L Hand")
		print("  hand pose global ", sk.get_bone_global_pose(b2).origin)
	quit()
