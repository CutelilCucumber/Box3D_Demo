extends Box3DCharacterBody

## Mobile warbot enemy: reuses the player's warbot body/head visuals,
## driven by a simple AI — aggro the mech, close to attack range,
## fire plasma bolts. Stationary-aggro behavior for Phase 5.

const _Self = preload("res://lib/models/units/warbot_enemy.gd")
const WarbotBody := preload("res://lib/models/units/parts/body/warbot_body.tscn")
const WarbotHead := preload("res://lib/models/units/parts/heads/warbot_head.tscn")
const LightPlasma := preload("res://lib/models/projectiles/light_plasma.gd")
const BreakableBlock := preload("res://lib/bodies/breakable_block.gd")
const FractureFX := preload("res://lib/fx/fracture_fx.gd")

# --- Tunables ---
const WALK_SPEED := 3.0           # m/s
const TURN_SPEED := 6.0           # rad/s
const ATTACK_RANGE := 15.0        # m, stop and shoot
const SIGHT_RANGE := 40.0         # m, aggro distance
const FIRE_INTERVAL := .5       # s between bolts
const BOLT_SPEED := 40.0          # m/s, slower than player's plasma
const BOLT_DAMAGE := 5.0         # hp per hit
const HP := 60.0

var _world: Box3DWorld
var _mech: Node3D
var _torso: Node3D
var _body_part: Node3D
var _head_part: Node3D
var _gun_tip: Node3D
var _hp := HP
var _fire_cooldown := 0.0
var _vel := Vector3.ZERO
var _dead := false
var _flash_until := -1.0
var _model_meshes: Array = []
var _flash_mat: StandardMaterial3D


static func spawn(world: Box3DWorld, at: Vector3) -> Box3DCharacterBody:
	var e := _Self.new()
	e._world = world
	# Capsule center at 0.9, so bottom is at ground level (0.9 - 1.8/2 = 0.0)
	e.position = at + Vector3(0.0, 0.9, 0.0)
	world.add_child(e)
	return e


func _ready() -> void:
	# Configure physics body (self) - Box3DCharacterBody uses radius/height
	radius = 0.5
	height = 1.8
	
	_build_visual()
	
	# Flash material
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.albedo_color = Color(1.0, 0.3, 0.25)
	_flash_mat.emission_enabled = true
	_flash_mat.emission = Color(1.0, 0.25, 0.2)
	_flash_mat.emission_energy_multiplier = 4.0
	
	add_to_group("enemy")


func _build_visual() -> void:
	# Torso offset: visual shell rides 0.9m below physics center
	_torso = Node3D.new()
	_torso.position = Vector3(0.0, -0.9, 0.0)
	add_child(_torso)
	
	# Body part
	var body_scene := WarbotBody.instantiate()
	add_child(body_scene)
	_body_part = body_scene
	
	# Apply body's visual offset ONCE (like player does)
	var body_root := body_scene.get_node_or_null("Body")
	if body_root != null:
		body_root.position.y += -0.96  # warbot_body.visual_y_offset
	
	# Head part - attach at body's HeadMount
	var head_scene := WarbotHead.instantiate()
	var mount := body_scene.get_node_or_null("HeadMount")
	if mount != null:
		mount.add_child(head_scene)
	else:
		add_child(head_scene)  # fallback
	_head_part = head_scene
	
	# Cache gun tip for firing
	_gun_tip = head_scene.get_node_or_null("GunTip")
	if _gun_tip == null:
		# Fallback: create marker at head position
		_gun_tip = Marker3D.new()
		_gun_tip.position = Vector3(0.0, 1.2, 0.0)
		head_scene.add_child(_gun_tip)
	
	# Collect meshes for flash effect
	_collect_meshes(body_scene)
	_collect_meshes(head_scene)


func _collect_meshes(root: Node) -> void:
	for c in root.get_children():
		if c is MeshInstance3D:
			_model_meshes.append(c)
		elif c is Node3D:
			_collect_meshes(c)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_flash_tick()
	
	var mech := _find_mech()
	if mech == null or (mech.has_method("is_active") and not mech.is_active()):
		return
	
	var mech_pos: Vector3 = _mech_hit_center(mech)
	var dist := global_position.distance_to(mech_pos)
	
	if dist > SIGHT_RANGE or not _los_clear(mech_pos):
		return
	
	var to_mech := (mech_pos - global_position).normalized()
	to_mech.y = 0.0
	
	if dist > ATTACK_RANGE:
		# Move toward mech
		_move_toward(to_mech, delta)
		_face(to_mech, delta)
	else:
		# Stop, aim, fire
		_vel.x = 0.0
		_vel.z = 0.0
		_face(to_mech, delta)
		_fire_if_ready(delta)
	
	# Apply gravity and move
	_vel.y -= 25.0 * delta
	var result := move_and_slide(_vel, delta)
	_vel.y = result.y


func _move_toward(dir: Vector3, delta: float) -> void:
	var target_v := dir * WALK_SPEED
	_vel.x = lerp(_vel.x, target_v.x, clampf(TURN_SPEED * delta, 0.0, 1.0))
	_vel.z = lerp(_vel.z, target_v.z, clampf(TURN_SPEED * delta, 0.0, 1.0))


func _face(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.01:
		return
	var target_yaw := atan2(dir.x, dir.z)
	var diff := wrapf(target_yaw - rotation.y, -PI, PI)
	rotation.y += diff * clampf(TURN_SPEED * delta, 0.0, 1.0)


func _fire_if_ready(delta: float) -> void:
	_fire_cooldown -= delta
	if _fire_cooldown <= 0.0:
		_fire_cooldown = FIRE_INTERVAL
		_fire_plasma()


func _fire_plasma() -> void:
	if _gun_tip == null or _world == null:
		return
	var mech := _find_mech()
	if mech == null:
		return
	var from := _gun_tip.global_position
	var target := _mech_hit_center(mech)
	var dir := (target - from).normalized()
	LightPlasma.spawn(_world, from + dir * 1.0, dir * BOLT_SPEED, BOLT_DAMAGE, mech, 0.0, self)


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


func _mech_hit_center(mech: Node3D) -> Vector3:
	if mech.has_method("hit_center"):
		return mech.hit_center()
	return mech.global_position


func _los_clear(target: Vector3) -> bool:
	if _world == null:
		return true
	var from := global_position + Vector3.UP * 1.0
	var dir := target - from
	var dist := dir.length()
	if dist < 0.01:
		return true
	var hit: Dictionary = _world.raycast(from, from + dir.normalized() * dist)
	if not hit.get("hit", false):
		return true
	return hit["position"].distance_to(target) < 1.5


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


func _die() -> void:
	if _dead:
		return
	_dead = true
	var parent := get_parent()
	var rng := BreakableBlock.shared_rng()
	var xf := global_transform
	# Use the capsule dimensions for debris
	var hull_size := Vector3(1.0, 1.8, 1.0)  # capsule diameter x2, height
	var pieces := BreakableBlock.split_box_uneven(hull_size, 6, 0.16, rng, Vector3.ZERO)
	for piece in pieces:
		BreakableBlock.spawn_piece(parent, BreakableBlock.new(),
				Transform3D(xf.basis, xf.origin + xf.basis * piece.off),
				piece.size, Color(0.55, 0.2, 0.18), 1,
				Vector3(rng.randf() - 0.5, rng.randf(), rng.randf() - 0.5) * 2.0,
				Vector3.ZERO)
	FractureFX.burst(parent, xf.origin, hull_size.length() * 0.5, Color(0.55, 0.2, 0.18))
	queue_free()
