extends RefCounted

func run(ctx: Variant) -> void:
	await ctx.restart_scene()
	var players := get_tree().get_nodes_in_group("player")
	ctx.log("player count=%d" % players.size())
	if players.is_empty():
		ctx.log("NO MECH SPAWNED")
		return
	var m = players[0]
	var gt = m.gun_tip()
	var rt = m.reclaim_tip()
	ctx.log("gun_tip_global=%s" % str(gt.global_position if gt != null else "null"))
	ctx.log("reclaim_global=%s" % str(rt.global_position if rt != null else "null"))
