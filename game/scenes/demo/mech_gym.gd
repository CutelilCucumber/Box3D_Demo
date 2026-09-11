extends "res://scenes/demo/city_gym.gd"

## Mech gym: the destructible city with the player mech on the ground. Extends
## the city gym so it inherits the whole generated city, street props and all
## the destruction toys; it swaps the free-fly spectator camera for the mech's
## third-person follow cam and hands WASD/mouse to the mech.
##
##   WASD / arrows   walk (camera-relative)   mouse   look
##   Shift           sprint                   Space   jump
##   LMB             (Phase 2)                R       reset
##   Esc             free / re-grab the cursor
##
## The base gym's destruction keys still work (B barrage, N nuke, F ignite,
## V tornado, 1-5 scenes, etc.).

const MechBody := preload("res://lib/bodies/mech_body.gd")
const Turret := preload("res://lib/bodies/turret.gd")
const CannonBall := preload("res://lib/bodies/cannon_ball.gd")

var _mech: Node3D = null
var _health_bar: ProgressBar
var _fill_style: StyleBoxFlat


func _ready() -> void:
	_free_fly = false
	super()
	_mount_mech()
	_set_mouse_captured(true)
	_build_health_bar()
	if _help_label != null:
		_help_label.text = "WASD/arrows walk | mouse look | Shift sprint | Space jump | M mech mode | LMB cannon | RMB laser (melts debris) | B barrage | N nuke | F ignite | V tornado | R reset | 1-5 scenes"


func _process(delta: float) -> void:
	super(delta)
	_update_health_bar()


## Build the mech in place of the free-fly pivot, and point the gym's camera at
## the mech's own follow cam so the existing shake/aim systems keep working.
func _build_camera() -> void:
	# No pivot: the mech owns the camera. This runs during the base gym's _ready
	# (after the world/structures are built) but before we're fully set up, so
	# mounting the mech is deferred to _ready's end to guarantee _world exists.
	pass


## Spawn the mech on the street and hand the gym its camera. Called after super
## _ready so _world, _camera plumbing and the HUD all exist.
func _mount_mech() -> void:
	# On the street between the two nearest building rows (roads run at
	# (i+0.5)*SPACING = ±7.5, ±22.5 for the default 3x3 city), not in a wall.
	_mech = MechBody.spawn(_world, Vector3(0.0, 0.05, 7.5))
	_mech.set_active(true)
	_camera = _mech.camera()
	_mech.died.connect(_on_mech_died)
	# Two turrets on the same street the mech spawns on (the z=7.5 road runs
	# from -ext to +ext on the road-centerlines), deterministic positions so
	# verification runs the same fight every reload.
	Turret.spawn(_world, Vector3(14.0, 0.05, 7.5))
	Turret.spawn(_world, Vector3(-14.0, 0.05, -7.5))


## Death placeholder: a clean scene reload (design's accepted stand-in).
func _on_mech_died() -> void:
	get_tree().reload_current_scene()


## Bottom-left health bar: a rounded ProgressBar whose fill goes green -> red
## as the mech's HP falls, anchored to the bottom-left of the screen.
func _build_health_bar() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_border_width_all(2)
	bg.border_color = Color(0.9, 0.9, 0.9, 0.7)
	bg.set_corner_radius_all(4)

	_fill_style = StyleBoxFlat.new()
	_fill_style.set_corner_radius_all(3)

	_health_bar = ProgressBar.new()
	_health_bar.max_value = MechBody.MECH_HP
	_health_bar.value = MechBody.MECH_HP
	_health_bar.add_theme_stylebox_override("background", bg)
	_health_bar.add_theme_stylebox_override("fill", _fill_style)
	_health_bar.anchor_left = 0.0
	_health_bar.anchor_top = 1.0
	_health_bar.anchor_right = 0.0
	_health_bar.anchor_bottom = 1.0
	_health_bar.offset_left = 16.0
	_health_bar.offset_top = -38.0
	_health_bar.offset_right = 236.0
	_health_bar.offset_bottom = -16.0
	layer.add_child(_health_bar)
	_update_health_bar()


