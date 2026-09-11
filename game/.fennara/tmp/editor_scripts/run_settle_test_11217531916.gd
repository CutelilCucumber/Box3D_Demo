@tool
extends RefCounted

func run(ctx) -> void:
	var glb: PackedScene = load("res://lib/fx/models/turrets/a1_turret.glb")
	var root: Node3D = glb.instantiate()
	var barrel: Node3D = root.get_node("Barrel") as Node3D
	var base_mi := root.get_node("Base") as MeshInstance3D
	ctx.log("base_aabb=%s barrel_origin_local=%s" % [str(base_mi.get_aabb()), str(barrel.position)])
	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0.0, 0.0, -0.8)
	barrel.add_child(muzzle)
	var ground := Vector3(14.0, 0.05, 7.5)
	root.position = ground
	ctx.log("barrel_pivot_world=%s" % str(barrel.global_position))
	ctx.log("muzzle_world=%s" % str(muzzle.global_position))
	var mech_pos := ground + Vector3(-14.0, 1.8, 0.0)
	var aim_dir: Vector3 = (mech_pos - barrel.global_position).normalized()
	barrel.basis = Basis.looking_at(aim_dir, Vector3.UP)
	var tip_dir: Vector3 = (muzzle.global_position - barrel.global_position).normalized()
	ctx.log("aim_dir=%s tip_dir=%s dot=%.3f" % [str(aim_dir), str(tip_dir), aim_dir.dot(tip_dir)])
	ctx.log("barrel_fwd_world=%s" % str(-barrel.global_transform.basis.z))