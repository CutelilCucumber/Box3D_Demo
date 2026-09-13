extends RefCounted

func run(ctx: Variant) -> void:
	var root = ctx.get_scene_root()
	if root == null:
		ctx.error("No root")
		return
	
	var mech = root.get_tree().get_nodes_in_group("player")[0]
	if mech == null:
		ctx.error("Mech not found")
		return
	
	ctx.log("Mech found: " + mech.get_class() + " at " + str(mech.global_position))
	ctx.log("Mech active: " + str(mech.is_active()))
	
	# Test 1: WASD movement
	ctx.log("=== Test 1: WASD movement ===")
	var start_pos = mech.global_position
	ctx.press_key(KEY_W)
	await ctx.wait(1.0)
	var pos_w = mech.global_position
	ctx.log("Position after W (1s): " + str(pos_w) + " delta: " + str(pos_w - start_pos))
	ctx.release_key(KEY_W)
	await ctx.wait(0.2)
	
	# Test 2: Mouse look while moving
	ctx.log("=== Test 2: Mouse look while moving (W+A + mouse right) ===")
	ctx.press_key(KEY_W)
	ctx.press_key(KEY_A)
	await ctx.wait(0.2)
	
	# Check initial yaw
	var yaw_before = mech.get("_yaw")
	ctx.log("Yaw before: " + str(yaw_before))
	
	# Simulate mouse motion right (positive relative.x = yaw left/negative)
	for i in range(10):
		ctx.move_mouse_relative(Vector2(10.0, 0.0))
		await ctx.wait(0.016)
	
	var yaw_after = mech.get("_yaw")
	ctx.log("Yaw after mouse motion while moving: " + str(yaw_after))
	ctx.log("Yaw delta: " + str(yaw_after - yaw_before))
	
	ctx.release_key(KEY_W)
	ctx.release_key(KEY_A)
	await ctx.wait(0.3)
	
	# Test 3: [ and ] keys (part cycling)
	ctx.log("=== Test 3: Part cycling with [ and ] ===")
	ctx.log("Body before: " + str(mech.get("body_scene")))
	ctx.log("Head before: " + str(mech.get("head_scene")))
	
	ctx.press_key(KEY_BRACKETLEFT)
	await ctx.wait(0.1)
	ctx.release_key(KEY_BRACKETLEFT)
	await ctx.wait(0.5)
	ctx.log("Body after [: " + str(mech.get("body_scene")))
	
	ctx.press_key(KEY_BRACKETRIGHT)
	await ctx.wait(0.1)
	ctx.release_key(KEY_BRACKETRIGHT)
	await ctx.wait(0.5)
	ctx.log("Head after ]: " + str(mech.get("head_scene")))
	
	ctx.log("=== All tests done ===")
	ctx.close_scene()
