extends "res://scenes/demo/mech_gym.gd"

## Mech gym on the handmade drone city (scenes/drone_city/drone_city.tscn).
## That scene is an imported visual model with no physics, so this gym bakes
## it up for the mech: a big invisible ground slab matches the city's ground
## mesh, every solid building piece gets a static collider
## (drone_city_building.gd) the mech collides with and its weapons grind down,
## crate stacks on the streets feed the absorb -> upgrade loop, and a laser
## plus a bolt turret make it a fight. The mech spawns on the street at the
## city's centre.
##
## Same controls as the mech gym: WASD walk | mouse look | Shift sprint |
## Space jump | M free-fly | LMB plasma | RMB laser (cannon after the tank
## upgrade) | B barrage | N nuke | F ignite | V tornado | R reset.

const DroneCityScene := preload("res://scenes/drone_city/drone_city.tscn")
const DroneBuilding := preload("res://lib/gen/drone_city_building.gd")
const StructureController := preload("res://lib/gen/structure_controller.gd")

const CITY_GROUND_TOP := 0.39   # the city's flat ground mesh sits at this y
const GROUND_SPAN := 210.0      # a little larger than the 192 m city

## Building styles that get a real destructible skeleton (panels, glass,
## metal columns) with the imported mesh as a skin: matched by mesh name prefix.
const STRUCTURAL_STYLES := [
	"orto-edificio22-completo",  # the tall tower slabs
	"Cube",                       # big block buildings
	"kiosko",                     # street kiosks
	"techolocalcomercialoxxo",    # commercial roof units
	"ortoedificiocontechorojo-",  # red-roof buildings
]
## Instances whose base sits far above the ground are stacked roof pieces of a
## taller building; they keep the simple collider (their neighbour below owns
## the destructible skeleton).
const STRUCT_GROUND_EPS := 1.0

var _city: Node3D = null
var _baked := 0


func _ground_size() -> float:
	return GROUND_SPAN


func _windsock_pos() -> Vector3:
	return Vector3(-55.0, 0.0, 55.0)


## One big invisible static slab under the city's ground mesh, so the mech,
## turrets and debris have a floor to stand on. (The slab carries no visual --
## the imported model provides the streets.)
func _build_ground() -> void:
	var slab := Box3DBody.new()
	slab.body_type = Box3DBody.STATIC
	slab.box_size = Vector3(GROUND_SPAN, 1.0, GROUND_SPAN)
	slab.position = Vector3(0.0, CITY_GROUND_TOP - 0.5, 0.0)
	slab.friction = 0.8
	_world.add_child(slab)


## The imported city replaces the procedural one: instance it, box up its
## solids, sprinkle absorbable debris on the streets and post the turrets.
func _build_structures() -> void:
	_city = DroneCityScene.instantiate()
	_city.name = "DroneCity"
	add_child(_city)
	_baked = 0
	_bake_node(_city, Transform3D.IDENTITY)
	print("[drone city] baked %d building colliders" % _baked)
	_scatter_absorb_crates()
	LaserTurret.spawn(_world, Vector3(32.1, CITY_GROUND_TOP + 0.06, -7.7))
	BoltTurret.spawn(_world, Vector3(-33.0, CITY_GROUND_TOP + 0.06, -7.7))


## The mech spawns at the street crossing in the city's centre (clear of any
## building footprint). Turrets already stand in _build_structures.
func _mount_mech() -> void:
	_mech = MechBody.spawn(_world, Vector3(0.0, CITY_GROUND_TOP + 0.06, 0.0))
	_mech.set_active(true)
	_camera = _mech.camera()
	_mech.died.connect(_on_mech_died)


## Depth-first walk over the imported model, baking a collider per solid mesh
## piece (global transform computed by hand -- the instanced tree is not live).
func _bake_node(node: Node, parent_xf: Transform3D) -> void:
	var xf := parent_xf
	if node is Node3D:
		xf = parent_xf * (node as Node3D).transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var world: AABB = xf * mi.get_aabb()
		if _build_structure(mi, xf, world):
			return  # structure owns the skin + skeleton; no simple collider
		if _wants_collider(mi.name, world):
			var b := DroneBuilding.new()
			b.box_size = world.size
			b.position = world.get_center()
			b.hp = DroneBuilding.durability(world.size)
			b.source = mi
			_world.add_child(b)
			_baked += 1
	for c in node.get_children():
		_bake_node(c, xf)


## For a structural style instance sitting on the ground, replace the plain
## collider with a real destructible skeleton under a skin. Returns true if the
## structure was built (the mesh becomes the controller's skin).
func _build_structure(mi: MeshInstance3D, xf: Transform3D, world: AABB) -> bool:
	var style := ""
	for s in STRUCTURAL_STYLES:
		if mi.name.begins_with(s):
			style = s
			break
	if style == "":
		return false
	if world.position.y > CITY_GROUND_TOP + STRUCT_GROUND_EPS:
		return false  # stacked roof piece: keep the simple collider
	# A controller node under the world at the origin; the skeleton's pieces
	# are placed in world coordinates (the bake tree is not live, so the mesh's
	# transform is passed in by hand rather than read from global_transform).
	var ctrl := StructureController.new()
	ctrl.name = "%s_Structure" % mi.name
	_world.add_child(ctrl)
	ctrl.setup(mi, xf, world)
	_baked += 1
	return true


## Which meshes become colliders: substantial solids the mech walks around and
## shoots. Flat ground/roads are covered by the slab; hedges and tiny props
## (cars, kiosks, signs) stay walk-through so the streets drive cleanly;
## pieces floating above head height (rooftop decor) are skipped.
func _wants_collider(mesh_name: String, aabb: AABB) -> bool:
	if aabb.size.y < 0.05 and aabb.size.x > 100.0:
		return false  # the 192 m ground plane: covered by the slab
	if aabb.size.y < 0.05:
		return false  # roads / sidewalks: flat, covered by the slab
	if aabb.position.y > 1.5:
		return false  # rooftop or elevated decor the mech can't reach
	if mesh_name.begins_with("Cube") or mesh_name.begins_with("kiosko"):
		return false  # hedges / planters / street stands: skip
	if aabb.size.y < 0.3:
		return false
	if maxf(aabb.size.x, aabb.size.z) < 1.2:
		return false
	return true


## Crate stacks on the streets feed the mech's absorb -> upgrade loop: the
## laser melts loose debris (group "block") toward the tank-body threshold.
func _scatter_absorb_crates() -> void:
	var spots := [
		Vector3(3.6, 0.0, 0.84),
		Vector3(-9.6, 0.0, -7.7),
		Vector3(17.0, 0.0, -7.77),
		Vector3(-21.2, 0.0, 22.1),
		Vector3(41.5, 0.0, -7.75),
		Vector3(-3.7, 0.0, -16.1),
	]
	var rot := 0.0
	for p in spots:
		for i in 3:
			var crate := BreakableBlock.new()
			crate.box_size = Vector3.ONE * 0.75
			crate.density = 0.5
			crate.friction = 0.7
			crate.block_color = Color(0.62, 0.47, 0.3)
			crate.position = Vector3(p.x, CITY_GROUND_TOP + 0.375 + i * 0.75, p.z)
			crate.rotation.y = rot
			_world.add_child(crate)