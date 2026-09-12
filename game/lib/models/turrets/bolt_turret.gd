extends Box3DBody

## Bolt-only turret: a stationary enemy that lobs slow, dodgeable light-plasma
## bolts at the player. The whole turret rotates to track the player.
##
##   BoltTurret.spawn(world, Vector3(x, 0, z))

const _Self = preload("res://lib/models/turrets/bolt_turret.gd")

const BreakableBlock := preload("res://lib/bodies/breakable_block.gd")
const FractureFX := preload("res://lib/fx/fracture_fx.gd")
const TurretModel := preload("res://lib/models/turrets/a1_turret.glb")
const LightPlasma := preload("res://lib/models/projectiles/light_plasma.gd")

const HP := 40.0
const HULL_SIZE := Vector3(1.7, 1.8, 1.7)
const HULL_COLOR := Color(0.55, 0.2, 0.18)

const SIGHT_RANGE := 60.0
const BOLT_PERIOD := 2.0
const BOLT_SPEED := 11.0
const BOLT_DAMAGE := 20.0

var _hp := HP
var _mech: Node3D
var _model: Node3D
var _base_mesh: MeshInstance3D
var _barrel_mesh: MeshInstance3D
var _model_meshes: Array = []
var _flash_mat: StandardMaterial3D
var _bolt_cooldown := 0.0
var _dead := false
var _flash_until := -1.0

static func spawn(world: Box3DWorld, at: Vector3) -> Box3DBody:
	var t := _Self.new()
	t.position = at + Vector3(0.0, HULL_SIZE.y * 0.5, 0.0)
	world.add_child(t)
	return t


func _ready() -> void:
	body_type = Box3DBody.KINEMATIC
	shape_type = Box3DBody.BOX
	box_size = HULL_SIZE
	add_to_group("enemy")
	var model := TurretModel.instantiate()
	model.position = Vector3(0.0, -HULL_SIZE.y * 0.5, 0.0)
	add_child(model)
	_model = model
	_base_mesh = model.get_node("Base") as MeshInstance3D
	_barrel_mesh = model.get_node("Barrel") as MeshInstance3D
	_model_meshes = [_base_mesh, _barrel_mesh]
	# Muzzle marker at the barrel's tip; bolts emit from here.
	var muzzle := Marker3D.new()
	muzzle.position = Vector3(0.0, 0.0, -0.8)
	model.get_node("Barrel").add_child(muzzle)
	# Shared red emissive flash for the damage-hit overlay.
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.albedo_color = Color(1.0, 0.3, 0.25)
	_flash_mat.emission_enabled = true
	_flash_mat.emission = Color(1.0, 0.25, 0.2)
	_flash_mat.emission_energy_multiplier = 4.0


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_flash_tick()
	var mech := _find_mech()
	if mech == null or (mech.has_method("is_active") and not mech.is_active()):
		return
	var mech_pos: Vector3 = mech.hit_center()

	var dist := global_position.distance_to(mech_pos)
	if dist > SIGHT_RANGE or not _los_clear(mech_pos):
		return
	# Keep the whole turret tracking the mech.
	var target_dir := (mech_pos - global_position).normalized()
	target_dir.y = 0.0
	if target_dir.length() > 0.01:
		look_at(global_position + target_dir, Vector3.UP)
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
		_set_flash(false)


func _find_mech() -> Node3D:
	if _mech != null and is_instance_valid(_mech):
		return _mech
	_mech = null
	for n in get_tree().get_nodes_in_group("player"):
		_mech = n
		break
	return _mech


func _los_clear(target: Vector3) -> bool:
	var from: Vector3 = global_position
	var dir: Vector3 = target - from
	var dist := dir.length()
	if dist < 0.01:
		return true
	var hit: Dictionary = (get_parent() as Box3DWorld).raycast(from, from + dir.normalized() * dist)
	if not hit.get("hit", false):
		return true
	return hit["position"].distance_to(target) < 1.5


## Lob a slow light-plasma bolt at the mech's CURRENT position: standing still
## means a hit. The projectile flies straight (no gravity) and keeps its own
## travel + damage sweep; the mech is passed along so bolts can hit the player.
func _fire_bolt(target: Vector3, _delta: float) -> void:
	var from: Vector3 = global_position
	var dir := (target - from).normalized()
	# Spawn a bolt-length out along the shot so the round never spawns
	# overlapping the turret's own hull.
	LightPlasma.spawn(get_parent() as Box3DWorld,
			from + dir * 1.2, dir * BOLT_SPEED, BOLT_DAMAGE, _find_mech())


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


## The mech ships shots duck-typed on take_damage, same as panels do.
func take_damage(amount: float, _at: Vector3) -> void:
	if _dead:
		return
	_hp -= amount
	_flash_until = Time.get_ticks_msec() + 100.0
	_set_flash(true)
	if _hp <= 0.0:
		_die()


func _set_flash(on: bool) -> void:
	for mi in _model_meshes:
		if is_instance_valid(mi):
			mi.material_override = _flash_mat if on else null
