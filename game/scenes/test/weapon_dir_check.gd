extends Node3D

const MechBody := preload("res://lib/models/units/mech_body.gd")

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
	if _t < 2.5:
		return
	var turret: Node3D = _m.get("_turret")
	var cdir: Vector3 = _m.cannon_dir()
	var ldir: Vector3 = _m.laser_dir()
	var g: Vector3 = _m.get("_gun_tip").global_position - turret.global_position
	var r: Vector3 = _m.get("_reclaim_tip").global_position - turret.global_position
	g.y = 0.0; r.y = 0.0
	var g_yaw := atan2(g.x, g.z)
	var r_yaw := atan2(r.x, r.z)
	var cyaw := atan2(cdir.x, cdir.z)
	var lyaw := atan2(ldir.x, ldir.z)
	var ok_c := absf(wrapf(cyaw - g_yaw, -PI, PI)) < 0.01
	var ok_l := absf(wrapf(lyaw - r_yaw, -PI, PI)) < 0.01
	print("[verify] cannon_dir yaw=%.3f gun_pivot yaw=%.3f -> %s" % [cyaw, g_yaw, ok_c])
	print("[verify] laser_dir  yaw=%.3f reclaim yaw=%.3f -> %s" % [lyaw, r_yaw, ok_l])
	print("[verify] RESULT %s" % ["PASS" if (ok_c and ok_l) else "FAIL"])
	get_tree().quit(0 if (ok_c and ok_l) else 1)