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

# Leg / turret animation tuning (procedural, on the model's joint pivots).
const LEG_SWING := 0.55      # rad swing amplitude at full walk speed
const LEG_RATE := 5.5        # rad of phase per metre travelled
const TURRET_SPEED := 6.0    # rad/s turret yaw/pitch smoothing toward the aim
const TURRET_PITCH_MIN := -1.0  # rad, downward pitch limit
const TURRET_PITCH_MAX := 1.6   # rad, upward pitch limit
const TORSO_PITCH_FACTOR := 1.0  # fraction of the aim pitch the torso leans with
const TORSO_PITCH_MAX := 0.9     # rad clamp on the torso lean

const _Self = preload("res://lib/bodies/mech_body.gd")
const FractureFX := preload("res://lib/fx/fracture_fx.gd")
const WarRobot := preload("res://war_robot.tscn")

const WALK_SPEED := 4.0     # m/s
const SPRINT_SPEED := 9.0   # m/s
const ACCEL := 30.0         # m/s^2 toward the desired walk velocity
const GRAVITY := 25.0       # m/s^2
const JUMP_SPEED := 7.5     # m/s (just for fun / clearing low rubble)
const TURN_SPEED := 10.0     # rad/s mech yaw toward its heading

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
const LASER_DPS := 10.0       # hp/s while the beam is on a target
const LASER_RANGE := 50.0
const LASER_THICK := 0.1
const CANNON_DAMAGE := 30.0   # hp on the first body the ball touches
const MECH_HP := 100000.0
# Phase 3 absorption: the beam MELTS loose debris instead of damaging it — a
# short sustained beam consumes a piece, feeding growth and restoring HP.
const MELT_TIME := 0.4        # s of sustained beam to consume one debris piece
const ABSORB_HEAL := 6.0      # hp restored per piece absorbed

signal died

var speed := WALK_SPEED
var jump_speed := JUMP_SPEED
## Mech HP: the turret's beam/projectile chip at this; at 0 `died` fires and
## the gym reloads the scene (design's accepted placeholder for death).
var hp := MECH_HP
## Phase 3 growth counter: loose debris consumed by the laser. Plain integer,
## no economy naming/spending yet (that is Phase 4).
var absorbed_count := 0

var _char: Box3DCharacterBody
var _world: Box3DWorld
var _camera: Camera3D
var _torso: Node3D
var _robot: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _turret: Node3D
var _turret_pivot: Node3D   # centerline pivot the turret rotates around (see _build_visual)
var _gun_tip: Node3D   # Marker3D under the turret: cannon muzzle
var _reclaim_tip: Node3D   # Marker3D under the turret: laser/reclaim muzzle
# The GunTip's forward direction, measured ONCE at rest (turret.rotation ==
# ZERO) in the turret's own local space, with the vertical component zeroed
# out. Because this is captured at rest, it never changes as the turret
# pitches later — that stability is what makes it safe to use for yaw
# tracking (see _aim_turret). Falls back to Vector3.ZERO when there's no
# GunTip marker, which _aim_turret treats as "barrel = pivot's own +Z".
var _gun_fwd_local := Vector3.ZERO
var _walk_phase := 0.0
var _muzzle_r: Node3D   # right shoulder: the laser
var _muzzle_l: Node3D   # left shoulder: the cannon
var _laser_beam: MeshInstance3D
var _flash_mat: StandardMaterial3D
var _flash_until := -1.0
var _absorbing: Box3DBody = null   # loose-debris piece the beam is currently melting
var _absorb_progress := 0.0
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
	_animate_parts(delta)
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
		_apply_flash(c, on)


func _apply_flash(n: Node, on: bool) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_overlay = _flash_mat if on else null
	for c in n.get_children():
		_apply_flash(c, on)


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


## Procedural rig: swing the two legs with a walk cycle (amplitude scaled by
## how fast we're moving) and aim the turret head at the aim point.
func _animate_parts(delta: float) -> void:
	if _robot == null:
		return
	# Aim the turret first so the torso lean it produces is known before the
	# legs are placed (they are children of the leaning torso and must
	# counter-rotate to keep the feet planted).
	_aim_turret(delta)
	var move_speed := Vector2(_vel.x, _vel.z).length()
	var amount := clampf(move_speed / WALK_SPEED, 0.0, 1.0)
	if move_speed > 0.05:
		_walk_phase += move_speed * LEG_RATE * delta
	# Two legs, half a cycle apart; idle returns them to straight. The torso
	# lean is subtracted so the feet stay on the ground while the body pitches.
	var swing := LEG_SWING * amount
	var lean := _torso.rotation.x if _torso != null else 0.0
	if _leg_l != null:
		_leg_l.rotation.x = -lean + swing * sin(_walk_phase)
	if _leg_r != null:
		_leg_r.rotation.x = -lean + swing * sin(_walk_phase + PI)


