extends RefCounted

func run(ctx: Variant) -> void:
	var enemies: Array = ctx.node("/root/MechGym/World")["group:enemy"] if false else []
	var root: Node = ctx.get_scene_root()
	var world: Node = root.get_node("World")
	var turrets: Array = world.get_tree().get_nodes_in_group("enemy")
	ctx.log("enemy count=%d" % turrets.size())
	if turrets.is_empty():
		ctx.error("no turrets found")
		return
	var t: Node = turrets[0]
	var pos: Vector3 = (t as Node3D).global_position
	ctx.log("turret0 class=%s pos=%s box_size=%s" % [t.get_class(), pos, str((t as Box3DBody).box_size)])
	var model: Node = t.get_child(0) if t.get_child_count() > 0 else null
	if model == null:
		ctx.log("turret has no model child")
		return
	ctx.log("model=%s children=%d" % [model.get_name(), model.get_child_count()])
	for i: int in range(model.get_child_count()):
		var c: Node = model.get_child(i)
		var mi := c as MeshInstance3D
		ctx.log("  model child[%d]=%s class=%s origin=%s" % [
			i, c.get_name(), c.get_class(), (c as Node3D).global_position - pos])
	var barrel: Node = model.get_node_or_null("Barrel")
	if barrel != null:
		var muzzle: Node = barrel.get_node_or_null("Muzzle")
		var muzzle_world: Vector3 = (muzzle as Node3D).global_position if muzzle != null else Vector3.INF
		ctx.log("barrel.rotation=%s muzzle_world=%s" % [str((barrel as Node3D).rotation), muzzle_world])