func _update_health_bar() -> void:
	if _health_bar == null or _mech == null or not is_instance_valid(_mech):
		return
	_health_bar.value = maxf(_mech.hp, 0.0)
	var ratio := clampf(_mech.hp / MechBody.MECH_HP, 0.0, 1.0)
	_fill_style.bg_color = Color(0.3, 0.9, 0.35, 0.95).lerp(Color(0.9, 0.2, 0.2, 0.95), 1.0 - ratio)


## Handle the mech-mode toggle key (M). The base gym routes unhandled keys here.
func _extra_key(code: int) -> void:
	if code == KEY_M:
		_toggle_mech_mode()
	else:
		super._extra_key(code)


## Toggle between controlling the mech and the free-fly spectator camera.
func _toggle_mech_mode() -> void:
	_free_fly = not _free_fly
	if _free_fly:
		# Exit mech mode: hand the camera to a free-fly pivot at its current view.
		_mech.set_active(false)
		_pivot = Node3D.new()
		add_child(_pivot)
		_pivot.global_transform = _camera.global_transform
		_camera.reparent(_pivot)
		_camera.position = Vector3.ZERO
		_camera.rotation = Vector3.ZERO
		var euler := _pivot.rotation
		_yaw = euler.y
		_pitch = euler.x
	else:
		# Re-enter mech mode: return the camera to the mech.
		_mech.set_active(true)
		_camera.reparent(_mech)
		_camera.current = true
		_pivot.queue_free()
		_pivot = null
	_set_mouse_captured(true)
	_update_help_label()


func _update_help_label() -> void:
	if _help_label == null:
		return
	var mode := "FREE-FLY" if _free_fly else "MECH"
	_help_label.text = "WASD/arrows walk | mouse look | Shift sprint | Space jump | M mech mode | LMB cannon | RMB laser | B barrage | N nuke | F ignite | V tornado | R reset | 1-5 scenes"
	_help_label.text += " | [%s]" % mode


## Mech mode: LMB fires the left-shoulder cannon. The round is a kinematic
## shell (cannon_ball.gd) driven by hand — the fork's solver freezes dynamic
## bodies spawned near the player character, so the shell does its own
## travel + overlap sweep. It aims at the world point under the crosshair;
## when the aim point is below the shoulder (the follow cam looks down at the
## mech) it fires LEVEL so the round lobs out ahead instead of ploughing into
## the floor. Free-fly keeps the base cannonball toy.
func _shoot(sp: Vector2) -> void:
	if _free_fly or _mech == null:
		super._shoot(sp)
		return
	var from: Vector3 = _mech.muzzle_left()
	var to_target: Vector3 = _mech.aim_point() - from
	if to_target.y < 0.0:
		to_target.y = 0.0  # never shoot the ground under the follow cam
	if to_target.length() < 0.01:
		to_target = Vector3(0.0, 0.0, -1.0)
	var dir := to_target.normalized()
	CannonBall.spawn(_world, from + dir * 1.0, dir * BALL_SPEED,
			MechBody.CANNON_DAMAGE, Color(0.16, 0.16, 0.18))


## Mech mode: RMB is the laser, a physics-loop hold in the mech — so the base
## gym's single-shot blast hook is deliberately empty. Free-fly keeps the
## blast toy.
func _blast(sp: Vector2, radius := BLAST_RADIUS, impulse := BLAST_IMPULSE) -> void:
	if _free_fly:
		super._blast(sp, radius, impulse)


## Mech HP readout next to the fps/bodies line.
func _extra_stats() -> String:
	if _mech == null or not is_instance_valid(_mech):
		return ""
	return " | hp %.0f | absorbed %d" % [maxf(_mech.hp, 0.0), _mech.absorbed_count]