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


func _process(delta: float) -> void:
	_t += delta
	if _t < 1.5:
		return
	var turret: Node3D = _m.get("_turret")
	var g: Vector3 = _m.get("_gun_tip").global_position - turret.global_position
	var r: Vector3 = _m.get("_reclaim_tip").global_position - turret.global_position
	print("[m] pivot=%s" % turret.global_position)
	print("[m] gun local=(%.3f,%.3f,%.3f) yaw=%.1f pitch=%.1f" % [
		g.x, g.y, g.z, rad_to_deg(atan2(g.x, g.z)), rad_to_deg(atan2(g.y, Vector2(g.x,g.z).length()))])
	print("[m] rec local=(%.3f,%.3f,%.3f) yaw=%.1f pitch=%.1f" % [
		r.x, r.y, r.z, rad_to_deg(atan2(r.x, r.z)), rad_to_deg(atan2(r.y, Vector2(r.x,r.z).length()))])
	get_tree().quit(0)