extends Node3D

const MechBody := preload("res://lib/bodies/mech_body.gd")

var _m
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
	_m = MechBody.spawn(w, Vector3(0.0, 0.05, 0.0))
	_m.set("_yaw", 1.4)


func _process(delta: float) -> void:
	_t += delta
	if _t < 3.0:
		return
	var turret: Node3D = _m.get("_turret")
	var ap: Vector3 = _m.aim_point()
	var to_t: Vector3 = ap - turret.global_position
	var target_yaw := atan2(to_t.x, to_t.z)
	var target_pitch := atan2(to_t.y, Vector2(to_t.x, to_t.z).length())
	var vis: Vector3 = _m.get("_gun_tip").global_position - turret.global_position
	var vis_yaw := atan2(vis.x, vis.z)
	var cd: Vector3 = _m.cannon_dir()
	var cd_yaw := atan2(cd.x, cd.z)
	var cd_pitch := atan2(cd.y, Vector2(cd.x, cd.z).length())
	print("[v] turret.y=%.3f turret.x=%.3f" % [turret.rotation.y, turret.rotation.x])
	print("[v] target yaw=%.3f pitch=%.3f" % [target_yaw, target_pitch])
	print("[v] vis_yaw=%.3f (converged to target?)" % vis_yaw)
	print("[v] cannon_dir yaw=%.3f pitch=%.3f" % [cd_yaw, cd_pitch])
	print("[v] yaw_err=%.3f pitch_err=%.3f" % [
		absf(wrapf(cd_yaw - target_yaw, -PI, PI)), absf(cd_pitch - target_pitch)])
	get_tree().quit(0)