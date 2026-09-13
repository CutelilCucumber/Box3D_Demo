@tool
extends RefCounted

func run(ctx) -> void:
	var root: Node = ctx.get_scene_root()
	if root == null:
		ctx.error("Scene root was null")
		return
	var head: Node3D = root.get_node_or_null("chibi_head")
	if head == null:
		ctx.error("chibi_head node not found")
		return
	head.scale = Vector3(0.37, 0.37, 0.37)
	ctx.log("Set chibi_head scale to 0.37")
	ctx.mark_modified()