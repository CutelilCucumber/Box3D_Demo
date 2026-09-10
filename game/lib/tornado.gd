extends Node3D

## A wandering destruction tornado: a localized vortex that sucks loose,
## compact debris and props into a swirling column, whirls them around and
## spits them out as it roams. Built for the demolition gyms.
##
##   Tornado.spawn(world, at, wander)   # a tornado roaming a ~wander m radius
##
## Physics: every physics tick it queries the world around its centre with
## overlap_sphere and drives the bodies it finds. The coupling splits on SIZE
## (compactness), not mass — the demo's density scale is such that a whole
## wall panel (~5 "kg") weighs about the same as a big crate, so mass cannot
## tell debris from architecture:
##   - COMPACT bodies (crates, bricks, fragments, cones, bins) are CAPTURED:
##     their velocity is eased toward a swirl+inward+lift target, so they
##     spiral in, climb the funnel and tumble around the core.
##   - LARGE bodies (wall panels, cars, slabs) get only a gentle tangential
##     shove — the tornado rattles them but never lifts a building.
## The swirl, lift and inward terms are pure functions of (position, time), so
## the whole effect replays bit-identically under the fixed-tick harness; the
## wander path is seeded from the spawn transform, not the wall clock.
##
## Purely cosmetic forces are also the point: none of this touches the body's
## structural health — a panel the tornado shoves into a neighbour fast enough
## still fractures on impact like any other collision.

const _Self = preload("res://lib/tornado.gd")

const GROUP := "tornado"
const LIFETIME := 45.0  # s before the funnel lets go and dissolves

# --- Physics field ---
const OUTER_R := 16.0    # m, radius of influence (also the query sphere)
const CAPTURE_SIZE := 2.2  # bodies whose largest axis is <= this get captured
const SWIRL_DIR := -1.0  # -1 = clockwise from above (matches the funnel lean)
const SWIRL_SPEED := 19.0  # m/s of tangential velocity at the core
const INWARD_SPEED := 5.0  # m/s pulling bodies toward the axis mid-radius
const LIFT_SPEED := 11.0   # m/s of upward velocity at ground, in the core
const LIFT_SCALE := 13.0   # m, height falloff of the lift (e^(-h/LIFT_SCALE))
const VBLEND := 0.26       # per-tick easing of captured bodies toward target
const TUMBLE := 10.0       # rad/s of spin added to captured debris
const SHOVE := 0.35        # large bodies: tangential accel scalar (m/s^2)

# --- Visual ---
const HEIGHT := 34.0       # m, funnel top
const CORE_R := 3.2        # m, funnel bottom radius (narrows toward the ground)
const TOP_R := 9.0         # m, funnel top radius (spreads into the cloud)

var _world: Box3DWorld
var _origin := Vector3.ZERO
var _wander := 0.0
var _t := 0.0
var _omega: Vector2
var _phase: Vector2
var _amp: Vector2
var _rng_seed := 0
var _funnel_material: StandardMaterial3D
var _cloud_material: StandardMaterial3D
var _dissolving := false

## Build a tornado under `world`, starting at `at` (ground level) and roaming
## within ~`wander` metres of it. Returns the tornado node.
static func spawn(world: Box3DWorld, at: Vector3, wander := 16.0) -> Node3D:
	var t := _Self.new()
	t._world = world
	t._origin = at
	t._wander = wander
	world.add_child(t)
	return t


func _ready() -> void:
	add_to_group(GROUP)
	position = _origin
	# Seed the wander path (Lissajous-like) from the origin so it is
	# deterministic: the same spawn point always roams the same path.
	var rng := RandomNumberGenerator.new()
	_rng_seed = int(_origin.x * 73856093) ^ int(_origin.z * 19349663) & 0x7FFFFFFF
	rng.seed = _rng_seed
	_amp = Vector2(_wander * rng.randf_range(0.5, 1.0),
			_wander * rng.randf_range(0.5, 1.0))
	_omega = Vector2(rng.randf_range(0.06, 0.14), rng.randf_range(0.05, 0.11))
	_phase = Vector2(rng.randf() * TAU, rng.randf() * TAU)
	_build_visual()
	# Let go after LIFETIME: a slow fade-out then free, so debris settles back
	# to the ground rather than being left spinning forever.
	var timer := Timer.new()
	timer.wait_time = LIFETIME
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(_dissolve)
	add_child(timer)


