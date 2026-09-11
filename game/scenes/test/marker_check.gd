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
	_m = MechBody.spawn(w, Vector3(0.0, 0.05, 0.0))


var _m


func _process(delta: float) -> void:
	_t += delta
	if _t < 1.5:
		return
	print("[verify] gun_tip=%s reclaim_tip=%s" % [_m.gun_tip(), _m.reclaim_tip()])
	print("[verify] gun_found=%s reclaim_found=%s" % [
		str(_m.get("_gun_tip") != null), str(_m.get("_reclaim_tip") != null)])
	get_tree().quit(0)