## Smoothly point the turret's barrel at the world-space aim point, on both
## yaw and pitch, with the two axes fully decoupled.
##
## Two bugs used to live here:
##  1. Pitch was inverted. A world "look up" angle was written straight into
##     rotation.x, but a positive local-X rotation tips this rig's forward
##     vector DOWN, not up — so the turret nodded the opposite way from the
##     aim point. Fixed by negating the world pitch before applying it. (If
##     your turret is still inverted after this, this is the one line to
##     flip back — rig axis conventions vary by how the model was exported.)
##  2. Yaw and pitch were coupled. The old code re-read the GunTip marker's
##     LIVE global position every frame to estimate "which way the barrel
##     currently faces," then steered yaw toward that. But the marker's
##     position already includes the turret's current pitch — so pitching
##     shifted the marker's horizontal direction even though the turret
##     hadn't turned, and the yaw controller "corrected" for that phantom
##     turn. Fixed by using a fixed calibration angle (_gun_fwd_local,
##     captured once at rest) instead of re-measuring the marker live.
func _aim_turret(delta: float) -> void:
	if _turret_pivot == null:
		return
	var parent := _turret_pivot.get_parent() as Node3D
	if parent == null:
		return

	var step := clampf(TURRET_SPEED * delta, 0.0, 1.0)

	# Where the barrel should point, in WORLD space — measured from the
	# PIVOT's position, since that's the actual point rotation happens
	# around now, not the (deliberately off-center) turret mesh riding on it.
	var to_target: Vector3 = aim_point() - _turret_pivot.global_position
	var world_yaw := atan2(to_target.x, to_target.z)
	var world_pitch := atan2(to_target.y, Vector2(to_target.x, to_target.z).length())

	# rotation.y / rotation.x are local to the pivot's PARENT, not to the
	# world, so convert the world aim into that frame. The parent (the
	# model's body node) only ever yaws — it never pitches or rolls on its
	# own — so reading its yaw straight off the global basis is safe and
	# unambiguous, unlike trying to decompose the PIVOT's own basis (which
	# also carries its live pitch and would give an ambiguous Euler
	# decomposition).
	var parent_yaw: float = parent.global_transform.basis.get_euler().y
	var target_yaw := wrapf(world_yaw - parent_yaw, -PI, PI)

	# Fix #2: fold in the barrel's fixed calibration offset instead of
	# re-measuring the marker live. When there's no GunTip marker,
	# _gun_fwd_local is ZERO and atan2(0, 0) is 0, so this naturally reduces
	# to "the pivot's own +Z axis is the barrel" — no separate branch needed.
	target_yaw -= atan2(_gun_fwd_local.x, _gun_fwd_local.z)

	# Fix #1: flip world "look up" into this rig's local pitch convention. With
	# the torso-lean split below, the barrel's total world pitch is the torso
	# lean plus the pivot's own pitch, so the pivot only takes the remainder
	# (factor 1.0 = the whole body leans and the turret stays level on it).
	var target_pitch := -world_pitch

	# The torso leans up/down with the turret so the mech reads as aiming with
	# its whole body. Kept on the same smoothing step as the pivot so they move
	# together. Clamped so the body never over-leans.
	if _torso != null:
		var torso_target := -world_pitch * TORSO_PITCH_FACTOR
		_torso.rotation.x += wrapf(torso_target - _torso.rotation.x, -PI, PI) * step
		_torso.rotation.x = clampf(_torso.rotation.x, -TORSO_PITCH_MAX, TORSO_PITCH_MAX)

	_turret_pivot.rotation.y += wrapf(target_yaw - _turret_pivot.rotation.y, -PI, PI) * step
	_turret_pivot.rotation.x += wrapf(target_pitch * (1.0 - TORSO_PITCH_FACTOR) - _turret_pivot.rotation.x, -PI, PI) * step
	_turret_pivot.rotation.x = clampf(_turret_pivot.rotation.x, TURRET_PITCH_MIN, TURRET_PITCH_MAX)


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
## sustained beam grinds structural targets and MELTS loose debris (Phase 3).
func _weapon(delta: float) -> void:
	var firing := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if firing:
		_laser(delta)
	else:
		_reset_absorb()
		if _laser_beam != null and _laser_beam.visible:
			_laser_beam.visible = false


