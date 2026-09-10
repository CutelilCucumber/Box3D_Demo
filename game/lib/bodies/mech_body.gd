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

var speed := WALK_SPEED
var jump_speed := JUMP_SPEED

var _char: Box3DCharacterBody
var _world: Box3DWorld
var _camera: Camera3D
var _torso: Node3D
var _vel := Vector3.ZERO
var _grounded := false
var _yaw := 0.0
var _pitch := -0.18
var _heading := 0.0
var _push_pool := []


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


func _ready() -> void:
	_build_body()
	_build_visual()
	_build_camera()


func _physics_process(delta: float) -> void:
	if _char == null or not is_instance_valid(_char):
		return
	# A subtle bob so the standing shell reads as alive, not frozen.
	if _torso != null:
		_torso.position.y = sin(Time.get_ticks_msec() * 0.004) * 0.015
	_look(delta)
	_move(delta)
	_push_dynamics(delta)


func _unhandled_input(event: InputEvent) -> void:
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
	add_child(_torso)
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