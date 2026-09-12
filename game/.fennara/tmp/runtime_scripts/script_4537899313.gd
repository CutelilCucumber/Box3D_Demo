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
		ctx.error("no Box3DWorld found")
		return
		
	ctx.log("world children: %d" % world.get_child_count())
	for n in world.get_children():
		ctx.log("  %s (%s)" % [n.name, n.get_class()])
