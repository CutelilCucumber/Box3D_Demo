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
##   RMB (hold)      right-shoulder reclaim laser — a sustained beam
##   LMB             left-shoulder cannon — fired by the gym: plasma for
##                   walker mechs, a lobbed cannonball for tanks
##
## The mech yaws to face its heading and the camera swings around it, keeping
## WASD tied to the viewport rather than the body (a tank-style feel without a
## turret).

# Turret animation tuning (procedural, on the head's aiming pivot).
const TURRET_SPEED := 6.0    # rad/s turret yaw/pitch smoothing toward the aim
const TURRET_PITCH_MIN := -1.57  # -PI/2, straight down
const TURRET_PITCH_MAX := 1.57   # PI/2, straight up
const TORSO_PITCH_MAX := 0.9     # rad clamp on the torso lean

const _Self = preload("res://lib/models/units/mech_body.gd")
const FractureFX := preload("res://lib/fx/fracture_fx.gd")

# --- Modular parts (Phase 4). A mech is composed of a body + head part scene;
# set_parts() swaps them at runtime to tier up. ---
const WarbotBody := preload("res://lib/models/units/parts/body/warbot_body.tscn")
const WarbotHead := preload("res://lib/models/units/parts/heads/warbot_head.tscn")
const ChibitankBody := preload("res://lib/models/units/parts/body/chibitank_body.tscn")
const ChibitankHead := preload("res://lib/models/units/parts/heads/chibitank_head.tscn")

## Which body and head the mech wears. Exported so a scene can pick a set;
## set_parts() swaps them at runtime (Phase 4 tiering).
@export var body_scene: PackedScene = WarbotBody
@export var head_scene: PackedScene = WarbotHead

# Debug part cycling: [ and ] step through these sets (in order) at runtime.
# Add future body/head scenes here to make them cycle-ready.
const BODY_SETS: Array[PackedScene] = [WarbotBody, ChibitankBody]
const HEAD_SETS: Array[PackedScene] = [WarbotHead, ChibitankHead]

const WALK_SPEED := 4.0     # m/s
const SPRINT_SPEED := 9.0   # m/s
const ACCEL := 30.0         # m/s^2 toward the desired walk velocity
const GRAVITY := 25.0       # m/s^2
const JUMP_SPEED := 7.5     # m/s (just for fun / clearing low rubble)
const TURN_SPEED := 10.0     # rad/s mech yaw toward its heading

# Third-person camera rig.
const CAM_DIST := 6.5       # m behind the mech
const CAM_LIFT := 3.2       # m above the mech
const CAM_PITCH_MIN := -1.57  # -PI/2, straight down
const CAM_PITCH_MAX := 1.57   # PI/2, straight up
const LOOK_SPEED := 0.0035  # rad per mouse pixel
# When aiming down, ease the camera higher and closer so the turret doesn't
# block the view of the target. Factors are exposed for tuning.
const CAM_AIM_LIFT_MULT := 1.5   # CAM_LIFT x when fully aiming down
const CAM_AIM_DIST_MULT := 0.7   # distance x when fully aiming down
# Camera collision: raycast from just behind the mech's capsule to the desired
# camera spot; on a hit, pull the camera in front of the obstacle by this margin.
const CAM_COLLIDE_MARGIN := 0.3
const CAM_RAY_START := 0.7    # behind the focus point, past the capsule radius
const CAM_SMOOTH := 12.0    # lerp speed toward the (collided) camera spot
# Zoom tuning.
const CAM_DIST_MIN := 2.0   # closest zoom (scroll in)
const CAM_DIST_MAX := 12.0  # farthest zoom (scroll out)
const CAM_ZOOM_STEP := 1.5  # distance changed per scroll notch
const CAM_ZOOM_SMOOTH := 6.0  # lerp speed toward the target distance

# Prop-shoving (see header). Push is a force, so it transfers momentum scaled
# to each prop's own mass — but the demo's props are VERY light (a crate is
# ~0.1 "kg"), so the force must stay small or a single tick launches them. 8 N
# on a 0.1 kg crate adds ~1 m/s per tick and eases it up to walk speed; the
# same force on a multi-kg wall barely stirs it.
const PUSH_FORCE := 8.0
const PUSH_REACH := 0.45    # m beyond the capsule radius

