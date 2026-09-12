extends Box3DBody

## One destructible static collider baked from a mesh in the handmade drone
## city (scenes/drone_city/drone_city.tscn). That scene is an imported visual
## model with no physics, so the mech gym boxes up each solid piece: a STATIC
## hull that stops the mech and is visible to its laser/cannon. The mech's
## weapons grind it down via take_damage; at zero it bursts a dust puff and
## hides its source mesh -- the mech chews a hole in the city instead of
## levelling the whole model.

const FractureFX := preload("res://lib/fx/fracture_fx.gd")

## Durability scales with bulk: a storefront melts in a few hits, a tower
## needs a sustained grind.
static func durability(size: Vector3) -> float:
	return 30.0 + size.y * 6.0 + maxf(size.x, size.z) * 4.0

var hp := 80.0
## The mesh this collider shadows; hidden when the shell bursts away.
var source: MeshInstance3D = null

var _dead := false


func _ready() -> void:
	body_type = Box3DBody.STATIC
	friction = 0.8


## The mech's laser and cannon call this. Static hulls stay put -- only the
## weapons' HP grind (never physics impacts) breaks them.
func take_damage(amount: float, at: Vector3) -> void:
	if _dead:
		return
	hp -= amount
	if hp > 0.0:
		FractureFX.burst(get_parent(), at, 0.5, Color(0.6, 0.55, 0.48))
		return
	_dead = true
	FractureFX.burst(get_parent(), global_position, box_size.length() * 0.6,
			Color(0.6, 0.55, 0.48))
	if source != null and is_instance_valid(source):
		source.visible = false
	queue_free()