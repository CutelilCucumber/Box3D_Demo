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
	
	# Spawn a turret bolt at the mech (simulating turret fire)
	var BoltTurret = preload("res://lib/models/turrets/bolt_turret.gd")
	var turret = root.get_node_or_null("World/@Box3DBody@1480")  # laser turret
	if turret == null:
		ctx.error("no turret found")
		return
	
	ctx.log("turret=%s at %s" % [turret.name, str(turret.global_position)])
	
	# Make turret fire at mech
	var mech_pos = mech.global_position
	turret._fire_bolt(mech_pos, 0.016)
	ctx.log("turret fired at mech")
	
	await ctx.wait(0.5)
	
	# Check for scorch marks on the mech
	var scorch_count = 0
	if mech is Box3DBody:
		for c in mech.get_children():
			if c is Node3D:
				for gc in c.get_children():
					if gc is MeshInstance3D and gc.mesh is QuadMesh:
						var mat = gc.material_override
						if mat and mat.albedo_color.a > 0.01:
							scorch_count += 1
							ctx.log("scorch on mech at %s alpha=%.2f" % [str(gc.global_position), mat.albedo_color.a])
	else:
		# Mech might be a Node3D with char_body inside
		var cb = mech.char_body() if mech.has_method("char_body") else null
		if cb != null and cb is Box3DBody:
			for c in cb.get_children():
				if c is Node3D:
					for gc in c.get_children():
						if gc is MeshInstance3D and gc.mesh is QuadMesh:
							var mat = gc.material_override
							if mat and mat.albedo_color.a > 0.01:
								scorch_count += 1
								ctx.log("scorch on mech char_body at %s alpha=%.2f" % [str(gc.global_position), mat.albedo_color.a])
	
	ctx.log("scorch_on_mech=%d" % scorch_count)
