@tool
extends RefCounted

## Verification rig for projectile flight orientation.
##
## Spawns light_plasma bolts through the real spawn() path with several
## different velocities, then proves two things:
##   1. numerically -- the capsule's long axis (+Z of the bolt root, measured
##      from light_plasma.tscn) ends up parallel to the velocity, including the
##      near-vertical shots where the direction is parallel to the up vector.
##   2. visually -- one render of all six directions at once.
##
## Bolts are frozen with set_physics_process(false) immediately after spawn so
## no physics tick can move or free them before the capture.

const LightPlasma := preload("res://lib/models/projectiles/light_plasma.gd")

## Deliberately includes two degenerate-up directions (straight up / steep up)
## because Node3D.look_at errors on those while Basis.looking_at must not.
const DIRS := [
	Vector3(1.0, 0.0, 0.0),
	Vector3(0.0, 1.0, 0.0),
	Vector3(1.0, 1.0, 0.0),
	Vector3(1.0, -1.0, 0.0),
	Vector3(0.3, 0.9, 0.3),
	Vector3(0.9, -0.2, -0.4),
]

const LABELS := [
	"+X flat",
	"+Y straight up (degenerate)",
	"45 deg up-right",
	"45 deg down-right",
	"steep up + depth",
	"right/down/depth",
]

const POSITIONS := [
	Vector3(-2.2, 1.1, 0.0),
	Vector3(0.0, 1.1, 0.0),
	Vector3(2.2, 1.1, 0.0),
	Vector3(-2.2, -1.1, 0.0),
	Vector3(0.0, -1.1, 0.0),
	Vector3(2.2, -1.1, 0.0),
]

const VIS_SCALE := 4.0   # capsule is only 0.2 m long; enlarge for readability


func run(ctx) -> void:
	var root: Node3D = ctx.root as Node3D
	if root == null:
		ctx.error("ctx.root is not a Node3D")
		return
	ctx.log("root=%s class=%s" % [root.name, root.get_class()])

	# Hide the scene's own capsule so it cannot read as a stray seventh bolt.
	for c in root.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).visible = false

	var cam: Camera3D = Camera3D.new()
	cam.name = "ProbeCamera"
	cam.fov = 70.0
	root.add_child(cam)

	# Initialization render: the detached scene only enters a retained
	# SceneTree here, and global_basis / look_at_from_position need that.
	await ctx.capture(root, {"camera": cam})

	var backdrop: MeshInstance3D = MeshInstance3D.new()
	backdrop.name = "Backdrop"
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(24.0, 14.0)
	backdrop.mesh = quad
	var bmat: StandardMaterial3D = StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Mid-gray rather than near-black: the bolt material carries
	# GeometryInstance3D.transparency = 0.54, so a dark backdrop left the
	# half-transparent capsules with almost nothing to contrast against.
	bmat.albedo_color = Color(0.42, 0.45, 0.50)
	backdrop.material_override = bmat
	backdrop.position = Vector3(0.0, 0.0, -2.0)
	root.add_child(backdrop)

	var world: Box3DWorld = Box3DWorld.new()
	world.name = "ProbeWorld"
	root.add_child(world)

	var bolts: Array = []
	for i in DIRS.size():
		var d: Vector3 = (DIRS[i] as Vector3).normalized()
		# max_range 0 = no travel cap, damage 0 = the sweep cannot free it.
		var bolt: Node3D = LightPlasma.spawn(world, POSITIONS[i], d * 32.0, 0.0, null, 0.0)
		bolt.set_physics_process(false)
		bolt.name = "Bolt_%d" % i
		bolts.append({"bolt": bolt, "dir": d, "label": LABELS[i]})

	# Numeric proof, read before any cosmetic scaling.
	var worst: float = 1.0
	for s in bolts:
		var bolt: Node3D = s["bolt"]
		var d: Vector3 = s["dir"]
		var axis: Vector3 = bolt.global_basis.z.normalized()
		var align: float = absf(axis.dot(d))
		worst = minf(worst, align)
		ctx.log("[%-28s] dir=%s axis=%s |dot|=%.4f" % [s["label"], str(d), str(axis), align])
	ctx.log("worst_alignment=%.4f  (1.0 == capsule exactly along flight path)" % worst)

	# Scale the visual child, not the bolt root, so the oriented basis is left
	# untouched.
	for s in bolts:
		var bolt: Node3D = s["bolt"]
		for c in bolt.get_children():
			if c is Node3D:
				(c as Node3D).scale = Vector3.ONE * VIS_SCALE
				break

	cam.look_at_from_position(Vector3(0.0, 0.0, 4.2), Vector3.ZERO, Vector3.UP)

	var img: Image = await ctx.capture(root, {"camera": cam})

	# Pixel audit: do not trust the image alone, confirm the capsules actually
	# rendered. Orange at 46% alpha over the gray backdrop reads as r > g > b
	# with a wide red-blue gap, which the flat backdrop can never produce.
	img.convert(Image.FORMAT_RGB8)
	var orange: int = 0
	var samples: int = 0
	for y in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			samples += 1
			var p: Color = img.get_pixel(x, y)
			if p.r > 0.5 and p.r - p.b > 0.2:
				orange += 1
	ctx.log("audit size=%dx%d orange=%d of %d sampled (%.2f%%)" % [
			img.get_width(), img.get_height(), orange, samples,
			100.0 * float(orange) / float(maxi(samples, 1))])

	# Per-bolt placement/visibility, so an empty render can be told apart from
	# a mis-framed one.
	for s in bolts:
		var bolt: Node3D = s["bolt"]
		var shot: Node3D = null
		for c in bolt.get_children():
			if c is Node3D:
				shot = c as Node3D
				break
		ctx.log("bolt %-8s pos=%-24s visible=%-5s shot=%s shot_visible=%s" % [
				bolt.name, str(bolt.global_position),
				str(bolt.is_visible_in_tree()),
				str(shot.name) if shot != null else "none",
				str(shot.is_visible_in_tree()) if shot != null else "n/a"])

	ctx.output(img, "Plasma bolts oriented along six different flight directions")
