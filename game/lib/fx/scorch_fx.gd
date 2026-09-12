extends RefCounted

## A scorch decal left where a plasma bolt hits. Uses a Decal node to project
## onto the target mesh geometry, wrapping around surfaces properly.
## If `target` is provided, the decal is parented to that body so it moves with it.
##
##   ScorchFX.leave_mark(world, position, normal, target := null, size := 0.8, lifetime := 10.0)

const _Self = preload("res://lib/fx/scorch_fx.gd")

const MAX_ACTIVE := 64
static var _active := 0


static func leave_mark(parent: Node, at: Vector3, normal: Vector3,
		target: Box3DBody = null, size: float = 0.8, lifetime: float = 10.0) -> void:
	if _active >= MAX_ACTIVE or parent == null or not parent.is_inside_tree():
		return
	_active += 1

	# If we have a target body, parent the decal to it so it moves with the debris.
	var decal_parent: Node = target if target != null and is_instance_valid(target) else parent

	var decal := Decal.new()
	decal_parent.add_child(decal)
	# Position slightly above surface, oriented to project along -normal
	decal.global_position = at + normal * 0.02
	var up := Vector3.UP
	if absf(normal.dot(up)) > 0.999:
		up = Vector3.RIGHT
	decal.look_at_from_position(decal.global_position, decal.global_position - normal, up)
	decal.size = Vector3(size, size, size * 2.0)  # depth = 2x size to penetrate surface
	_make_scorch_material(decal, size, lifetime)

	var timer := Timer.new()
	timer.wait_time = lifetime + 1.0
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(func() -> void:
		_active -= 1
		decal.queue_free())
	decal.add_child(timer)


static func _make_scorch_material(decal: Decal, size: float, lifetime: float) -> void:
	# Create the scorch texture procedurally: dark radial gradient with noise
	var img: Image = Image.create(int(size * 128), int(size * 128), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx: float = img.get_width() * 0.5
	var cy: float = img.get_height() * 0.5
	var max_r: float = min(cx, cy) * 0.95
	
	for y in img.get_height():
		for x in img.get_width():
			var dx: float = x - cx
			var dy: float = y - cy
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist > max_r:
				continue
			var t: float = 1.0 - dist / max_r
			t = t * t  # ease out
			# Add subtle noise for realism
			var noise: float = sin(x * 0.17 + y * 0.23) * 0.5 + sin(x * 0.31 - y * 0.19) * 0.5
			noise = noise * 0.15 + 0.85
			var alpha: float = t * noise * 0.7
			img.set_pixel(x, y, Color(0.08, 0.06, 0.04, alpha))
	
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	decal.texture_albedo = tex
	decal.modulate = Color(1, 1, 1, 1)
	# Soften edges with fade
	decal.upper_fade = 0.2
	decal.lower_fade = 0.2
	
	# Fade out via tween on modulate alpha
	var tween := decal.create_tween()
	tween.tween_property(decal, "modulate:a", 0.0, lifetime)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)