func _laser(delta: float) -> void:
	if _world == null:
		return
	var dir := laser_dir()
	var origin := reclaim_tip()
	var hit: Dictionary = _world.raycast(origin, origin + dir * LASER_RANGE)
	var to: Vector3
	if hit.get("hit", false):
		to = hit["position"]
		var c: Box3DBody = hit.get("collider")
		if _is_debris(c):
			_absorb(c, delta)
		else:
			_reset_absorb()
			if c != null and c.has_method("take_damage"):
				c.take_damage(LASER_DPS * delta, to)
	else:
		to = origin + dir * LASER_RANGE
		_reset_absorb()
	_show_beam(reclaim_tip(), to)


## Loose debris (crates, bricks, rubble, turret wreckage) is consumable: a
## short sustained beam on one piece melts it away, feeding absorbed_count and
## restoring a little HP. Structural material never enters here.
func _absorb(target: Box3DBody, delta: float) -> void:
	if target != _absorbing:
		_absorbing = target
		_absorb_progress = 0.0
	_absorb_progress += delta
	if _absorb_progress < MELT_TIME:
		return
	_absorb_progress = 0.0
	_absorbing = null
	absorbed_count += 1
	_heal(ABSORB_HEAL)
	if is_instance_valid(target) and target.is_inside_tree():
		FractureFX.burst(get_parent(), target.global_position, 0.6, Color(0.55, 0.85, 1.0))
		target.queue_free()


## Any loose debris body (breakable blocks + fragments) is absorbable — "all
## debris is consumable, through the laser."
func _is_debris(body: Box3DBody) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	return body.is_in_group("block") or body.is_in_group("fragment")


func _reset_absorb() -> void:
	_absorbing = null
	_absorb_progress = 0.0


## Heal restores HP up to the mech's maximum (absorbing is the heal source).
func _heal(amount: float) -> void:
	hp = minf(MECH_HP, hp + amount)


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


## World position of the cannon's muzzle marker (GunTip), falling back to the
## left shoulder if the model has no marker.
func gun_tip() -> Vector3:
	if _gun_tip != null and is_instance_valid(_gun_tip):
		return _gun_tip.global_position
	return muzzle_left()


## World position of the laser's muzzle marker (ReclaimTip), falling back to
## the right shoulder if the model has no marker.
func reclaim_tip() -> Vector3:
	if _reclaim_tip != null and is_instance_valid(_reclaim_tip):
		return _reclaim_tip.global_position
	return muzzle_right()


## The 3D direction the turret points: the GunTip's forward direction
## (captured once, at rest, as _gun_fwd_local) transformed by the turret's
## LIVE rotation — so it tracks the head's current yaw AND pitch correctly.
## BOTH weapons fire along this; the tip markers only choose WHERE they emit
## from. Falls back to the crosshair aim when there's no turret at all.
func turret_aim_dir() -> Vector3:
	if _gun_fwd_local != Vector3.ZERO and _turret != null:
		var d: Vector3 = _turret.global_transform.basis * _gun_fwd_local
		if d.length() > 0.01:
			return d.normalized()
	return aim_direction()


## The 3D direction the turret's cannon fires: the turret's aim.
func cannon_dir() -> Vector3:
	return turret_aim_dir()


## The 3D direction the turret's laser/reclaim beam fires: the turret's aim.
func laser_dir() -> Vector3:
	return turret_aim_dir()


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


