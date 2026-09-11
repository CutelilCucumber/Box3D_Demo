@tool
extends RefCounted

func run(ctx) -> void:
	var root: Node3D = ctx.root
	for i: int in range(root.get_child_count()):
		var c: Node = root.get_child(i)
		var mi := c as MeshInstance3D
		var aabb: AABB = mi.get_aabb()
		var tf: Transform3D = mi.transform
		ctx.log("child[%d]=%s origin=%s aabb_size=%s aabb_center=%s" % [
			i, c.get_name(), tf.origin, aabb.size, aabb.get_center()])
	var img: Image = await ctx.capture(ctx.root)
	ctx.output(img, "A1 turret clean split")