# Phase 2 weapons. Right-shoulder LASER: hold RMB for a sustained beam that
# grinds HP off anything carrying take_damage and MELTS loose debris (Phase 3).
# Left-shoulder CANNON: the gym fires it on LMB — a plasma bolt for walker
# mechs, a lobbed cannonball for tanks. Mech HP attrition feeds the death
# placeholder (scene reload — design's accepted stand-in).
const LASER_DPS := 10.0       # hp/s while the beam is on a target
const LASER_RANGE := 50.0
const LASER_THICK := 0.1
const CANNON_DAMAGE := 10.0   # hp on the first body the plasma touches
const CANNON_SPEED := 32.0    # m/s tank cannonball travel
const CANNON_BLAST_RADIUS := 3.0  # m, visual + physics blast radius
const CANNON_BLAST_IMPULSE := 4.0 # blast impulse strength
const MECH_HP := 100.0
# Phase 3 absorption: the beam MELTS loose debris instead of damaging it — a
# short sustained beam consumes a piece, feeding growth and restoring HP.
const MELT_TIME := 0.2        # s of sustained beam to consume one debris piece
const ABSORB_HEAL := 5.0      # hp restored per piece absorbed

signal died

var speed := WALK_SPEED
var jump_speed := JUMP_SPEED
## Mech HP: the turret's beam/projectile chip at this; at 0 `died` fires and
## the gym reloads the scene (design's accepted placeholder for death).
var hp := MECH_HP
## Phase 3 growth counter: loose debris consumed by the laser. Plain integer,
## no economy naming/spending yet (that is Phase 4).
var _absorb_count := 0
var _upgrade_threshold := 20

var _char: Box3DCharacterBody
var _world: Box3DWorld
var _camera: Camera3D
var _torso: Node3D
var _robot: Node3D
var _body_part: Node3D   # the instanced body part (its script carries layout)
var _head_part: Node3D   # the instanced head part (its script carries muzzles)
var _turret: Node3D
var _turret_pivot: Node3D   # pivot at the head mount the turret rotates around (see _build_visual)
var _gun_tip: Node3D   # Marker3D in the head: cannon/plasma muzzle
var _reclaim_tip: Node3D   # Marker3D in the head: laser/reclaim muzzle
# The GunTip's forward direction, measured ONCE at rest (turret.rotation ==
# ZERO) in the turret's own local space, with the vertical component zeroed
# out. Because this is captured at rest, it never changes as the turret
# pitches later — that stability is what makes it safe to use for yaw
# tracking (see _aim_turret). Falls back to Vector3.ZERO when there's no
# GunTip marker, which _aim_turret treats as "barrel = pivot's own +Z".
var _gun_fwd_local := Vector3.ZERO
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
var _cam_dist := CAM_DIST        # runtime zoom distance, eased by scroll
var _cam_target_dist := CAM_DIST # unscaled target zoom from the scroll wheel


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
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_cam_target_dist = clampf(_cam_target_dist - CAM_ZOOM_STEP, CAM_DIST_MIN, CAM_DIST_MAX)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_cam_target_dist = clampf(_cam_target_dist + CAM_ZOOM_STEP, CAM_DIST_MIN, CAM_DIST_MAX)
	elif event is InputEventKey and event.pressed and not event.echo:
		# Debug part cycling: [ cycles the body, ] cycles the head.
		match event.keycode:
			KEY_BRACKETLEFT:
				_cycle_body()
			KEY_BRACKETRIGHT:
				_cycle_head()


