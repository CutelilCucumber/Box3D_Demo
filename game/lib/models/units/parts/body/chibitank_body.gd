extends "res://lib/models/units/parts/mech_part.gd"

## Chibi Tank body part for the modular mech. A tracked hull with no legs, so
## leg() returns null and the mech skips the walk cycle. Sits on the ground at
## its own root origin, so visual_y_offset is 0.

## How far the body root sits above its feet; applied to stand it on the ground.
@export var visual_y_offset := 0.0

## The marker where the head part connects and rotates around.
func mount_marker() -> Node3D:
	return _find_descendant(self, "HeadMount") as Node3D


## The node the head part (and its aiming pivot) hangs from. The tank's mount
## is on the body root itself.
func mount_parent() -> Node3D:
	return self


## The left or right leg joint node, or null if this body has no legs.
func leg(_left: bool) -> Node3D:
	return null