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

var _mech: Node3D = null


func _ready() -> void:
	_free_fly = false
	super()
	_mount_mech()
	_set_mouse_captured(true)
	if _help_label != null:
		_help_label.text = "WASD/arrows walk | mouse look | Shift sprint | Space jump | LMB shoot | RMB blast | B barrage | N nuke | F ignite | V tornado | R reset | 1-5 scenes"


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
	_camera = _mech.camera()