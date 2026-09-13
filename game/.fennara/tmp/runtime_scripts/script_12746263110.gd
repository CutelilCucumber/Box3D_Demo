extends RefCounted

func run(ctx: Variant) -> void:
	var root = ctx.get_scene_root()
	if root == null:
		ctx.error("No root")
		return
	
	# Find the mech
	var mech = root.get_node_or_null("MechBody")
	if mech == null:
		# Try finding by group
		var mechs = root.get_tree().get_nodes_in_group("player")
		if mechs.size() > 0:
			mech = mechs[0]
	
	if mech == null:
		ctx.error("Mech not found")
		return
	
	ctx.log("Mech found: " + mech.get_class() + " at " + str(mech.global_position))
	ctx.log("Mech active: " + str(mech.is_active()))
	ctx.log("Mech mouse_captured: " + str(mech.get("_mouse_captured")))
	
	# Test 1: Press WASD and check if mech moves
	ctx.log("=== Test 1: WASD movement ===")
	await ctx.wait(0.5)
	ctx.action("move_forward", pressed=true)
	await ctx.wait(1.0)
	var pos_after_w = mech.global_position
	ctx.log("Position after W: " + str(pos_after_w))
	ctx.action("move_forward", pressed=false)
	
	# Test 2: Move mouse while holding WASD
	ctx.log("=== Test 2: Mouse look while moving ===")
	ctx.action("move_forward", pressed=true)
	ctx.action("move_left", pressed=true)
	
	# Simulate mouse motion - move right (positive relative.x = yaw left)
	for i in range(10):
		await ctx.input_event({
			"event_type": "mouse_motion",
			"relative": Vector2(10.0, 0.0)  # move mouse right
		})
		await ctx.wait(0.016)
	
	var yaw_after = mech.get("_yaw")
	ctx.log("Yaw after mouse motion while moving: " + str(yaw_after))
	
	ctx.action("move_forward", pressed=false)
	ctx.action("move_left", pressed=false)
	await ctx.wait(0.5)
	
	# Test 3: Fire while moving
	ctx.log("=== Test 3: Fire while moving ===")
	ctx.action("move_forward", pressed=true)
	ctx.action("shoot", pressed=true)
	await ctx.wait(0.5)
	ctx.action("shoot", pressed=false)
	ctx.action("move_forward", pressed=false)
	
	ctx.log("=== All tests done ===")
	ctx.close_scene()
