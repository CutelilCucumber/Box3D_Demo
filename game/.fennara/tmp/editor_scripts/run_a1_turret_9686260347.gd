@tool
extends RefCounted

func run(ctx) -> void:
	var root: Node3D = ctx.root
	ctx.log("root_class=%s children=%d" % [root.get_class(), root.get_child_count()])
	await ctx.capture(ctx.root)
	for i: int in range(root.get_child_count()):
		var c: Node = root.get_child(i)
		ctx.log("child[%d]=%s class=%s" % [i, c.get_name(), c.get_class()])