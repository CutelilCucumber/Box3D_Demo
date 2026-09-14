extends RefCounted

func run(ctx: Variant) -> void:
	var root = ctx.get_scene_root()
	if root == null:
		ctx.error("no root")
		return
	
	var world: Box3DWorld = null
	for n in root.get_children():
		if n is Box3DWorld:
			world = n
			break
	if world == null:
		ctx.error("no world")
		return
	
	# Find enemies
	for n in world.get_children():
		if n is Box3DCharacterBody and n.name.begins_with("@Box3DCharacterBody"):
			ctx.log("enemy: %s at %s" % [n.name, str(n.global_position)])
	
	ctx.log("enemy group count: %d" % get_tree().get_nodes_in_group("enemy").size())
