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
		
	ctx.log("mech=%s at %s" % [mech.name, str(mech.global_position)])
	
	# Test camera zoom and collision
	var camera = mech.camera()
	if camera != null:
		ctx.log("camera found: pos=%s" % str(camera.global_position))
		ctx.log("mech _cam_dist=%.2f _cam_target_dist=%.2f" % [mech._cam_dist, mech._cam_target_dist])
		
	# Test scroll zoom by checking if vars exist
	ctx.log("mech _cam_dist=%.2f _cam_target_dist=%.2f" % [mech._cam_dist, mech._cam_target_dist])
	
	await ctx.wait(0.1)
	
	# Check camera position after a moment
	ctx.log("camera pos=%.2f,%.2f,%.2f" % [camera.global_position.x, camera.global_position.y, camera.global_position.z])
