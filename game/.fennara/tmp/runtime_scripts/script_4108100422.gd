extends RefCounted

func run(ctx: Variant) -> void:
	# Fire a plasma bolt at the nearest wall/building
	var root = ctx.get_scene_root()
	if root == null:
		ctx.error("no root")
		return
		
	var world = root.find_child("World")
	if world == null:
		ctx.error("no World")
		return
		
	# Get the mech
	var mech = root.get_node_or_null("MechBody")
	if mech == null:
		ctx.error("no mech")
		return
		
	ctx.log("mech_pos=%s" % str(mech.global_position))
	
	# Fire the cannon
	mech.set_active(true)
	# The gun tip
	var gun_tip = mech.gun_tip()
	var dir = mech.cannon_dir()
	ctx.log("gun_tip=%s dir=%s" % [str(gun_tip), str(dir)])
	
	# Manually spawn a bolt
	var LightPlasma = preload("res://lib/models/projectiles/light_plasma.gd")
	var bolt = LightPlasma.spawn(world, gun_tip, dir * 32.0, 10.0)
	ctx.log("spawned bolt")
	
	# Wait a few frames for it to hit
	await ctx.wait(0.5)
	
	# Check if scorch marks exist
	var scorch_count = 0
	for n in world.get_children():
		if n.name.begins_with("Bolt_"):
			for c in n.get_children():
				if c.name == "MeshInstance3D":
					scorch_count += 1
	# Also check for scorch marks parented to hit bodies
	for n in world.get_children():
		if n is Box3DBody:
			for c in n.get_children():
				if c is Node3D:
					for gc in c.get_children():
						if gc is MeshInstance3D and gc.mesh is QuadMesh:
							scorch_count += 1
	
	ctx.log("scorch_marks_found=%d" % scorch_count)
	ctx.close_scene()
