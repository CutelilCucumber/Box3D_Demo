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

const MechBody := preload("res://lib/models/units/mech_body.gd")
const LaserTurret := preload("res://lib/models/turrets/laser_turret.gd")
const BoltTurret := preload("res://lib/models/turrets/bolt_turret.gd")
const LightPlasma := preload("res://lib/models/projectiles/light_plasma.gd")

var _mech: Node3D = null
var _health_bar: ProgressBar
var _fill_style: StyleBoxFlat
var _plasma_cooldown := 0.0
## Aim markers: replace the screen crosshair in mech mode. A reticle image on
## the surface where the plasma will hit, plus a red dot where the laser hits.
var _plasma_reticle: Sprite3D
var _laser_dot: Sprite3D

## Aim-marker tuning.
const AIM_TEX := 128
const RETICLE_WORLD := 0.55   # m, reticle diameter on the surface
const DOT_WORLD := 0.16       # m, laser-dot diameter on the surface
const RETICLE_COLOR := Color(0.35, 0.9, 1.0, 0.95)
const DOT_COLOR := Color(1.0, 0.22, 0.14, 1.0)


func _ready() -> void:
	_free_fly = false
	super()
	_mount_mech()
	_build_aim_markers()
	_set_mouse_captured(true)
	_build_health_bar()
	if _help_label != null:
		_help_label.text = "WASD/arrows walk | mouse look | Shift sprint | Space jump | M mech mode | LMB plasma (auto) | RMB laser (melts debris) | B barrage | N nuke | F ignite | V tornado | R reset | 1-5 scenes"


func _process(delta: float) -> void:
	super(delta)
	_update_health_bar()
	_update_aim_markers()


func _physics_process(delta: float) -> void:
	_auto_fire(delta)


## Full-auto: while LMB is held and the mouse is captured, fire on the
## projectile's cadence (LightPlasma.FIRE_INTERVAL). The press event (_shoot)
## already fired once — this only sustains the stream.
func _auto_fire(delta: float) -> void:
	if _free_fly or _mech == null:
		return
	if not _mouse_captured or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	_plasma_cooldown -= delta
	if _plasma_cooldown > 0.0:
		return
	_plasma_cooldown = LightPlasma.FIRE_INTERVAL
	_fire_plasma()


## In mech mode the aim reticles replace the screen crosshair; free-fly keeps
## the base "+" crosshair for the toy weapons.
func _set_mouse_captured(cap: bool) -> void:
	super._set_mouse_captured(cap)
	if _crosshair != null:
		_crosshair.visible = cap and _free_fly


## Two billboard sprites parked on the world: a reticle where the plasma's
## firing line first hits, a red dot where the laser's does. Both weapons aim
## along the turret's live aim direction, so we raycast each weapon's true
## muzzle line — not the camera ray — to place them.
func _build_aim_markers() -> void:
	_plasma_reticle = Sprite3D.new()
	_plasma_reticle.texture = _make_ring_texture()
	_plasma_reticle.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_plasma_reticle.pixel_size = RETICLE_WORLD / AIM_TEX
	_plasma_reticle.visible = false
	add_child(_plasma_reticle)

	_laser_dot = Sprite3D.new()
	_laser_dot.texture = _make_dot_texture()
	_laser_dot.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_laser_dot.pixel_size = DOT_WORLD / AIM_TEX
	_laser_dot.visible = false
	add_child(_laser_dot)


func _update_aim_markers() -> void:
	if _plasma_reticle == null or _laser_dot == null:
		return
	if _free_fly or _mech == null or not is_instance_valid(_mech) or not _mouse_captured:
		_plasma_reticle.visible = false
		_laser_dot.visible = false
		return
	_place_marker(_plasma_reticle, _mech.gun_tip(), _mech.cannon_dir(), LightPlasma.RANGE)
	_place_marker(_laser_dot, _mech.reclaim_tip(), _mech.laser_dir(), MechBody.LASER_RANGE)


func _place_marker(sprite: Sprite3D, from: Vector3, dir: Vector3, max_dist: float) -> void:
	if _world == null or dir.length() < 0.01:
		sprite.visible = false
		return
	var hit: Dictionary = _world.raycast(from, from + dir.normalized() * max_dist)
	if not hit.get("hit", false):
		sprite.visible = false
		return
	sprite.global_position = hit["position"] + hit["normal"] * 0.02
	sprite.visible = true


