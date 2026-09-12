extends RefCounted

func run(ctx: Variant) -> void:
	var root: Node = ctx.get_scene_root()
	ctx.log("root=%s" % root.name)
	var sprites: Array = []
	for c in root.get_children():
		if c is Sprite3D:
			sprites.append(c)
	ctx.log("sprite3d count=%d" % sprites.size())
	for s in sprites:
		ctx.log("sprite=%s visible=%s pos=%s pixel_size=%.4f tex=%s" % [
			s.name, s.visible, s.global_position, s.pixel_size,
			"null" if s.texture == null else "ok"])
	var img: Image = await ctx.frame(1280)
	ctx.output(img, "mech gym view with aim markers")
