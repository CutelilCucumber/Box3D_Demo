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
	
	ctx.log("INITIAL: camera pos=%.2f,%.2f,%.2f mech._pitch=%.2f _cam_dist=%.2f _cam_target_dist=%.2f" % 
		[camera.global_position.x, camera.global_position.y, camera.global_position.z, mech._pitch, mech._cam_dist, mech._cam_target_dist])
	
	# Aim DOWN by setting pitch directly
	mech._pitch = -1.5  # looking straight down
	await ctx.wait(0.2)
	
	ctx.log("AFTER AIM DOWN: camera pos=%.2f,%.2f,%.2f mech._pitch=%.2f _cam_dist=%.2f _cam_target_dist=%.2f" % 
		[camera.global_position.x, camera.global_position.y, camera.global_position.z, mech._pitch, mech._cam_dist, mech._cam_target_dist])
	
	# Aim UP
	mech._pitch = 1.5  # looking straight up
	await ctx.wait(0.2)
	
	ctx.log("AFTER AIM UP: camera pos=%.2f,%.2f,%.2f mech._pitch=%.2f _cam_dist=%.2f _cam_target_dist=%.2f" % 
		[camera.global_position.x, camera.global_position.y, camera.global_position.z, mech._pitch, mech._cam_dist, mech._cam_target_dist])
	
	# Reset pitch
	mech._pitch = -0.18
	await ctx.wait(0.2)
	
	ctx.log("RESET: camera pos=%.2f,%.2f,%.2f mech._pitch=%.2f _cam_dist=%.2f _cam_target_dist=%.2f" % 
		[camera.global_position.x, camera.global_position.y, camera.global_position.z, mech._pitch, mech._cam_dist, mech._cam_target_dist])
