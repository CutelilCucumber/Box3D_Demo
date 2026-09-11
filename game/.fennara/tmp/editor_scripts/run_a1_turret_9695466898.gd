@tool
extends RefCounted

func run(ctx) -> void:
	var root: Node3D = ctx.root
	var mesh: MeshInstance3D = root.get_child(0) as MeshInstance3D
	var aabb: AABB = mesh.get_aabb()
	ctx.log("root_class=%s children=%d" % [root.get_class(), root.get_child_count()])
	ctx.log("mesh=%s size=%s center=%s" % [mesh.get_name(), aabb.size, aabb.get_center()])
	ctx.log("mesh transform=%s" % str(mesh.transform))
	var img: Image = await ctx.capture(ctx.root)
	ctx.output(img, "A1 turret imported raw")