extends RefCounted

func run(ctx: Variant) -> void:
	var root: Node = ctx.get_scene_root()
	var mech: Node = null
	_find_mech(root, mech)
	ctx.log("mech_found=%s" % str(mech != null))
	if mech == null:
		ctx.log("NO MECH SPAWNED")
		return
	var gt: Node3D = mech.gun_tip()
	var rt: Node3D = mech.reclaim_tip()
	ctx.log("gun_tip_global=%s" % str(gt.global_position if gt != null else "null"))
	ctx.log("reclaim_global=%s" % str(rt.global_position if rt != null else "null"))


func _find_mech(n: Node, out: Node) -> void:
	if out != null:
		return
	if n.has_method("gun_tip") and n.has_method("char_body"):
		out = n
		return
	for c in n.get_children():
		_find_mech(c, out)