## Swing the follow camera around the mech on the current yaw/pitch, keeping it
## above ground so it can't sink through a slope. The distance eases toward the
## scroll-wheel target; when the player aims down, the camera rises and pulls
## closer so the turret/mech doesn't block the target. A raycast from the focus
## point to the desired spot keeps the camera from phasing through the world.
func _look(delta: float) -> void:
	var target := _char.global_position

	# Ease the zoom distance toward the scroll target.
	_cam_dist = lerpf(_cam_dist, _cam_target_dist, clampf(CAM_ZOOM_SMOOTH * delta, 0.0, 1.0))

	# When aiming down (pitch < 0), raise the lift and shorten the distance so
	# the target stays visible over the mech's shoulder. Fully at CAM_PITCH_MIN.
	var aim_factor := clampf(-_pitch / absf(CAM_PITCH_MIN), 0.0, 1.0)
	var lift := lerpf(CAM_LIFT, CAM_LIFT * CAM_AIM_LIFT_MULT, aim_factor)
	var dist := lerpf(_cam_dist, _cam_dist * CAM_AIM_DIST_MULT, aim_factor)

	# Desired camera spot in world space.
	var back := Vector3(sin(_yaw), 0.0, cos(_yaw))
	var focus := target + Vector3.UP * 1.0
	var desired := focus + back * dist + Vector3.UP * lift

	# Collide the camera against the world: raycast from just behind the mech's
	# capsule (so the ray doesn't hit the mech itself) toward the desired spot;
	# if something is in the way, pull the camera in front of it by a margin.
	var spot := desired
	if _world != null:
		var ray_from := focus + back * CAM_RAY_START
		var hit: Dictionary = _world.raycast(ray_from, desired)
		if hit.get("hit", false):
			var to_spot := desired - ray_from
			if to_spot.length_squared() > 0.0001:
				spot = (hit["position"] as Vector3) - to_spot.normalized() * CAM_COLLIDE_MARGIN

	# Smooth the camera position toward the spot to avoid jarring pops.
	_camera.global_position = _camera.global_position.lerp(spot, clampf(CAM_SMOOTH * delta, 0.0, 1.0))

	_camera.look_at(focus, Vector3.UP)
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


## Procedural rig: aim the turret head at the aim point, then let the body
## part drive its own movement animation (walker legs swing, a tank hull stays
## still). Each body part owns its walk phase and joints (mech_parts.gd /
## tank_parts.gd).
func _animate_parts(delta: float) -> void:
	if _robot == null:
		return
	# Aim the turret first so the torso lean it produces is known before the
	# body part places its legs (they are children of the leaning torso and
	# must counter-rotate to keep the feet planted).
	_aim_turret(delta)
	if _body_part == null or not is_instance_valid(_body_part):
		return
	if not _body_part.has_method("animate_parts"):
		return
	var move_speed := Vector2(_vel.x, _vel.z).length()
	var torso_lean := _torso.rotation.x if _torso != null else 0.0
	_body_part.animate_parts(delta, move_speed, torso_lean)


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
	# lean plus the pivot's own pitch, so the pivot only takes the remainder.
	var target_pitch := -world_pitch

	# How much the whole torso leans with the aim: mech walkers lean their
	# body (mech_parts.gd), tanks keep the hull level and only pitch the
	# turret (tank_parts.gd returns 0). Kept on the same smoothing step as the
	# pivot so they move together. Clamped so the body never over-leans.
	var lean_factor: float = 1.0
	if _body_part != null and is_instance_valid(_body_part) and _body_part.has_method("torso_lean"):
		lean_factor = _body_part.torso_lean()
	if _torso != null:
		var torso_target := -world_pitch * lean_factor
		_torso.rotation.x += wrapf(torso_target - _torso.rotation.x, -PI, PI) * step
		_torso.rotation.x = clampf(_torso.rotation.x, -TORSO_PITCH_MAX, TORSO_PITCH_MAX)

	_turret_pivot.rotation.y += wrapf(target_yaw - _turret_pivot.rotation.y, -PI, PI) * step
	_turret_pivot.rotation.x += wrapf(target_pitch * (1.0 - lean_factor) - _turret_pivot.rotation.x, -PI, PI) * step
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


## Right trigger: the reclaim laser — grinds structural targets and MELTS
## loose debris (Phase 3). A platform without a laser simply has no RMB weapon.
func _weapon(delta: float) -> void:
	var firing := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if firing and _uses_laser():
		_laser(delta)
	else:
		_reset_absorb()
		if _laser_beam != null and _laser_beam.visible:
			_laser_beam.visible = false


## Whether this platform has a reclaim laser on the right trigger. Both the
## walker mechs and the tanks carry one; anything without it gets no RMB weapon.
func _uses_laser() -> bool:
	if _body_part != null and is_instance_valid(_body_part) \
			and _body_part.has_method("uses_laser"):
		return _body_part.uses_laser()
	return true


## Whether this platform's LMB fires physics-free cannonballs instead of the
## walker mech's plasma bolt. Tanks fire cannonballs; walkers fire plasma.
## Weapon type is determined by the HEAD part.
func uses_cannonball() -> bool:
	if _head_part != null and is_instance_valid(_head_part) \
			and _head_part.has_method("uses_cannonball"):
		return _head_part.uses_cannonball()
	return false


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
	_absorb_count += 1
	if _absorb_count >= _upgrade_threshold:
		_upgrade_threshold += 20
		set_parts(ChibitankBody, ChibitankHead)
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


