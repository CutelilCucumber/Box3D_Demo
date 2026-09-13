@tool
extends RefCounted

func run(ctx) -> void:
	var root: Node = ctx.get_scene_root()
	if root == null:
		ctx.error("Scene root was null")
		return
	ctx.log("Root class: " + root.get_class())
	ctx.log("Root name: " + root.get_name())
	root.scale = Vector3(0.37, 0.37, 0.37)
	ctx.log("Set root scale to 0.37")
	ctx.mark_modified()