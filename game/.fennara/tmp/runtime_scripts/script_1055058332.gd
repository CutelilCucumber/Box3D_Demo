extends RefCounted

func run(ctx: Variant) -> void:
	var root = ctx.get_scene_root()
	if root == null:
		ctx.error("no root")
		return
	
	var mech = root.get_node_or_null("World/@Node3D@1473")
	if mech == null:
		ctx.error("no mech")
		return
		
	var camera = mech.camera()
	if camera == null:
		ctx.error("no camera")
		return
	
	ctx.log("TEST COLLISION: mech at %s" % str(mech.global_position))
	
	# Move mech near a building to test collision
	# First check what's around
	var world = root.get_node_or_null("World")
	if world != null:
		ctx.log("world children: %d" % world.get_child_count())
	
	# Test scroll zoom by modifying _cam_target_dist
	ctx.log("BEFORE ZOOM: _cam_dist=%.2f _cam_target_dist=%.2f cam pos=%.2f,%.2f,%.2f" % 
		[mech._cam_dist, mech._cam_target_dist, camera.global_position.x, camera.global_position.y, camera.global_position.z])
	
	# Zoom in
	mech._cam_target_dist = 3.0
	await ctx.wait(0.5)
	
	ctx.log("AFTER ZOOM IN: _cam_dist=%.2f _cam_target_dist=%.2f cam pos=%.2f,%.2f,%.2f" % 
		[mech._cam_dist, mech._cam_target_dist, camera.global_position.x, camera.global_position.y, camera.global_position.z])
	
	# Zoom out
	mech._cam_target_dist = 10.0
	await ctx.wait(0.5)
	
	ctx.log("AFTER ZOOM OUT: _cam_dist=%.2f _cam_target_dist=%.2f cam pos=%.2f,%.2f,%.2f" % 
		[mech._cam_dist, mech._cam_target_dist, camera.global_position.x, camera.global_position.y, camera.global_position.z])
	
	# Reset
	mech._cam_target_dist = 6.5
	await ctx.wait(0.2)
	
	ctx.log("RESET: _cam_dist=%.2f _cam_target_dist=%.2f cam pos=%.2f,%.2f,%.2f" % 
		[mech._cam_dist, mech._cam_target_dist, camera.global_position.x, camera.global_position.y, camera.global_position.z])
