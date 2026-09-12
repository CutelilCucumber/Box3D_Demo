extends Node3D

## The mech's light-plasma bolt: a straight-line kinematic projectile (no
## gravity) that instantiates light_plasma.tscn as its visual. Each physics
## tick it advances in a straight line and sweeps an overlap sphere sized to
## the bolt's visual bounds; first contact — a wall, a turret, a crate —
## deals the round's damage and frees it. Turrets can pass an optional mech
## target so bolts aimed at the player's kinematic character (which has no
## physics proxy) still land.
##
##   LightPlasma.spawn(world, from, velocity, damage [, mech [, range]])

const _Self = preload("res://lib/models/projectiles/light_plasma.gd")
const PlasmaScene = preload("res://lib/models/projectiles/light_plasma.tscn")

const LIFE := 6.0        # seconds before it fizzles out
const SWEEP := 0.15      # overlap radius: matches the bolt's visual size
## Plasma weapon stats live here so any scene (mech gym, turret, future
## weapons) fires the same bolt without duplicating tunables.
const RANGE := 20.0      # m the bolt travels before it fizzles out (default)
const FIRE_INTERVAL := 0.15  # s between shots while the trigger is held

var _world: Box3DWorld
var _vel := Vector3.ZERO
var _damage := 0.0
var _age := 0.0
var _mech: Node3D = null   # optional player mech to hit (turret bolts)
var _range := RANGE        # hard max travel distance; 0 = no range cap
var _travelled := 0.0


static func spawn(world: Box3DWorld, from: Vector3, vel: Vector3,
		damage: float, mech: Node3D = null, max_range := RANGE) -> Node3D:
	var b := _Self.new()
	b._world = world
	b._vel = vel
	b._damage = damage
	b._mech = mech
	b._range = max_range
	b.position = from
	world.add_child(b)
	b.add_child(PlasmaScene.instantiate())
	return b


func _ready() -> void:
	add_to_group("projectile")


func _physics_process(delta: float) -> void:
	_age += delta
	if _range > 0.0:
		_travelled += _vel.length() * delta
		if _travelled >= _range:
			queue_free()
			return
	var prev := global_position
	global_position += _vel * delta
	if _hit_player():
		return
	# Sweep the whole travelled segment (a fast bolt can skip a thin panel if
	# we only probe the final point).
	for t in [0.25, 0.5, 0.75, 1.0]:
		if _hit(prev.lerp(global_position, t)):
			return
	if _age >= LIFE:
		queue_free()


## The player mech is a kinematic mover whose character body is not a
## Box3DBody, so the overlap sweep can't catch it — test proximity to its char
## body directly instead.
func _hit_player() -> bool:
	if _mech == null or not is_instance_valid(_mech) \
			or not _mech.has_method("char_body"):
		return false
	var cb: Box3DCharacterBody = _mech.char_body()
	if cb == null or not is_instance_valid(cb):
		return false
	if global_position.distance_to(cb.global_position) > SWEEP + 0.5:
		return false
	_mech.take_damage(_damage, cb.global_position)
	queue_free()
	return true


## Check one sample point for contact. Frees the bolt and deals damage on the
## first thing carrying take_damage; plain scenery also stops it.
func _hit(at: Vector3) -> bool:
	if _world == null:
		return false
	for b in _world.overlap_sphere(at, SWEEP, 0xFFFFFFFF):
		if not (b is Box3DBody):
			continue
		if b.has_method("take_damage") and _damage > 0.0:
			b.take_damage(_damage, at)
		queue_free()
		return true
	return false
