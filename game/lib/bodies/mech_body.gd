extends Node3D

## The player mech: a Box3DCharacterBody mover wearing a boxy capsule-on-legs
## shell, driven by a third-person over-shoulder camera. It is a GEOMETRIC
## mover (kinematic), not a simulated body — the engine solves its position
## against every shape it touches but never pushes back, so to keep the mech
## reading as a heavy thing that shoves the rubble, it applies a capped FORCE
## to the dynamic props it walks into (the same trick as the character sample's
## _push_dynamics). That force scales with the prop's own mass, so a crate
## gets shoved while a wall barely budges.
##
## Controls (mouse captured):
##   WASD / arrows   walk (camera-relative)
##   mouse           look (yaw/pitch around the mech)
##   Shift           sprint
##   RMB (hold)      right-shoulder laser — a sustained beam, not an instant shot
##   LMB             left-shoulder cannon — the gym's existing ball spawner
##
## The mech yaws to face its heading and the camera swings around it, keeping
## WASD tied to the viewport rather than the body (a tank-style feel without a
## turret).

const _Self = preload("res://lib/bodies/mech_body.gd")

const WALK_SPEED := 5.5     # m/s
const SPRINT_SPEED := 9.0   # m/s
const ACCEL := 18.0         # m/s^2 toward the desired walk velocity
const GRAVITY := 22.0       # m/s^2
const JUMP_SPEED := 7.5     # m/s (just for fun / clearing low rubble)
const TURN_SPEED := 8.0     # rad/s mech yaw toward its heading

# Third-person camera rig.
const CAM_DIST := 6.5       # m behind the mech
const CAM_LIFT := 3.2       # m above the mech
const CAM_PITCH_MIN := -0.9
const CAM_PITCH_MAX := 0.6
const LOOK_SPEED := 0.0035  # rad per mouse pixel

# Prop-shoving (see header). Push is a force, so it transfers momentum scaled
# to each prop's own mass — but the demo's props are VERY light (a crate is
# ~0.1 "kg"), so the force must stay small or a single tick launches them. 8 N
# on a 0.1 kg crate adds ~1 m/s per tick and eases it up to walk speed; the
# same force on a multi-kg wall barely stirs it.
const PUSH_FORCE := 8.0
const PUSH_REACH := 0.45    # m beyond the capsule radius

# Phase 2 weapons. Right-shoulder LASER: hold RMB for a sustained beam that
# grinds HP off anything carrying take_damage. Left-shoulder CANNON: LMB lobs
# a ball via the gym's existing spawner. Mech HP attrition feeds the death
# placeholder (scene reload — design's accepted stand-in).
const LASER_DPS := 35.0       # hp/s while the beam is on a target
const LASER_RANGE := 250.0
const LASER_THICK := 0.07
const CANNON_DAMAGE := 30.0   # hp on the first body the ball touches
const MECH_HP := 100.0

signal died

var speed := WALK_SPEED
var jump_speed := JUMP_SPEED
## Mech HP: the turret's beam/projectile chip at this; at 0 `died` fires and
## the gym reloads the scene (design's accepted placeholder for death).
var hp := MECH_HP

var _char: Box3DCharacterBody
var _world: Box3DWorld
var _camera: Camera3D
var _torso: Node3D
var _muzzle_r: Node3D   # right shoulder: the laser
var _muzzle_l: Node3D   # left shoulder: the cannon
var _laser_beam: MeshInstance3D
var _flash_mat: StandardMaterial3D
var _flash_until := -1.0
var _vel := Vector3.ZERO
var _grounded := false
var _yaw := 0.0
var _pitch := -0.18
var _heading := 0.0
var _push_pool := []
var _active := true


## Build a mech under `world` at ground position `at`, returning the controller.
## The mech mounts its own follow camera; set gym._camera to it for shake/aim.
static func spawn(world: Box3DWorld, at: Vector3) -> Node3D:
	var m := _Self.new()
	m._world = world
	m.position = at
	world.add_child(m)
	return m


