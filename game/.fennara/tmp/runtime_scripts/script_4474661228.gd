extends RefCounted

func run(ctx: Variant) -> void:
	var root: Node = ctx.get_scene_root()
	var mech: Node = _find_mech(root)
	var ChibitankBody: PackedScene = load("res://lib/models/units/parts/body/chibitank_body.tscn")
	var ChibitankHead: PackedScene = load("res://lib/models/units/parts/heads/chibitank_head.tscn")
	mech.set_parts(ChibitankBody, ChibitankHead)
	await ctx.frame()
	ctx.log("AFTER SET_PARTS gun_tip=%s reclaim_tip=%s cannon_dir=%s" % [
		str(mech.gun_tip()), str(mech.reclaim_tip()), str(mech.cannon_dir())])
	# swap back to warbot default
	var WarbotBody: PackedScene = load("res://lib/models/units/parts/body/warbot_body.tscn")
	var WarbotHead: PackedScene = load("res://lib/models/units/parts/heads/warbot_head.tscn")
	mech.set_parts(WarbotBody, WarbotHead)
	await ctx.frame()
	ctx.log("SWAPPED BACK gun_tip=%s" % str(mech.gun_tip()))


func _find_mech(n: Node) -> Node:
	if n.has_method("gun_tip") and n.has_method("char_body"):
		return n
	for c in n.get_children():
		var found: Node = _find_mech(c)
		if found != null:
			return found
	return null
