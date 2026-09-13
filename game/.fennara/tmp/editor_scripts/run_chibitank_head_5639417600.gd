@tool
extends RefCounted

func run(ctx) -> void:
	var root: Node = ctx.get_scene_root()
	if root == null:
		ctx.error("Scene root was null")
		return
	root.scale = Vector3(1.0, 1.0, 1.0)
	ctx.log("Reverted root scale to 1.0")
	ctx.mark_modified()