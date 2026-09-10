extends Box3DBody

## A stationary enemy turret (Phase 2): a fixed hull on a street corner with
## a rotating barrel. Two attacks, both gated on line-of-sight to the player
## mech: a continuous beam (DPS at close range ≤ BEAM_RANGE) plus a slow,
## dodgeable bolt every BOLT_PERIOD seconds (within SIGHT_RANGE). Anything the
## player can hit carries duck-typed take_damage — the same hook blast and the
## fork's fracture queue use. No pathfinding by design (defer to Phase 5).
##
##   Turret.spawn(world, Vector3(x, 0, z))

const _Self = preload("res://lib/bodies/turret.gd")
const BoxVis := preload("res://lib/fx/box_visuals.gd")
const BreakableBlock := preload("res://lib/bodies/breakable_block.gd")
const FractureFX := preload("res://lib/fx/fracture_fx.gd")

const HP := 40.0               # ~1.2 s of full laser or 2 cannon hits
const HULL_SIZE := Vector3(1.0, 1.8, 1.0)
const HULL_COLOR := Color(0.55, 0.2, 0.18)

const BEAM_DPS := 12.0         # hp/s while the beam touches the mech
const BEAM_RANGE := 25.0
const BEAM_THICK := 0.05
const SIGHT_RANGE := 60.0      # turret sleeps past this
const BOLT_PERIOD := 3.0       # seconds between lobbed bolts
const BOLT_SPEED := 11.0       # m/s — slow enough to sidestep
const BOLT_DAMAGE := 18.0
const BOLT_LIFE_TICKS := 360   # ~6 s at 60 physics ticks/s

var _hp := HP
var _mech: Node3D              # cached "player" group member
var _barrel: Node3D            # visual pivot aiming at the mech
var _beam: MeshInstance3D
var _bolts: Array = []         # { b: Box3DBody, expire: int }
var _bolt_cooldown := 0.0
var _flash_until := -1.0
var _base_color := HULL_COLOR
var _dead := false


static func spawn(world: Box3DWorld, at: Vector3) -> Box3DBody:
	var t := _Self.new()
	t.position = at  # before add_child: Box3D snapshots the transform on ready
	world.add_child(t)
	return t


func _ready() -> void:
	body_type = Box3DBody.KINEMATIC
	shape_type = Box3DBody.BOX
	box_size = HULL_SIZE
	add_to_group("enemy")
	BoxVis.box(self, HULL_SIZE, HULL_COLOR, true)
	# A barrel pivot on top of the hull: it aims at the mech and carries the
	# muzzle the beam/bolts originate from.
	_barrel = Node3D.new()
	_barrel.position = Vector3(0.0, HULL_SIZE.y * 0.5 + 0.06, 0.0)
	add_child(_barrel)
	var barrel_mi := MeshInstance3D.new()
	var barrel_mesh := BoxMesh.new()
	barrel_mesh.size = Vector3(0.16, 0.16, 0.7)
	barrel_mi.mesh = barrel_mesh
	var gun := StandardMaterial3D.new()
	gun.albedo_color = Color(0.22, 0.2, 0.2)
	gun.metallic = 0.5
	gun.roughness = 0.6
	barrel_mi.material_override = gun
	barrel_mi.position = Vector3(0.0, 0.0, 0.35)
	_barrel.add_child(barrel_mi)


## The mech ships shots duck-typed on take_damage, same as panels do.
func take_damage(amount: float, _at: Vector3) -> void:
	if _dead:
		return
	_hp -= amount
	_flash_until = Time.get_ticks_msec() + 100.0
	BoxVis.recolor(self, HULL_COLOR.lerp(Color(1.0, 0.4, 0.3), 0.8))
	if _hp <= 0.0:
		_die()


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_flash_tick()
	_sweep_bolts()
	var mech := _find_mech()
	if mech == null or (mech.has_method("is_active") and not mech.is_active()):
		_set_beam_visible(false)
		return
	var mech_pos: Vector3 = mech.hit_center()

	var dist := _barrel.global_position.distance_to(mech_pos)
	if dist > SIGHT_RANGE or not _los_clear(mech_pos):
		_set_beam_visible(false)
		return
	# Keep the barrel tracking the mech whenever it is engaged.
	_barrel.look_at(mech_pos, Vector3.UP)
	# Beam attack: close range, continuous DPS.
	if dist <= BEAM_RANGE:
		mech.take_damage(BEAM_DPS * delta, mech_pos)
		_set_beam_visible(true, mech_pos)
	# Bolt attack: on its own countdown, independent of beam range.
	_bolt_cooldown -= delta
	if _bolt_cooldown <= 0.0:
		_bolt_cooldown = BOLT_PERIOD
		_fire_bolt(mech_pos, delta)


func _flash_tick() -> void:
	if _flash_until < 0.0:
		return
	if Time.get_ticks_msec() >= _flash_until:
		_flash_until = -1.0
		BoxVis.recolor(self, HULL_COLOR)


func _find_mech() -> Node3D:
	if _mech != null and is_instance_valid(_mech):
		return _mech
	_mech = null
	for n in get_tree().get_nodes_in_group("player"):
		_mech = n
		break
	return _mech