func _physics_process(delta: float) -> void:
	_t += delta
	if _dissolving:
		return
	_roam(delta)
	_drive(delta)


## Smooth, seeded roam: a slow Lissajous sweep around the origin so the funnel
## creeps across the neighbourhood instead of standing still. Pure function of
## _t — deterministic.
func _roam(delta: float) -> void:
	var w := _omega
	var p := _phase
	var a := _amp
	var x := sin(w.x * _t + p.x) * cos(w.y * _t + p.y) * a.x
	var z := sin(w.y * _t + p.y) * cos(w.x * _t + p.x) * a.y
	var target := _origin + Vector3(x, 0.0, z)
	position = position.lerp(target, clampf(delta * 1.6, 0.0, 1.0))
	_funnel_material.emission_energy_multiplier = 0.6 + 0.4 * sin(_t * 2.2 + _rng_seed)


## Apply the vortex to every dynamic body within reach. See the header for the
## compact (captured) vs large (shoved) split.
func _drive(delta: float) -> void:
	var c := position
	var up := Vector3.UP
	for item in _world.overlap_sphere(c, OUTER_R, 0xFFFFFFFF):
		var body: Box3DBody = item
		if not is_instance_valid(body) \
				or body.body_type != Box3DBody.DYNAMIC:
			continue
		var r := body.global_position - c
		r.y = 0.0
		var dist := r.length()
		if dist > OUTER_R or dist < 0.01:
			continue
		var strength := 1.0 - dist / OUTER_R  # 1 at the axis, 0 at the rim
		var tangent := r.cross(up).normalized() * SWIRL_DIR
		var maxdim: float = body.box_size[body.box_size.max_axis_index()]
		if maxdim <= CAPTURE_SIZE:
			# Captured: ease velocity toward swirl + inward + climb, tumble.
			var radial := -r / dist
			var h := maxf(body.global_position.y - c.y, 0.0)
			var target := tangent * (SWIRL_SPEED * strength) \
					+ radial * (INWARD_SPEED * strength * (0.4 + 0.6 * dist / OUTER_R)) \
					+ up * (LIFT_SPEED * exp(-h / LIFT_SCALE) * strength)
			body.set_linear_velocity(body.get_linear_velocity().lerp(target, VBLEND))
			body.set_angular_velocity(body.get_angular_velocity() + up * (TUMBLE * delta))
		else:
			# Large: a tangential nudge that scales DOWN with size, so a dumpster
			# gets shoved and a wall just rocks — never launched. Scaled by mass
			# (=> constant acceleration) so it affects big and small alike per m.
			var scale := CAPTURE_SIZE / maxf(maxdim, CAPTURE_SIZE)
			body.apply_impulse(tangent * SHOVE * strength * scale * body.get_mass() * delta,
					body.global_position + up * 0.3)


## Fade the funnel and cloud out, then free the node (leaving the already-flung
## debris to land on its own).
func _dissolve() -> void:
	_dissolving = true
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "modulate:a", 0.0, 1.4)
	tween.parallel().tween_property(_funnel_material, "albedo_color:a", 0.0, 1.4)
	tween.parallel().tween_property(_cloud_material, "albedo_color:a", 0.0, 1.4)
	tween.tween_callback(queue_free)


## --- Visuals: a translucent funnel tube, a swirling dust column that rises
## through it, and a churning debris cloud at the top. ---

func _build_visual() -> void:
	# The funnel: a widening tube from ground to the cloud. Translucent, so the
	# debris bodies whirling inside stay readable through it.
	_funnel_material = StandardMaterial3D.new()
	_funnel_material.albedo_color = Color(0.62, 0.6, 0.56, 0.13)
	_funnel_material.roughness = 1.0
	_funnel_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_funnel_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_funnel_material.no_depth_test = true

	var cone := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = TOP_R
	cyl.bottom_radius = CORE_R
	cyl.height = HEIGHT
	cyl.radial_segments = 12
	cone.mesh = cyl
	cone.material_override = _funnel_material
	cone.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cone)

	# Swirling dust: continuous ring-emission that spirals up the tube.
	add_child(_swirl_dust())
	# Debris cloud billowing off the top of the funnel.
	add_child(_cloud())
	add_child(_ground_ring())


