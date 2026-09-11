@tool
extends RefCounted

func run(ctx) -> void:
	var root: Node3D = ctx.root
	var out: Array[String] = []
	out.append("root=%s children=%d" % [root.get_class(), root.get_child_count()])
	for i: int in range(root.get_child_count()):
		var c: Node = root.get_child(i)
		var mi := c as MeshInstance3D
		var aabb: AABB = mi.get_aabb()
		var tf: Transform3D = mi.transform
		out.append("child[%d]=%s class=%s origin=%s aabb_size=%s aabb_center=%s" % [
			i, c.get_name(), c.get_class(), tf.origin, aabb.size, aabb.get_center()])
	for line in out:
		ctx.log(line)
	var img: Image = await ctx.capture(ctx.root)
	ctx.output(img, "A1 turret split")