extends "res://lib/models/units/parts/tank_parts.gd"

## Chibi Tank body part for the modular mech. A tracked hull with no legs, so
## leg() returns null (from tank_parts.gd) and the mech skips the walk cycle.
## The hull never leans into the aim pitch — only the turret pitches (see
## tank_parts.gd). Sits on the ground at its own root origin, so
## visual_y_offset is 0; the root carries the scene scale that makes the hull
## match the warbot's height.

## How far the body root sits above its feet; applied to stand it on the ground.
@export var visual_y_offset := -0.96

## The marker where the head part connects and rotates around.
func mount_marker() -> Node3D:
	return _find_descendant(self, "HeadMount") as Node3D


## The node the head part (and its aiming pivot) hangs from. The tank's mount
## is on the body root itself.
func mount_parent() -> Node3D:
	return self


## The chibitank root is scaled to 0.111 to match warbot height.
## Return the inverse so the head maintains a fixed world size.
func get_head_scale() -> float:
	return 1.0 / 0.111