## A continuous dust spiral: particles born on a ring at the funnel mouth pick
## up tangential acceleration (the swirl) and a rising gravity (the lift), so
## they trace a widening helix up the column.
func _swirl_dust() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 320
	p.lifetime = 5.0
	p.preprocess = 4.0
	p.emitting = true
	p.visibility_aabb = AABB(Vector3(-TOP_R * 2.0, -2.0, -TOP_R * 2.0),
			Vector3(TOP_R * 4.0, HEIGHT + 4.0, TOP_R * 4.0))
	p.draw_pass_1 = _dust_quad()

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_radius = CORE_R * 0.7
	pm.emission_ring_inner_radius = 0.3
	pm.tangential_accel_min = -SWIRL_DIR * 8.0
	pm.tangential_accel_max = -SWIRL_DIR * 14.0
	pm.radial_accel_min = -2.0
	pm.radial_accel_max = -4.0
	pm.gravity = Vector3(0.0, 7.0, 0.0)  # rising drift up the tube
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.6
	pm.damping_min = 0.1
	pm.damping_max = 0.6
	pm.scale_min = 0.9
	pm.scale_max = 2.6
	pm.angular_velocity_min = SWIRL_DIR * 3.0
	pm.angular_velocity_max = SWIRL_DIR * 7.0
	pm.color_ramp = _dust_ramp()
	p.process_material = pm
	return p


## The murky cloud swirling at the top of the funnel — the "head" of the storm.
func _cloud() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 90
	p.lifetime = 6.0
	p.preprocess = 5.0
	p.emitting = true
	p.visibility_aabb = AABB(Vector3(-TOP_R * 2.2, HEIGHT - 2.0, -TOP_R * 2.2),
			Vector3(TOP_R * 4.4, 6.0, TOP_R * 4.4))
	p.draw_pass_1 = _dust_quad()

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_radius = TOP_R * 0.6
	pm.emission_ring_inner_radius = TOP_R * 0.2
	pm.tangential_accel_min = -SWIRL_DIR * 5.0
	pm.tangential_accel_max = -SWIRL_DIR * 9.0
	pm.radial_accel_min = 0.5   # spread outward as they hit the cloud
	pm.radial_accel_max = 1.5
	pm.gravity = Vector3(0.0, 0.6, 0.0)
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 1.0
	pm.damping_min = 0.2
	pm.damping_max = 0.8
	pm.scale_min = 4.0
	pm.scale_max = 8.0
	pm.color_ramp = _cloud_ramp()
	p.process_material = pm
	return p


## A faint dark disc at ground level marking the funnel's wide mouth, so the
## capture radius reads against the street.
func _ground_ring() -> MeshInstance3D:
	_cloud_material = StandardMaterial3D.new()
	_cloud_material.albedo_color = Color(0.12, 0.11, 0.1, 0.22)
	_cloud_material.roughness = 1.0
	_cloud_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cloud_material.no_depth_test = true
	var ring := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = OUTER_R * 0.5
	dm.bottom_radius = OUTER_R * 0.5
	dm.height = 0.02
	dm.radial_segments = 24
	ring.mesh = dm
	ring.material_override = _cloud_material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ring


func _dust_quad() -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.58, 0.52)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = false
	quad.material = mat
	return quad


func _dust_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 0.5, 1.0])
	g.colors = PackedColorArray([
		Color(0.62, 0.6, 0.54, 0.0),
		Color(0.66, 0.63, 0.55, 0.35),
		Color(0.58, 0.55, 0.5, 0.5),
		Color(0.5, 0.47, 0.43, 0.0),
	])
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex


func _cloud_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	g.colors = PackedColorArray([
		Color(0.16, 0.15, 0.14, 0.0),
		Color(0.18, 0.17, 0.16, 0.5),
		Color(0.12, 0.11, 0.1, 0.0),
	])
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex