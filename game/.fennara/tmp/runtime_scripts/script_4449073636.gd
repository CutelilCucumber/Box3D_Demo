extends RefCounted

func run(ctx: Variant) -> void:
	var root = ctx.get_scene_root()
	if root == null:
		ctx.error("no root")
		return
		
	# Find Box3DWorld by class
	var world: Box3DWorld = null
	for n in root.get_children():
		if n is Box3DWorld:
			world = n
			break
	if world == null:
		ctx.error("no Box3DWorld found")
		return
		
	ctx.log("root children: %d" % root.get_child_count())
	for n in root.get_children():
		ctx.log("  child: %s (%s)" % [n.name, n.get_class()])
	
	# Find mech
	var mech: Node3D = null
	for n in root.get_children():
		if n.name.begins_with("Mech"):
			mech = n
			break
	if mech == null:
		ctx.error("no mech found")
		return
		
	ctx.log("mech=%s at %s" % [mech.name, str(mech.global_position)])
