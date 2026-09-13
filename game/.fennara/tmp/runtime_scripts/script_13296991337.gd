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
	ctx.log("Mech mouse_captured: " + str(mech.get("_mouse_captured")))
	
	# Test 1: WASD movement
	ctx.log("=== Test 1: WASD movement ===")
	var start_pos = mech.global_position
	ctx.press_key(KEY_W)  # forward
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
	
	# Simulate mouse motion right (positive relative.x = yaw left/negative)
	for i in range(10):
		ctx.move_mouse_relative(Vector2(10.0, 0.0))
		await ctx.wait(0.016)
	
	var yaw_after = mech.get("_yaw")
	ctx.log("Yaw after mouse motion while moving: " + str(yaw_after))
	
	ctx.release_key(KEY_W)
	ctx.release_key(KEY_A)
	await ctx.wait(0.3)
	
	# Test 3: Fire while moving
	ctx.log("=== Test 3: Fire while moving ===")
	ctx.press_key(KEY_W)
	await ctx.wait(0.2)
	ctx.press_mouse(MOUSE_BUTTON_LEFT)
	await ctx.wait(0.3)
	ctx.release_mouse(MOUSE_BUTTON_LEFT)
	ctx.release_key(KEY_W)
	
	ctx.log("=== All tests done ===")
	ctx.close_scene()
