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
	var turret: Node3D = _m.get("_turret")
	var gun_tip: Node3D = _m.get("_gun_tip")
	if _t < 1.0:
		if _t + delta >= 1.0:
			print("[verify] gun_tip found=%s" % str(gun_tip != null))
		return
	var aim: Vector3 = _m.aim_direction()
	var aim_yaw := atan2(aim.x, aim.z)
	var vis: Vector3 = gun_tip.global_position - turret.global_position
	var vis_yaw := atan2(vis.x, vis.z)
	if int(_t * 5.0) != int((_t - delta) * 5.0):
		print("[verify] aim_yaw=%.3f gun_yaw=%.3f err=%.3f" % [
			aim_yaw, vis_yaw, wrapf(vis_yaw - aim_yaw, -PI, PI)])
	if _t >= 3.0:
		var err := absf(wrapf(vis_yaw - aim_yaw, -PI, PI))
		print("[verify] RESULT %s (err %.3f rad)" % ["PASS" if err < 0.05 else "FAIL", err])
		get_tree().quit(0 if err < 0.05 else 1)