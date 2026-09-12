@tool
extends RefCounted

func run(ctx) -> void:
	var root: Node = ctx.get_scene_root()
	if root == null:
		ctx.error("root null")
		return
	ctx.log("root=%s class=%s children=%d" % [root.name, root.get_class(), root.get_child_count()])

	var mi: MeshInstance3D = null
	for c: Node in root.get_children():
		if c is MeshInstance3D:
			mi = c
			break
	if mi == null:
		ctx.error("no MeshInstance3D")
		return

	var b: Basis = mi.transform.basis
	ctx.log("mi=%s" % mi.name)
	ctx.log("x_axis=%s" % str(b.x))
	ctx.log("y_axis=%s" % str(b.y))
	ctx.log("z_axis=%s" % str(b.z))

	var mesh: Mesh = mi.mesh
	ctx.log("mesh_class=%s" % mesh.get_class())
	if mesh is CapsuleMesh:
		var cm: CapsuleMesh = mesh
		ctx.log("capsule radius=%f height=%f" % [cm.radius, cm.height])

	# Which Shot-local axis does the capsule length run along?
	var aabb: AABB = mi.get_aabb()
	ctx.log("local_aabb=%s" % str(aabb))
	var ext: Vector3 = aabb.size
	# Manual longest-axis search (avoids version-specific max_axis naming).
	var longest: int = 0
	for i: int in range(1, 3):
		if ext[i] > ext[longest]:
			longest = i
	ctx.log("aabb_size=%s  longest_axis_index=%d" % [str(ext), longest])

	# Map the mesh's long local axis into Shot space.
	var long_axis_local := Vector3.ZERO
	long_axis_local[longest] = 1.0
	var long_in_shot: Vector3 = b * long_axis_local
	ctx.log("long_axis_in_shot_space=%s" % str(long_in_shot.normalized()))

	# Verify Basis.looking_at exists and check its degenerate-up handling.
	var fwd: Basis = Basis.looking_at(Vector3(0.0, 0.0, -1.0), Vector3.UP)
	ctx.log("looking_at(fwd,-Z) ok, -Z maps to %s" % str(fwd * Vector3(0.0, 0.0, -1.0)))
	var up_deg: Basis = Basis.looking_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	ctx.log("looking_at degenerate up ok, -Z maps to %s" % str(up_deg * Vector3(0.0, 0.0, -1.0)))