## Procedural aim-marker textures (no asset files): a hollow ring with four
## tick marks for the plasma reticle, a soft red dot for the laser.
func _make_ring_texture() -> ImageTexture:
	var img := Image.create(AIM_TEX, AIM_TEX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(AIM_TEX, AIM_TEX) * 0.5
	_draw_ring(img, c, AIM_TEX * 0.44, AIM_TEX * 0.40, RETICLE_COLOR)
	var tick := AIM_TEX * 0.05
	var at := AIM_TEX * 0.44
	_draw_rect(img, Rect2(c.x - at - tick, c.y - 1.0, tick, 2.0), RETICLE_COLOR)
	_draw_rect(img, Rect2(c.x + at, c.y - 1.0, tick, 2.0), RETICLE_COLOR)
	_draw_rect(img, Rect2(c.x - 1.0, c.y - at - tick, 2.0, tick), RETICLE_COLOR)
	_draw_rect(img, Rect2(c.x - 1.0, c.y + at, 2.0, tick), RETICLE_COLOR)
	return ImageTexture.create_from_image(img)


func _make_dot_texture() -> ImageTexture:
	var img := Image.create(AIM_TEX, AIM_TEX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_draw_dot(img, Vector2(AIM_TEX, AIM_TEX) * 0.5, AIM_TEX * 0.42, DOT_COLOR)
	return ImageTexture.create_from_image(img)


func _draw_ring(img: Image, c: Vector2, r_out: float, r_in: float, col: Color) -> void:
	var aa := 1.5
	for y in img.get_height():
		for x in img.get_width():
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var a := 0.0
			if d >= r_in and d <= r_out:
				a = 1.0
			elif d > r_out and d < r_out + aa:
				a = 1.0 - (d - r_out) / aa
			elif d < r_in and d > r_in - aa:
				a = (d - (r_in - aa)) / aa
			if a > 0.0:
				var p := img.get_pixel(x, y)
				img.set_pixel(x, y, Color(col.r, col.g, col.b, maxf(p.a, col.a * a)))


func _draw_dot(img: Image, c: Vector2, r: float, col: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if d >= r:
				continue
			var a := 1.0 - d / r
			a = a * a
			var p := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, maxf(p.a, col.a * a)))


func _draw_rect(img: Image, rect: Rect2, col: Color) -> void:
	for y in range(maxi(int(rect.position.y), 0), mini(int(rect.end.y), img.get_height())):
		for x in range(maxi(int(rect.position.x), 0), mini(int(rect.end.x), img.get_width())):
			var p := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, maxf(p.a, col.a)))


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
	# One laser turret and one bolt turret on the same street the mech spawns on
	# (the z=7.5 road runs from -ext to +ext on the road-centerlines), deterministic
	# positions so verification runs the same fight every reload.
	LaserTurret.spawn(_world, Vector3(14.0, 0.05, 7.5))
	BoltTurret.spawn(_world, Vector3(-14.0, 0.05, -7.5))


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
	_help_label.text = "WASD/arrows walk | mouse look | Shift sprint | Space jump | M mech mode | LMB plasma (auto) | RMB laser | B barrage | N nuke | F ignite | V tornado | R reset | 1-5 scenes"
	_help_label.text += " | [%s]" % mode


## Mech mode: LMB fires the left-shoulder cannon. The round is a straight-line
## kinematic bolt (light_plasma.gd) driven by hand — the fork's solver freezes
## dynamic bodies spawned near the player character, so the bolt does its own
## travel + overlap sweep. It fires along the turret's barrel direction; the
## bolt keeps a straight line, so no lobbing arc, and dies at its RANGE.
## Holding LMB keeps firing (see _auto_fire). Free-fly keeps the base
## cannonball toy.
func _shoot(sp: Vector2) -> void:
	if _free_fly or _mech == null:
		super._shoot(sp)
		return
	# The press event fires once immediately; the hold sustains the stream.
	_plasma_cooldown = LightPlasma.FIRE_INTERVAL
	_fire_plasma()


func _fire_plasma() -> void:
	# Fire along the turret's barrel direction (from the pivot to the GunTip
	# marker), not the crosshair ray — the bolt goes exactly where the head
	# points.
	var from: Vector3 = _mech.gun_tip()
	var dir: Vector3 = _mech.cannon_dir()
	if dir.length() < 0.01:
		dir = Vector3(0.0, 0.0, -1.0)
	LightPlasma.spawn(_world, from, dir * BALL_SPEED, MechBody.CANNON_DAMAGE)


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
