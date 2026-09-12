extends RefCounted

func run(ctx: Variant) -> void:
	await ctx.restart_scene()
	var root: Node = ctx.get_scene_root()
	ctx.log("restarted root=%s" % root.name)
	var world: Node = null
	for c in root.get_children():
		if c.name == "World":
			world = c
	ctx.log("world found: %s" % (world != null))
	var mechs: Array = []
	for g in get_tree().get_nodes_in_group("player"):
		mechs.append(g)
	ctx.log("player count=%d" % mechs.size())
	if mechs.is_empty():
		ctx.log("NO MECH SPAWNED")
		return
	var m = mechs[0]
	ctx.log("mech=%s gun_tip=%s reclaim_tip=%s" % [
		m.name,
		str(m.gun_tip()) if m.has_method("gun_tip") else "n/a",
		str(m.reclaim_tip()) if m.has_method("reclaim_tip") else "n/a"])
	ctx.log("mech gun_tip_global=%s" % str(m.gun_tip().global_position if m.has_method("gun_tip") and m.gun_tip() != null else "null"))
	ctx.log("mech reclaim_global=%s" % str(m.reclaim_tip().global_position if m.has_method("reclaim_tip") and m.reclaim_tip() != null else "null"))
