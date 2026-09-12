extends RefCounted

func run(ctx: Variant) -> void:
	var root: Node = ctx.get_scene_root()
	var mech: Node = _find_mech(root)
	ctx.log("mech_found=%s" % str(mech != null))
	if mech == null:
		return
	var gt: Node3D = mech.gun_tip()
	var rt: Node3D = mech.reclaim_tip()
	ctx.log("gun_tip_global=%s" % str(gt.global_position if gt != null else "null"))
	ctx.log("reclaim_global=%s" % str(rt.global_position if rt != null else "null"))


func _find_mech(n: Node) -> Node:
	if n.has_method("gun_tip") and n.has_method("char_body"):
		return n
	for c in n.get_children():
		var found: Node = _find_mech(c)
		if found != null:
			return found
	return null
