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
		ctx.error("no world")
		return
	
	ctx.log("world children: %d" % world.get_child_count())
	
	# Find all enemies
	var enemies = []
	for n in world.get_children():
		if n is Box3DCharacterBody and n.name.begins_with("@Box3DCharacterBody"):
			enemies.append(n)
			ctx.log("found enemy: %s at %s hp=%s" % [n.name, str(n.global_position), str(n.get("_hp")) if n.has("_hp") else "N/A"])
	
	if enemies.size() == 0:
		ctx.error("no enemies found")
		return
	
	# Test: fire a plasma bolt at the first enemy
	var enemy = enemies[0]
	var mech = root.get_node_or_null("World/@Node3D@1473") or root.get_node_or_null("@Node3D@1473")
	if mech == null:
		ctx.error("no mech")
		return
	
	ctx.log("mech at %s" % str(mech.global_position))
	ctx.log("enemy at %s" % str(enemy.global_position))
	
	# Spawn a plasma bolt from mech toward enemy
	var from = mech.gun_tip()
	var to = enemy.global_position
	var dir = (to - from).normalized()
	
	var LightPlasma = preload("res://lib/models/projectiles/light_plasma.gd")
	var _bolt = LightPlasma.spawn(world, from, dir * 32.0, 15.0, null, 0.0)
	ctx.log("spawned bolt at %s dir=%s" % [str(from), str(dir)])
	
	await ctx.wait(1.0)
	
	# Check enemy HP
	for n in world.get_children():
		if n is Box3DCharacterBody and n.name.begins_with("@Box3DCharacterBody"):
			ctx.log("enemy %s hp=%s" % [n.name, str(n.get("_hp") if n.has("_hp") else "N/A")])
	
	ctx.log("test complete")
