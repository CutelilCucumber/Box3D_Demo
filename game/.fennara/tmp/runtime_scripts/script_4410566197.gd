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
		
	# Get the mech
	var mech = root.get_node_or_null("MechBody")
	if mech == null:
		ctx.error("no mech")
		return
		
	ctx.log("mech_pos=%s" % str(mech.global_position))
	
	# Fire the cannon
	ctx.press_action("ui_select")
	await ctx.wait(0.05)
	ctx.release_action("ui_select")
	
	await ctx.wait(0.5)
	
	# Check for scorch marks on hit bodies
	var scorch_count = 0
	for n in world.get_children():
		if n is Box3DBody:
			for c in n.get_children():
				if c is Node3D:
					for gc in c.get_children():
						if gc is MeshInstance3D and gc.mesh is QuadMesh:
							var mat = gc.material_override
							if mat and mat.albedo_color.a > 0.01:
								scorch_count += 1
								ctx.log("scorch on body %s at %s alpha=%.2f" % [n.name, str(gc.global_position), mat.albedo_color.a])
	
	ctx.log("scorch_marks_found=%d" % scorch_count)