## The war-robot model as the mech's visual shell. The model's local origin
## sits ~0.96 m above its feet, so we sink it by that much to stand on ground.
const VISUAL_Y_OFFSET := -0.96

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

	# The downloaded war-robot model, standing on its feet.
	var robot: Node3D = WarRobot.instantiate()
	robot.position = Vector3(0.0, VISUAL_Y_OFFSET, 0.0)
	_torso.add_child(robot)
	_robot = robot
	# Grab the joint pivots the model was exported with (Body/Leg_L/Leg_R/Turret).
	var body := robot.get_child(0) as Node3D
	if body != null:
		for c in body.get_children():
			if c.name == "Leg_L" and c is Node3D:
				_leg_l = c as Node3D
			elif c.name == "Leg_R" and c is Node3D:
				_leg_r = c as Node3D
			elif c.name == "Turret" and c is Node3D:
				_turret = c as Node3D

	# The exported "Body" node itself carries a baked rotation (measured at
	# 39.8° on Y in this model) — an export quirk, not worth re-exporting
	# over. That means body-LOCAL X/Z axes aren't aligned with the mech's
	# actual left/right and forward/back, so guessing a body-local pivot
	# offset (as an earlier version of this fix did) lands in the wrong spot
	# once that rotation is factored in.
	#
	# Fix: solve for the pivot's position in WORLD space instead, where we
	# know exactly where the centerline is — directly above _torso, since
	# _torso and everything built above it (_char, the follow camera rig)
	# are deliberately constructed with zero X/Z offset. Then convert that
	# world point into body's local frame using body's REAL transform. This
	# cancels out whatever position or rotation quirks "body" carries
	# without this code ever needing to know their values.
	if _turret != null and body != null:
		var pivot_world_pos := Vector3(
				_torso.global_position.x, _turret.global_position.y, _torso.global_position.z)
		var pivot_local_pos: Vector3 = body.global_transform.affine_inverse() * pivot_world_pos

		_turret_pivot = Node3D.new()
		_turret_pivot.position = pivot_local_pos
		body.add_child(_turret_pivot)

		var turret_local_pos: Vector3 = _turret.position
		body.remove_child(_turret)
		_turret_pivot.add_child(_turret)
		# The pivot starts unrotated, so re-expressing the turret's position
		# relative to it is a plain subtraction — no orientation to account
		# for yet. This keeps the turret's world position identical to
		# before the reparenting; only its rotation CENTER has moved.
		_turret.position = turret_local_pos - pivot_local_pos

	# The GunTip/ReclaimTip markers (Marker3D under the turret) define where the
	# cannon and laser emit from; the code reads them to place shots and beams.
	if _turret != null:
		_gun_tip = _find_descendant(_turret, "GunTip") as Node3D
		_reclaim_tip = _find_descendant(_turret, "ReclaimTip") as Node3D
	# Capture the GunTip's horizontal direction in the turret's own frame, AT
	# REST (both the pivot's and the turret's own rotation are still zero
	# here). This calibration is unaffected by the pivot wrapper above — it's
	# still just "which way the barrel points relative to the turret mesh's
	# own local frame" — and _aim_turret uses it the same way as before, just
	# applied to the pivot's rotation instead of the turret's directly. It's
	# also what _aim_turret and turret_aim_dir() use instead of re-measuring
	# the marker's live position later, which is what used to couple yaw to
	# pitch (see the comment on _aim_turret).
	if _gun_tip != null and _turret != null:
		var lp := _turret.global_transform.affine_inverse() * _gun_tip.global_position
		lp.y = 0.0
		if lp.length() > 0.01:
			_gun_fwd_local = lp.normalized()

	# Shoulder weapon muzzles (the laser rides the right, the cannon the left).
	# The robot's "head" is its turret, so the muzzles sit on either side of the
	# turret mount. They are markers on the shell; the robot model ships empty.
	_muzzle_r = Node3D.new()
	_muzzle_r.position = Vector3(0.45, 1.45, 0.3)
	_torso.add_child(_muzzle_r)
	_muzzle_l = Node3D.new()
	_muzzle_l.position = Vector3(-0.45, 1.45, 0.3)
	_torso.add_child(_muzzle_l)

	# One shared red emissive material for the damage flash overlay.
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.albedo_color = Color(1.0, 0.25, 0.2)
	_flash_mat.emission_enabled = true
	_flash_mat.emission = Color(1.0, 0.2, 0.15)


## Depth-first search for a descendant node by name (used to find the turret's
## GunTip marker wherever it sits in the model's hierarchy).
func _find_descendant(root: Node, name: String) -> Node:
	if root.name == name:
		return root
	for c in root.get_children():
		var found := _find_descendant(c, name)
		if found != null:
			return found
	return null


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.fov = 70.0
	add_child(_camera)
	_camera.current = true
