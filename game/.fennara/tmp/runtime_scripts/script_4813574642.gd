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
	
	# Get mech's character body (the physics body)
	var cb = null
	if mech.has_method("char_body"):
		cb = mech.char_body()
	if cb == null:
		ctx.error("no char_body on mech")
		return
		
	ctx.log("mech char_body=%s at %s" % [cb.name, str(cb.global_position)])
	
	# Manually spawn a plasma bolt directly at the mech's char_body
	var LightPlasma = preload("res://lib/models/projectiles/light_plasma.gd")
	var from := cb.global_position + Vector3(-5.0, 1.0, 0.0)
	var dir := (cb.global_position - from).normalized()
	var bolt = LightPlasma.spawn(world, from, dir * 32.0, 10.0, mech)
	ctx.log("spawned bolt at mech")
	
	await ctx.wait(0.5)
	
	# Check for scorch marks on the mech's char_body
	var scorch_count = 0
	for c in cb.get_children():
		if c is Node3D:
			for gc in c.get_children():
				if gc is MeshInstance3D and gc.mesh is QuadMesh:
					var mat = gc.material_override
					if mat and mat.albedo_color.a > 0.01:
						scorch_count += 1
						ctx.log("scorch on char_body at %s alpha=%.2f" % [str(gc.global_position), mat.albedo_color.a])
	
	ctx.log("scorch_on_mech=%d" % scorch_count)
