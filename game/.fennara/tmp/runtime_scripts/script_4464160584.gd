extends RefCounted

func run(ctx: Variant) -> void:
	var root: Node = ctx.get_scene_root()
	var mech: Node = _find_mech(root)
	ctx.log("gun_tip=%s" % str(mech.gun_tip()))
	ctx.log("reclaim_tip=%s" % str(mech.reclaim_tip()))
	ctx.log("cannon_dir=%s" % str(mech.cannon_dir()))
	ctx.log("laser_dir=%s" % str(mech.laser_dir()))


func _find_mech(n: Node) -> Node:
	if n.has_method("gun_tip") and n.has_method("char_body"):
		return n
	for c in n.get_children():
		var found: Node = _find_mech(c)
		if found != null:
			return found
	return null