func camera() -> Camera3D:
	return _camera


func set_active(active: bool) -> void:
	_active = active


func is_active() -> bool:
	return _active


func _ready() -> void:
	add_to_group("player")
	_build_body()
	_build_visual()
	_build_camera()


func _physics_process(delta: float) -> void:
	if not _active or _char == null or not is_instance_valid(_char):
		return
	# A subtle bob so the standing shell reads as alive, not frozen.
	if _torso != null:
		_torso.position.y = sin(Time.get_ticks_msec() * 0.004) * 0.015
	_look(delta)
	_move(delta)
	_push_dynamics(delta)
	_weapon(delta)
	_flash_tick()


## Turret hits chip HP; at 0 `died` fires and the gym reloads (design's
## accepted placeholder). A short red flash marks the hit — timed on the
## real clock, purely visual.
func take_damage(amount: float, _at: Vector3) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	_flash_until = Time.get_ticks_msec() + 120.0
	_set_flash(true)
	if hp <= 0.0:
		died.emit()


func _set_flash(on: bool) -> void:
	if _torso == null:
		return
	for c in _torso.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).material_overlay = _flash_mat if on else null


func _flash_tick() -> void:
	if _flash_until < 0.0:
		return
	if Time.get_ticks_msec() >= _flash_until:
		_flash_until = -1.0
		_set_flash(false)


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	# Mouse look: only while captured, and never consume the event so the gym's
	# key handling (scene switch, blasts) keeps working.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm: InputEventMouseMotion = event
		_yaw -= mm.relative.x * LOOK_SPEED
		_pitch = clampf(_pitch - mm.relative.y * LOOK_SPEED, CAM_PITCH_MIN, CAM_PITCH_MAX)


## Swing the follow camera around the mech on the current yaw/pitch, keeping it
## above ground so it can't sink through a slope.
func _look(delta: float) -> void:
	var target := _char.global_position
	_camera.global_position = target + Vector3(
			sin(_yaw) * CAM_DIST, CAM_LIFT, cos(_yaw) * CAM_DIST)
	_camera.look_at(target + Vector3.UP * 1.0, Vector3.UP)
	_camera.rotation_degrees.x += rad_to_deg(_pitch)
	# Keep the camera above the ground so it can't drop through a slope.
	var gpos := _camera.global_position
	if gpos.y < 0.4:
		_camera.global_position = Vector3(gpos.x, 0.4, gpos.z)


## Kinematic locomotion: gather a camera-relative walk direction, ease the
## horizontal velocity toward it, apply gravity, and slide against the world.
func _move(delta: float) -> void:
	_vel.y -= GRAVITY * delta

	var fwd := Vector3(sin(_yaw), 0.0, cos(_yaw))
	var right := Vector3(fwd.z, 0.0, -fwd.x)
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir -= fwd
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir += fwd
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir -= right
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir += right
	if dir.length() > 0.001:
		dir = dir.normalized()

	var moving: bool = dir.length() > 0.001
	var sprint: bool = Input.is_key_pressed(KEY_SHIFT)
	var target_speed: float = SPRINT_SPEED if sprint else speed
	var target_h := dir * target_speed if moving else Vector3.ZERO

	# Ease horizontal velocity toward the walk target (tank-style accel).
	var horiz := Vector3(_vel.x, 0.0, _vel.z)
	horiz = horiz.lerp(target_h, clampf(ACCEL * delta / maxf(target_speed, 0.1), 0.0, 1.0))
	_vel.x = horiz.x
	_vel.z = horiz.z

	if _grounded and Input.is_key_pressed(KEY_SPACE):
		_vel.y = jump_speed

	# Face the heading we're actually moving.
	if moving:
		_heading = atan2(dir.x, dir.z)

	var command := Vector3(horiz.x, _vel.y, horiz.z)
	var result := _char.move_and_slide(command, delta)
	_vel.y = result.y
	_grounded = command.y < 0.0 and result.y > command.y * 0.5

	# Smoothly turn the mech shell toward its heading.
	if _torso != null:
		var target_rot := Basis(Vector3.UP, _heading).get_euler().y
		var cur := _torso.rotation.y
		var diff := wrapf(target_rot - cur, -PI, PI)
		_torso.rotation.y = cur + diff * clampf(TURN_SPEED * delta, 0.0, 1.0)


