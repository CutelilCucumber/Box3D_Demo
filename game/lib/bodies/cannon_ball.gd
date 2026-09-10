extends Node3D

## The mech's cannon round: a kinematic shell flown by hand, NOT a Box3D body.
## The fork's solver freezes dynamic spheres spawned near the player character
## controller (the mover's collision queries bleed velocity off them), so the
## cannon round sidesteps the solver entirely: it advances a straight arc each
## physics tick and sweeps an overlap sphere for anything carrying
## take_damage. First contact — a wall, a turret, a crate — deals the round's
## damage and frees it.
##
##   CannonBall.spawn(world, from, velocity, damage, color)

const _Self = preload("res://lib/bodies/cannon_ball.gd")

const RADIUS := 0.4          # matches the old physical ball
const GRAVITY := 9.8         # m/s^2: a gentle lob, still flat enough to read
const LIFE := 6.0            # seconds before it fizzles out
const SWEEP := 0.9           # overlap radius: ball + half a tick of travel

var _world: Box3DWorld
var _vel := Vector3.ZERO
var _damage := 0.0
var _age := 0.0


static func spawn(world: Box3DWorld, from: Vector3, vel: Vector3,
		damage: float, color: Color) -> Node3D:
	var b := _Self.new()
	b._world = world
	b._vel = vel
	b._damage = damage
	b.position = from
	world.add_child(b)
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = RADIUS
	mesh.height = RADIUS * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.6
	mat.roughness = 0.4
	mi.material_override = mat
	b.add_child(mi)
	return b


func _ready() -> void:
	add_to_group("projectile")


func _physics_process(delta: float) -> void:
	_age += delta
	_vel.y -= GRAVITY * delta
	var prev := global_position
	global_position += _vel * delta
	# Sweep the whole travelled segment (a fast round can skip a thin panel
	# if we only probe the final point).
	for t in [0.25, 0.5, 0.75, 1.0]:
		if _hit(prev.lerp(global_position, t)):
			return
	if _age >= LIFE:
		queue_free()


## Check one sample point for contact. Frees the round and deals damage on
## the first thing carrying take_damage; plain scenery also stops it.
func _hit(at: Vector3) -> bool:
	if _world == null:
		return false
	for b in _world.overlap_sphere(at, SWEEP, 0xFFFFFFFF):
		if b == self or not (b is Box3DBody):
			continue
		if b.has_method("take_damage") and _damage > 0.0:
			b.take_damage(_damage, at)
		queue_free()
		return true
	return false