## Line-of-sight from the barrel muzzle to the target point. The mech's
## character body is a query-based mover with no shape proxy, so the ray can
## never hit it directly — LOS is instead "nothing solid blocks the shot":
## a hit that lands well before the target means geometry is in the way.
func _los_clear(target: Vector3) -> bool:
	var from: Vector3 = _barrel.global_position
	var dir: Vector3 = target - from
	var dist := dir.length()
	if dist < 0.01:
		return true
	var hit: Dictionary = (get_parent() as Box3DWorld).raycast(from, from + dir.normalized() * dist)
	if not hit.get("hit", false):
		return true  # nothing between the barrel and the target point
	# A hit AT the target is the mech shell or a body we are standing on;
	# a hit short of it is geometry blocking the shot.
	return hit["position"].distance_to(target) < 1.5


func _set_beam_visible(on: bool, target := Vector3.ZERO) -> void:
	if _beam == null and not on:
		return
	if _beam == null:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(BEAM_THICK, BEAM_THICK, 1.0)
		_beam = MeshInstance3D.new()
		_beam.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.55, 0.15)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.5, 0.1)
		mat.emission_energy_multiplier = 5.0
		_beam.material_override = mat
		add_child(_beam)
		_beam.top_level = true
	_beam.visible = on
	if not on:
		return
	var from: Vector3 = _barrel.global_position
	var length := maxf(from.distance_to(target), 0.01)
	_beam.global_position = (from + target) * 0.5
	_beam.look_at(target, Vector3.UP)
	_beam.scale = Vector3(1.0, 1.0, length)


## Lob a slow bolt at the mech's CURRENT position: standing still means a hit.
func _fire_bolt(target: Vector3, _delta: float) -> void:
	var from: Vector3 = _barrel.global_position
	var dir := (target - from).normalized()
	var bolt := Box3DBody.new()
	bolt.shape_type = Box3DBody.SPHERE
	bolt.sphere_radius = 0.22
	bolt.density = 4.0
	bolt.add_to_group("projectile")
	# Spawn a bolt-length out along the shot so the round never spawns
	# overlapping the turret's own hull (a spawn-overlap makes the solver
	# freeze the bolt's velocity as if it hit a wall).
	bolt.position = from + dir * 1.2
	bolt.contact_monitor = true
	bolt.body_entered.connect(_on_bolt_hit.bind(bolt))
	get_parent().add_child(bolt)
	bolt.set_linear_velocity(dir * BOLT_SPEED)
	_bolts.append({"b": bolt, "expire": Engine.get_physics_frames() + BOLT_LIFE_TICKS})
	BoxVis.sphere(bolt, 0.22, Color(1.0, 0.5, 0.2))


## Contact or cleanup: damage whatever was hit (mech char or a take_damage
## body), then free the bolt. The mech's char body is matched separately so a
## bolt clipping the character still deals damage even if has_method fails.
func _on_bolt_hit(other, bolt: Box3DBody) -> void:
	_remove_bolt(bolt)
	if other == null or not is_instance_valid(other):
		return
	var mech := _find_mech()
	if mech != null and mech.has_method("char_body") \
			and other == mech.char_body() and mech.has_method("take_damage"):
		mech.take_damage(BOLT_DAMAGE, mech.hit_center())
	elif other.has_method("take_damage"):
		other.take_damage(BOLT_DAMAGE, other.global_position)


func _remove_bolt(bolt: Box3DBody) -> void:
	for i in range(_bolts.size() - 1, -1, -1):
		if _bolts[i]["b"] == bolt:
			_bolts.remove_at(i)
	if is_instance_valid(bolt):
		bolt.queue_free()


## Sweep every live bolt: expire the stale ones, and run the char-proximity
## bonus check so a bolt clipping the mech mid-flight still lands (either path
## wins — contact via signal or this sweep, whichever fires first).
func _sweep_bolts() -> void:
	var mech := _find_mech()
	var now := Engine.get_physics_frames()
	for i in range(_bolts.size() - 1, -1, -1):
		var b: Box3DBody = _bolts[i]["b"]
		if not is_instance_valid(b):
			_bolts.remove_at(i)
			continue
		if now >= _bolts[i]["expire"]:
			_remove_bolt(b)
			continue
		if mech != null and mech.has_method("char_body") \
				and mech.has_method("is_active") and mech.is_active() \
				and mech.has_method("take_damage"):
			var cb: Box3DCharacterBody = mech.char_body()
			if cb != null and is_instance_valid(cb) \
					and b.global_position.distance_to(cb.global_position) < 0.8:
				mech.take_damage(BOLT_DAMAGE, cb.global_position)
				_remove_bolt(b)


## Death: the hull falls into bricks via the fork's fracture path, so killing
## a turret leaves absorbable rubble on the same debris queue as buildings.
func _die() -> void:
	if _dead:
		return
	_dead = true
	var parent := get_parent()
	var rng := BreakableBlock.shared_rng()
	var xf := global_transform
	var pieces := BreakableBlock.split_box_uneven(HULL_SIZE, 6, 0.16, rng, Vector3.ZERO)
	for piece in pieces:
		BreakableBlock.spawn_piece(parent, self,
				Transform3D(xf.basis, xf.origin + xf.basis * piece.off),
				piece.size, HULL_COLOR, 1,
				get_linear_velocity() + Vector3(rng.randf() - 0.5, rng.randf(), rng.randf() - 0.5) * 2.0,
				get_angular_velocity())
	FractureFX.burst(parent, xf.origin, HULL_SIZE.length() * 0.5, HULL_COLOR)
	queue_free()