## Shove dynamic props ahead of the walk direction with a capped force — the
## mech pushes rubble along rather than wedging against it.
func _push_dynamics(delta: float) -> void:
	var walk := Vector2(_vel.x, _vel.z).length()
	if walk < 0.01 or _world == null:
		return
	var push_dir := Vector3(_vel.x, 0.0, _vel.z) / walk
	var center := _char.global_position
	var reach := _char.radius + PUSH_REACH
	for item in _world.overlap_sphere(center, reach, 0xFFFFFFFF):
		var body: Box3DBody = item
		if not is_instance_valid(body) or body.body_type != Box3DBody.DYNAMIC:
			continue
		var to_body: Vector3 = body.global_position - center
		to_body.y = 0.0
		var d := to_body.length()
		if d > 0.01 and push_dir.dot(to_body / d) < 0.3:
			continue  # only push what's in front of our motion
		var v: Vector3 = body.get_linear_velocity()
		var v_fwd := Vector3(v.x, 0.0, v.z).dot(push_dir)
		if v_fwd < walk:
			body.apply_central_force(push_dir * PUSH_FORCE)


## Right-shoulder laser: while RMB is held (and the mouse is captured), a
## sustained beam grinds HP off whatever it touches. Not a single instant
## shot — damage flows each frame the trigger is down.
func _weapon(delta: float) -> void:
	var firing := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if firing:
		_laser(delta)
	elif _laser_beam != null and _laser_beam.visible:
		_laser_beam.visible = false


func _laser(delta: float) -> void:
	if _world == null:
		return
	var dir := aim_direction()
	var origin := _camera.global_position
	var hit: Dictionary = _world.raycast(origin, origin + dir * LASER_RANGE)
	var to: Vector3
	if hit.get("hit", false):
		to = hit["position"]
		var c: Box3DBody = hit.get("collider")
		if c != null and c.has_method("take_damage"):
			c.take_damage(LASER_DPS * delta, to)
	else:
		to = origin + dir * LASER_RANGE
	_show_beam(muzzle_right(), to)


## A stretched emissive box from the right muzzle to the hit point. Toggles
## visible as the beam starts/stops; freed with the mech.
func _show_beam(from: Vector3, to: Vector3) -> void:
	if _laser_beam == null:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(LASER_THICK, LASER_THICK, 1.0)
		_laser_beam = MeshInstance3D.new()
		_laser_beam.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.3, 0.25)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.25, 0.2)
		mat.emission_energy_multiplier = 5.0
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_laser_beam.material_override = mat
		add_child(_laser_beam)
		_laser_beam.top_level = true
	var length := maxf(from.distance_to(to), 0.01)
	_laser_beam.global_position = (from + to) * 0.5
	_laser_beam.look_at(to, Vector3.UP)
	_laser_beam.scale = Vector3(1.0, 1.0, length)
	_laser_beam.visible = true


## Aiming is always through the screen centre (the crosshair), computed from
## the mech's own camera so the gym's aim plumbing is not involved.
func aim_direction() -> Vector3:
	var center := get_viewport().get_visible_rect().size * 0.5
	return _camera.project_ray_normal(center)


