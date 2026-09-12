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
		
	var mech = root.get_node_or_null("World/@Node3D@1473")
	if mech == null:
		ctx.error("no mech")
		return
		
	ctx.log("mech=%s at %s" % [mech.name, str(mech.global_position)])
	
	# Manually spawn a plasma bolt directly at a nearby building
	var gun_tip = mech.gun_tip()
	var dir = mech.cannon_dir()
	ctx.log("gun_tip=%s dir=%s" % [str(gun_tip), str(dir)])
	
	var LightPlasma = preload("res://lib/models/projectiles/light_plasma.gd")
	var bolt = LightPlasma.spawn(world, gun_tip, dir * 32.0, 10.0)
	ctx.log("spawned bolt")
	
	await ctx.wait(0.5)
	
	# Check for decal nodes on hit bodies
	var decal_count = 0
	for n in world.get_children():
		if n is Box3DBody:
			for c in n.get_children():
				if c is Decal:
					decal_count += 1
					ctx.log("decal on body %s at %s size=%s" % [n.name, str(c.global_position), str(c.size)])
	
	ctx.log("decals_found=%d" % decal_count)
