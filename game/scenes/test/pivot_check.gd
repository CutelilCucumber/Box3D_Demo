extends Node3D

const MechBody := preload("res://lib/bodies/mech_body.gd")

var _t := 0.0


func _ready() -> void:
	var w := Box3DWorld.new()
	w.worker_count = 1
	add_child(w)
	var slab := Box3DBody.new()
	slab.body_type = Box3DBody.STATIC
	slab.box_size = Vector3(40.0, 1.0, 40.0)
	slab.position = Vector3(0.0, -0.5, 0.0)
	w.add_child(slab)
	var m := MechBody.spawn(w, Vector3(0.0, 0.05, 0.0))
	_m = m


var _m


func _process(delta: float) -> void:
	_t += delta
	if _t < 1.5:
		return
	var robot: Node3D = _m.get("_robot")
	var torso: Node3D = _m.get("_torso")
	var body: Node3D = null
	var mesh_count := 0
	if robot != null:
		body = robot.get_child(0) as Node3D
		mesh_count = _count_meshes(body)
	print("[pivot] robot=%s body=%s meshes=%d" % [
		robot, body, mesh_count])
	if robot != null and body != null:
		var legs := 0
		var turret := 0
		for c in body.get_children():
			if c.name == "Leg_L" or c.name == "Leg_R":
				legs += 1
			elif c.name == "Turret":
				turret += 1
		print("[pivot] pivot children of Body -> Leg_L/Leg_R=%d Turret=%d" % [legs, turret])
		var leg_l: Node3D = body.get_node_or_null("Leg_L")
		var leg_r: Node3D = body.get_node_or_null("Leg_R")
		var t: Node3D = body.get_node_or_null("Turret")
		# Drive them like _animate_parts does, to confirm they accept the pose.
		if leg_l != null and leg_r != null and t != null:
			leg_l.rotation.x = 0.3
			leg_r.rotation.x = -0.3
			t.rotation.y = 0.5
			print("[pivot] pivot drive OK: leg_l=%s leg_r=%s turret=%s" % [
				leg_l.rotation, leg_r.rotation, t.rotation])
	get_tree().quit(0)


func _count_meshes(n: Node3D) -> int:
	var c := 0
	for child in n.get_children():
		if child is MeshInstance3D:
			c += 1
	return c