## The world point under the crosshair (where the camera ray first hits).
## The cannon fires at this point rather than along the camera ray: the
## third-person camera sits high behind the mech and looks down at it, so the
## raw ray direction plunges into the ground — aiming at the crosshair's
## TARGET keeps the shot travelling out to whatever you're pointing at.
func aim_point(max_dist := 250.0) -> Vector3:
	var center := get_viewport().get_visible_rect().size * 0.5
	var origin := _camera.project_ray_origin(center)
	var dir := _camera.project_ray_normal(center)
	if _world != null:
		var hit: Dictionary = _world.raycast(origin, origin + dir * max_dist)
		if hit.get("hit", false):
			return hit["position"]
	return origin + dir * max_dist


func muzzle_right() -> Vector3:
	if _muzzle_r != null:
		return _muzzle_r.global_position
	return _char.global_position


func muzzle_left() -> Vector3:
	if _muzzle_l != null:
		return _muzzle_l.global_position
	return _char.global_position


## The character collation body — the thing enemies probe/contact against.
func char_body() -> Box3DCharacterBody:
	return _char


## Where shots should aim to register on the torso (feet + ~half height).
func hit_center() -> Vector3:
	if _char == null or not is_instance_valid(_char):
		return global_position + Vector3(0.0, 0.9, 0.0)
	return _char.global_position + Vector3(0.0, 0.9, 0.0)


## A man-sized kinematic capsule the mech collides with the world as.
func _build_body() -> void:
	_char = Box3DCharacterBody.new()
	_char.radius = 0.42
	_char.height = 1.8
	_char.position = Vector3(0.0, 0.9, 0.0)
	add_child(_char)


## Boxy capsule-on-legs shell built from primitives: a torso, a head block,
## two legs and two arm studs. Readable as a small mech at a glance.
func _build_visual() -> void:
	_torso = Node3D.new()
	# Parent the visual shell to the moving character body. _char is moved in
	# world space by move_and_slide, so the shell must ride it rather than the
	# static controller root. The -0.9 y offset keeps the original visual layout
	# (torso boxes were authored relative to the root, while _char sits 0.9 m
	# above the root).
	_torso.position = Vector3(0.0, -0.9, 0.0)
	_char.add_child(_torso)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.42, 0.46, 0.52)
	steel.metallic = 0.6
	steel.roughness = 0.5
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.24, 0.26, 0.3)
	dark.metallic = 0.4
	dark.roughness = 0.7

	var torso_mi := _box(0.9, 0.9, 0.6, Vector3(0.0, 0.95, 0.0), steel)
	_torso.add_child(torso_mi)
	var head := _box(0.42, 0.4, 0.42, Vector3(0.0, 1.55, 0.0), dark)
	_torso.add_child(head)
	_torso.add_child(_box(0.34, 0.12, 0.1, Vector3(0.0, 1.56, 0.24), _glow_material()))
	for side in [-1.0, 1.0]:
		_torso.add_child(_box(0.22, 0.7, 0.26, Vector3(side * 0.3, 0.35, 0.0), steel))
		_torso.add_child(_box(0.18, 0.18, 0.26, Vector3(side * 0.36, 0.85, 0.0), dark))

	# Shoulder weapon muzzles: the laser rides the right, the cannon the left.
	# They sit on the torso so the beam origin tracks the body as it turns.
	_muzzle_r = Node3D.new()
	_muzzle_r.position = Vector3(0.45, 1.15, 0.0)
	_torso.add_child(_muzzle_r)
	_muzzle_l = Node3D.new()
	_muzzle_l.position = Vector3(-0.45, 1.15, 0.0)
	_torso.add_child(_muzzle_l)

	# One shared red emissive material for the damage flash overlay.
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.albedo_color = Color(1.0, 0.25, 0.2)
	_flash_mat.emission_enabled = true
	_flash_mat.emission = Color(1.0, 0.2, 0.15)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.fov = 70.0
	add_child(_camera)
	_camera.current = true


func _box(w: float, h: float, d: float, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(w, h, d)
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	return mi


func _glow_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.8, 0.9, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.35, 0.6, 1.0)
	m.emission_energy_multiplier = 1.2
	return m