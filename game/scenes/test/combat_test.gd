extends Node3D

## Headless combat check (Phase 2): a bare world with one wall panel, one mech
## and a couple of turrets. Drives the Phase 2 damage layer deterministically:
##   - the beam's take_damage chips a panel down and the killing blow routes
##     into the fork's fracture queue (panel freed, bricks spawn)
##   - a turret survives one cannon hit and dies on the next, leaving debris
##   - a live turret's beam/bolts actually wear the mech's hp
## Run: Godot --headless --path game res://scenes/test/combat_test.tscn

const WallPanel := preload("res://lib/bodies/wall_panel.gd")
const MechBody := preload("res://lib/models/units/mech_body.gd")
const LaserTurret := preload("res://lib/models/turrets/laser_turret.gd")
const BoltTurret := preload("res://lib/models/turrets/bolt_turret.gd")
const CannonBall := preload("res://lib/bodies/cannon_ball.gd")
const BoxVis := preload("res://lib/fx/box_visuals.gd")

var _world: Box3DWorld
var _panel
var _mech
var _turret       # far away: direct-damage death test only
var _turret2      # live fight: actually engages the mech
var _cpanel       # target for the cannon-round flight check
var _cball
var _cball_start := Vector3.ZERO
var _cball_pos := Vector3.ZERO
var _cpanel_hp0 := 0.0
var _hp0 := 0.0
var _fire_t := 0.0
var _t := 0.0
var _step := 0
var _ok := true


func _ready() -> void:
	_build_world()
	_panel = WallPanel.new()
	_panel.box_size = Vector3(4.0, 3.0, 0.35)
	_panel.position = Vector3(0.0, 1.5, -6.0)
	_world.add_child(_panel)
	_mech = MechBody.spawn(_world, Vector3(0.0, 0.05, 2.0))
	_hp0 = _mech.hp
	# Far outside the turret's SIGHT_RANGE so it sleeps while we drive its
	# damage by hand (and never shoots the mech during the panel phase).
	_turret = BoltTurret.spawn(_world, Vector3(100.0, 0.05, 100.0))


func _build_world() -> void:
	_world = Box3DWorld.new()
	_world.name = "World"
	_world.worker_count = 1
	add_child(_world)
	var slab := Box3DBody.new()
	slab.body_type = Box3DBody.STATIC
	slab.box_size = Vector3(40.0, 1.0, 40.0)
	slab.position = Vector3(0.0, -0.5, 0.0)
	_world.add_child(slab)
	BoxVis.box(slab, slab.box_size, Color(0.75, 0.85, 0.65), true)


func _process(delta: float) -> void:
	_t += delta
	if _cball != null and is_instance_valid(_cball):
		_cball_pos = _cball.global_position
	match _step:
		0:
			for i in 5:  # 5 x 15 = 75 vs DEFAULT_HP 60: the last hit is lethal
				_panel.take_damage(15.0, _panel.global_position)
			_step = 1
		1:
			if _t >= 1.0:  # let the FractureQueue pump turn the panel into bricks
				var blocks := get_tree().get_nodes_in_group("block").size()
				var dead := not is_instance_valid(_panel)
				print("[combat] panel: dead=%s blocks=%d" % [dead, blocks])
				_check(dead and blocks > 0,
						"beam attrition fractures a panel into bricks")
				_step = 2
		2:
			_turret.take_damage(30.0, _turret.global_position)  # 40 - 30 = 10: lives
			_turret.take_damage(30.0, _turret.global_position)  # lethal
			_step = 3
		3:
			if _t >= 1.7:
				var blocks := get_tree().get_nodes_in_group("block").size()
				var dead := not is_instance_valid(_turret)
				print("[combat] turret: dead=%s blocks=%d" % [dead, blocks])
				_check(dead and blocks > 0,
						"a turret dies on lethal hits, leaving debris")
				# Fire the mech cannon at a fresh panel 10 m ahead.
				_cpanel = WallPanel.new()
				_cpanel.box_size = Vector3(4.0, 3.0, 0.35)
				_cpanel.position = Vector3(0.0, 1.5, 12.0)
				_world.add_child(_cpanel)
				_cpanel_hp0 = _cpanel.hp
				var from: Vector3 = _mech.muzzle_left()
				_cball = CannonBall.spawn(_world, from,
						(_cpanel.global_position - from).normalized() * 32.0,
						15.0, Color.RED)
				_cball_start = _cball.global_position
				_fire_t = _t
				_step = 4
		4:
			if _t >= _fire_t + 0.8:
				var travelled: float = _cball_pos.distance_to(_cball_start)
				var hurt: bool = not is_instance_valid(_cpanel) \
						or _cpanel.hp < _cpanel_hp0
				print("[combat] cannon round travelled %.1f m, panel hp %.0f" % [
					travelled, _cpanel.hp if is_instance_valid(_cpanel) else 0.0])
				_check(travelled > 2.0,
						"cannon round launches and travels from the shoulder")
				_check(hurt, "cannon round deals damage on contact")
				_mech.take_damage(25.0, _mech.hit_center())
				print("[combat] mech hp after 1 cannon hit = %.0f" % _mech.hp)
				_check(absf(_mech.hp - (_hp0 - 25.0)) < 0.01,
						"mech loses hp from a single hit")
				_step = 5
		5:
			if _t >= _fire_t + 1.2:
				# A laser (beam) and a bolt turret together, so the live fight
				# wears the mech down through both attack types.
				_turret2 = LaserTurret.spawn(_world, Vector3(6.0, 0.05, 2.0))
				BoltTurret.spawn(_world, Vector3(8.0, 0.05, 2.0))
				_step = 6
		6:
			if _t >= 6.5:  # several seconds of a live fight (beam + bolts)
				print("[combat] mech hp after turret fight = %.0f" % _mech.hp)
				_check(_mech.hp < _hp0 - 25.0,
						"a live turret's beam/bolts wear the mech down")
				print("[combat] RESULT -> %s" % ("PASS" if _ok else "FAIL"))
				# The exit code IS the verdict — CI must be able to gate on it.
				get_tree().quit(0 if _ok else 1)


func _check(passed: bool, what: String) -> void:
	print("[combat] %s %s" % ["PASS" if passed else "FAIL", what])
	if not passed:
		_ok = false