## Compose the mech from the configured body + head part scenes. The body is
## placed under the torso at its own ground offset; the head is hung from the
## body's mount marker inside an aiming pivot so the whole head rotates around
## the mount (yaw + pitch). The head's GunTip/ReclaimTip markers become the
## weapon muzzles; a legged body's Leg_L/Leg_R joints drive the walk cycle.
func _build_visual() -> void:
	_torso = Node3D.new()
	# Parent the visual shell to the moving character body. _char is moved in
	# world space by move_and_slide, so the shell must ride it rather than the
	# static controller root. The -0.9 y offset keeps the original visual layout
	# (parts were authored relative to the root, while _char sits 0.9 m above).
	_torso.position = Vector3(0.0, -0.9, 0.0)
	_char.add_child(_torso)

	# Instance the body part; its script carries the ground offset, the head
	# mount point, and (for legged bodies) the walk animation.
	var body := body_scene.instantiate()
	body.position = Vector3(0.0, body.visual_y_offset, 0.0)
	_torso.add_child(body)
	_robot = body
	_body_part = body

	# The head connects to the body's mount marker and aims around it. The
	# pivot is created at the marker, under the mount's own parent so the head
	# inherits the body's (possibly baked) rotation frame.
	var mount: Node3D = _body_part.mount_marker()
	var mount_parent: Node3D = _body_part.mount_parent()
	var mount_world: Vector3 = mount.global_position
	_turret_pivot = Node3D.new()
	_turret_pivot.position = mount_parent.global_transform.affine_inverse() * mount_world
	mount_parent.add_child(_turret_pivot)

	# The head's root origin is its connection point, so it rides the pivot.
	var head := head_scene.instantiate()
	_turret_pivot.add_child(head)
	_turret = head
	_head_part = head

	# Compensate for body root scale (e.g. chibitank at 0.111) so the head
	# maintains a fixed world size regardless of which body it's on.
	if _body_part != null and _body_part.has_method("get_head_scale"):
		head.scale = Vector3.ONE * _body_part.get_head_scale()

	# Weapon muzzles come from the head part's own markers.
	_gun_tip = _head_part.gun_tip()
	_reclaim_tip = _head_part.reclaim_tip()

	# Capture the main gun's horizontal direction in the head's own frame, AT
	# REST (head + pivot rotation are still zero here). _aim_turret and
	# turret_aim_dir() use this instead of re-measuring the muzzle live, which
	# is what used to couple yaw to pitch (see _aim_turret).
	if _gun_tip != null and _turret != null:
		var lp := _turret.global_transform.affine_inverse() * _gun_tip.global_position
		lp.y = 0.0
		if lp.length() > 0.01:
			_gun_fwd_local = lp.normalized()

	# Shoulder muzzles (fallbacks; the head's GunTip/ReclaimTip are primary).
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


## Swap the mech's parts (Phase 4 tiering): rebuild the visual shell in place
## with a new body + head, preserving the character, position and camera.
func set_parts(new_body: PackedScene, new_head: PackedScene) -> void:
	if new_body == null or new_head == null:
		return
	body_scene = new_body
	head_scene = new_head
	if _torso != null and is_instance_valid(_torso):
		_torso.queue_free()
	_torso = null
	_robot = null
	_body_part = null
	_head_part = null
	_turret = null
	_turret_pivot = null
	_gun_tip = null
	_reclaim_tip = null
	_gun_fwd_local = Vector3.ZERO
	_build_visual()


## Step to the next body in BODY_SETS, wrapping around; keeps the current head.
func _cycle_body() -> void:
	var idx := BODY_SETS.find(body_scene)
	var next := BODY_SETS[(idx + 1) % BODY_SETS.size()]
	set_parts(next, head_scene)


## Step to the next head in HEAD_SETS, wrapping around; keeps the current body.
func _cycle_head() -> void:
	var idx := HEAD_SETS.find(head_scene)
	var next := HEAD_SETS[(idx + 1) % HEAD_SETS.size()]
	set_parts(body_scene, next)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.fov = 70.0
	add_child(_camera)
	_camera.current = true
